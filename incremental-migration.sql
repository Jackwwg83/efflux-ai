-- =====================================================
-- Incremental Unified Model System Migration
-- This version handles existing tables gracefully
-- =====================================================

-- Step 1: Check and create models table if needed
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'models') THEN
        CREATE TABLE models (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            
            -- Core model identification
            model_id TEXT UNIQUE NOT NULL,
            display_name TEXT NOT NULL,
            description TEXT,
            model_type TEXT NOT NULL DEFAULT 'chat' CHECK (model_type IN ('chat', 'completion', 'image', 'audio', 'embedding', 'moderation')),
            
            -- Aggregated capabilities from all sources
            capabilities JSONB DEFAULT '{}',
            context_window INTEGER,
            max_output_tokens INTEGER,
            training_cutoff DATE,
            
            -- Admin configurations
            custom_name TEXT,
            input_price DECIMAL(10,6) DEFAULT 0,
            output_price DECIMAL(10,6) DEFAULT 0,
            tier_required TEXT DEFAULT 'free' CHECK (tier_required IN ('free', 'pro', 'max')),
            priority INTEGER DEFAULT 0,
            tags TEXT[] DEFAULT '{}',
            
            -- Status and health
            is_active BOOLEAN DEFAULT true,
            is_featured BOOLEAN DEFAULT false,
            health_status TEXT DEFAULT 'healthy' CHECK (health_status IN ('healthy', 'degraded', 'unavailable', 'maintenance')),
            health_message TEXT,
            
            -- Metadata
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        
        -- Create indexes
        CREATE INDEX idx_models_active ON models(is_active, model_type);
        CREATE INDEX idx_models_featured ON models(is_featured);
        CREATE INDEX idx_models_tags ON models USING GIN(tags);
    END IF;
END $$;

-- Step 2: Add missing columns to model_sources if it exists
DO $$
BEGIN
    -- Check if model_sources exists
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'model_sources') THEN
        -- Add columns if they don't exist
        IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'model_sources' AND column_name = 'provider_type') THEN
            ALTER TABLE model_sources ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'direct' CHECK (provider_type IN ('direct', 'aggregator'));
        END IF;
        
        IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'model_sources' AND column_name = 'provider_model_id') THEN
            ALTER TABLE model_sources ADD COLUMN provider_model_id TEXT;
        END IF;
        
        IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'model_sources' AND column_name = 'api_standard') THEN
            ALTER TABLE model_sources ADD COLUMN api_standard TEXT DEFAULT 'openai';
        END IF;
        
        IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'model_sources' AND column_name = 'custom_headers') THEN
            ALTER TABLE model_sources ADD COLUMN custom_headers JSONB DEFAULT '{}';
        END IF;
    ELSE
        -- Create the table if it doesn't exist
        CREATE TABLE model_sources (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            model_id TEXT NOT NULL,
            
            -- Provider information
            provider_type TEXT NOT NULL CHECK (provider_type IN ('direct', 'aggregator')),
            provider_name TEXT NOT NULL,
            provider_model_id TEXT,
            
            -- Original pricing from provider
            original_input_price DECIMAL(10,6) DEFAULT 0,
            original_output_price DECIMAL(10,6) DEFAULT 0,
            
            -- Routing configuration
            priority INTEGER DEFAULT 0,
            weight INTEGER DEFAULT 100,
            
            -- Provider-specific configurations
            api_endpoint TEXT,
            api_standard TEXT DEFAULT 'openai',
            custom_headers JSONB DEFAULT '{}',
            
            -- Status tracking
            is_available BOOLEAN DEFAULT true,
            last_checked TIMESTAMPTZ DEFAULT NOW(),
            consecutive_failures INTEGER DEFAULT 0,
            average_latency_ms INTEGER,
            
            UNIQUE(model_id, provider_name)
        );
        
        -- Create indexes
        CREATE INDEX idx_model_sources_routing ON model_sources(model_id, is_available, priority DESC);
        CREATE INDEX idx_model_sources_provider ON model_sources(provider_name, is_available);
    END IF;
END $$;

-- Step 3: Create routing logs table if needed
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'model_routing_logs') THEN
        CREATE TABLE model_routing_logs (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            model_id TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            user_id UUID,
            
            -- Routing decision
            selected_source_id UUID,
            routing_reason TEXT,
            
            -- Performance metrics
            latency_ms INTEGER,
            tokens_used INTEGER,
            estimated_cost DECIMAL(10,6),
            
            -- Status
            status TEXT DEFAULT 'routing' CHECK (status IN ('success', 'error', 'timeout', 'routing')),
            error_message TEXT,
            
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        
        -- Create indexes
        CREATE INDEX idx_routing_logs_model ON model_routing_logs(model_id, created_at);
        CREATE INDEX idx_routing_logs_provider ON model_routing_logs(provider_name, created_at);
    END IF;
END $$;

-- Step 4: Create or replace RPC functions
-- Function to get available models for a user
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

-- Function to get all models with sources (for admin)
CREATE OR REPLACE FUNCTION get_all_models_with_sources()
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    custom_name TEXT,
    model_type TEXT,
    capabilities JSONB,
    context_window INTEGER,
    max_output_tokens INTEGER,
    input_price DECIMAL,
    output_price DECIMAL,
    tier_required TEXT,
    tags TEXT[],
    is_active BOOLEAN,
    is_featured BOOLEAN,
    health_status TEXT,
    available_sources INTEGER,
    sources JSONB
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
        m.max_output_tokens,
        m.input_price,
        m.output_price,
        m.tier_required,
        m.tags,
        m.is_active,
        m.is_featured,
        m.health_status,
        COUNT(ms.id)::INTEGER as available_sources,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'provider_name', ms.provider_name,
                    'provider_type', ms.provider_type,
                    'is_available', ms.is_available,
                    'priority', ms.priority
                ) 
                ORDER BY ms.priority DESC
            ) FILTER (WHERE ms.id IS NOT NULL),
            '[]'::jsonb
        ) as sources
    FROM models m
    LEFT JOIN model_sources ms ON ms.model_id = m.model_id
    GROUP BY m.model_id, m.display_name, m.custom_name, m.model_type,
             m.capabilities, m.context_window, m.max_output_tokens,
             m.input_price, m.output_price, m.tier_required, m.tags,
             m.is_active, m.is_featured, m.health_status;
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
        id as source_id,
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

-- Update the model provider config function for compatibility
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

-- Step 5: Enable RLS
ALTER TABLE models ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_routing_logs ENABLE ROW LEVEL SECURITY;

-- Create policies (drop existing ones first to avoid conflicts)
DROP POLICY IF EXISTS "models_select_authenticated" ON models;
DROP POLICY IF EXISTS "models_admin_all" ON models;
DROP POLICY IF EXISTS "model_sources_select_authenticated" ON model_sources;
DROP POLICY IF EXISTS "model_sources_admin_all" ON model_sources;
DROP POLICY IF EXISTS "routing_logs_admin_select" ON model_routing_logs;
DROP POLICY IF EXISTS "routing_logs_insert_service" ON model_routing_logs;

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

-- Step 6: Create helper function for incrementing failures
CREATE OR REPLACE FUNCTION increment_source_failures(p_source_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE model_sources
    SET consecutive_failures = consecutive_failures + 1,
        is_available = CASE 
            WHEN consecutive_failures >= 5 THEN false 
            ELSE is_available 
        END
    WHERE id = p_source_id;
END;
$$ LANGUAGE plpgsql;

-- Step 7: Create function to update user usage (if not exists)
CREATE OR REPLACE FUNCTION update_user_usage(p_user_id UUID, p_tokens INTEGER, p_cost DECIMAL)
RETURNS void AS $$
BEGIN
    -- This is a placeholder - implement based on your user usage tracking needs
    -- For example, you might have a user_usage table to update
    NULL;
END;
$$ LANGUAGE plpgsql;