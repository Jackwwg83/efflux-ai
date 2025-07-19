-- 查询新用户 kisslight@163.com

-- 1. 在 auth.users 中查找
SELECT 
    id,
    email,
    created_at,
    email_confirmed_at,
    last_sign_in_at,
    CASE 
        WHEN email_confirmed_at IS NOT NULL THEN 'CONFIRMED'
        ELSE 'PENDING_CONFIRMATION'
    END as email_status
FROM auth.users
WHERE email = 'kisslight@163.com';

-- 2. 检查相关表是否都有记录
WITH user_info AS (
    SELECT id FROM auth.users WHERE email = 'kisslight@163.com'
)
SELECT 
    'auth.users' as table_name,
    EXISTS(SELECT 1 FROM auth.users WHERE email = 'kisslight@163.com') as has_record
UNION ALL
SELECT 
    'profiles' as table_name,
    EXISTS(SELECT 1 FROM profiles WHERE id IN (SELECT id FROM user_info)) as has_record
UNION ALL
SELECT 
    'user_tiers' as table_name,
    EXISTS(SELECT 1 FROM user_tiers WHERE user_id IN (SELECT id FROM user_info)) as has_record
UNION ALL
SELECT 
    'user_quotas' as table_name,
    EXISTS(SELECT 1 FROM user_quotas WHERE user_id IN (SELECT id FROM user_info)) as has_record
UNION ALL
SELECT 
    'users' as table_name,
    EXISTS(SELECT 1 FROM users WHERE id IN (SELECT id FROM user_info)) as has_record;

-- 3. 如果用户存在，查看详细信息
SELECT 
    au.id,
    au.email,
    au.created_at as auth_created,
    p.full_name,
    ut.tier,
    ut.credits_balance,
    ut.credits_limit,
    uq.tokens_used_today,
    uq.requests_today
FROM auth.users au
LEFT JOIN profiles p ON p.id = au.id
LEFT JOIN user_tiers ut ON ut.user_id = au.id
LEFT JOIN user_quotas uq ON uq.user_id = au.id
WHERE au.email = 'kisslight@163.com';