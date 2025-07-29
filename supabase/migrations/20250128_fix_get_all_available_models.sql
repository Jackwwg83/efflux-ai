-- Fix get_all_available_models function for unified model system
-- This updates the function to work with the new models table structure

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
    WITH model_providers AS (
        -- Get the primary provider for each model (highest priority)
        SELECT DISTINCT ON (ms.model_id)
            ms.model_id,
            ms.provider_name,
            ms.provider_type = 'aggregator' as is_aggregator
        FROM model_sources ms
        WHERE ms.is_available = true
        ORDER BY ms.model_id, ms.priority DESC
    )
    SELECT 
        m.model_id,
        COALESCE(m.custom_name, m.display_name) as display_name,
        mp.provider_name,
        m.model_type,
        m.context_window,
        mp.is_aggregator,
        m.capabilities,
        m.tier_required,
        m.health_status,
        m.health_message,
        m.is_featured,
        m.tags
    FROM models m
    LEFT JOIN model_providers mp ON mp.model_id = m.model_id
    WHERE m.is_active = true
        AND EXISTS (
            -- Ensure at least one active source exists
            SELECT 1 FROM model_sources ms2
            WHERE ms2.model_id = m.model_id
                AND ms2.is_available = true
        )
    ORDER BY m.is_featured DESC, m.priority DESC, m.display_name;
END;
$$ LANGUAGE plpgsql;

-- Add comment explaining the function
COMMENT ON FUNCTION get_all_available_models() IS 
'Returns all available models from the unified model system, including their primary provider and tier requirements.';