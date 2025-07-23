-- 诊断 RLS 权限问题的查询脚本

-- 1. 查看当前用户信息和角色
SELECT 
    auth.uid() as user_id,
    auth.role() as current_role,
    auth.jwt() -> 'user_metadata' ->> 'role' as metadata_role,
    auth.jwt() -> 'user_metadata' as full_metadata,
    auth.jwt() -> 'raw_user_meta_data' ->> 'role' as raw_metadata_role,
    auth.jwt() -> 'raw_user_meta_data' as full_raw_metadata;

-- 2. 查看 aggregator_models 表的当前 RLS 策略
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'aggregator_models'
ORDER BY policyname;

-- 3. 查看 auth.users 表的结构（如果有权限）
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'auth' 
AND table_name = 'users'
ORDER BY ordinal_position;

-- 4. 测试是否能访问 auth.users 表
SELECT COUNT(*) as can_access_auth_users
FROM auth.users
WHERE id = auth.uid();

-- 5. 查看当前用户在 auth.users 表中的数据
SELECT 
    id,
    email,
    raw_user_meta_data->>'role' as role_in_metadata,
    raw_user_meta_data
FROM auth.users
WHERE id = auth.uid();

-- 6. 查看 aggregator_models 表的结构
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'aggregator_models'
ORDER BY ordinal_position;

-- 7. 查看是否有其他可能影响的触发器或函数
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND event_object_table = 'aggregator_models';