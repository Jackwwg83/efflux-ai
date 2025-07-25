-- 检查所有相关函数的存在情况和定义

-- 1. 查看所有自定义函数
SELECT 
  proname as function_name,
  pg_get_function_identity_arguments(oid) as arguments,
  pg_get_function_result(oid) as return_type
FROM pg_proc
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND proname IN (
    'get_all_models_with_sources',
    'get_all_available_models',
    'get_provider_health_stats',
    'update_model_health_status',
    'update_model_config'
  )
ORDER BY proname;

-- 2. 检查 get_provider_health_stats 的具体定义（如果存在）
SELECT 
  proname,
  prosrc 
FROM pg_proc 
WHERE proname = 'get_provider_health_stats'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');