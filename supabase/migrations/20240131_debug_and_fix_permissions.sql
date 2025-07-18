-- 调试和修复权限问题

-- 1. 首先检查当前用户是否真的是管理员
DO $$
DECLARE
  current_user_id uuid;
  is_admin boolean;
BEGIN
  -- 获取当前用户 ID（这个在 DO 块中可能不工作，但先试试）
  current_user_id := auth.uid();
  
  -- 检查是否是管理员
  SELECT EXISTS(SELECT 1 FROM admin_users WHERE user_id = current_user_id) INTO is_admin;
  
  RAISE NOTICE 'Current user ID: %, Is admin: %', current_user_id, is_admin;
END $$;

-- 2. 检查 admin_users 表中的数据
SELECT 
  au.user_id,
  u.email,
  au.created_at
FROM admin_users au
JOIN auth.users u ON au.user_id = u.id;

-- 3. 测试函数是否正常工作
SELECT is_admin('76443a23-7734-4500-9cd2-89d685eba7d3'::uuid) as is_admin_check;

-- 4. 创建一个调试函数来查看当前上下文
CREATE OR REPLACE FUNCTION debug_current_user()
RETURNS TABLE (
  current_uid uuid,
  is_authenticated boolean,
  is_admin boolean,
  jwt_role text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    auth.uid() as current_uid,
    (auth.uid() IS NOT NULL) as is_authenticated,
    is_current_user_admin() as is_admin,
    current_setting('request.jwt.claim.role', true) as jwt_role;
END;
$$;

GRANT EXECUTE ON FUNCTION debug_current_user() TO authenticated;

-- 5. 修复问题：错误信息显示 "permission denied for table users"
-- 这可能是因为在某些地方还在访问 users 表而不是 users_view
-- 让我们确保 users_view 有正确的权限

-- 先删除旧的 users_view 如果存在
DROP VIEW IF EXISTS users_view;

-- 重新创建 users_view 并确保权限正确
CREATE VIEW users_view AS
SELECT 
  id,
  email,
  created_at,
  updated_at,
  email_confirmed_at,
  last_sign_in_at
FROM auth.users;

-- 授予权限
GRANT SELECT ON users_view TO authenticated;
GRANT SELECT ON users_view TO service_role;

-- 6. 再次检查并确保所有 RLS 策略都正确
-- 为 api_key_pool 创建一个更明确的插入策略
DROP POLICY IF EXISTS "Only admins can insert api keys" ON api_key_pool;

CREATE POLICY "Only admins can insert api keys"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  )
);

-- 7. 确保 api_key_pool 表的其他权限也正确
DROP POLICY IF EXISTS "Only admins can view api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can delete api keys" ON api_key_pool;

CREATE POLICY "Only admins can view api keys"
ON api_key_pool FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Only admins can update api keys"
ON api_key_pool FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Only admins can delete api keys"
ON api_key_pool FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  )
);

-- 8. 最重要的：确保 admin_users 表本身可以被查询
DROP POLICY IF EXISTS "Users can check if they are admin" ON admin_users;

CREATE POLICY "Anyone can check admin status"
ON admin_users FOR SELECT
TO authenticated
USING (true);  -- 允许所有认证用户查询这个表

-- 9. 创建一个简化的管理员检查函数，直接在 RLS 中使用
CREATE OR REPLACE FUNCTION auth_is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION auth_is_admin() TO authenticated;

-- 10. 使用新的简化函数重建 api_key_pool 的策略
DROP POLICY IF EXISTS "Only admins can view api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can insert api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Only admins can delete api keys" ON api_key_pool;

CREATE POLICY "Admin select api keys"
ON api_key_pool FOR SELECT
TO authenticated
USING (auth_is_admin());

CREATE POLICY "Admin insert api keys"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (auth_is_admin());

CREATE POLICY "Admin update api keys"
ON api_key_pool FOR UPDATE
TO authenticated
USING (auth_is_admin())
WITH CHECK (auth_is_admin());

CREATE POLICY "Admin delete api keys"
ON api_key_pool FOR DELETE
TO authenticated
USING (auth_is_admin());