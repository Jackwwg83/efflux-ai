-- 创建新的 RPC 函数，替代旧的 get_all_available_models
CREATE OR REPLACE FUNCTION get_all_available_models()
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    provider_name TEXT,
    model_type TEXT,
    context_window INTEGER,
    is_aggregator BOOLEAN,
    capabilities JSONB,
    tier_required TEXT,
    health_status TEXT,
    health_message TEXT,
    is_featured BOOLEAN,
    tags TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    WITH user_tier AS (
        SELECT COALESCE(ut.tier, 'free'::user_tier) as tier
        FROM auth.users u
        LEFT JOIN user_tiers ut ON ut.user_id = u.id
        WHERE u.id = auth.uid()
    ),
    available_models AS (
        SELECT 
            m.model_id,
            COALESCE(m.custom_name, m.display_name) as display_name,
            -- 使用第一个可用的供应商名称
            COALESCE(
                (SELECT ms.provider_name 
                 FROM model_sources ms 
                 WHERE ms.model_id = m.model_id 
                   AND ms.is_available = true
                 ORDER BY ms.priority DESC
                 LIMIT 1),
                'unknown'
            ) as provider_name,
            m.model_type,
            m.context_window,
            -- 检查是否有聚合器来源
            EXISTS (
                SELECT 1 FROM model_sources ms 
                WHERE ms.model_id = m.model_id 
                  AND ms.provider_type = 'aggregator'
                  AND ms.is_available = true
            ) as is_aggregator,
            m.capabilities,
            m.tier_required,
            m.health_status,
            m.health_message,
            m.is_featured,
            m.tags
        FROM models m
        WHERE m.is_active = true
          AND EXISTS (
              SELECT 1 FROM model_sources ms 
              WHERE ms.model_id = m.model_id 
                AND ms.is_available = true
          )
          AND m.tier_required IN (
              SELECT 
                  CASE 
                      WHEN ut.tier = 'max' THEN unnest(ARRAY['free', 'pro', 'max'])
                      WHEN ut.tier = 'pro' THEN unnest(ARRAY['free', 'pro'])
                      ELSE 'free'
                  END
              FROM user_tier ut
          )
    )
    SELECT * FROM available_models
    ORDER BY is_featured DESC, display_name;
END;
$$ LANGUAGE plpgsql;

-- 测试函数
SELECT * FROM get_all_available_models() LIMIT 5;