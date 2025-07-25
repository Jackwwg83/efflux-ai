-- 全面诊断数据库当前状态

-- ========== 1. 检查所有相关函数 ==========
SELECT '===== 现有函数列表 =====' as info;
SELECT 
  proname as function_name,
  pg_get_function_identity_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type
FROM pg_proc
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND (
    proname LIKE '%model%' 
    OR proname LIKE '%health%'
    OR proname LIKE '%provider%'
  )
ORDER BY proname;

-- ========== 2. 检查表结构 ==========
SELECT '===== models 表结构 =====' as info;
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'models'
  AND table_schema = 'public'
ORDER BY ordinal_position;

SELECT '===== model_sources 表结构 =====' as info;
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'model_sources'
  AND table_schema = 'public'
ORDER BY ordinal_position;

-- ========== 3. 检查数据状态 ==========
SELECT '===== 数据统计 =====' as info;
SELECT 
  'models' as table_name,
  COUNT(*) as total_rows,
  COUNT(*) FILTER (WHERE is_active = true) as active_rows
FROM models
UNION ALL
SELECT 
  'model_sources' as table_name,
  COUNT(*) as total_rows,
  COUNT(*) FILTER (WHERE is_available = true) as active_rows
FROM model_sources;

-- ========== 4. 检查管理员状态 ==========
SELECT '===== 管理员用户 =====' as info;
SELECT 
  user_id,
  created_at,
  CASE 
    WHEN user_id = '76443a23-7734-4500-9cd2-89d685eba7d3' THEN '当前用户'
    ELSE '其他管理员'
  END as user_type
FROM admin_users
ORDER BY created_at;

-- ========== 5. 检查 RLS 策略 ==========
SELECT '===== RLS 策略 =====' as info;
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('models', 'model_sources', 'admin_users')
ORDER BY tablename, policyname;

-- ========== 6. 检查具体函数的返回类型 ==========
SELECT '===== get_provider_health_stats 函数详情 =====' as info;
SELECT 
  proname,
  prorettype::regtype as return_type,
  proargnames as argument_names,
  proallargtypes::regtype[] as all_arg_types
FROM pg_proc
WHERE proname = 'get_provider_health_stats'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- ========== 7. 测试关键查询 ==========
SELECT '===== 测试 models 表基本查询 =====' as info;
SELECT COUNT(*) as can_query_models FROM models LIMIT 1;

SELECT '===== 测试 model_sources 表基本查询 =====' as info;
SELECT COUNT(*) as can_query_model_sources FROM model_sources LIMIT 1;