-- 🔧 CRITICAL DATABASE SCHEMA FIX
-- 解决多重表定义冲突和数据完整性问题

-- =====================================
-- STEP 1: 检查当前表结构
-- =====================================

DO $$
BEGIN
  RAISE NOTICE '=== CURRENT DATABASE STATE ===';
  
  -- 检查 user_tiers 表结构
  PERFORM 1 FROM information_schema.tables 
  WHERE table_name = 'user_tiers' AND table_schema = 'public';
  
  IF FOUND THEN
    RAISE NOTICE 'user_tiers table exists';
  ELSE
    RAISE NOTICE 'user_tiers table MISSING';
  END IF;
  
  -- 检查 user_quotas 表结构  
  PERFORM 1 FROM information_schema.tables 
  WHERE table_name = 'user_quotas' AND table_schema = 'public';
  
  IF FOUND THEN
    RAISE NOTICE 'user_quotas table exists';
  ELSE  
    RAISE NOTICE 'user_quotas table MISSING';
  END IF;
END $$;

-- =====================================
-- STEP 2: 创建标准化的 user_tiers 表
-- =====================================

-- 备份现有数据（如果存在）
CREATE TEMP TABLE user_tiers_backup AS 
SELECT * FROM user_tiers WHERE 1=0; -- 仅结构，无数据

DO $$
BEGIN
  BEGIN
    INSERT INTO user_tiers_backup SELECT * FROM user_tiers;
    RAISE NOTICE 'Backed up % rows from user_tiers', (SELECT COUNT(*) FROM user_tiers_backup);
  EXCEPTION 
    WHEN others THEN
      RAISE NOTICE 'No existing user_tiers data to backup: %', SQLERRM;
  END;
END $$;

-- 删除冲突的表
DROP TABLE IF EXISTS user_tiers CASCADE;

-- 创建标准化的 user_tiers 表（用户等级实例）
CREATE TABLE user_tiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier user_tier DEFAULT 'free'::user_tier NOT NULL,
  credits_balance DECIMAL(10,2) DEFAULT 5000.00 NOT NULL CHECK (credits_balance >= 0),
  credits_limit DECIMAL(10,2) DEFAULT 5000.00 NOT NULL,  -- 🔧 添加默认值
  rate_limit INTEGER DEFAULT 5 NOT NULL,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================  
-- STEP 3: 创建或修复 user_quotas 表
-- =====================================

-- 删除旧的配额表（如果存在）
DROP TABLE IF EXISTS user_quotas CASCADE;

-- 创建现代化配额表
CREATE TABLE user_quotas (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tokens_used_today BIGINT DEFAULT 0 NOT NULL,
  tokens_used_month BIGINT DEFAULT 0 NOT NULL,
  requests_today INTEGER DEFAULT 0 NOT NULL,
  requests_month INTEGER DEFAULT 0 NOT NULL,
  cost_today DECIMAL(10,6) DEFAULT 0.00 NOT NULL,
  cost_month DECIMAL(10,6) DEFAULT 0.00 NOT NULL,
  last_reset_daily TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_DATE,
  last_reset_monthly TIMESTAMP WITH TIME ZONE DEFAULT DATE_TRUNC('month', CURRENT_DATE),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================
-- STEP 4: 创建层级定义表（配置表）
-- =====================================

CREATE TABLE IF NOT EXISTS tier_definitions (
  tier user_tier PRIMARY KEY,
  display_name TEXT NOT NULL,
  daily_token_limit INTEGER NOT NULL,
  monthly_token_limit INTEGER NOT NULL,
  credits_per_month DECIMAL(10,2) DEFAULT 0,
  rate_limit_per_minute INTEGER DEFAULT 60,
  price_per_month DECIMAL(10,2) DEFAULT 0.00
);

-- 插入标准层级定义
INSERT INTO tier_definitions (tier, display_name, daily_token_limit, monthly_token_limit, credits_per_month, rate_limit_per_minute, price_per_month) 
VALUES
  ('free'::user_tier, 'Free', 5000, 150000, 5000, 5, 0.00),
  ('pro'::user_tier, 'Pro', 50000, 1500000, 50000, 60, 29.99),
  ('max'::user_tier, 'Max', 500000, 15000000, 500000, 300, 99.99)
ON CONFLICT (tier) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  daily_token_limit = EXCLUDED.daily_token_limit,
  monthly_token_limit = EXCLUDED.monthly_token_limit,
  credits_per_month = EXCLUDED.credits_per_month,
  rate_limit_per_minute = EXCLUDED.rate_limit_per_minute,
  price_per_month = EXCLUDED.price_per_month;

-- =====================================
-- STEP 5: 为所有用户创建记录
-- =====================================

-- 为 jackwwg@gmail.com 创建用户等级记录
INSERT INTO user_tiers (user_id, tier, credits_balance, credits_limit, rate_limit)
SELECT 
  id, 
  'free'::user_tier, 
  5000.00, 
  5000.00, 
  5
FROM auth.users 
WHERE email = 'jackwwg@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET
  tier = EXCLUDED.tier,
  credits_balance = GREATEST(user_tiers.credits_balance, EXCLUDED.credits_balance),
  credits_limit = EXCLUDED.credits_limit,
  rate_limit = EXCLUDED.rate_limit,
  updated_at = NOW();

-- 为所有用户创建配额记录
INSERT INTO user_quotas (
  user_id,
  tokens_used_today,
  tokens_used_month,
  requests_today,
  requests_month,
  cost_today,
  cost_month
)
SELECT 
  id,
  0,
  0, 
  0,
  0,
  0.00,
  0.00
FROM auth.users
ON CONFLICT (user_id) DO UPDATE SET
  tokens_used_today = 0,  -- 重置每日使用量
  requests_today = 0,
  cost_today = 0.00,
  last_reset_daily = CURRENT_DATE,
  updated_at = NOW();

-- =====================================
-- STEP 6: 重建 RLS 策略
-- =====================================

ALTER TABLE user_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE tier_definitions ENABLE ROW LEVEL SECURITY;

-- user_tiers 策略
DROP POLICY IF EXISTS "Users can view own tier" ON user_tiers;
CREATE POLICY "Users can view own tier" ON user_tiers
  FOR SELECT USING (auth.uid() = user_id);

-- user_quotas 策略  
DROP POLICY IF EXISTS "Users can view own quotas" ON user_quotas;
CREATE POLICY "Users can view own quotas" ON user_quotas
  FOR SELECT USING (auth.uid() = user_id);

-- tier_definitions 策略（所有人可读）
DROP POLICY IF EXISTS "Everyone can read tier definitions" ON tier_definitions;
CREATE POLICY "Everyone can read tier definitions" ON tier_definitions
  FOR SELECT USING (true);

-- =====================================
-- STEP 7: 重建关键函数
-- =====================================

-- 修复 get_user_quota_status 函数
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
  v_tier user_tier;
BEGIN
  -- 获取用户等级
  SELECT ut.tier INTO v_tier
  FROM user_tiers ut
  WHERE ut.user_id = p_user_id;
  
  IF v_tier IS NULL THEN
    v_tier := 'free'::user_tier;
  END IF;
  
  -- 确保配额记录存在
  INSERT INTO user_quotas (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  -- 重置每日配额（如果需要）
  UPDATE user_quotas
  SET 
    tokens_used_today = 0,
    requests_today = 0,
    cost_today = 0.00,
    last_reset_daily = CURRENT_DATE
  WHERE user_id = p_user_id
    AND last_reset_daily < CURRENT_DATE;
  
  -- 返回配额状态
  RETURN QUERY
  SELECT 
    uq.tokens_used_today,
    uq.tokens_used_month,
    uq.requests_today,
    uq.requests_month,
    uq.cost_today,
    uq.cost_month,
    v_tier::TEXT as tier,
    td.daily_token_limit as daily_limit
  FROM user_quotas uq
  CROSS JOIN tier_definitions td
  WHERE uq.user_id = p_user_id
    AND td.tier = v_tier;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================
-- STEP 8: 权限设置
-- =====================================

GRANT SELECT ON user_tiers TO authenticated;
GRANT SELECT ON user_quotas TO authenticated;
GRANT SELECT ON tier_definitions TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_user_quota_status(UUID) TO authenticated, anon;

-- =====================================
-- STEP 9: 验证修复
-- =====================================

DO $$
DECLARE
  user_record RECORD;
  quota_record RECORD;
BEGIN
  RAISE NOTICE '=== VERIFICATION ===';
  
  -- 检查 jackwwg@gmail.com 的记录
  SELECT 
    u.email,
    ut.tier,
    ut.credits_balance,
    ut.credits_limit,
    uq.tokens_used_today,
    td.daily_token_limit
  INTO user_record
  FROM auth.users u
  LEFT JOIN user_tiers ut ON u.id = ut.user_id
  LEFT JOIN user_quotas uq ON u.id = uq.user_id
  LEFT JOIN tier_definitions td ON ut.tier = td.tier
  WHERE u.email = 'jackwwg@gmail.com';
  
  IF user_record.email IS NOT NULL THEN
    RAISE NOTICE 'User: %, Tier: %, Balance: %, Limit: %, Used Today: %, Daily Limit: %',
      user_record.email,
      user_record.tier,
      user_record.credits_balance,
      user_record.credits_limit,
      user_record.tokens_used_today,
      user_record.daily_token_limit;
  ELSE
    RAISE NOTICE 'User record not found!';
  END IF;
  
  -- 测试配额函数
  SELECT * INTO quota_record
  FROM get_user_quota_status((SELECT id FROM auth.users WHERE email = 'jackwwg@gmail.com'));
  
  IF quota_record IS NOT NULL THEN
    RAISE NOTICE 'Quota function works: tier=%, daily_limit=%, tokens_used=%',
      quota_record.tier,
      quota_record.daily_limit,
      quota_record.tokens_used_today;
  ELSE
    RAISE NOTICE 'Quota function failed!';
  END IF;
END $$;

RAISE NOTICE '=== DATABASE SCHEMA REPAIR COMPLETED ===';
RAISE NOTICE 'Please refresh your application and test the quota system.';