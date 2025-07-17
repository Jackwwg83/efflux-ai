-- API Key 池表（支持负载均衡和轮换）
CREATE TABLE IF NOT EXISTS api_key_pool (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL CHECK (provider IN ('openai', 'anthropic', 'google', 'bedrock')),
  api_key TEXT NOT NULL,
  name TEXT, -- 便于识别的名称，如 "OpenAI Key 1"
  is_active BOOLEAN DEFAULT true,
  rate_limit_remaining INTEGER DEFAULT 10000,
  rate_limit_reset_at TIMESTAMP WITH TIME ZONE,
  last_used_at TIMESTAMP WITH TIME ZONE,
  error_count INTEGER DEFAULT 0,
  consecutive_errors INTEGER DEFAULT 0, -- 连续错误次数
  total_requests BIGINT DEFAULT 0,
  total_tokens_used BIGINT DEFAULT 0,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(provider, name)
);

-- 详细的使用记录（增强版）
DROP TABLE IF EXISTS usage_logs;
CREATE TABLE usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  model TEXT NOT NULL,
  provider TEXT NOT NULL,
  api_key_id UUID REFERENCES api_key_pool(id),
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  estimated_cost DECIMAL(10,6) DEFAULT 0,
  latency_ms INTEGER,
  status TEXT DEFAULT 'success', -- success, error, timeout
  error_message TEXT,
  request_payload JSONB, -- 存储请求参数
  response_metadata JSONB, -- 存储响应元数据
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 用户配额表（更精确的追踪）
CREATE TABLE IF NOT EXISTS user_quotas (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tokens_used_today BIGINT DEFAULT 0,
  tokens_used_month BIGINT DEFAULT 0,
  requests_today INTEGER DEFAULT 0,
  requests_month INTEGER DEFAULT 0,
  cost_today DECIMAL(10,6) DEFAULT 0,
  cost_month DECIMAL(10,6) DEFAULT 0,
  last_reset_daily TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_DATE,
  last_reset_monthly TIMESTAMP WITH TIME ZONE DEFAULT DATE_TRUNC('month', CURRENT_DATE),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 模型配置（更新）
ALTER TABLE model_configs 
ADD COLUMN IF NOT EXISTS provider_model_id TEXT, -- Provider 的实际模型 ID
ADD COLUMN IF NOT EXISTS supports_streaming BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS supports_functions BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS default_temperature DECIMAL(2,1) DEFAULT 0.7;

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_api_key_pool_provider_active ON api_key_pool(provider, is_active);
CREATE INDEX IF NOT EXISTS idx_api_key_pool_last_used ON api_key_pool(last_used_at);
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_created ON usage_logs(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_user_quotas_user_id ON user_quotas(user_id);

-- 获取可用的 API Key（带负载均衡）
CREATE OR REPLACE FUNCTION get_available_api_key(p_provider TEXT)
RETURNS TABLE(
  id UUID,
  provider TEXT,
  api_key TEXT
) AS $$
BEGIN
  -- 先尝试获取一个可用的 key
  RETURN QUERY
  WITH selected_key AS (
    SELECT 
      akp.id,
      akp.provider,
      akp.api_key
    FROM api_key_pool akp
    WHERE akp.provider = p_provider
      AND akp.is_active = true
      AND akp.consecutive_errors < 5 -- 连续错误少于5次
      AND (akp.rate_limit_remaining > 100 OR akp.rate_limit_reset_at < NOW())
    ORDER BY 
      akp.last_used_at ASC NULLS FIRST,
      akp.total_requests ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  SELECT * FROM selected_key;
  
  -- 如果找到了 key，更新其使用时间
  IF FOUND THEN
    UPDATE api_key_pool
    SET 
      last_used_at = NOW(),
      total_requests = total_requests + 1
    WHERE api_key_pool.id = (SELECT id FROM selected_key);
  END IF;
END;
$$ LANGUAGE plpgsql;

-- 检查并更新用户配额
CREATE OR REPLACE FUNCTION check_and_update_user_quota(
  p_user_id UUID,
  p_model TEXT,
  p_estimated_tokens INTEGER DEFAULT 0
)
RETURNS TABLE(
  can_use BOOLEAN,
  daily_limit INTEGER,
  used_today INTEGER,
  remaining INTEGER
) AS $$
DECLARE
  v_tier user_tier;
  v_daily_limit INTEGER;
  v_used_today INTEGER;
  v_model_config RECORD;
BEGIN
  -- 获取用户等级
  SELECT ut.tier INTO v_tier
  FROM user_tiers ut
  WHERE ut.user_id = p_user_id;
  
  IF v_tier IS NULL THEN
    v_tier := 'free';
  END IF;
  
  -- 获取模型配置
  SELECT * INTO v_model_config
  FROM model_configs
  WHERE model = p_model AND is_active = true;
  
  -- 检查用户等级是否可以使用该模型
  IF v_model_config.tier_required IS NOT NULL THEN
    CASE v_tier
      WHEN 'free' THEN
        IF v_model_config.tier_required IN ('pro', 'max') THEN
          RETURN QUERY SELECT false, 0, 0, 0;
          RETURN;
        END IF;
      WHEN 'pro' THEN
        IF v_model_config.tier_required = 'max' THEN
          RETURN QUERY SELECT false, 0, 0, 0;
          RETURN;
        END IF;
    END CASE;
  END IF;
  
  -- 根据等级设置每日限制
  v_daily_limit := CASE v_tier
    WHEN 'free' THEN 5000
    WHEN 'pro' THEN 50000
    WHEN 'max' THEN 500000
    ELSE 5000
  END;
  
  -- 确保用户配额记录存在
  INSERT INTO user_quotas (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  -- 检查是否需要重置每日配额
  UPDATE user_quotas
  SET 
    tokens_used_today = 0,
    requests_today = 0,
    cost_today = 0,
    last_reset_daily = CURRENT_DATE
  WHERE user_id = p_user_id
    AND last_reset_daily < CURRENT_DATE;
  
  -- 获取今日使用量
  SELECT tokens_used_today INTO v_used_today
  FROM user_quotas
  WHERE user_id = p_user_id;
  
  -- 返回结果
  RETURN QUERY
  SELECT 
    (v_used_today + p_estimated_tokens) <= v_daily_limit,
    v_daily_limit,
    v_used_today::INTEGER,
    (v_daily_limit - v_used_today)::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- 记录 API Key 错误
CREATE OR REPLACE FUNCTION record_api_key_error(
  p_api_key_id UUID,
  p_error_message TEXT
) RETURNS VOID AS $$
BEGIN
  UPDATE api_key_pool
  SET 
    error_count = error_count + 1,
    consecutive_errors = consecutive_errors + 1,
    updated_at = NOW(),
    -- 如果连续错误超过10次，自动禁用
    is_active = CASE 
      WHEN consecutive_errors >= 9 THEN false 
      ELSE is_active 
    END
  WHERE id = p_api_key_id;
END;
$$ LANGUAGE plpgsql;

-- 记录 API Key 成功
CREATE OR REPLACE FUNCTION record_api_key_success(
  p_api_key_id UUID,
  p_tokens_used INTEGER DEFAULT 0
) RETURNS VOID AS $$
BEGIN
  UPDATE api_key_pool
  SET 
    consecutive_errors = 0, -- 重置连续错误计数
    total_tokens_used = total_tokens_used + p_tokens_used,
    updated_at = NOW()
  WHERE id = p_api_key_id;
END;
$$ LANGUAGE plpgsql;

-- 更新用户使用量
CREATE OR REPLACE FUNCTION update_user_usage(
  p_user_id UUID,
  p_tokens INTEGER,
  p_cost DECIMAL(10,6)
) RETURNS VOID AS $$
BEGIN
  -- 确保记录存在
  INSERT INTO user_quotas (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  -- 更新使用量
  UPDATE user_quotas
  SET 
    tokens_used_today = tokens_used_today + p_tokens,
    tokens_used_month = tokens_used_month + p_tokens,
    requests_today = requests_today + 1,
    requests_month = requests_month + 1,
    cost_today = cost_today + p_cost,
    cost_month = cost_month + p_cost,
    updated_at = NOW()
  WHERE user_id = p_user_id;
  
  -- 同时更新 user_tiers 表的余额（如果使用预付费模式）
  UPDATE user_tiers
  SET 
    credits_balance = GREATEST(0, credits_balance - p_tokens),
    updated_at = NOW()
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- 迁移现有的 API Keys 到新的池表
INSERT INTO api_key_pool (provider, api_key, name, created_by)
SELECT 
  provider, 
  api_key, 
  provider || ' Key ' || ROW_NUMBER() OVER (PARTITION BY provider ORDER BY created_at),
  created_by
FROM api_keys
WHERE is_active = true
ON CONFLICT DO NOTHING;

-- 为现有用户创建配额记录
INSERT INTO user_quotas (user_id)
SELECT id FROM auth.users
ON CONFLICT DO NOTHING;

-- Row Level Security
ALTER TABLE api_key_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quotas ENABLE ROW LEVEL SECURITY;

-- 只有管理员可以查看和修改 API Key 池
CREATE POLICY "Admin can manage api_key_pool" ON api_key_pool
  FOR ALL USING (
    auth.uid() IN (
      SELECT id FROM auth.users 
      WHERE email IN ('admin@efflux.ai', 'jackwwg@gmail.com')
    )
  );

-- 用户只能查看自己的配额
CREATE POLICY "Users can view own quota" ON user_quotas
  FOR SELECT USING (auth.uid() = user_id);

-- 系统可以更新所有用户的配额（通过 service role）
CREATE POLICY "System can update quotas" ON user_quotas
  FOR UPDATE USING (true);

-- 添加一些测试数据（可选）
-- INSERT INTO model_configs (provider, model, provider_model_id, display_name, input_price, output_price, max_tokens, context_window, tier_required)
-- VALUES 
-- ('openai', 'gpt-4-turbo', 'gpt-4-turbo-preview', 'GPT-4 Turbo', 10, 30, 4096, 128000, 'pro'),
-- ('openai', 'gpt-3.5-turbo', 'gpt-3.5-turbo', 'GPT-3.5 Turbo', 0.5, 1.5, 4096, 16384, 'free')
-- ON CONFLICT (provider, model) DO UPDATE
-- SET provider_model_id = EXCLUDED.provider_model_id;