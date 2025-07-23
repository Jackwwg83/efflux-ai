-- 全面诊断 RLS 权限问题

-- ========================================
-- 第1部分：理解 JWT 结构和内容
-- ========================================

-- 1.1 检查从应用端看到的 JWT 内容（需要在应用中执行，不是SQL Editor）
-- 这个查询模拟应用端的视角
DO $$
DECLARE
    jwt_content jsonb;
BEGIN
    -- 尝试获取 JWT 内容
    jwt_content := auth.jwt();
    RAISE NOTICE 'JWT Content: %', jwt_content;
    RAISE NOTICE 'JWT Keys: %', jsonb_object_keys(jwt_content);
END $$;

-- 1.2 查看你的用户在 auth.users 表中的完整数据
SELECT 
    id,
    email,
    role as auth_role,
    raw_user_meta_data,
    raw_app_meta_data,
    jsonb_pretty(raw_user_meta_data) as pretty_user_meta,
    jsonb_pretty(raw_app_meta_data) as pretty_app_meta
FROM auth.users
WHERE email = 'jackwwg@gmail.com';

-- ========================================
-- 第2部分：查看其他表是如何处理admin权限的
-- ========================================

-- 2.1 查看所有使用admin检查的RLS策略
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE (qual LIKE '%admin%' OR with_check LIKE '%admin%')
AND schemaname = 'public'
ORDER BY tablename, policyname;

-- 2.2 特别查看 api_key_pool 表的RLS策略（这个表的admin操作是正常的）
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'api_key_pool'
AND (qual LIKE '%admin%' OR with_check LIKE '%admin%');

-- ========================================
-- 第3部分：测试不同的角色检查方法
-- ========================================

-- 3.1 创建一个测试函数来检查各种角色获取方法
CREATE OR REPLACE FUNCTION test_role_methods()
RETURNS TABLE (
    method TEXT,
    result TEXT,
    is_admin BOOLEAN
) AS $$
BEGIN
    -- 方法1：从 raw_user_meta_data 获取
    RETURN QUERY
    SELECT 
        'auth.jwt()->raw_user_meta_data->role'::TEXT,
        (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::TEXT,
        ((auth.jwt() -> 'raw_user_meta_data' ->> 'role')::TEXT = 'admin');

    -- 方法2：从 user_metadata 获取
    RETURN QUERY
    SELECT 
        'auth.jwt()->user_metadata->role'::TEXT,
        (auth.jwt() -> 'user_metadata' ->> 'role')::TEXT,
        ((auth.jwt() -> 'user_metadata' ->> 'role')::TEXT = 'admin');

    -- 方法3：从 app_metadata 获取
    RETURN QUERY
    SELECT 
        'auth.jwt()->app_metadata->role'::TEXT,
        (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT,
        ((auth.jwt() -> 'app_metadata' ->> 'role')::TEXT = 'admin');

    -- 方法4：检查是否在特定的admin用户表中
    RETURN QUERY
    SELECT 
        'profiles.role'::TEXT,
        (SELECT role FROM profiles WHERE id = auth.uid())::TEXT,
        ((SELECT role FROM profiles WHERE id = auth.uid()) = 'admin');

    -- 方法5：直接检查用户ID是否匹配（硬编码admin用户）
    RETURN QUERY
    SELECT 
        'hardcoded admin check'::TEXT,
        CASE WHEN auth.uid() = '76443a23-7734-4500-9cd2-89d685eba7d3' THEN 'admin' ELSE 'user' END,
        (auth.uid() = '76443a23-7734-4500-9cd2-89d685eba7d3');
END;
$$ LANGUAGE plpgsql;

-- 执行测试
SELECT * FROM test_role_methods();

-- ========================================
-- 第4部分：查看 profiles 表的结构和数据
-- ========================================

-- 4.1 查看 profiles 表结构
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'profiles'
ORDER BY ordinal_position;

-- 4.2 查看你的 profile 数据
SELECT * FROM profiles WHERE id = '76443a23-7734-4500-9cd2-89d685eba7d3';

-- ========================================
-- 第5部分：检查 Supabase 的 auth 配置
-- ========================================

-- 5.1 查看所有的 auth 配置
SELECT * FROM auth.schema_migrations ORDER BY version DESC LIMIT 10;

-- 5.2 检查是否有自定义的 claims 或 hooks
SELECT 
    routine_name,
    routine_type,
    routine_definition
FROM information_schema.routines
WHERE routine_schema = 'auth'
AND routine_name LIKE '%claim%' OR routine_name LIKE '%jwt%' OR routine_name LIKE '%hook%';