-- 修复列名歧义问题

-- 1. 重新创建 is_admin 函数，使用不同的参数名
CREATE OR REPLACE FUNCTION is_admin(check_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users WHERE admin_users.user_id = check_user_id
  );
END;
$$;

-- 2. 重新创建 is_current_user_admin 函数
CREATE OR REPLACE FUNCTION is_current_user_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users WHERE admin_users.user_id = auth.uid()
  );
END;
$$;

-- 3. 创建更简单的 SQL 函数版本（推荐）
CREATE OR REPLACE FUNCTION auth_is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users WHERE admin_users.user_id = auth.uid()
  );
$$;

-- 4. 测试函数
SELECT is_admin('76443a23-7734-4500-9cd2-89d685eba7d3'::uuid) as is_admin_test;
SELECT is_current_user_admin() as is_current_admin_test;
SELECT auth_is_admin() as auth_admin_test;

-- 5. 重新创建所有使用简单 EXISTS 查询的 RLS 策略
-- 删除现有策略
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

-- 6. 为 admin_users 表设置基础权限
CREATE POLICY "admin_users_select"
ON admin_users FOR SELECT
TO authenticated
USING (true);

-- 7. api_key_pool 表权限 - 使用明确的表别名
CREATE POLICY "api_key_pool_admin_select"
ON api_key_pool FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "api_key_pool_admin_insert"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "api_key_pool_admin_update"
ON api_key_pool FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()));

CREATE POLICY "api_key_pool_admin_delete"
ON api_key_pool FOR DELETE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()));

-- 8. usage_logs 表权限
CREATE POLICY "usage_logs_admin_select"
ON usage_logs FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "usage_logs_user_select"
ON usage_logs FOR SELECT
TO authenticated
USING (
  usage_logs.user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "usage_logs_service_insert"
ON usage_logs FOR INSERT
TO service_role
WITH CHECK (true);

-- 9. user_quotas 表权限
CREATE POLICY "user_quotas_admin_select"
ON user_quotas FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "user_quotas_admin_update"
ON user_quotas FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()));

CREATE POLICY "user_quotas_user_select"
ON user_quotas FOR SELECT
TO authenticated
USING (
  user_quotas.user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "user_quotas_service_update"
ON user_quotas FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

-- 10. user_tiers 表权限
CREATE POLICY "user_tiers_admin_select"
ON user_tiers FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "user_tiers_admin_insert"
ON user_tiers FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

CREATE POLICY "user_tiers_admin_update"
ON user_tiers FOR UPDATE
TO authenticated
USING (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid()));

CREATE POLICY "user_tiers_user_select"
ON user_tiers FOR SELECT
TO authenticated
USING (
  user_tiers.user_id = auth.uid() AND 
  NOT EXISTS (SELECT 1 FROM admin_users au WHERE au.user_id = auth.uid())
);

-- 11. 验证设置
SELECT 
  tablename,
  policyname,
  cmd,
  roles
FROM pg_policies
WHERE tablename IN ('api_key_pool', 'admin_users')
ORDER BY tablename, policyname;