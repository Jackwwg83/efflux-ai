-- 完全重建 aggregator_models 表的 RLS 策略
-- 错误提示 "permission denied for table users" 可能是因为策略中引用了 auth.users 表

-- 1. 先禁用 RLS 来测试
ALTER TABLE aggregator_models DISABLE ROW LEVEL SECURITY;

-- 2. 删除所有现有策略
DROP POLICY IF EXISTS "aggregator_models_select_all" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_admin_write" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_select_authenticated" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_admin_all" ON aggregator_models;

-- 3. 重新启用 RLS
ALTER TABLE aggregator_models ENABLE ROW LEVEL SECURITY;

-- 4. 创建简化的策略，避免直接查询 auth.users 表
-- 允许所有认证用户读取
CREATE POLICY "aggregator_models_read" ON aggregator_models
    FOR SELECT 
    TO authenticated
    USING (true);

-- 允许管理员删除（使用 auth.jwt() 函数检查角色）
CREATE POLICY "aggregator_models_delete" ON aggregator_models
    FOR DELETE 
    TO authenticated
    USING (
        (auth.jwt() -> 'user_metadata' ->> 'role')::text = 'admin'
    );

-- 允许管理员插入
CREATE POLICY "aggregator_models_insert" ON aggregator_models
    FOR INSERT 
    TO authenticated
    WITH CHECK (
        (auth.jwt() -> 'user_metadata' ->> 'role')::text = 'admin'
    );

-- 允许管理员更新
CREATE POLICY "aggregator_models_update" ON aggregator_models
    FOR UPDATE 
    TO authenticated
    USING (
        (auth.jwt() -> 'user_metadata' ->> 'role')::text = 'admin'
    )
    WITH CHECK (
        (auth.jwt() -> 'user_metadata' ->> 'role')::text = 'admin'
    );

-- 5. 验证策略
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
WHERE tablename = 'aggregator_models';

-- 6. 测试当前用户的角色
SELECT 
    auth.uid() as user_id,
    auth.jwt() -> 'user_metadata' ->> 'role' as role,
    auth.jwt() -> 'user_metadata' as full_metadata;