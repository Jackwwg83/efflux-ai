-- 修复 token 使用量追踪问题

-- 修复 update_user_usage 函数，确保正确处理每日配额重置
CREATE OR REPLACE FUNCTION update_user_usage(
  p_user_id UUID,
  p_tokens INTEGER,
  p_cost DECIMAL(10,6)
) RETURNS VOID AS $$
DECLARE
  v_last_reset_daily DATE;
  v_needs_reset BOOLEAN;
BEGIN
  -- 确保记录存在
  INSERT INTO user_quotas (
    user_id, 
    tokens_used_today, 
    tokens_used_month,
    requests_today,
    requests_month,
    cost_today,
    cost_month,
    last_reset_daily,
    last_reset_monthly
  )
  VALUES (
    p_user_id,
    0,
    0,
    0,
    0,
    0,
    0,
    CURRENT_DATE,
    DATE_TRUNC('month', CURRENT_DATE)
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  -- 获取上次重置日期
  SELECT last_reset_daily INTO v_last_reset_daily
  FROM user_quotas
  WHERE user_id = p_user_id;
  
  -- 检查是否需要重置
  v_needs_reset := (v_last_reset_daily IS NULL OR v_last_reset_daily < CURRENT_DATE);
  
  -- 更新使用量
  IF v_needs_reset THEN
    -- 需要重置，所以将今日使用量设为传入的值
    UPDATE user_quotas
    SET 
      tokens_used_today = p_tokens,
      tokens_used_month = tokens_used_month + p_tokens,
      requests_today = 1,
      requests_month = requests_month + 1,
      cost_today = p_cost,
      cost_month = cost_month + p_cost,
      last_reset_daily = CURRENT_DATE,
      updated_at = NOW()
    WHERE user_id = p_user_id;
  ELSE
    -- 不需要重置，累加使用量
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
  END IF;
  
  -- 同时更新 user_tiers 表的余额（如果使用预付费模式）
  UPDATE user_tiers
  SET 
    credits_balance = GREATEST(0, credits_balance - p_tokens),
    updated_at = NOW()
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- 添加一个函数来获取用户的实时配额状态（包含自动重置逻辑）
CREATE OR REPLACE FUNCTION get_user_quota_status(p_user_id UUID)
RETURNS TABLE (
  tokens_used_today BIGINT,
  tokens_used_month BIGINT,
  requests_today INTEGER,
  requests_month INTEGER,
  cost_today DECIMAL(10,6),
  cost_month DECIMAL(10,6),
  tier TEXT,
  daily_limit INTEGER
) AS $$
DECLARE
  v_last_reset_daily DATE;
  v_last_reset_monthly DATE;
  v_tier TEXT;
BEGIN
  -- 确保记录存在
  INSERT INTO user_quotas (
    user_id, 
    last_reset_daily,
    last_reset_monthly
  )
  VALUES (
    p_user_id,
    CURRENT_DATE,
    DATE_TRUNC('month', CURRENT_DATE)
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  -- 获取重置日期
  SELECT uq.last_reset_daily, uq.last_reset_monthly
  INTO v_last_reset_daily, v_last_reset_monthly
  FROM user_quotas uq
  WHERE uq.user_id = p_user_id;
  
  -- 如果需要重置每日配额
  IF v_last_reset_daily < CURRENT_DATE THEN
    UPDATE user_quotas
    SET 
      tokens_used_today = 0,
      requests_today = 0,
      cost_today = 0,
      last_reset_daily = CURRENT_DATE
    WHERE user_id = p_user_id;
  END IF;
  
  -- 如果需要重置每月配额
  IF v_last_reset_monthly < DATE_TRUNC('month', CURRENT_DATE) THEN
    UPDATE user_quotas
    SET 
      tokens_used_month = 0,
      requests_month = 0,
      cost_month = 0,
      last_reset_monthly = DATE_TRUNC('month', CURRENT_DATE)
    WHERE user_id = p_user_id;
  END IF;
  
  -- 获取用户层级
  SELECT COALESCE(ut.tier, 'free') INTO v_tier
  FROM user_tiers ut
  WHERE ut.user_id = p_user_id;
  
  -- 返回当前状态
  RETURN QUERY
  SELECT 
    uq.tokens_used_today,
    uq.tokens_used_month,
    uq.requests_today,
    uq.requests_month,
    uq.cost_today,
    uq.cost_month,
    COALESCE(v_tier, 'free') as tier,
    CASE COALESCE(v_tier, 'free')
      WHEN 'free' THEN 5000
      WHEN 'pro' THEN 50000
      WHEN 'max' THEN 500000
      ELSE 5000
    END as daily_limit
  FROM user_quotas uq
  WHERE uq.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- 给函数授权
GRANT EXECUTE ON FUNCTION update_user_usage(UUID, INTEGER, DECIMAL) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_user_quota_status(UUID) TO authenticated, service_role;

-- 为了确保现有用户有正确的配额记录，初始化所有用户的配额
INSERT INTO user_quotas (
  user_id,
  tokens_used_today,
  tokens_used_month,
  requests_today,
  requests_month,
  cost_today,
  cost_month,
  last_reset_daily,
  last_reset_monthly
)
SELECT 
  id,
  0,
  0,
  0,
  0,
  0,
  0,
  CURRENT_DATE,
  DATE_TRUNC('month', CURRENT_DATE)
FROM auth.users
ON CONFLICT (user_id) DO NOTHING;