-- 检查 Supabase Auth API 可能的问题

-- 1. 检查是否有重复的 email
SELECT email, COUNT(*) as count
FROM auth.users
GROUP BY email
HAVING COUNT(*) > 1;

-- 2. 检查最近失败的注册尝试（如果有记录的话）
SELECT 
    id,
    instance_id,
    email,
    created_at,
    raw_app_meta_data,
    CASE 
        WHEN email_confirmed_at IS NULL THEN 'NOT_CONFIRMED'
        ELSE 'CONFIRMED'
    END as email_status
FROM auth.users
WHERE created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC
LIMIT 10;

-- 3. 检查 instance_id 设置
SELECT DISTINCT instance_id 
FROM auth.users 
WHERE instance_id IS NOT NULL;

-- 4. 检查 Supabase 的系统表（如果存在）
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'auth'
AND table_name LIKE '%audit%' OR table_name LIKE '%log%'
ORDER BY table_name;

-- 5. 检查是否有 email 域名限制
SELECT *
FROM auth.users
WHERE email LIKE '%@example.com'
LIMIT 5;

-- 6. 创建一个测试来模拟 Auth API 的验证
CREATE OR REPLACE FUNCTION test_auth_validation()
RETURNS TABLE(test text, result text)
LANGUAGE plpgsql
AS $$
DECLARE
    test_email text;
BEGIN
    -- 测试1: 检查 email 格式验证
    test_email := 'test_' || gen_random_uuid() || '@example.com';
    IF test_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
        RETURN QUERY SELECT 'email_format'::text, 'VALID'::text;
    ELSE
        RETURN QUERY SELECT 'email_format'::text, 'INVALID'::text;
    END IF;
    
    -- 测试2: 检查是否有 auth.users 的约束
    RETURN QUERY
    SELECT 
        'constraints'::text,
        string_agg(conname, ', ')::text
    FROM pg_constraint
    WHERE conrelid = 'auth.users'::regclass
    AND contype = 'c';  -- CHECK constraints
    
    -- 测试3: 检查默认的 instance_id
    RETURN QUERY
    SELECT 
        'default_instance_id'::text,
        COALESCE(
            (SELECT setting FROM pg_settings WHERE name = 'app.settings.jwt.secret'),
            'NOT_SET'
        )::text;
END;
$$;

SELECT * FROM test_auth_validation();

-- 清理
DROP FUNCTION test_auth_validation();