-- 生产级别的管理员权限系统（修复版）

-- 1. 先清理所有旧的策略
-- api_key_pool 表的策略
DROP POLICY IF EXISTS "Admin users can view all api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can insert api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can delete api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Authenticated users can view api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Authenticated users can insert api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Authenticated users can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Authenticated users can delete api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can view api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can insert api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can delete api keys" ON api_key_pool;

-- usage_logs 表的策略
DROP POLICY IF EXISTS "Admin users can view all logs" ON usage_logs;
DROP POLICY IF EXISTS "Users can view own usage logs" ON usage_logs;
DROP POLICY IF EXISTS "Admins can view all usage logs" ON usage_logs;
DROP POLICY IF EXISTS "Edge Functions can insert usage logs" ON usage_logs;

-- user_quotas 表的策略
DROP POLICY IF EXISTS "Admin users can manage all quotas" ON user_quotas;
DROP POLICY IF EXISTS "Users can view own quotas" ON user_quotas;
DROP POLICY IF EXISTS "Admins can view all user quotas" ON user_quotas;
DROP POLICY IF EXISTS "Only admins can update user quotas" ON user_quotas;
DROP POLICY IF EXISTS "Edge Functions can update quotas" ON user_quotas;

-- user_tiers 表的策略
DROP POLICY IF EXISTS "Admin users can manage all tiers" ON user_tiers;
DROP POLICY IF EXISTS "Users can view own tier" ON user_tiers;
DROP POLICY IF EXISTS "Admins can view all user tiers" ON user_tiers;
DROP POLICY IF EXISTS "Only admins can insert user tiers" ON user_tiers;
DROP POLICY IF EXISTS "Only admins can update user tiers" ON user_tiers;

-- admin_users 表的策略
DROP POLICY IF EXISTS "Authenticated can check admin status" ON admin_users;
DROP POLICY IF EXISTS "Users can check if they are admin" ON admin_users;

-- 2. 创建管理员检查函数（避免 RLS 中的权限嵌套）
CREATE OR REPLACE FUNCTION is_admin(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = $1
  );
END;
$$;

-- 3. 创建当前用户是否为管理员的便捷函数
CREATE OR REPLACE FUNCTION is_current_user_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN is_admin(auth.uid());
END;
$$;

-- 4. 为 api_key_pool 创建生产级别的 RLS 策略
CREATE POLICY "Only admins can view api keys"
ON api_key_pool FOR SELECT
TO authenticated
USING (is_current_user_admin());

CREATE POLICY "Only admins can insert api keys"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (is_current_user_admin());

CREATE POLICY "Only admins can update api keys"
ON api_key_pool FOR UPDATE
TO authenticated
USING (is_current_user_admin())
WITH CHECK (is_current_user_admin());

CREATE POLICY "Only admins can delete api keys"
ON api_key_pool FOR DELETE
TO authenticated
USING (is_current_user_admin());

-- 5. 为其他管理表创建策略
-- 5.1 usage_logs 表
CREATE POLICY "Admins can view all usage logs"
ON usage_logs FOR SELECT
TO authenticated
USING (is_current_user_admin());

CREATE POLICY "Users can view own usage logs"
ON usage_logs FOR SELECT
TO authenticated
USING (NOT is_current_user_admin() AND auth.uid() = user_id);

-- Edge Functions 需要能插入日志
CREATE POLICY "Edge Functions can insert usage logs"
ON usage_logs FOR INSERT
TO service_role
WITH CHECK (true);

-- 5.2 user_quotas 表
CREATE POLICY "Admins can view all user quotas"
ON user_quotas FOR SELECT
TO authenticated
USING (is_current_user_admin());

CREATE POLICY "Users can view own quotas"
ON user_quotas FOR SELECT
TO authenticated
USING (NOT is_current_user_admin() AND auth.uid() = user_id);

CREATE POLICY "Only admins can update user quotas"
ON user_quotas FOR UPDATE
TO authenticated
USING (is_current_user_admin())
WITH CHECK (is_current_user_admin());

-- Edge Functions 需要能更新配额
CREATE POLICY "Edge Functions can update quotas"
ON user_quotas FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

-- 5.3 user_tiers 表
CREATE POLICY "Admins can view all user tiers"
ON user_tiers FOR SELECT
TO authenticated
USING (is_current_user_admin());

CREATE POLICY "Users can view own tier"
ON user_tiers FOR SELECT
TO authenticated
USING (NOT is_current_user_admin() AND auth.uid() = user_id);

CREATE POLICY "Only admins can insert user tiers"
ON user_tiers FOR INSERT
TO authenticated
WITH CHECK (is_current_user_admin());

CREATE POLICY "Only admins can update user tiers"
ON user_tiers FOR UPDATE
TO authenticated
USING (is_current_user_admin())
WITH CHECK (is_current_user_admin());

-- 6. admin_users 表权限
CREATE POLICY "Users can check if they are admin"
ON admin_users FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR is_current_user_admin());

-- 7. 授予函数执行权限
GRANT EXECUTE ON FUNCTION is_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION is_current_user_admin() TO authenticated;

-- 8. 创建管理员角色管理函数
CREATE OR REPLACE FUNCTION add_admin_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 检查当前用户是否为管理员
  IF NOT is_current_user_admin() THEN
    RAISE EXCEPTION 'Only admins can add other admins';
  END IF;
  
  -- 添加管理员
  INSERT INTO admin_users (user_id) 
  VALUES (target_user_id)
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION remove_admin_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 检查当前用户是否为管理员
  IF NOT is_current_user_admin() THEN
    RAISE EXCEPTION 'Only admins can remove other admins';
  END IF;
  
  -- 防止删除最后一个管理员
  IF (SELECT COUNT(*) FROM admin_users) <= 1 THEN
    RAISE EXCEPTION 'Cannot remove the last admin';
  END IF;
  
  -- 删除管理员
  DELETE FROM admin_users WHERE user_id = target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION add_admin_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION remove_admin_user(uuid) TO authenticated;

-- 9. 创建索引以提高性能
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON admin_users(user_id);
CREATE INDEX IF NOT EXISTS idx_api_key_pool_provider ON api_key_pool(provider);
CREATE INDEX IF NOT EXISTS idx_api_key_pool_is_active ON api_key_pool(is_active);
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_created_at ON usage_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_user_quotas_user_id ON user_quotas(user_id);
CREATE INDEX IF NOT EXISTS idx_user_tiers_user_id ON user_tiers(user_id);

-- 10. 确保 Edge Functions 可以访问必要的表
GRANT SELECT ON api_key_pool TO service_role;
GRANT UPDATE ON api_key_pool TO service_role;
GRANT INSERT ON usage_logs TO service_role;
GRANT SELECT ON user_quotas TO service_role;
GRANT UPDATE ON user_quotas TO service_role;
GRANT SELECT ON user_tiers TO service_role;