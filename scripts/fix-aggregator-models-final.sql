-- 修复 aggregator_models 表的 RLS 策略
-- 使用 JWT 中的信息而不是查询 auth.users 表

-- 1. 删除现有的有问题的策略
DROP POLICY IF EXISTS "aggregator_models_admin_all" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_select_authenticated" ON aggregator_models;

-- 2. 创建新的策略，使用 JWT 信息
-- 允许所有认证用户读取可用的模型
CREATE POLICY "aggregator_models_select" ON aggregator_models
    FOR SELECT 
    TO authenticated
    USING (is_available = true);

-- 允许管理员删除（使用 JWT 中的 raw_user_meta_data）
CREATE POLICY "aggregator_models_delete" ON aggregator_models
    FOR DELETE 
    TO authenticated
    USING (
        (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text = 'admin'
    );

-- 允许管理员插入
CREATE POLICY "aggregator_models_insert" ON aggregator_models
    FOR INSERT 
    TO authenticated
    WITH CHECK (
        (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text = 'admin'
    );

-- 允许管理员更新
CREATE POLICY "aggregator_models_update" ON aggregator_models
    FOR UPDATE 
    TO authenticated
    USING (
        (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text = 'admin'
    )
    WITH CHECK (
        (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text = 'admin'
    );

-- 3. 验证新策略
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'aggregator_models'
ORDER BY policyname;

-- 4. 为了确保你的用户有 admin 角色，运行这个更新
-- 请将 'YOUR_USER_ID' 替换为你的实际用户 ID
-- UPDATE auth.users 
-- SET raw_user_meta_data = jsonb_set(
--     COALESCE(raw_user_meta_data, '{}'::jsonb),
--     '{role}',
--     '"admin"'
-- )
-- WHERE id = 'YOUR_USER_ID';