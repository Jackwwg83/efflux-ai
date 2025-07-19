-- 诊断 Auth 服务问题

-- 1. 检查 auth schema 的所有触发器
SELECT 
    t.tgname as trigger_name,
    CASE 
        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END as timing,
    CASE
        WHEN t.tgtype & 4 = 4 THEN 'INSERT'
        WHEN t.tgtype & 8 = 8 THEN 'DELETE'
        WHEN t.tgtype & 16 = 16 THEN 'UPDATE'
    END as event,
    p.proname as function_name,
    t.tgenabled as enabled
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' 
AND c.relname = 'users'
AND t.tgname NOT LIKE 'RI_ConstraintTrigger%'
ORDER BY t.tgname;

-- 2. 检查是否有其他 BEFORE INSERT 触发器可能阻止插入
SELECT 
    t.tgname,
    p.proname,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgrelid = 'auth.users'::regclass
AND t.tgtype & 2 = 2  -- BEFORE
AND t.tgtype & 4 = 4  -- INSERT
AND t.tgname NOT LIKE 'RI_ConstraintTrigger%';

-- 3. 检查 Supabase 特定的设置
SELECT 
    name,
    setting,
    category
FROM pg_settings
WHERE name IN (
    'row_security',
    'check_function_bodies',
    'default_transaction_isolation'
);

-- 4. 检查 auth.users 表是否有 RLS 策略
SELECT
    pol.polname as policy_name,
    pol.polcmd as command,
    CASE pol.polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        ELSE 'ALL'
    END as operation,
    pol.polroles::regrole[] as roles,
    pg_get_expr(pol.polqual, pol.polrelid) as using_expression,
    pg_get_expr(pol.polwithcheck, pol.polrelid) as with_check_expression
FROM pg_policy pol
WHERE pol.polrelid = 'auth.users'::regclass;

-- 5. 创建一个简单的测试来验证 Auth API 的行为
CREATE OR REPLACE FUNCTION test_auth_api_behavior()
RETURNS TABLE(test text, result text)
LANGUAGE plpgsql
AS $$
DECLARE
    test_email text := 'api_test_' || gen_random_uuid()::text || '@example.com';
BEGIN
    -- 测试1: 检查 email 唯一性约束
    RETURN QUERY 
    SELECT 'unique_email_check'::text, 
           CASE 
               WHEN EXISTS (SELECT 1 FROM auth.users WHERE email = test_email) 
               THEN 'EMAIL_EXISTS' 
               ELSE 'EMAIL_AVAILABLE' 
           END::text;
    
    -- 测试2: 检查是否需要 instance_id
    RETURN QUERY
    SELECT 'instance_id_required'::text,
           CASE
               WHEN EXISTS (
                   SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'auth' 
                   AND table_name = 'users' 
                   AND column_name = 'instance_id'
                   AND is_nullable = 'NO'
                   AND column_default IS NULL
               )
               THEN 'YES'
               ELSE 'NO'
           END::text;
    
    -- 测试3: 检查默认值
    RETURN QUERY
    SELECT 'has_defaults'::text,
           (SELECT COUNT(*)::text FROM information_schema.columns 
            WHERE table_schema = 'auth' 
            AND table_name = 'users' 
            AND column_default IS NOT NULL);
            
    -- 测试4: 尝试最小化插入
    BEGIN
        INSERT INTO auth.users (id, email)
        VALUES (gen_random_uuid(), test_email);
        
        RETURN QUERY SELECT 'minimal_insert'::text, 'SUCCESS'::text;
        
        -- 立即删除
        DELETE FROM auth.users WHERE email = test_email;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'minimal_insert'::text, SQLERRM::text;
    END;
END;
$$;

SELECT * FROM test_auth_api_behavior();

-- 6. 最重要的：检查 Supabase Auth 的内部函数
-- 查找可能影响注册的函数
SELECT 
    p.proname as function_name,
    n.nspname as schema_name,
    obj_description(p.oid, 'pg_proc') as description
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'auth'
AND p.proname LIKE '%signup%' OR p.proname LIKE '%user%'
ORDER BY n.nspname, p.proname
LIMIT 20;

-- 清理
DROP FUNCTION IF EXISTS test_auth_api_behavior();