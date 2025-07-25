-- 修复剩余的问题

-- 1. 确保当前用户是管理员
INSERT INTO admin_users (user_id, created_at)
VALUES ('76443a23-7734-4500-9cd2-89d685eba7d3', now())
ON CONFLICT (user_id) DO NOTHING;

-- 2. 创建缺失的 get_provider_health_stats 函数
-- 先删除已存在的函数
DROP FUNCTION IF EXISTS get_provider_health_stats();

CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE (
  provider_name text,
  provider_type text,
  total_models integer,
  active_models integer,
  health_percentage numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH provider_stats AS (
    SELECT 
      ms.provider_name,
      ms.provider_type,
      COUNT(DISTINCT ms.model_id) as total_models,
      COUNT(DISTINCT ms.model_id) FILTER (WHERE ms.is_available = true) as active_models
    FROM model_sources ms
    GROUP BY ms.provider_name, ms.provider_type
  )
  SELECT 
    ps.provider_name,
    ps.provider_type,
    ps.total_models,
    ps.active_models,
    CASE 
      WHEN ps.total_models > 0 THEN 
        ROUND((ps.active_models::numeric / ps.total_models::numeric) * 100, 2)
      ELSE 0
    END as health_percentage
  FROM provider_stats ps
  ORDER BY ps.provider_type, ps.provider_name;
END;
$$;

-- 授予权限
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO anon;

-- 3. 修复 admin_users 表的 RLS 策略
-- 首先删除现有策略
DROP POLICY IF EXISTS "Admin users can view admin_users" ON admin_users;
DROP POLICY IF EXISTS "Admin users can manage admin_users" ON admin_users;

-- 创建新的 RLS 策略
CREATE POLICY "Users can check their own admin status"
  ON admin_users
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admin users can view all admin_users"
  ON admin_users
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Admin users can manage admin_users"
  ON admin_users
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE user_id = auth.uid()
    )
  );

-- 4. 检查并修复 models 表的 RLS 策略
ALTER TABLE models ENABLE ROW LEVEL SECURITY;

-- 删除旧策略
DROP POLICY IF EXISTS "Public read access to active models" ON models;
DROP POLICY IF EXISTS "Admin full access to models" ON models;

-- 创建新策略
CREATE POLICY "Anyone can view active models"
  ON models
  FOR SELECT
  USING (is_active = true);

CREATE POLICY "Admin users can manage all models"
  ON models
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE user_id = auth.uid()
    )
  );

-- 5. 检查 model_sources 表的 RLS 策略
ALTER TABLE model_sources ENABLE ROW LEVEL SECURITY;

-- 删除旧策略
DROP POLICY IF EXISTS "Public read access to model sources" ON model_sources;
DROP POLICY IF EXISTS "Admin full access to model sources" ON model_sources;

-- 创建新策略
CREATE POLICY "Anyone can view model sources"
  ON model_sources
  FOR SELECT
  USING (true);

CREATE POLICY "Admin users can manage model sources"
  ON model_sources
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE user_id = auth.uid()
    )
  );

-- 6. 验证数据存在
DO $$
DECLARE
  model_count integer;
  source_count integer;
BEGIN
  SELECT COUNT(*) INTO model_count FROM models;
  SELECT COUNT(*) INTO source_count FROM model_sources;
  
  RAISE NOTICE 'Models count: %', model_count;
  RAISE NOTICE 'Model sources count: %', source_count;
  
  IF model_count = 0 THEN
    RAISE WARNING 'No models found in the database!';
  END IF;
  
  IF source_count = 0 THEN
    RAISE WARNING 'No model sources found in the database!';
  END IF;
END $$;