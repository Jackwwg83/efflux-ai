-- Migration: Update API Aggregator for Admin Management
-- Description: Convert user-level aggregator management to admin-level

-- First, let's modify the api_key_pool table to support aggregator types
ALTER TABLE api_key_pool ADD COLUMN IF NOT EXISTS provider_type TEXT DEFAULT 'direct' CHECK (provider_type IN ('direct', 'aggregator'));
ALTER TABLE api_key_pool ADD COLUMN IF NOT EXISTS provider_config JSONB DEFAULT '{}';

-- Drop user-specific tables since admin will manage everything
DROP TABLE IF EXISTS user_api_providers CASCADE;

-- First drop the existing policy that depends on is_active column
DROP POLICY IF EXISTS "api_providers_select" ON api_providers;

-- Now we can safely modify api_providers
ALTER TABLE api_providers DROP COLUMN IF EXISTS is_active;
ALTER TABLE api_providers ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN DEFAULT true;

-- Create new RLS policies for api_providers (admin only)
CREATE POLICY "api_providers_admin_all" ON api_providers
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- Update aggregator_models policies (read for all, write for admin)
DROP POLICY IF EXISTS "aggregator_models_select" ON aggregator_models;
CREATE POLICY "aggregator_models_select_all" ON aggregator_models
    FOR SELECT TO authenticated
    USING (is_available = true);

DROP POLICY IF EXISTS "aggregator_models_admin_write" ON aggregator_models;
CREATE POLICY "aggregator_models_admin_write" ON aggregator_models
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- Create a function to get all available models (direct + aggregator)
CREATE OR REPLACE FUNCTION get_all_available_models()
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    provider_name TEXT,
    model_type TEXT,
    context_window INTEGER,
    is_aggregator BOOLEAN,
    capabilities JSONB,
    tier_required TEXT
) AS $$
BEGIN
    RETURN QUERY
    -- Direct provider models
    SELECT 
        mc.model as model_id,
        mc.display_name,
        mc.provider as provider_name,
        'chat' as model_type,
        CASE
            WHEN mc.model LIKE '%32k%' THEN 32768
            WHEN mc.model LIKE '%16k%' THEN 16384
            WHEN mc.model LIKE '%100k%' THEN 100000
            ELSE 8192
        END as context_window,
        false as is_aggregator,
        '{"streaming": true}'::jsonb as capabilities,
        mc.tier_required
    FROM model_configs mc
    WHERE mc.is_active = true
    
    UNION ALL
    
    -- Aggregator models from active API keys
    SELECT 
        am.model_id,
        am.display_name,
        ap.display_name as provider_name,
        am.model_type,
        am.context_window,
        true as is_aggregator,
        am.capabilities,
        'free'::text as tier_required -- All aggregator models available to all tiers
    FROM aggregator_models am
    JOIN api_providers ap ON am.provider_id = ap.id
    WHERE am.is_available = true
        AND ap.is_enabled = true
        AND EXISTS (
            SELECT 1 FROM api_key_pool akp
            WHERE akp.provider = ap.name
            AND akp.is_active = true
            AND akp.provider_type = 'aggregator'
        );
END;
$$ LANGUAGE plpgsql;

-- Update the model provider config function for aggregators
CREATE OR REPLACE FUNCTION get_model_provider_config_v2(p_model_id TEXT)
RETURNS TABLE (
    provider_id UUID,
    provider_type TEXT,
    provider_name TEXT,
    model_name TEXT,
    base_url TEXT,
    api_key TEXT,
    api_key_id UUID,
    api_standard TEXT,
    features JSONB,
    custom_headers JSONB,
    requires_referer BOOLEAN,
    requires_site_name BOOLEAN,
    input_price NUMERIC,
    output_price NUMERIC
) AS $$
BEGIN
    -- Check if it's an aggregator model
    RETURN QUERY
    SELECT 
        ap.id as provider_id,
        'aggregator'::TEXT as provider_type,
        ap.name as provider_name,
        am.model_name,
        ap.base_url,
        akp.api_key,
        akp.id as api_key_id,
        ap.api_standard,
        ap.features,
        akp.provider_config->'custom_headers' as custom_headers,
        COALESCE((ap.features->>'requires_referer')::boolean, false) as requires_referer,
        COALESCE((ap.features->>'requires_site_name')::boolean, false) as requires_site_name,
        COALESCE((am.pricing->>'input')::numeric, 0) as input_price,
        COALESCE((am.pricing->>'output')::numeric, 0) as output_price
    FROM aggregator_models am
    JOIN api_providers ap ON am.provider_id = ap.id
    JOIN api_key_pool akp ON akp.provider = ap.name AND akp.provider_type = 'aggregator'
    WHERE am.model_id = p_model_id
        AND akp.is_active = true
        AND ap.is_enabled = true
        AND am.is_available = true
    ORDER BY akp.last_used_at ASC NULLS FIRST  -- Use least recently used key
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_api_key_pool_provider_type ON api_key_pool(provider, provider_type);