-- 重置特定用户的配额（用于测试）
-- 将 jackwwg@gmail.com 的配额重置为 0

-- 首先查看用户的当前配额
SELECT 
  u.email,
  uq.*,
  ut.tier
FROM auth.users u
LEFT JOIN user_quotas uq ON u.id = uq.user_id
LEFT JOIN user_tiers ut ON u.id = ut.user_id
WHERE u.email = 'jackwwg@gmail.com';

-- 重置用户的每日配额
UPDATE user_quotas
SET 
  tokens_used_today = 0,
  requests_today = 0,
  cost_today = 0,
  last_reset_daily = CURRENT_DATE,
  updated_at = NOW()
WHERE user_id IN (
  SELECT id FROM auth.users WHERE email = 'jackwwg@gmail.com'
);

-- 如果用户没有配额记录，创建一个
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
WHERE email = 'jackwwg@gmail.com'
ON CONFLICT (user_id) DO NOTHING;

-- 再次查看更新后的配额
SELECT 
  u.email,
  uq.*,
  ut.tier
FROM auth.users u
LEFT JOIN user_quotas uq ON u.id = uq.user_id
LEFT JOIN user_tiers ut ON u.id = ut.user_id
WHERE u.email = 'jackwwg@gmail.com';