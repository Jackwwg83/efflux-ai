-- =====================================================
-- 最终修复版本：统一模型系统迁移脚本
-- 只使用实际存在的列
-- =====================================================

-- 步骤1: 重命名旧表，保留数据
-- =====================================================

-- 1.1 重命名现有的 models 表为 models_old
ALTER TABLE IF EXISTS models RENAME TO models_old;

-- 1.2 重命名现有的 model_routing_logs 表（如果结构不对）
ALTER TABLE IF EXISTS model_routing_logs RENAME TO model_routing_logs_old;

-- =====================================================
-- 步骤2: 创建新的统一模型表结构
-- =====================================================

-- 2.1 创建新的 models 表
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

-- 创建索引
CREATE INDEX idx_models_active ON models(is_active, model_type);
CREATE INDEX idx_models_featured ON models(is_featured);
CREATE INDEX idx_models_tags ON models USING GIN(tags);

-- 2.2 创建新的 model_routing_logs 表
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

-- 创建索引
CREATE INDEX idx_routing_logs_model ON model_routing_logs(model_id, created_at);
CREATE INDEX idx_routing_logs_provider ON model_routing_logs(provider_name, created_at);

-- =====================================================
-- 步骤3: 迁移数据（只使用实际存在的列）
-- =====================================================

-- 3.1 从 model_configs 表迁移数据到新的 models 表
-- 基于实际的列：provider, model, display_name, input_price, output_price, 
-- max_tokens, context_window, tier_required, is_active, description
INSERT INTO models (
    model_id,
    display_name,
    description,
    model_type,
    capabilities,
    context_window,
    max_output_tokens,
    custom_name,
    input_price,
    output_price,
    tier_required,
    tags,
    is_active,
    is_featured
)
SELECT 
    mc.model,
    mc.display_name,
    mc.description,
    'chat', -- Default to chat type
    jsonb_build_object(
        'vision', false, -- 默认不支持 vision，后面会根据模型名称更新
        'function_calling', COALESCE(mc.supports_functions, false),
        'streaming', COALESCE(mc.supports_streaming, true)
    ),
    mc.context_window,
    mc.max_tokens as max_output_tokens,
    NULL, -- custom_name 不存在，设为 NULL
    mc.input_price,
    mc.output_price,
    mc.tier_required,
    CASE 
        WHEN mc.display_name LIKE '%GPT-4%' THEN ARRAY['powerful', 'recommended']
        WHEN mc.display_name LIKE '%Claude%' THEN ARRAY['powerful', 'popular']
        WHEN mc.display_name LIKE '%GPT-3.5%' THEN ARRAY['fast', 'popular']
        ELSE ARRAY[]::TEXT[]
    END,
    mc.is_active,
    false -- Set featured manually later
FROM model_configs mc
ON CONFLICT (model_id) DO NOTHING;

-- 3.2 更新支持 vision 的模型（基于模型名称）
UPDATE models 
SET capabilities = jsonb_set(capabilities, '{vision}', 'true'::jsonb)
WHERE model_id IN (
    'gpt-4-vision-preview',
    'gpt-4-turbo',
    'gpt-4-turbo-2024-04-09',
    'gpt-4o',
    'gpt-4o-2024-05-13',
    'claude-3-opus-20240229',
    'claude-3-sonnet-20240229',
    'claude-3-haiku-20240307',
    'gemini-pro-vision',
    'gemini-1.5-pro',
    'gemini-1.5-flash'
) OR display_name LIKE '%vision%' OR display_name LIKE '%Vision%';

-- 3.3 清理并重新填充 model_sources 表
TRUNCATE model_sources;

-- 从 model_configs 创建直接提供商的 model sources
-- 注意：original_input_price 和 original_output_price 在 model_configs 中不存在
INSERT INTO model_sources (
    model_id,
    provider_type,
    provider_name,
    provider_model_id,
    original_input_price,
    original_output_price,
    priority,
    weight,
    api_standard,
    is_available
)
SELECT 
    mc.model,
    'direct',
    mc.provider,
    mc.model,
    mc.input_price, -- 使用 input_price 作为 original_input_price
    mc.output_price, -- 使用 output_price 作为 original_output_price
    CASE 
        WHEN mc.provider = 'openai' THEN 100
        WHEN mc.provider = 'anthropic' THEN 95
        WHEN mc.provider = 'google' THEN 90
        ELSE 80
    END,
    100,
    CASE 
        WHEN mc.provider = 'openai' THEN 'openai'
        WHEN mc.provider = 'anthropic' THEN 'anthropic'
        WHEN mc.provider = 'google' THEN 'google'
        ELSE 'openai'
    END,
    mc.is_active
FROM model_configs mc;

-- 3.4 从 aggregator_models 迁移数据
-- 首先确保这些模型存在于 models 表中
INSERT INTO models (
    model_id,
    display_name,
    description,
    model_type,
    capabilities,
    context_window,
    max_output_tokens,
    input_price,
    output_price,
    tier_required,
    tags,
    is_active,
    is_featured
)
SELECT DISTINCT
    am.model_id,
    am.model_name,
    'Model from ' || am.aggregator_name,
    am.model_type,
    COALESCE(am.capabilities, '{"streaming": true, "function_calling": false, "vision": false}'::jsonb),
    am.context_window,
    am.max_output_tokens,
    am.input_price,
    am.output_price,
    'free',
    CASE 
        WHEN am.model_name LIKE '%gpt-4%' THEN ARRAY['powerful']
        WHEN am.model_name LIKE '%claude%' THEN ARRAY['powerful']
        WHEN am.model_name LIKE '%gpt-3.5%' THEN ARRAY['fast']
        ELSE ARRAY[]::TEXT[]
    END,
    am.is_active,
    COALESCE(am.is_featured, false)
FROM aggregator_models am
ON CONFLICT (model_id) DO UPDATE SET
    -- Update pricing if aggregator has better prices
    input_price = LEAST(EXCLUDED.input_price, models.input_price),
    output_price = LEAST(EXCLUDED.output_price, models.output_price),
    -- Update capabilities if aggregator has more info
    capabilities = CASE 
        WHEN EXCLUDED.capabilities IS NOT NULL 
        THEN models.capabilities || EXCLUDED.capabilities 
        ELSE models.capabilities 
    END;

-- 创建聚合器的 model sources
INSERT INTO model_sources (
    model_id,
    provider_type,
    provider_name,
    provider_model_id,
    original_input_price,
    original_output_price,
    priority,
    weight,
    api_endpoint,
    api_standard,
    is_available
)
SELECT 
    am.model_id,
    'aggregator',
    am.aggregator_name,
    am.aggregator_model_id,
    am.original_input_price,
    am.original_output_price,
    CASE 
        WHEN am.aggregator_name = 'openrouter' THEN 90
        WHEN am.aggregator_name = 'aigateway' THEN 85
        ELSE 80
    END,
    100,
    am.api_endpoint,
    'openai', -- Most aggregators use OpenAI-compatible API
    am.is_active
FROM aggregator_models am;

-- 3.5 设置一些模型为推荐
UPDATE models 
SET is_featured = true 
WHERE model_id IN (
    'gpt-4-turbo-preview',
    'gpt-4',
    'gpt-4o',
    'claude-3-opus-20240229',
    'claude-3-sonnet-20240229',
    'gpt-3.5-turbo',
    'gemini-1.5-pro'
);

-- 3.6 添加更多标签
UPDATE models SET tags = array_append(tags, 'new') 
WHERE created_at > NOW() - INTERVAL '30 days';

UPDATE models SET tags = array_append(tags, 'vision') 
WHERE (capabilities->>'vision')::boolean = true;

UPDATE models SET tags = array_append(tags, 'fast') 
WHERE model_id LIKE '%turbo%' OR model_id LIKE '%flash%' OR model_id LIKE '%haiku%';

-- =====================================================
-- 步骤4: 创建必要的函数
-- =====================================================

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

-- =====================================================
-- 步骤5: 设置 RLS
-- =====================================================

-- Enable RLS
ALTER TABLE models ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_routing_logs ENABLE ROW LEVEL SECURITY;

-- Create policies
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
    )
    WITH CHECK (
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
    )
    WITH CHECK (
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
    WITH CHECK (true);

-- =====================================================
-- 步骤6: 创建辅助函数
-- =====================================================

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

CREATE OR REPLACE FUNCTION update_user_usage(p_user_id UUID, p_tokens INTEGER, p_cost DECIMAL)
RETURNS void AS $$
BEGIN
    -- Placeholder - implement based on your user usage tracking needs
    NULL;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 步骤7: 验证迁移
-- =====================================================

-- 查看迁移结果
SELECT 
    'Models' as table_name,
    COUNT(*) as count
FROM models
UNION ALL
SELECT 
    'Model Sources' as table_name,
    COUNT(*) as count
FROM model_sources
UNION ALL
SELECT 
    'Direct Sources' as table_name,
    COUNT(*) as count
FROM model_sources
WHERE provider_type = 'direct'
UNION ALL
SELECT 
    'Aggregator Sources' as table_name,
    COUNT(*) as count
FROM model_sources
WHERE provider_type = 'aggregator';

-- 测试新函数
SELECT * FROM get_all_models_with_sources() LIMIT 5;