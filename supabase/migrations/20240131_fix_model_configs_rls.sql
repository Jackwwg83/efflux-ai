-- 修复 model_configs 表的 RLS 策略，允许所有用户查看模型

-- 1. 为所有认证用户添加查看权限（可以看到所有激活的模型，不管tier）
CREATE POLICY "All users can view active models" ON model_configs
    FOR SELECT USING (
        -- 所有认证用户都可以查看所有激活的模型
        -- 前端会根据用户的tier来控制是否可以使用
        auth.uid() IS NOT NULL 
        AND is_active = true
    );

-- 2. 检查策略是否创建成功
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename = 'model_configs'
ORDER BY policyname;