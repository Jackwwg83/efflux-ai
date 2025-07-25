-- 系统诊断查询

-- 1. 检查你是否是管理员
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM admin_users 
      WHERE user_id = '76443a23-7734-4500-9cd2-89d685eba7d3'
    ) THEN '✅ 你是管理员'
    ELSE '❌ 你不是管理员'
  END as admin_status;

-- 2. 检查模型数量
SELECT 
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  COUNT(*) FILTER (WHERE is_featured = true) as featured_models
FROM models;

-- 3. 检查模型源数量
SELECT 
  provider_type,
  COUNT(DISTINCT provider_name) as providers,
  COUNT(DISTINCT model_id) as models
FROM model_sources
GROUP BY provider_type;

-- 4. 测试主要的 RPC 函数
SELECT COUNT(*) as model_count 
FROM get_all_models_with_sources();

-- 5. 测试模型可用性函数
SELECT COUNT(*) as available_model_count 
FROM get_all_available_models();

-- 6. 检查健康状态统计
SELECT * FROM get_provider_health_stats() LIMIT 5;