-- Migration: Add API Aggregator Provider Support
-- Description: Enable integration with API aggregator services like AiHubMix

-- =====================================================
-- API Provider Registry
-- =====================================================
CREATE TABLE IF NOT EXISTS api_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    provider_type TEXT NOT NULL CHECK (provider_type IN ('aggregator', 'direct')),
    base_url TEXT NOT NULL,
    api_standard TEXT NOT NULL CHECK (api_standard IN ('openai', 'anthropic', 'google', 'custom')),
    features JSONB DEFAULT '{}',
    documentation_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for active providers
CREATE INDEX idx_api_providers_active ON api_providers(is_active) WHERE is_active = true;

-- =====================================================
-- User API Provider Configurations
-- =====================================================
CREATE TABLE IF NOT EXISTS user_api_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    provider_id UUID REFERENCES api_providers(id) ON DELETE CASCADE NOT NULL,
    api_key_encrypted TEXT NOT NULL,
    api_key_hash TEXT NOT NULL, -- For duplicate detection
    endpoint_override TEXT, -- Custom endpoint if user wants different URL
    settings JSONB DEFAULT '{}', -- Provider-specific settings
    monthly_budget DECIMAL(10, 2), -- Optional spending limit
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, provider_id)
);

-- Indexes for user provider lookups
CREATE INDEX idx_user_api_providers_user ON user_api_providers(user_id);
CREATE INDEX idx_user_api_providers_active ON user_api_providers(user_id, is_active) WHERE is_active = true;

-- =====================================================
-- Aggregator Model Registry
-- =====================================================
CREATE TABLE IF NOT EXISTS aggregator_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID REFERENCES api_providers(id) ON DELETE CASCADE NOT NULL,
    model_id TEXT NOT NULL, -- Provider's model identifier
    model_name TEXT NOT NULL, -- Technical name
    display_name TEXT NOT NULL, -- User-friendly name
    model_type TEXT NOT NULL CHECK (model_type IN ('chat', 'completion', 'image', 'audio', 'embedding', 'moderation')),
    capabilities JSONB DEFAULT '{}', -- vision, function_calling, etc.
    pricing JSONB DEFAULT '{}', -- input/output costs
    context_window INTEGER,
    max_output_tokens INTEGER,
    training_cutoff DATE,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    is_available BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    UNIQUE(provider_id, model_id)
);

-- Indexes for model queries
CREATE INDEX idx_aggregator_models_provider ON aggregator_models(provider_id);
CREATE INDEX idx_aggregator_models_type ON aggregator_models(model_type);
CREATE INDEX idx_aggregator_models_available ON aggregator_models(is_available, model_type) WHERE is_available = true;
CREATE INDEX idx_aggregator_models_featured ON aggregator_models(is_featured) WHERE is_featured = true;

-- =====================================================
-- Model Aliases (for compatibility)
-- =====================================================
CREATE TABLE IF NOT EXISTS model_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_model_id UUID REFERENCES aggregator_models(id) ON DELETE CASCADE,
    alias TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_model_aliases_model ON model_aliases(aggregator_model_id);

-- =====================================================
-- Aggregator Usage Logs
-- =====================================================
CREATE TABLE IF NOT EXISTS aggregator_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    provider_id UUID REFERENCES api_providers(id) NOT NULL,
    model_id TEXT NOT NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    request_id TEXT, -- Provider's request ID
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    cost_estimate DECIMAL(10, 6),
    latency_ms INTEGER,
    status TEXT CHECK (status IN ('success', 'error', 'timeout', 'cancelled')),
    error_code TEXT,
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for usage analytics (fixed: removed DATE functions from index definitions)
CREATE INDEX idx_aggregator_usage_user_date ON aggregator_usage_logs(user_id, created_at DESC);
CREATE INDEX idx_aggregator_usage_provider ON aggregator_usage_logs(provider_id, created_at DESC);
CREATE INDEX idx_aggregator_usage_model ON aggregator_usage_logs(model_id, created_at DESC);

-- =====================================================
-- Insert Initial Providers
-- =====================================================

-- AiHubMix
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features, documentation_url)
VALUES (
    'aihubmix',
    'AiHubMix',
    'aggregator',
    'https://api.aihubmix.com/v1',
    'openai',
    '{
        "supports_streaming": true,
        "supports_functions": true,
        "supports_vision": true,
        "supports_audio": true,
        "supports_embeddings": true,
        "supports_image_generation": true,
        "model_list_endpoint": "/models",
        "requires_model_prefix": false,
        "header_format": "Bearer"
    }'::jsonb,
    'https://docs.aihubmix.com'
) ON CONFLICT (name) DO NOTHING;

-- OpenRouter
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features, documentation_url)
VALUES (
    'openrouter',
    'OpenRouter',
    'aggregator',
    'https://openrouter.ai/api/v1',
    'openai',
    '{
        "supports_streaming": true,
        "supports_functions": true,
        "supports_vision": true,
        "requires_referer": true,
        "requires_site_name": true,
        "model_list_endpoint": "/models",
        "header_format": "Bearer"
    }'::jsonb,
    'https://openrouter.ai/docs'
) ON CONFLICT (name) DO NOTHING;

-- =====================================================
-- RLS Policies
-- =====================================================

-- API Providers (read-only for all authenticated users)
ALTER TABLE api_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "api_providers_select" ON api_providers
    FOR SELECT TO authenticated
    USING (is_active = true);

-- User API Providers (users manage their own)
ALTER TABLE user_api_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_api_providers_select" ON user_api_providers
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "user_api_providers_insert" ON user_api_providers
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_api_providers_update" ON user_api_providers
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "user_api_providers_delete" ON user_api_providers
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- Aggregator Models (read-only for all authenticated users)
ALTER TABLE aggregator_models ENABLE ROW LEVEL SECURITY;

CREATE POLICY "aggregator_models_select" ON aggregator_models
    FOR SELECT TO authenticated
    USING (is_available = true);

-- Model Aliases (read-only)
ALTER TABLE model_aliases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "model_aliases_select" ON model_aliases
    FOR SELECT TO authenticated
    USING (true);

-- Usage Logs (users see their own)
ALTER TABLE aggregator_usage_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "aggregator_usage_logs_select" ON aggregator_usage_logs
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "aggregator_usage_logs_insert" ON aggregator_usage_logs
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- Helper Functions
-- =====================================================

-- Function to get user's available models
CREATE OR REPLACE FUNCTION get_user_available_models(p_user_id UUID)
RETURNS TABLE (
    model_id TEXT,
    display_name TEXT,
    provider_name TEXT,
    model_type TEXT,
    context_window INTEGER,
    is_aggregator BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    -- Direct provider models (existing logic)
    SELECT 
        mc.model as model_id,
        mc.model as display_name,
        mc.provider as provider_name,
        'chat' as model_type,
        CASE
            WHEN mc.model LIKE '%32k%' THEN 32768
            WHEN mc.model LIKE '%16k%' THEN 16384
            WHEN mc.model LIKE '%100k%' THEN 100000
            ELSE 8192
        END as context_window,
        false as is_aggregator
    FROM model_configs mc
    WHERE mc.is_active = true
    
    UNION ALL
    
    -- Aggregator models
    SELECT 
        am.model_id,
        am.display_name,
        ap.display_name as provider_name,
        am.model_type,
        am.context_window,
        true as is_aggregator
    FROM aggregator_models am
    JOIN api_providers ap ON am.provider_id = ap.id
    JOIN user_api_providers uap ON uap.provider_id = ap.id
    WHERE uap.user_id = p_user_id
        AND uap.is_active = true
        AND am.is_available = true
        AND ap.is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Function to validate and get provider config
CREATE OR REPLACE FUNCTION get_model_provider_config(p_user_id UUID, p_model_id TEXT)
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
        COALESCE(uap.endpoint_override, ap.base_url) as base_url,
        uap.api_key_encrypted as api_key,
        uap.id as api_key_id,
        ap.api_standard,
        ap.features,
        uap.settings->'custom_headers' as custom_headers,
        COALESCE((ap.features->>'requires_referer')::boolean, false) as requires_referer,
        COALESCE((ap.features->>'requires_site_name')::boolean, false) as requires_site_name,
        COALESCE((am.pricing->>'input')::numeric, 0) as input_price,
        COALESCE((am.pricing->>'output')::numeric, 0) as output_price
    FROM aggregator_models am
    JOIN api_providers ap ON am.provider_id = ap.id
    JOIN user_api_providers uap ON uap.provider_id = ap.id
    WHERE am.model_id = p_model_id
        AND uap.user_id = p_user_id
        AND uap.is_active = true
        AND ap.is_active = true
        AND am.is_available = true
    LIMIT 1;
    
    -- If not found, return empty (will fall back to direct provider logic)
    IF NOT FOUND THEN
        RETURN;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Triggers
-- =====================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_api_providers_updated_at
    BEFORE UPDATE ON api_providers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_user_api_providers_updated_at
    BEFORE UPDATE ON user_api_providers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_aggregator_models_updated_at
    BEFORE UPDATE ON aggregator_models
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- Additional indexes for analytics (using created_at directly)
-- =====================================================

-- Performance indexes for daily and monthly analytics
CREATE INDEX idx_aggregator_usage_logs_user_created ON aggregator_usage_logs(user_id, created_at);
CREATE INDEX idx_aggregator_usage_logs_provider_created ON aggregator_usage_logs(provider_id, created_at);

-- =====================================================
-- Comments for Documentation
-- =====================================================

COMMENT ON TABLE api_providers IS 'Registry of API providers including aggregators like AiHubMix';
COMMENT ON TABLE user_api_providers IS 'User configurations for each API provider';
COMMENT ON TABLE aggregator_models IS 'Available models from aggregator providers';
COMMENT ON TABLE aggregator_usage_logs IS 'Detailed usage tracking for aggregator API calls';
COMMENT ON COLUMN api_providers.api_standard IS 'API format standard: openai, anthropic, google, or custom';
COMMENT ON COLUMN user_api_providers.api_key_hash IS 'SHA-256 hash for duplicate detection';
COMMENT ON COLUMN aggregator_models.capabilities IS 'JSON object with boolean flags for vision, functions, etc';