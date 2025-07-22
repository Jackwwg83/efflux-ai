-- 修复 jackwwg@gmail.com 的配额问题

-- 1. 查看用户当前状态
DO $$
DECLARE
  user_record RECORD;
  quota_record RECORD;
  tier_record RECORD;
BEGIN
  -- 获取用户信息
  SELECT id, email, created_at INTO user_record
  FROM auth.users 
  WHERE email = 'jackwwg@gmail.com';
  
  IF user_record.id IS NOT NULL THEN
    RAISE NOTICE 'User found: % (ID: %)', user_record.email, user_record.id;
    
    -- 检查配额记录
    SELECT * INTO quota_record
    FROM user_quotas
    WHERE user_id = user_record.id;
    
    IF quota_record IS NOT NULL THEN
      RAISE NOTICE 'Current quota: used_today=%, daily_reset=%', 
        quota_record.tokens_used_today, quota_record.last_reset_daily;
    ELSE
      RAISE NOTICE 'No quota record found';
    END IF;
    
    -- 检查用户等级
    SELECT * INTO tier_record
    FROM user_tiers
    WHERE user_id = user_record.id;
    
    IF tier_record IS NOT NULL THEN
      RAISE NOTICE 'User tier: %', tier_record.tier;
    ELSE
      RAISE NOTICE 'No tier record found - will create free tier';
    END IF;
    
  ELSE
    RAISE NOTICE 'User not found!';
  END IF;
END $$;

-- 2. 确保用户有正确的配额和等级记录（包含所有必需字段）
INSERT INTO user_tiers (user_id, tier, credits_balance, credits_limit, rate_limit)
SELECT id, 'free'::user_tier, 5000.00, 5000.00, 5
FROM auth.users
WHERE email = 'jackwwg@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET
  tier = EXCLUDED.tier,
  credits_balance = GREATEST(user_tiers.credits_balance, 5000.00),
  credits_limit = 5000.00,
  rate_limit = 5,
  updated_at = NOW();

-- 3. 重置配额记录
INSERT INTO user_quotas (
  user_id,
  tokens_used_today,
  tokens_used_month,
  requests_today,
  requests_month,
  cost_today,
  cost_month,
  last_reset_daily,
  last_reset_monthly,
  created_at,
  updated_at
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
  DATE_TRUNC('month', CURRENT_DATE),
  NOW(),
  NOW()
FROM auth.users
WHERE email = 'jackwwg@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET
  tokens_used_today = 0,
  requests_today = 0,
  cost_today = 0,
  last_reset_daily = CURRENT_DATE,
  updated_at = NOW();

-- 4. 测试 RPC 函数
DO $$
DECLARE
  user_id UUID;
  quota_result RECORD;
BEGIN
  SELECT id INTO user_id FROM auth.users WHERE email = 'jackwwg@gmail.com';
  
  IF user_id IS NOT NULL THEN
    -- 测试配额状态函数
    SELECT * INTO quota_result
    FROM get_user_quota_status(user_id);
    
    RAISE NOTICE 'Quota status: tokens_used=%, daily_limit=%, tier=%', 
      quota_result.tokens_used_today, quota_result.daily_limit, quota_result.tier;
  END IF;
END $$;

-- 5. 最终验证
SELECT 
  'Final Status' as section,
  u.email,
  ut.tier,
  uq.tokens_used_today,
  uq.last_reset_daily,
  CASE 
    WHEN ut.tier = 'free' THEN 5000
    WHEN ut.tier = 'pro' THEN 50000
    WHEN ut.tier = 'max' THEN 500000
    ELSE 5000
  END as daily_limit,
  ROUND((uq.tokens_used_today * 100.0 / CASE 
    WHEN ut.tier = 'free' THEN 5000
    WHEN ut.tier = 'pro' THEN 50000
    WHEN ut.tier = 'max' THEN 500000
    ELSE 5000
  END), 2) as percentage_used
FROM auth.users u
LEFT JOIN user_tiers ut ON u.id = ut.user_id
LEFT JOIN user_quotas uq ON u.id = uq.user_id
WHERE u.email = 'jackwwg@gmail.com';