-- Fix tier data before updating constraint

BEGIN;

-- First, let's see what tier values currently exist
SELECT DISTINCT tier_required, COUNT(*) 
FROM models 
GROUP BY tier_required 
ORDER BY tier_required;

-- Update any non-standard tier values to standard ones
UPDATE models 
SET tier_required = CASE
  -- Map any non-standard values to standard ones
  WHEN tier_required IS NULL THEN NULL
  WHEN tier_required IN ('free', 'pro', 'premium', 'enterprise') THEN tier_required
  WHEN tier_required = 'basic' THEN 'free'
  WHEN tier_required = 'professional' THEN 'pro'
  WHEN tier_required = 'business' THEN 'pro'
  WHEN tier_required = 'advanced' THEN 'premium'
  WHEN tier_required = 'max' THEN 'premium'  -- Map 'max' to 'premium'
  WHEN tier_required = 'ultimate' THEN 'premium'
  WHEN tier_required = 'plus' THEN 'pro'
  ELSE 'free' -- Default any unknown values to free
END
WHERE tier_required IS NOT NULL;

-- Log the changes
SELECT 'Tier values cleaned up' as status, COUNT(*) as models_updated
FROM models 
WHERE tier_required = 'max';

-- Now we can safely drop and recreate the constraint
ALTER TABLE models DROP CONSTRAINT IF EXISTS models_tier_required_check;

-- Add new constraint that includes all tiers we want
ALTER TABLE models ADD CONSTRAINT models_tier_required_check 
CHECK (tier_required IN ('free', 'pro', 'premium', 'enterprise') OR tier_required IS NULL);

-- Now run the optimized defaults
-- First, disable all models
UPDATE models SET is_active = false;

-- Enable popular and recent models based on patterns
UPDATE models SET is_active = true
WHERE 
  -- Featured models should always be active
  is_featured = true
  
  -- GPT-4 series (latest versions only)
  OR model_id IN ('gpt-4-turbo-2024-04-09', 'gpt-4o', 'gpt-4o-mini', 'gpt-4-vision-preview', 'gpt-4-turbo', 'gpt-4')
  
  -- GPT-3.5 series (latest versions only)
  OR model_id IN ('gpt-3.5-turbo', 'gpt-3.5-turbo-1106', 'gpt-3.5-turbo-0125')
  
  -- Claude 3 series (all variants)
  OR model_id LIKE 'claude-3-opus%'
  OR model_id LIKE 'claude-3-sonnet%'
  OR model_id LIKE 'claude-3-haiku%'
  OR model_id LIKE 'claude-3-5%'
  OR model_id = 'claude-2.1'
  
  -- Google Gemini series
  OR model_id IN ('gemini-pro', 'gemini-pro-vision', 'gemini-1.5-pro', 'gemini-1.5-flash')
  
  -- Popular open-source models (latest versions)
  OR model_id LIKE 'llama-3-%'
  OR model_id IN ('mixtral-8x7b-instruct', 'mixtral-8x22b-instruct')
  OR model_id IN ('mistral-7b-instruct', 'mistral-large')
  OR model_id = 'deepseek-coder-v2'
  OR model_id LIKE 'qwen2-%'
  
  -- Other popular models
  OR model_id IN ('command-r-plus', 'command-r')
  
  -- Image generation models (popular ones)
  OR model_id = 'dall-e-3'
  OR model_id = 'stable-diffusion-xl'
  
  -- Embedding models (commonly used)
  OR model_id IN ('text-embedding-3-small', 'text-embedding-3-large', 'text-embedding-ada-002');

-- Additionally enable models with specific tags
UPDATE models SET is_active = true
WHERE 
  'recommended' = ANY(tags)
  OR 'popular' = ANY(tags);

-- Show the results
SELECT 
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  COUNT(*) FILTER (WHERE is_active = false) as inactive_models,
  ROUND((COUNT(*) FILTER (WHERE is_active = true)::numeric / COUNT(*)::numeric) * 100, 2) as active_percentage
FROM models;

-- Show tier distribution
SELECT 
  COALESCE(tier_required, 'free') as tier,
  COUNT(*) as model_count,
  COUNT(*) FILTER (WHERE is_active = true) as active_count
FROM models
GROUP BY tier_required
ORDER BY 
  CASE COALESCE(tier_required, 'free')
    WHEN 'free' THEN 1
    WHEN 'pro' THEN 2
    WHEN 'premium' THEN 3
    WHEN 'enterprise' THEN 4
  END;

-- List some activated models
SELECT model_id, display_name, tier_required, is_featured, is_active
FROM models 
WHERE is_active = true
ORDER BY 
  CASE 
    WHEN is_featured THEN 0
    WHEN model_id LIKE 'gpt-4%' THEN 1
    WHEN model_id LIKE 'claude-3%' THEN 2
    ELSE 3
  END,
  model_id
LIMIT 30;

COMMIT;