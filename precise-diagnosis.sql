-- 精确诊断 models 表结构

-- 1. 重新检查 models 表结构
SELECT '===== models 表的真实结构 =====' as info;
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'models'
  AND table_schema = 'public'
ORDER BY ordinal_position
LIMIT 30;

-- 2. 检查 models 表是否有必要的列
SELECT '===== 检查 models 表关键列 =====' as info;
SELECT 
  COUNT(*) FILTER (WHERE column_name = 'model_id') as has_model_id,
  COUNT(*) FILTER (WHERE column_name = 'display_name') as has_display_name,
  COUNT(*) FILTER (WHERE column_name = 'is_active') as has_is_active,
  COUNT(*) FILTER (WHERE column_name = 'is_featured') as has_is_featured,
  COUNT(*) FILTER (WHERE column_name = 'priority') as has_priority
FROM information_schema.columns
WHERE table_name = 'models'
  AND table_schema = 'public';

-- 3. 测试 get_all_models_with_sources 函数
SELECT '===== 测试 get_all_models_with_sources =====' as info;
SELECT COUNT(*) as function_returns_rows 
FROM get_all_models_with_sources()
LIMIT 1;

-- 4. 查看一条模型数据样本
SELECT '===== models 表数据样本 =====' as info;
SELECT * FROM models LIMIT 1;

-- 5. 查看前端可能调用的健康统计
SELECT '===== 测试当前的 get_provider_health_stats =====' as info;
SELECT * FROM get_provider_health_stats() LIMIT 5;