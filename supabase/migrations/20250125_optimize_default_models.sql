-- Migration: Optimize default model activation
-- Only enable the most popular and recent models by default

BEGIN;

-- First, disable all models
UPDATE models SET is_active = false;

-- Enable popular and recent models based on patterns
UPDATE models SET is_active = true
WHERE 
  -- Featured models should always be active
  is_featured = true
  
  -- GPT-4 series (latest)
  OR model_id LIKE 'gpt-4-turbo%'
  OR model_id LIKE 'gpt-4o%'
  OR model_id = 'gpt-4'
  OR model_id = 'gpt-4-vision-preview'
  
  -- GPT-3.5 series (still popular)
  OR model_id LIKE 'gpt-3.5-turbo%'
  
  -- Claude 3 series (all variants)
  OR model_id LIKE 'claude-3-opus%'
  OR model_id LIKE 'claude-3-sonnet%'
  OR model_id LIKE 'claude-3-haiku%'
  OR model_id LIKE 'claude-3.5%'
  
  -- Google Gemini series
  OR model_id LIKE 'gemini-pro%'
  OR model_id LIKE 'gemini-1.5%'
  OR model_id = 'gemini-pro'
  OR model_id = 'gemini-pro-vision'
  
  -- Popular open-source models
  OR model_id LIKE 'llama-3%'
  OR model_id LIKE 'mixtral-8x7b%'
  OR model_id LIKE 'mistral-7b%'
  OR model_id = 'deepseek-coder-v2'
  OR model_id LIKE 'qwen2%'
  
  -- Amazon Bedrock popular models
  OR model_id LIKE '%claude-v3%'
  OR model_id LIKE '%titan-text%'
  
  -- Other popular models
  OR model_id = 'command-r-plus'
  OR model_id = 'command-r'
  OR model_id LIKE 'yi-%'
  
  -- Image generation models (popular ones)
  OR model_id LIKE 'dall-e-3%'
  OR model_id = 'stable-diffusion-xl'
  OR model_id = 'midjourney'
  
  -- Embedding models (commonly used)
  OR model_id LIKE 'text-embedding-3%'
  OR model_id = 'text-embedding-ada-002';

-- Additionally enable models with specific tags
UPDATE models SET is_active = true
WHERE 
  'recommended' = ANY(tags)
  OR 'popular' = ANY(tags)
  OR 'new' = ANY(tags);

-- Note: Commenting out tier updates until we verify the allowed values
-- The error suggests 'premium' might not be an allowed value in the check constraint
-- UPDATE models SET tier_required = 'pro'
-- WHERE is_active = true
-- AND (
--   model_id LIKE 'gpt-4%'
--   OR model_id LIKE 'claude-3-opus%'
--   OR model_id LIKE 'gemini-1.5-pro%'
--   OR input_price > 10 -- Models costing more than $10 per million tokens
-- );

-- UPDATE models SET tier_required = 'premium'
-- WHERE is_active = true
-- AND (
--   model_id = 'gpt-4-turbo-2024-04-09'
--   OR model_id = 'claude-3-opus-20240229'
--   OR input_price > 30 -- Very expensive models
-- );

-- Create a function to get activation statistics
CREATE OR REPLACE FUNCTION get_model_activation_stats()
RETURNS TABLE (
  total_models bigint,
  active_models bigint,
  inactive_models bigint,
  free_tier_models bigint,
  pro_tier_models bigint,
  premium_tier_models bigint,
  activation_percentage numeric
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::bigint as total_models,
    COUNT(*) FILTER (WHERE is_active = true)::bigint as active_models,
    COUNT(*) FILTER (WHERE is_active = false)::bigint as inactive_models,
    COUNT(*) FILTER (WHERE is_active = true AND (tier_required = 'free' OR tier_required IS NULL))::bigint as free_tier_models,
    COUNT(*) FILTER (WHERE is_active = true AND tier_required = 'pro')::bigint as pro_tier_models,
    COUNT(*) FILTER (WHERE is_active = true AND tier_required = 'premium')::bigint as premium_tier_models,
    ROUND((COUNT(*) FILTER (WHERE is_active = true)::numeric / COUNT(*)::numeric) * 100, 2) as activation_percentage
  FROM models;
END;
$$ LANGUAGE plpgsql;

-- Show the results
SELECT * FROM get_model_activation_stats();

-- List some of the activated models for verification
SELECT model_id, display_name, tier_required, is_featured
FROM models 
WHERE is_active = true
ORDER BY 
  CASE 
    WHEN is_featured THEN 0
    WHEN tier_required = 'premium' THEN 1
    WHEN tier_required = 'pro' THEN 2
    ELSE 3
  END,
  model_id
LIMIT 20;

COMMIT;

-- Add comment explaining the strategy
COMMENT ON FUNCTION get_model_activation_stats() IS 
'Returns statistics about model activation status. Used to monitor the distribution of active vs inactive models and their tier assignments. Default activation strategy focuses on popular, recent, and featured models while disabling outdated or rarely used models.';