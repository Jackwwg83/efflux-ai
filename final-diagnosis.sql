-- 最终诊断：检查 Auth 服务配置

-- 1. 检查 audit_log_entries 是否有最近的失败记录
SELECT 
    id,
    instance_id,
    ip_address,
    payload->>'actor_id' as actor_id,
    payload->>'actor_username' as actor_username,
    payload->>'action' as action,
    payload->>'type' as type,
    payload->'traits'->>'provider' as provider,
    created_at
FROM auth.audit_log_entries
WHERE created_at > NOW() - INTERVAL '1 hour'
AND (
    payload->>'action' LIKE '%signup%' 
    OR payload->>'action' LIKE '%register%'
    OR payload->>'type' LIKE '%signup%'
)
ORDER BY created_at DESC
LIMIT 10;

-- 2. 检查 instance 配置
SELECT *
FROM auth.instances
LIMIT 1;

-- 3. 检查必需字段和默认值
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default,
    CASE 
        WHEN is_nullable = 'NO' AND column_default IS NULL THEN 'REQUIRED'
        ELSE 'OPTIONAL'
    END as field_status
FROM information_schema.columns
WHERE table_schema = 'auth' 
AND table_name = 'users'
AND column_name IN ('id', 'email', 'instance_id', 'aud', 'role')
ORDER BY ordinal_position;

-- 4. 测试 Supabase 的内部函数是否存在
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'auth'
AND (
    routine_name LIKE '%signup%' 
    OR routine_name LIKE '%register%'
    OR routine_name LIKE '%create_user%'
)
LIMIT 10;

-- 5. 检查最近的成功用户创建
SELECT 
    id,
    email,
    instance_id,
    created_at,
    EXTRACT(EPOCH FROM (NOW() - created_at))/3600 as hours_ago
FROM auth.users
WHERE email NOT LIKE '%test%'
ORDER BY created_at DESC
LIMIT 5;