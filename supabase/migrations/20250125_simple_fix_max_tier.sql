-- Simple fix for the 'max' tier issue

BEGIN;

-- First update all 'max' tier values to 'premium'
UPDATE models 
SET tier_required = 'premium'
WHERE tier_required = 'max';

-- Check if there are any other non-standard values
SELECT DISTINCT tier_required, COUNT(*) as count
FROM models 
WHERE tier_required NOT IN ('free', 'pro', 'premium', 'enterprise')
AND tier_required IS NOT NULL
GROUP BY tier_required;

-- If the above query returns empty, we can proceed with the model activation optimization
-- First, disable all models
UPDATE models SET is_active = false;

-- Enable only the most popular and recent models (50-70 models)
UPDATE models SET is_active = true
WHERE 
  -- Featured models
  is_featured = true
  
  -- Latest GPT-4 models
  OR model_id IN (
    'gpt-4-turbo-2024-04-09', 
    'gpt-4o', 
    'gpt-4o-mini', 
    'gpt-4-vision-preview',
    'gpt-4'
  )
  
  -- Latest GPT-3.5 models
  OR model_id IN (
    'gpt-3.5-turbo',
    'gpt-3.5-turbo-1106',
    'gpt-3.5-turbo-0125'
  )
  
  -- Claude 3 family
  OR model_id IN (
    'claude-3-opus-20240229',
    'claude-3-sonnet-20240229',
    'claude-3-haiku-20240307',
    'claude-3-5-sonnet-20241022',
    'claude-2.1'
  )
  
  -- Gemini models
  OR model_id IN (
    'gemini-pro',
    'gemini-pro-vision',
    'gemini-1.5-pro',
    'gemini-1.5-flash'
  )
  
  -- Popular open-source models
  OR model_id IN (
    'llama-3-70b-instruct',
    'llama-3-8b-instruct',
    'mixtral-8x7b-instruct',
    'mistral-7b-instruct',
    'deepseek-coder-v2',
    'qwen2-72b-instruct'
  )
  
  -- Other popular models
  OR model_id IN (
    'command-r-plus',
    'command-r',
    'dall-e-3',
    'text-embedding-3-small',
    'text-embedding-3-large'
  );

-- Show results
SELECT 
  'Model Activation Summary' as report,
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  ROUND((COUNT(*) FILTER (WHERE is_active = true)::numeric / COUNT(*)::numeric) * 100, 2) as active_percentage
FROM models;

-- Show tier distribution of active models
SELECT 
  COALESCE(tier_required, 'free') as tier,
  COUNT(*) as active_model_count
FROM models
WHERE is_active = true
GROUP BY tier_required
ORDER BY 
  CASE COALESCE(tier_required, 'free')
    WHEN 'free' THEN 1
    WHEN 'pro' THEN 2
    WHEN 'premium' THEN 3
    WHEN 'enterprise' THEN 4
  END;

COMMIT;