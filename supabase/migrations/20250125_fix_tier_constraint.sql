-- First, let's check what tier values are allowed
-- and update the constraint if needed

BEGIN;

-- Check current constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'models'::regclass
AND conname LIKE '%tier%';

-- If the constraint doesn't include 'premium', we need to update it
-- First drop the old constraint
ALTER TABLE models DROP CONSTRAINT IF EXISTS models_tier_required_check;

-- Add new constraint that includes all tiers we want
ALTER TABLE models ADD CONSTRAINT models_tier_required_check 
CHECK (tier_required IN ('free', 'pro', 'premium', 'enterprise') OR tier_required IS NULL);

-- Now run the optimized defaults without tier updates
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

-- Set proper tiers for expensive models (now that constraint is fixed)
UPDATE models SET tier_required = 'pro'
WHERE is_active = true
AND tier_required IS NULL -- Only update if not already set
AND (
  model_id LIKE 'gpt-4%'
  OR model_id LIKE 'claude-3-opus%'
  OR model_id LIKE 'claude-3-sonnet%'
  OR model_id LIKE 'gemini-1.5-pro%'
  OR input_price > 10 -- Models costing more than $10 per million tokens
);

UPDATE models SET tier_required = 'premium'
WHERE is_active = true
AND tier_required IS NULL -- Only update if not already set
AND (
  model_id = 'gpt-4-turbo-2024-04-09'
  OR model_id = 'gpt-4o-2024-08-06'
  OR model_id = 'claude-3-opus-20240229'
  OR input_price > 20 -- Very expensive models
);

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

COMMIT;