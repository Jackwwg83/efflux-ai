-- 正确修复函数，使用 model_id 文本字段关联

-- ========== 1. 修复 get_all_models_with_sources 函数 ==========
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
      ms.model_id,  -- text 类型
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
  LEFT JOIN model_source_info msi ON msi.model_id = m.model_id  -- 使用 model_id (text) = model_id (text)
  ORDER BY 
    m.is_featured DESC NULLS LAST,
    m.is_active DESC NULLS LAST,
    COALESCE(m.priority, 0) DESC,
    m.model_id;
END;
$$;

-- 授予权限
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
  WITH provider_stats AS (
    SELECT 
      CASE 
        WHEN akp.provider_type = 'direct' THEN akp.provider
        ELSE ap.name
      END as provider_name,
      COUNT(DISTINCT akp.id) as total_keys,
      COUNT(DISTINCT akp.id) FILTER (WHERE akp.is_active = true) as active_keys,
      COALESCE(SUM(akp.total_requests), 0) as total_requests,
      COALESCE(SUM(akp.failed_requests), 0) as total_errors,
      CASE 
        WHEN SUM(akp.total_requests) > 0 THEN
          AVG(akp.average_latency_ms)
        ELSE 0
      END as avg_latency
    FROM api_key_pool akp
    LEFT JOIN api_providers ap ON akp.provider_id = ap.id
    GROUP BY 
      CASE 
        WHEN akp.provider_type = 'direct' THEN akp.provider
        ELSE ap.name
      END
  )
  SELECT 
    provider_name::text as provider,
    total_keys::integer,
    active_keys::integer,
    total_requests::bigint,
    total_errors::bigint,
    COALESCE(avg_latency, 0)::numeric
  FROM provider_stats
  ORDER BY provider_name;
END;
$$;

-- 授予权限
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO anon;

-- ========== 3. 验证修复 ==========
-- 测试函数是否能正常工作
DO $$
DECLARE
  test_count integer;
BEGIN
  -- 测试 get_all_models_with_sources
  SELECT COUNT(*) INTO test_count FROM get_all_models_with_sources();
  RAISE NOTICE 'get_all_models_with_sources 返回 % 行', test_count;
  
  -- 测试 get_provider_health_stats
  SELECT COUNT(*) INTO test_count FROM get_provider_health_stats();
  RAISE NOTICE 'get_provider_health_stats 返回 % 行', test_count;
  
  -- 测试 get_all_available_models
  SELECT COUNT(*) INTO test_count FROM get_all_available_models();
  RAISE NOTICE 'get_all_available_models 返回 % 行', test_count;
END $$;

-- ========== 4. 查看一些结果样本 ==========
SELECT '===== get_all_models_with_sources 样本 =====' as info;
SELECT 
  model_id,
  display_name,
  available_sources,
  is_active,
  is_featured
FROM get_all_models_with_sources()
WHERE available_sources > 0
LIMIT 10;

-- ========== 5. 检查模型和源的匹配情况 ==========
SELECT '===== 模型源匹配统计 =====' as info;
WITH match_stats AS (
  SELECT 
    COUNT(DISTINCT m.model_id) as total_models,
    COUNT(DISTINCT ms.model_id) as total_source_model_ids,
    COUNT(DISTINCT m.model_id) FILTER (
      WHERE EXISTS (
        SELECT 1 FROM model_sources ms2 
        WHERE ms2.model_id = m.model_id
      )
    ) as models_with_sources
  FROM models m
  FULL OUTER JOIN model_sources ms ON ms.model_id = m.model_id
)
SELECT * FROM match_stats;