-- 检查 jackwwg@gmail.com 的配额状态

-- 1. 检查用户基本信息
SELECT 
  'User Info' as section,
  u.id as user_id,
  u.email,
  u.created_at,
  ut.tier,
  ut.credits_balance
FROM auth.users u
LEFT JOIN user_tiers ut ON u.id = ut.user_id
WHERE u.email = 'jackwwg@gmail.com';

-- 2. 检查配额状态
SELECT 
  'Quota Status' as section,
  uq.*
FROM user_quotas uq
WHERE uq.user_id IN (
  SELECT id FROM auth.users WHERE email = 'jackwwg@gmail.com'
);

-- 3. 使用 RPC 函数检查配额状态
SELECT 
  'RPC Quota Status' as section,
  *
FROM get_user_quota_status((
  SELECT id FROM auth.users WHERE email = 'jackwwg@gmail.com'
));

-- 4. 检查最近的使用记录
SELECT 
  'Recent Usage' as section,
  ul.created_at,
  ul.model,
  ul.provider,
  ul.prompt_tokens,
  ul.completion_tokens,
  ul.total_tokens,
  ul.estimated_cost,
  ul.status
FROM usage_logs ul
WHERE ul.user_id IN (
  SELECT id FROM auth.users WHERE email = 'jackwwg@gmail.com'
)
ORDER BY ul.created_at DESC
LIMIT 10;