-- 最终权限修复方案

-- 1. 确保所有表的 RLS 都已启用
ALTER TABLE api_key_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- 2. 对所有管理员相关的表使用相同的权限模式
-- 删除所有现有策略
DO $$ 
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE tablename IN ('api_key_pool', 'usage_logs', 'user_quotas', 'user_tiers', 'admin_users')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- 3. 为 admin_users 表设置基础权限（所有认证用户都可以查询）
CREATE POLICY "admin_users_select"
ON admin_users FOR SELECT
TO authenticated
USING (true);

-- 4. api_key_pool 表权限
CREATE POLICY "api_key_pool_select"
ON api_key_pool FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

CREATE POLICY "api_key_pool_insert"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

CREATE POLICY "api_key_pool_update"
ON api_key_pool FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()));

CREATE POLICY "api_key_pool_delete"
ON api_key_pool FOR DELETE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()));

-- 5. usage_logs 表权限
-- 管理员可以查看所有
CREATE POLICY "usage_logs_admin_select"
ON usage_logs FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- 普通用户可以查看自己的
CREATE POLICY "usage_logs_user_select"
ON usage_logs FOR SELECT
TO authenticated
USING (
  user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- Service role 可以插入
CREATE POLICY "usage_logs_service_insert"
ON usage_logs FOR INSERT
TO service_role
WITH CHECK (true);

-- 6. user_quotas 表权限
-- 管理员可以查看和更新所有
CREATE POLICY "user_quotas_admin_select"
ON user_quotas FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

CREATE POLICY "user_quotas_admin_update"
ON user_quotas FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()));

-- 普通用户可以查看自己的
CREATE POLICY "user_quotas_user_select"
ON user_quotas FOR SELECT
TO authenticated
USING (
  user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- Service role 可以更新
CREATE POLICY "user_quotas_service_update"
ON user_quotas FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

-- 7. user_tiers 表权限
-- 管理员可以查看、插入和更新所有
CREATE POLICY "user_tiers_admin_select"
ON user_tiers FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

CREATE POLICY "user_tiers_admin_insert"
ON user_tiers FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

CREATE POLICY "user_tiers_admin_update"
ON user_tiers FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()));

-- 普通用户可以查看自己的
CREATE POLICY "user_tiers_user_select"
ON user_tiers FOR SELECT
TO authenticated
USING (
  user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- 8. 确保 service_role 有必要的权限
GRANT ALL ON api_key_pool TO service_role;
GRANT ALL ON usage_logs TO service_role;
GRANT ALL ON user_quotas TO service_role;
GRANT ALL ON user_tiers TO service_role;
GRANT SELECT ON admin_users TO service_role;
GRANT SELECT ON users_view TO service_role;

-- 9. 验证权限设置
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename IN ('api_key_pool', 'usage_logs', 'user_quotas', 'user_tiers', 'admin_users')
ORDER BY tablename, policyname;