-- =====================================================
-- Data Migration from Old Tables to Unified System
-- =====================================================

-- Step 1: Migrate data from model_configs to models table
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
        'vision', mc.supports_vision,
        'function_calling', mc.supports_function_calling
    ),
    mc.context_window,
    mc.max_output_tokens,
    mc.custom_name,
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

-- Step 2: Create model sources for direct provider models
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
    mc.original_input_price,
    mc.original_output_price,
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
FROM model_configs mc
ON CONFLICT (model_id, provider_name) DO NOTHING;

-- Step 3: Migrate aggregator models
-- First, ensure aggregator models exist in the models table
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
    'chat',
    '{}',
    128000, -- Default context window
    4096,   -- Default max output
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
    false
FROM aggregator_models am
ON CONFLICT (model_id) DO UPDATE SET
    -- Update pricing if aggregator has better prices
    input_price = LEAST(EXCLUDED.input_price, models.input_price),
    output_price = LEAST(EXCLUDED.output_price, models.output_price);

-- Step 4: Create model sources for aggregator models
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
FROM aggregator_models am
ON CONFLICT (model_id, provider_name) DO NOTHING;

-- Step 5: Set some models as featured
UPDATE models 
SET is_featured = true 
WHERE model_id IN (
    'gpt-4-turbo-preview',
    'gpt-4',
    'claude-3-opus-20240229',
    'claude-3-sonnet-20240229',
    'gpt-3.5-turbo',
    'gemini-pro'
);

-- Step 6: Update tags for specific models
UPDATE models SET tags = array_append(tags, 'vision') 
WHERE model_id IN ('gpt-4-vision-preview', 'claude-3-opus-20240229', 'gemini-pro-vision');

UPDATE models SET tags = array_append(tags, 'new') 
WHERE created_at > NOW() - INTERVAL '30 days';

-- Step 7: Verify migration
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