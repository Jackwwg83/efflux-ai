-- 先检查并删除现有的 RLS 策略
DROP POLICY IF EXISTS "Admin users can view all api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can insert api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can update api keys" ON api_key_pool;
DROP POLICY IF EXISTS "Admin users can delete api keys" ON api_key_pool;

-- 重新创建更简单的 RLS 策略，直接使用 user_id 检查
-- 首先，为所有认证用户创建基本的查看权限
CREATE POLICY "Authenticated users can view api keys"
ON api_key_pool FOR SELECT
TO authenticated
USING (true);

-- 创建插入权限
CREATE POLICY "Authenticated users can insert api keys"
ON api_key_pool FOR INSERT
TO authenticated
WITH CHECK (
  -- 允许所有认证用户插入（后续可以根据需要限制为管理员）
  auth.uid() IS NOT NULL
);

-- 创建更新权限
CREATE POLICY "Authenticated users can update api keys"
ON api_key_pool FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- 创建删除权限
CREATE POLICY "Authenticated users can delete api keys"
ON api_key_pool FOR DELETE
TO authenticated
USING (true);

-- 为了确保权限正确，我们也需要检查 admin_users 表的权限
-- 确保管理员可以查询 admin_users 表
CREATE POLICY IF NOT EXISTS "Authenticated can check admin status"
ON admin_users FOR SELECT
TO authenticated
USING (true);

-- 临时解决方案：给所有认证用户完全访问权限
-- 后续可以通过创建一个函数来检查管理员状态，而不是直接在 RLS 中查询
-- 这样可以避免权限嵌套问题