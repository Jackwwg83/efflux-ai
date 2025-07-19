-- Create missing tables for the chat functionality

-- 1. Create user_tiers enum if not exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_tier') THEN
    CREATE TYPE user_tier AS ENUM ('free', 'pro', 'max');
  END IF;
END $$;

-- 2. Create users table
CREATE TABLE IF NOT EXISTS users (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  email text NOT NULL,
  tier user_tier DEFAULT 'free',
  total_tokens_used bigint DEFAULT 0,
  total_cost numeric(10,6) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 3. Create user_tiers table (tier definitions)
CREATE TABLE IF NOT EXISTS user_tiers (
  tier user_tier PRIMARY KEY,
  display_name text NOT NULL,
  daily_token_limit integer NOT NULL,
  monthly_token_limit integer NOT NULL,
  max_models_access text[] DEFAULT '{}',
  rate_limit_per_minute integer DEFAULT 60,
  priority integer DEFAULT 1,
  price_per_month numeric(10,2) DEFAULT 0
);

-- 4. Insert tier definitions
INSERT INTO user_tiers (tier, display_name, daily_token_limit, monthly_token_limit, max_models_access, rate_limit_per_minute, priority, price_per_month) VALUES
('free', 'Free', 10000, 100000, ARRAY['gpt-3.5-turbo', 'claude-3-5-haiku', 'gemini-2.5-flash'], 10, 1, 0),
('pro', 'Pro', 100000, 3000000, ARRAY['gpt-4o', 'gpt-4o-mini', 'claude-3-5-sonnet', 'claude-3-5-haiku', 'gemini-2.5-pro', 'gemini-2.5-flash'], 60, 2, 29.99),
('max', 'Max', 500000, 15000000, ARRAY[]::text[], 300, 3, 99.99)
ON CONFLICT (tier) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  daily_token_limit = EXCLUDED.daily_token_limit,
  monthly_token_limit = EXCLUDED.monthly_token_limit,
  max_models_access = EXCLUDED.max_models_access,
  rate_limit_per_minute = EXCLUDED.rate_limit_per_minute,
  priority = EXCLUDED.priority,
  price_per_month = EXCLUDED.price_per_month;

-- 5. Create usage_logs table
CREATE TABLE IF NOT EXISTS usage_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES users(id) NOT NULL,
  model text NOT NULL,
  provider text NOT NULL,
  api_key_id uuid REFERENCES api_key_pool(id),
  prompt_tokens integer DEFAULT 0,
  completion_tokens integer DEFAULT 0,
  total_tokens integer DEFAULT 0,
  estimated_cost numeric(10,6) DEFAULT 0,
  latency_ms integer,
  status text DEFAULT 'success',
  error_message text,
  created_at timestamptz DEFAULT now()
);

-- 6. Add current user to users table
INSERT INTO users (id, email, tier)
SELECT 
  id,
  COALESCE(email, 'user@example.com'),
  'free'::user_tier
FROM auth.users
WHERE email = 'jackwwg@gmail.com'
ON CONFLICT (id) DO UPDATE SET
  tier = 'free';

-- 7. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_tier ON users(tier);
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_created ON usage_logs(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_usage_logs_status ON usage_logs(status);

-- 8. Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;

-- 9. Create RLS policies for users table
CREATE POLICY "Users can view own profile"
ON users FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Admins can view all users"
ON users FOR SELECT
TO authenticated
USING (auth_is_admin());

CREATE POLICY "Users can update own profile"
ON users FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 10. Create RLS policies for usage_logs table
CREATE POLICY "Users can view own usage logs"
ON usage_logs FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Admins can view all usage logs"
ON usage_logs FOR SELECT
TO authenticated
USING (auth_is_admin());

CREATE POLICY "System can insert usage logs"
ON usage_logs FOR INSERT
TO authenticated, service_role
WITH CHECK (true);

-- 11. Grant permissions
GRANT SELECT ON users TO authenticated, service_role;
GRANT UPDATE (tier, updated_at) ON users TO authenticated;
GRANT INSERT, UPDATE ON users TO service_role;

GRANT SELECT ON user_tiers TO authenticated, service_role;

GRANT SELECT ON usage_logs TO authenticated;
GRANT INSERT ON usage_logs TO authenticated, service_role;

-- 12. Test the setup
SELECT 'Tables created successfully' as status;