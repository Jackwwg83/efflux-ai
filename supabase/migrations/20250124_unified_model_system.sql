-- =====================================================
-- Unified Model Management System Migration
-- =====================================================
-- This migration creates a unified model management system
-- that treats all providers (direct and aggregators) as token suppliers

-- Step 1: Create the unified models table
-- =====================================================
CREATE TABLE IF NOT EXISTS models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Core model identification
    model_id TEXT UNIQUE NOT NULL, -- e.g., 'gpt-4', 'claude-3'
    display_name TEXT NOT NULL,
    description TEXT,
    model_type TEXT NOT NULL CHECK (model_type IN ('chat', 'completion', 'image', 'audio', 'embedding', 'moderation')),
    
    -- Aggregated capabilities from all sources
    capabilities JSONB DEFAULT '{}', -- {vision: true, functions: true, streaming: true}
    context_window INTEGER,
    max_output_tokens INTEGER,
    training_cutoff DATE,
    
    -- Admin configurations
    custom_name TEXT, -- Admin can override display name
    input_price DECIMAL(10,6), -- Unified pricing for users
    output_price DECIMAL(10,6),
    tier_required TEXT DEFAULT 'free' CHECK (tier_required IN ('free', 'pro', 'max')),
    priority INTEGER DEFAULT 0, -- Display order priority
    tags TEXT[], -- ['recommended', 'popular', 'new', 'vision', 'fast']
    
    -- Status and health
    is_active BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    health_status TEXT DEFAULT 'healthy' CHECK (health_status IN ('healthy', 'degraded', 'unavailable', 'maintenance')),
    health_message TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Indexes
    INDEX idx_models_active (is_active, model_type),
    INDEX idx_models_featured (is_featured),
    INDEX idx_models_tags (tags) USING GIN
);

-- Step 2: Create model sources table (tracks all providers for each model)
-- =====================================================
CREATE TABLE IF NOT EXISTS model_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id TEXT NOT NULL REFERENCES models(model_id) ON DELETE CASCADE,
    
    -- Provider information
    provider_type TEXT NOT NULL CHECK (provider_type IN ('direct', 'aggregator')),
    provider_name TEXT NOT NULL, -- 'openai', 'anthropic', 'aihubmix', etc.
    provider_model_id TEXT, -- Provider's specific model identifier
    
    -- Original pricing from provider (for reference/cost calculation)
    original_input_price DECIMAL(10,6),
    original_output_price DECIMAL(10,6),
    
    -- Routing configuration
    priority INTEGER DEFAULT 0, -- Higher priority = preferred source
    weight INTEGER DEFAULT 100, -- For load balancing (1-100)
    
    -- Provider-specific configurations
    api_endpoint TEXT,
    api_standard TEXT DEFAULT 'openai', -- 'openai', 'anthropic', 'custom'
    custom_headers JSONB DEFAULT '{}',
    
    -- Status tracking
    is_available BOOLEAN DEFAULT true,
    last_checked TIMESTAMPTZ DEFAULT NOW(),
    consecutive_failures INTEGER DEFAULT 0,
    average_latency_ms INTEGER,
    
    -- Constraints and indexes
    UNIQUE(model_id, provider_name),
    INDEX idx_model_sources_routing (model_id, is_available, priority DESC),
    INDEX idx_model_sources_provider (provider_name, is_available)
);

-- Step 3: Simplified API keys table
-- =====================================================
-- Note: We'll keep the existing api_key_pool structure but add indexes
CREATE INDEX IF NOT EXISTS idx_api_key_pool_routing 
ON api_key_pool(provider, is_active, last_used_at);

-- Step 4: Create model routing logs for analytics
-- =====================================================
CREATE TABLE IF NOT EXISTS model_routing_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    user_id UUID REFERENCES users(id),
    
    -- Routing decision
    selected_source_id UUID REFERENCES model_sources(id),
    routing_reason TEXT, -- 'priority', 'availability', 'load_balance', 'cost'
    
    -- Performance metrics
    latency_ms INTEGER,
    tokens_used INTEGER,
    estimated_cost DECIMAL(10,6),
    
    -- Status
    status TEXT CHECK (status IN ('success', 'error', 'timeout')),
    error_message TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Indexes for analytics
    INDEX idx_routing_logs_model (model_id, created_at),
    INDEX idx_routing_logs_provider (provider_name, created_at)
);

-- Step 5: Create functions for model management
-- =====================================================

-- Function to get available models for a user (considering tier)
CREATE OR REPLACE FUNCTION get_available_models_unified(p_user_id UUID)
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    custom_name TEXT,
    model_type TEXT,
    capabilities JSONB,
    context_window INTEGER,
    input_price DECIMAL,
    output_price DECIMAL,
    tags TEXT[],
    is_featured BOOLEAN,
    available_sources INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.model_id,
        m.display_name,
        m.custom_name,
        m.model_type,
        m.capabilities,
        m.context_window,
        m.input_price,
        m.output_price,
        m.tags,
        m.is_featured,
        COUNT(ms.id)::INTEGER as available_sources
    FROM models m
    LEFT JOIN model_sources ms ON ms.model_id = m.model_id AND ms.is_available = true
    WHERE m.is_active = true
        AND m.tier_required IN (
            SELECT tier FROM user_tiers WHERE user_id = p_user_id
            UNION SELECT 'free'::user_tier
        )
    GROUP BY m.model_id, m.display_name, m.custom_name, m.model_type, 
             m.capabilities, m.context_window, m.input_price, m.output_price, 
             m.tags, m.is_featured
    HAVING COUNT(ms.id) > 0
    ORDER BY m.is_featured DESC, m.priority DESC, m.display_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get optimal provider for a model
CREATE OR REPLACE FUNCTION get_optimal_model_source(p_model_id TEXT)
RETURNS TABLE (
    source_id UUID,
    provider_name TEXT,
    provider_type TEXT,
    api_endpoint TEXT,
    api_standard TEXT,
    custom_headers JSONB,
    api_key TEXT,
    api_key_id UUID
) AS $$
BEGIN
    RETURN QUERY
    WITH available_sources AS (
        SELECT 
            ms.*,
            akp.api_key,
            akp.id as api_key_id,
            akp.last_used_at,
            -- Calculate routing score
            (ms.priority * 1000 + 
             ms.weight - 
             COALESCE(ms.consecutive_failures * 10, 0) -
             COALESCE(ms.average_latency_ms / 100, 0)) as routing_score
        FROM model_sources ms
        JOIN api_key_pool akp ON akp.provider = ms.provider_name 
            AND akp.is_active = true
            AND akp.provider_type = ms.provider_type
        WHERE ms.model_id = p_model_id
            AND ms.is_available = true
    )
    SELECT 
        source_id,
        provider_name,
        provider_type,
        api_endpoint,
        api_standard,
        custom_headers,
        api_key,
        api_key_id
    FROM available_sources
    ORDER BY routing_score DESC, last_used_at ASC NULLS FIRST
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Step 6: Create migration functions
-- =====================================================

-- Function to migrate existing data
CREATE OR REPLACE FUNCTION migrate_to_unified_models()
RETURNS void AS $$
DECLARE
    v_model RECORD;
    v_source_id UUID;
BEGIN
    -- Migrate direct provider models from model_configs
    FOR v_model IN 
        SELECT DISTINCT ON (model) * FROM model_configs WHERE is_active = true
    LOOP
        -- Insert into models table
        INSERT INTO models (
            model_id,
            display_name,
            model_type,
            capabilities,
            context_window,
            max_tokens,
            input_price,
            output_price,
            tier_required,
            is_active,
            health_status,
            health_message
        ) VALUES (
            v_model.model,
            v_model.display_name,
            'chat', -- Assuming chat for existing models
            jsonb_build_object(
                'streaming', COALESCE(v_model.supports_streaming, true),
                'functions', COALESCE(v_model.supports_functions, false)
            ),
            v_model.context_window,
            v_model.max_tokens,
            v_model.input_price,
            v_model.output_price,
            v_model.tier_required,
            v_model.is_active,
            COALESCE(v_model.health_status, 'healthy'),
            v_model.health_message
        ) ON CONFLICT (model_id) DO UPDATE
        SET 
            display_name = EXCLUDED.display_name,
            input_price = EXCLUDED.input_price,
            output_price = EXCLUDED.output_price;
        
        -- Insert into model_sources
        INSERT INTO model_sources (
            model_id,
            provider_type,
            provider_name,
            provider_model_id,
            original_input_price,
            original_output_price,
            priority,
            is_available
        ) VALUES (
            v_model.model,
            'direct',
            v_model.provider,
            v_model.provider_model_id,
            v_model.input_price,
            v_model.output_price,
            100, -- High priority for direct providers
            true
        ) ON CONFLICT (model_id, provider_name) DO NOTHING;
    END LOOP;
    
    -- Migrate aggregator models
    FOR v_model IN 
        SELECT DISTINCT ON (am.model_id) am.*, ap.name as provider_name
        FROM aggregator_models am
        JOIN api_providers ap ON am.provider_id = ap.id
        WHERE am.is_available = true
    LOOP
        -- Insert into models table
        INSERT INTO models (
            model_id,
            display_name,
            model_type,
            capabilities,
            context_window,
            max_output_tokens,
            input_price,
            output_price,
            training_cutoff,
            is_active
        ) VALUES (
            v_model.model_id,
            v_model.display_name,
            v_model.model_type,
            v_model.capabilities,
            v_model.context_window,
            v_model.max_output_tokens,
            COALESCE((v_model.pricing->>'input')::DECIMAL, 0),
            COALESCE((v_model.pricing->>'output')::DECIMAL, 0),
            v_model.training_cutoff,
            true
        ) ON CONFLICT (model_id) DO UPDATE
        SET 
            -- Update capabilities by merging
            capabilities = models.capabilities || EXCLUDED.capabilities,
            -- Keep the best specs
            context_window = GREATEST(models.context_window, EXCLUDED.context_window),
            max_output_tokens = GREATEST(models.max_output_tokens, EXCLUDED.max_output_tokens);
        
        -- Insert into model_sources
        INSERT INTO model_sources (
            model_id,
            provider_type,
            provider_name,
            provider_model_id,
            original_input_price,
            original_output_price,
            priority,
            is_available
        ) VALUES (
            v_model.model_id,
            'aggregator',
            v_model.provider_name,
            v_model.model_name,
            COALESCE((v_model.pricing->>'input')::DECIMAL, 0),
            COALESCE((v_model.pricing->>'output')::DECIMAL, 0),
            50, -- Lower priority for aggregators
            true
        ) ON CONFLICT (model_id, provider_name) DO NOTHING;
    END LOOP;
    
    -- Set recommended tags for popular models
    UPDATE models SET tags = array_append(tags, 'recommended') 
    WHERE model_id IN ('gpt-4', 'gpt-3.5-turbo', 'claude-3-opus', 'claude-3-sonnet');
    
    UPDATE models SET tags = array_append(tags, 'fast') 
    WHERE model_id IN ('gpt-3.5-turbo', 'claude-3-haiku', 'gemini-1.5-flash');
    
    UPDATE models SET tags = array_append(tags, 'vision') 
    WHERE capabilities->>'vision' = 'true';
    
    RAISE NOTICE 'Migration completed successfully';
END;
$$ LANGUAGE plpgsql;

-- Step 7: Create RLS policies
-- =====================================================

-- Enable RLS
ALTER TABLE models ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_routing_logs ENABLE ROW LEVEL SECURITY;

-- Models table policies
CREATE POLICY "models_select_authenticated" ON models
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "models_admin_all" ON models
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM admin_users
            WHERE admin_users.user_id = auth.uid()
        )
    );

-- Model sources policies
CREATE POLICY "model_sources_select_authenticated" ON model_sources
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "model_sources_admin_all" ON model_sources
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM admin_users
            WHERE admin_users.user_id = auth.uid()
        )
    );

-- Routing logs policies
CREATE POLICY "routing_logs_admin_select" ON model_routing_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM admin_users
            WHERE admin_users.user_id = auth.uid()
        )
    );

CREATE POLICY "routing_logs_insert_service" ON model_routing_logs
    FOR INSERT TO service_role
    USING (true);

-- Step 8: Create helper functions for the Edge Function
-- =====================================================

-- Update the existing get_model_provider_config_v2 to use new structure
CREATE OR REPLACE FUNCTION get_model_provider_config_v3(p_model_id TEXT)
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
    input_price NUMERIC,
    output_price NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH optimal_source AS (
        SELECT * FROM get_optimal_model_source(p_model_id)
    )
    SELECT 
        os.source_id as provider_id,
        os.provider_type,
        os.provider_name,
        p_model_id as model_name,
        COALESCE(os.api_endpoint, 
            CASE os.provider_name
                WHEN 'openai' THEN 'https://api.openai.com/v1'
                WHEN 'anthropic' THEN 'https://api.anthropic.com/v1'
                WHEN 'google' THEN 'https://generativelanguage.googleapis.com/v1beta'
                ELSE ap.base_url
            END
        ) as base_url,
        os.api_key,
        os.api_key_id,
        os.api_standard,
        ap.features,
        os.custom_headers,
        m.input_price,
        m.output_price
    FROM optimal_source os
    LEFT JOIN api_providers ap ON ap.name = os.provider_name
    JOIN models m ON m.model_id = p_model_id
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Add comment explaining the migration
COMMENT ON FUNCTION migrate_to_unified_models() IS 
'Migrates existing model_configs and aggregator_models data to the new unified models structure.
This creates a single source of truth for all AI models regardless of their provider source.';