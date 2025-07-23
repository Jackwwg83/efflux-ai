-- 基于 Supabase 最佳实践的 Admin 角色解决方案

-- ========================================
-- 方案1：使用 profiles 表存储角色（推荐）
-- ========================================

-- 1.1 确保 profiles 表有 role 字段
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user' 
CHECK (role IN ('user', 'admin', 'moderator'));

-- 1.2 更新你的 profile 为 admin
UPDATE profiles 
SET role = 'admin' 
WHERE id = '76443a23-7734-4500-9cd2-89d685eba7d3';

-- 1.3 创建一个辅助函数来检查是否是admin
CREATE OR REPLACE FUNCTION auth.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM public.profiles 
        WHERE id = auth.uid() 
        AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1.4 更新 aggregator_models 的 RLS 策略使用 profiles 表
DROP POLICY IF EXISTS "aggregator_models_delete" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_insert" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_update" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_select" ON aggregator_models;

-- 重新创建策略
CREATE POLICY "aggregator_models_select" ON aggregator_models
    FOR SELECT TO authenticated
    USING (is_available = true);

CREATE POLICY "aggregator_models_insert" ON aggregator_models
    FOR INSERT TO authenticated
    WITH CHECK (auth.is_admin());

CREATE POLICY "aggregator_models_update" ON aggregator_models
    FOR UPDATE TO authenticated
    USING (auth.is_admin())
    WITH CHECK (auth.is_admin());

CREATE POLICY "aggregator_models_delete" ON aggregator_models
    FOR DELETE TO authenticated
    USING (auth.is_admin());

-- ========================================
-- 方案2：使用自定义 JWT claims（需要 Supabase 函数）
-- ========================================

-- 2.1 创建一个 hook 函数在用户登录时添加角色到 JWT
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb AS $$
DECLARE
    claims jsonb;
    user_role text;
BEGIN
    -- 获取用户角色
    SELECT role INTO user_role
    FROM public.profiles
    WHERE id = (event->>'user_id')::uuid;

    -- 构建自定义 claims
    claims := event -> 'claims';
    
    -- 添加角色到 claims
    IF user_role IS NOT NULL THEN
        claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
    END IF;

    -- 返回修改后的 event
    RETURN jsonb_set(event, '{claims}', claims);
END;
$$ LANGUAGE plpgsql;

-- 2.2 注册 hook（需要在 Supabase Dashboard 中配置）
-- 注意：这需要在 Supabase Dashboard > Authentication > Hooks 中配置

-- ========================================
-- 方案3：立即可用的解决方案（使用 profiles 表）
-- ========================================

-- 3.1 创建一个简化的admin检查（直接查询profiles表）
CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN COALESCE(
        (SELECT role = 'admin' FROM public.profiles WHERE id = auth.uid()),
        FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3.2 使用简化的函数更新RLS策略
DROP POLICY IF EXISTS "aggregator_models_delete" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_insert" ON aggregator_models;
DROP POLICY IF EXISTS "aggregator_models_update" ON aggregator_models;

CREATE POLICY "aggregator_models_insert_admin" ON aggregator_models
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

CREATE POLICY "aggregator_models_update_admin" ON aggregator_models
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

CREATE POLICY "aggregator_models_delete_admin" ON aggregator_models
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- ========================================
-- 验证步骤
-- ========================================

-- 1. 检查 profiles 表中的角色
SELECT id, email, role FROM profiles WHERE id = '76443a23-7734-4500-9cd2-89d685eba7d3';

-- 2. 测试 admin 检查函数
SELECT auth.is_admin() as is_admin_via_function;
SELECT public.is_admin_user() as is_admin_via_simple_function;

-- 3. 查看更新后的策略
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'aggregator_models'
ORDER BY policyname;