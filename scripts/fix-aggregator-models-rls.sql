-- 修复 aggregator_models 表的 RLS 策略
-- 错误显示 "permission denied for table users"，这说明 RLS 策略有问题

-- 1. 确保 RLS 已启用
ALTER TABLE aggregator_models ENABLE ROW LEVEL SECURITY;

-- 2. 删除现有的策略
DROP POLICY IF EXISTS "aggregator_models_select_all" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_admin_write" ON aggregator_models;

-- 3. 创建新的策略
-- 允许所有认证用户读取可用的模型
CREATE POLICY "aggregator_models_select_authenticated" ON aggregator_models
    FOR SELECT TO authenticated
    USING (is_available = true);

-- 允许管理员进行所有操作
CREATE POLICY "aggregator_models_admin_all" ON aggregator_models
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- 4. 验证策略
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

-- 5. 测试：尝试查询表（应该成功）
SELECT COUNT(*) FROM aggregator_models;