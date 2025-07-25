-- 最终修复函数脚本

-- ========== 1. 修复 get_all_models_with_sources 函数（第一个函数已经正确）==========
DROP FUNCTION IF EXISTS get_all_models_with_sources();

CREATE OR REPLACE FUNCTION get_all_models_with_sources()
RETURNS TABLE (
  model_id text,
  display_name text,
  custom_name text,
  model_type text,
  capabilities jsonb,
  context_window integer,
  max_output_tokens integer,
  input_price numeric,
  output_price numeric,
  tier_required text,
  tags text[],
  is_active boolean,
  is_featured boolean,
  health_status text,
  available_sources integer,
  sources jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH model_source_info AS (
    SELECT 
      ms.model_id,
      COUNT(DISTINCT ms.id) as source_count,
      jsonb_agg(
        jsonb_build_object(
          'provider_name', ms.provider_name,
          'provider_type', ms.provider_type,
          'is_available', ms.is_available,
          'priority', ms.priority
        ) ORDER BY ms.priority DESC
      ) FILTER (WHERE ms.id IS NOT NULL) as source_list
    FROM model_sources ms
    GROUP BY ms.model_id
  )
  SELECT 
    m.model_id,
    COALESCE(m.display_name, m.model_id) as display_name,
    m.custom_name,
    COALESCE(m.model_type, 'chat') as model_type,
    COALESCE(m.capabilities, '{"supports_chat": true}'::jsonb) as capabilities,
    COALESCE(m.context_window, 4096) as context_window,
    m.max_output_tokens,
    COALESCE(m.input_price, 0) as input_price,
    COALESCE(m.output_price, 0) as output_price,
    COALESCE(m.tier_required, 'free') as tier_required,
    COALESCE(m.tags, ARRAY['new']::text[]) as tags,
    COALESCE(m.is_active, false) as is_active,
    COALESCE(m.is_featured, false) as is_featured,
    COALESCE(m.health_status, 'unknown') as health_status,
    COALESCE(msi.source_count, 0)::integer as available_sources,
    COALESCE(msi.source_list, '[]'::jsonb) as sources
  FROM models m
  LEFT JOIN model_source_info msi ON msi.model_id = m.model_id
  ORDER BY 
    m.is_featured DESC NULLS LAST,
    m.is_active DESC NULLS LAST,
    COALESCE(m.priority, 0) DESC,
    m.model_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_all_models_with_sources() TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_models_with_sources() TO anon;

-- ========== 2. 修复 get_provider_health_stats 函数 ==========
DROP FUNCTION IF EXISTS get_provider_health_stats();

CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE (
  provider text,
  total_keys integer,
  active_keys integer,
  total_requests bigint,
  total_errors bigint,
  avg_latency numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    akp.provider::text,
    COUNT(*)::integer as total_keys,
    COUNT(*) FILTER (WHERE akp.is_active = true)::integer as active_keys,
    COALESCE(SUM(akp.total_requests), 0)::bigint as total_requests,
    COALESCE(SUM(akp.error_count), 0)::bigint as total_errors,
    0::numeric as avg_latency  -- api_key_pool 表没有 latency 相关字段
  FROM api_key_pool akp
  GROUP BY akp.provider
  ORDER BY akp.provider;
END;
$$;

GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO anon;

-- ========== 3. 验证修复 ==========
DO $$
DECLARE
  test_count integer;
  error_msg text;
BEGIN
  -- 测试 get_all_models_with_sources
  BEGIN
    SELECT COUNT(*) INTO test_count FROM get_all_models_with_sources();
    RAISE NOTICE '✅ get_all_models_with_sources 返回 % 行', test_count;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
    RAISE NOTICE '❌ get_all_models_with_sources 错误: %', error_msg;
  END;
  
  -- 测试 get_provider_health_stats
  BEGIN
    SELECT COUNT(*) INTO test_count FROM get_provider_health_stats();
    RAISE NOTICE '✅ get_provider_health_stats 返回 % 行', test_count;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
    RAISE NOTICE '❌ get_provider_health_stats 错误: %', error_msg;
  END;
  
  -- 测试 get_all_available_models
  BEGIN
    SELECT COUNT(*) INTO test_count FROM get_all_available_models();
    RAISE NOTICE '✅ get_all_available_models 返回 % 行', test_count;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
    RAISE NOTICE '❌ get_all_available_models 错误: %', error_msg;
  END;
END $$;

-- ========== 4. 查看一些结果样本 ==========
SELECT '===== get_all_models_with_sources 前10个模型 =====' as info;
SELECT 
  model_id,
  display_name,
  available_sources,
  is_active,
  is_featured,
  tags
FROM get_all_models_with_sources()
LIMIT 10;

SELECT '===== get_provider_health_stats 结果 =====' as info;
SELECT * FROM get_provider_health_stats();

-- ========== 5. 检查为什么模型管理页面可能看不到数据 ==========
SELECT '===== 检查活跃模型数量 =====' as info;
SELECT 
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  COUNT(*) FILTER (WHERE is_featured = true) as featured_models
FROM models;

SELECT '===== 检查是否有模型源匹配 =====' as info;
SELECT 
  COUNT(DISTINCT m.model_id) as unique_models,
  COUNT(DISTINCT ms.model_id) as unique_sources,
  COUNT(DISTINCT m.model_id) FILTER (
    WHERE EXISTS (
      SELECT 1 FROM model_sources ms2 
      WHERE ms2.model_id = m.model_id
    )
  ) as models_with_sources
FROM models m
FULL OUTER JOIN model_sources ms ON ms.model_id = m.model_id;