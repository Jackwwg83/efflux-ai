# Efflux AI - Supabase 设置指南

## 第一步：初始化数据库

1. 打开 Supabase Dashboard: https://app.supabase.com/project/lzvwduadnunbtxqaqhkg

2. 进入 SQL Editor (左侧菜单)

3. 点击 "New query"

4. 复制以下完整的 SQL 脚本并粘贴:

```sql
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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
  rate_limit INTEGER NOT NULL DEFAULT 5,
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
  input_price DECIMAL(10,6) NOT NULL,
  output_price DECIMAL(10,6) NOT NULL,
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
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own tier" ON user_tiers
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create own conversations" ON conversations
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own conversations" ON conversations
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own conversations" ON conversations
  FOR DELETE USING (auth.uid() = user_id);

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

CREATE POLICY "Users can view own usage logs" ON usage_logs
  FOR SELECT USING (auth.uid() = user_id);

-- Functions
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
  
  INSERT INTO public.user_tiers (user_id, tier, credits_limit)
  VALUES (
    NEW.id,
    'free',
    5000
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

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
  SELECT credits_balance INTO v_current_balance
  FROM user_tiers
  WHERE user_id = p_user_id
  FOR UPDATE;
  
  IF v_current_balance >= p_tokens THEN
    UPDATE user_tiers
    SET credits_balance = credits_balance - p_tokens,
        updated_at = NOW()
    WHERE user_id = p_user_id;
    
    v_success := true;
  END IF;
  
  RETURN v_success;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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

-- Insert default model configurations
INSERT INTO model_configs (provider, model, display_name, input_price, output_price, max_tokens, context_window, tier_required) VALUES
('google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', 0.1, 0.4, 8192, 1048576, 'free'),
('google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 1.25, 10, 8192, 2097152, 'max'),
('openai', 'gpt-4o-mini', 'GPT-4o Mini', 0.15, 0.6, 16384, 128000, 'free'),
('openai', 'gpt-4o', 'GPT-4o', 5, 20, 4096, 128000, 'pro'),
('openai', 'gpt-4.1', 'GPT-4.1', 5, 20, 4096, 1000000, 'max'),
('anthropic', 'claude-3.5-haiku', 'Claude 3.5 Haiku', 0.8, 4, 4096, 200000, 'free'),
('anthropic', 'claude-3.5-sonnet', 'Claude 3.5 Sonnet', 3, 15, 4096, 200000, 'pro'),
('bedrock', 'claude-3-haiku', 'Claude 3 Haiku (Bedrock)', 0.25, 1.25, 4096, 200000, 'pro'),
('bedrock', 'claude-3-sonnet', 'Claude 3 Sonnet (Bedrock)', 3, 15, 4096, 200000, 'max');
```

5. 点击 "Run" 按钮执行

## 第二步：配置认证提供商

### 1. 启用 Email 认证
- 在 Dashboard 中进入 Authentication → Providers
- Email 应该已经默认启用
- 确保 "Enable Email Confirmations" 是关闭的（用于测试）

### 2. 配置 Google OAuth
1. 进入 Authentication → Providers → Google
2. 点击 "Enable Sign in with Google"
3. 你需要：
   - Google Cloud Console 项目
   - OAuth 2.0 客户端 ID 和密钥

如果你还没有 Google OAuth 凭据：
1. 访问 https://console.cloud.google.com/
2. 创建新项目或选择现有项目
3. 启用 Google+ API
4. 创建 OAuth 2.0 凭据
5. 添加授权重定向 URI:
   ```
   https://lzvwduadnunbtxqaqhkg.supabase.co/auth/v1/callback
   ```

### 3. 配置 Apple Sign In (可选)
- 需要 Apple Developer 账号
- 创建 Service ID 和 Private Key

## 第三步：部署 Edge Functions

### 安装 Supabase CLI

```bash
# 如果还没安装
npm install -g supabase
```

### 部署 Chat Function

在项目根目录执行：

```bash
# 登录 Supabase
supabase login

# 链接到你的项目
supabase link --project-ref lzvwduadnunbtxqaqhkg

# 部署 chat function
supabase functions deploy chat

# 如果你有 AWS Bedrock 的凭据，设置环境变量
supabase secrets set AWS_ACCESS_KEY_ID=your_key AWS_SECRET_ACCESS_KEY=your_secret AWS_REGION=us-east-1
```

## 第四步：测试应用

1. 启动开发服务器：
```bash
cd /home/ubuntu/jack/projects/efflux/efflux-ai
npm run dev
```

2. 访问 http://localhost:3000

3. 注册一个新账户

4. 你会看到 "No API keys configured for any provider" 的提示

## 第五步：配置 API Keys (管理员)

1. 修改 `app/(admin)/admin/layout.tsx` 文件
2. 在 `ADMIN_EMAILS` 数组中添加你的邮箱：
```typescript
const ADMIN_EMAILS = [
  'your-email@example.com'  // 替换成你的邮箱
];
```

3. 重新登录后访问 `/admin/api-keys`
4. 添加 AI Provider 的 API Keys

## 获取免费的 API Key 进行测试

### Google Gemini (推荐)
1. 访问 https://makersuite.google.com/app/apikey
2. 创建 API Key
3. 在管理面板中添加：
   - Provider: google
   - API Key: 你的 Gemini API Key

## 常见问题

### Q: SQL 执行失败？
- 检查是否有语法错误
- 尝试分段执行（先执行 CREATE EXTENSION，再执行其他）

### Q: Edge Function 部署失败？
- 确保已经安装并登录 Supabase CLI
- 检查是否有正确的项目权限

### Q: 无法访问管理页面？
- 确保已经在代码中添加了你的邮箱到 ADMIN_EMAILS
- 重新登录以刷新权限

## 下一步

完成以上步骤后，你的 Efflux AI 应该已经可以正常运行了！

1. 测试聊天功能
2. 尝试不同的 AI 模型
3. 查看使用统计
4. 准备部署到 Vercel

需要帮助？随时告诉我！