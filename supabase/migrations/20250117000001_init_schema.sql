-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Create enum types
CREATE TYPE user_tier AS ENUM ('free', 'pro', 'max');
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'system');

-- User profiles table (extends auth.users)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User tiers and credits
CREATE TABLE user_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier user_tier DEFAULT 'free' NOT NULL,
  credits_balance DECIMAL(10,2) DEFAULT 1000 NOT NULL CHECK (credits_balance >= 0),
  credits_limit DECIMAL(10,2) NOT NULL,
  rate_limit INTEGER NOT NULL DEFAULT 5, -- requests per minute
  reset_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '1 day'),
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- API keys table (admin only)
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL CHECK (provider IN ('openai', 'anthropic', 'google', 'bedrock')),
  api_key TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New Conversation',
  model TEXT,
  provider TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_message_at TIMESTAMP WITH TIME ZONE
);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role message_role NOT NULL,
  content TEXT NOT NULL,
  model TEXT,
  provider TEXT,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  total_tokens INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Usage logs table
CREATE TABLE usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  model TEXT NOT NULL,
  provider TEXT NOT NULL,
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  cost DECIMAL(10,6) NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Model configurations (for pricing and limits)
CREATE TABLE model_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  display_name TEXT NOT NULL,
  input_price DECIMAL(10,6) NOT NULL, -- per million tokens
  output_price DECIMAL(10,6) NOT NULL, -- per million tokens
  max_tokens INTEGER NOT NULL,
  context_window INTEGER NOT NULL,
  tier_required user_tier NOT NULL DEFAULT 'free',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(provider, model)
);

-- Indexes for performance
CREATE INDEX idx_conversations_user_id ON conversations(user_id);
CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_created_at ON messages(created_at);
CREATE INDEX idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX idx_usage_logs_created_at ON usage_logs(created_at);

-- Row Level Security (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Profiles: Users can view and update their own profile
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- User tiers: Users can view their own tier
CREATE POLICY "Users can view own tier" ON user_tiers
  FOR SELECT USING (auth.uid() = user_id);

-- Conversations: Users can CRUD their own conversations
CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create own conversations" ON conversations
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own conversations" ON conversations
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own conversations" ON conversations
  FOR DELETE USING (auth.uid() = user_id);

-- Messages: Users can CRUD messages in their conversations
CREATE POLICY "Users can view messages in own conversations" ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM conversations 
      WHERE conversations.id = messages.conversation_id 
      AND conversations.user_id = auth.uid()
    )
  );
CREATE POLICY "Users can create messages in own conversations" ON messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM conversations 
      WHERE conversations.id = messages.conversation_id 
      AND conversations.user_id = auth.uid()
    )
  );

-- Usage logs: Users can view their own usage
CREATE POLICY "Users can view own usage logs" ON usage_logs
  FOR SELECT USING (auth.uid() = user_id);

-- API keys: Admin only (no RLS policy = no access for regular users)

-- Functions
-- Function to automatically create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  
  -- Create default tier for new user
  INSERT INTO public.user_tiers (user_id, tier, credits_limit)
  VALUES (
    NEW.id,
    'free',
    CASE 
      WHEN 'free' = 'free' THEN 5000
      WHEN 'free' = 'pro' THEN 500000
      ELSE 5000000
    END
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update credits
CREATE OR REPLACE FUNCTION public.deduct_credits(
  p_user_id UUID,
  p_tokens INTEGER,
  p_cost DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_current_balance DECIMAL;
  v_success BOOLEAN := false;
BEGIN
  -- Get current balance with lock
  SELECT credits_balance INTO v_current_balance
  FROM user_tiers
  WHERE user_id = p_user_id
  FOR UPDATE;
  
  -- Check if user has enough credits
  IF v_current_balance >= p_tokens THEN
    -- Deduct credits
    UPDATE user_tiers
    SET credits_balance = credits_balance - p_tokens,
        updated_at = NOW()
    WHERE user_id = p_user_id;
    
    v_success := true;
  END IF;
  
  RETURN v_success;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reset daily credits
CREATE OR REPLACE FUNCTION public.reset_daily_credits()
RETURNS void AS $$
BEGIN
  UPDATE user_tiers
  SET credits_balance = credits_limit,
      reset_at = NOW() + INTERVAL '1 day',
      updated_at = NOW()
  WHERE reset_at <= NOW();
END;
$$ LANGUAGE plpgsql;

-- Schedule daily credit reset using pg_cron
SELECT cron.schedule(
  'reset-daily-credits',
  '0 0 * * *', -- Run at midnight every day
  'SELECT public.reset_daily_credits();'
);

-- Insert default model configurations
INSERT INTO model_configs (provider, model, display_name, input_price, output_price, max_tokens, context_window, tier_required) VALUES
-- Google Gemini
('google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', 0.1, 0.4, 8192, 1048576, 'free'),
('google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 1.25, 10, 8192, 2097152, 'max'),
-- OpenAI
('openai', 'gpt-4o-mini', 'GPT-4o Mini', 0.15, 0.6, 16384, 128000, 'free'),
('openai', 'gpt-4o', 'GPT-4o', 5, 20, 4096, 128000, 'pro'),
('openai', 'gpt-4.1', 'GPT-4.1', 5, 20, 4096, 1000000, 'max'),
-- Anthropic
('anthropic', 'claude-3.5-haiku', 'Claude 3.5 Haiku', 0.8, 4, 4096, 200000, 'free'),
('anthropic', 'claude-3.5-sonnet', 'Claude 3.5 Sonnet', 3, 15, 4096, 200000, 'pro'),
-- AWS Bedrock (prices are estimates)
('bedrock', 'claude-3-haiku', 'Claude 3 Haiku (Bedrock)', 0.25, 1.25, 4096, 200000, 'pro'),
('bedrock', 'claude-3-sonnet', 'Claude 3 Sonnet (Bedrock)', 3, 15, 4096, 200000, 'max');