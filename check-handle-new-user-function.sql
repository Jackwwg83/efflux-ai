-- 查看 handle_new_user 函数的定义
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'handle_new_user';

-- 查看 create_user_from_profile 函数的定义
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'create_user_from_profile';

-- 检查最近创建的用户是否有相关记录
SELECT 
    au.id,
    au.email,
    au.created_at,
    p.id as profile_id,
    u.id as user_id,
    ut.user_id as user_tier_id,
    uq.user_id as user_quota_id
FROM auth.users au
LEFT JOIN profiles p ON p.id = au.id
LEFT JOIN users u ON u.id = au.id
LEFT JOIN user_tiers ut ON ut.user_id = au.id
LEFT JOIN user_quotas uq ON uq.user_id = au.id
ORDER BY au.created_at DESC
LIMIT 5;

-- 查看触发器的详细信息
SELECT 
    tgname,
    tgtype,
    tgenabled,
    tgisinternal
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';