-- Optimize model activation with correct tier values

BEGIN;

-- First show current state
SELECT 'Current State' as status;
SELECT 
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as currently_active,
  COUNT(*) FILTER (WHERE tier_required = 'free') as free_tier,
  COUNT(*) FILTER (WHERE tier_required = 'pro') as pro_tier,
  COUNT(*) FILTER (WHERE tier_required = 'max') as max_tier
FROM models;

-- Step 1: Disable all models
UPDATE models SET is_active = false;

-- Step 2: Enable only the most popular and recent models
UPDATE models SET is_active = true
WHERE 
  -- Featured models should always be active
  is_featured = true
  
  -- Latest GPT-4 models
  OR model_id IN (
    'gpt-4-turbo-2024-04-09', 
    'gpt-4o', 
    'gpt-4o-mini', 
    'gpt-4-vision-preview',
    'gpt-4',
    'gpt-4-32k'
  )
  
  -- Latest GPT-3.5 models
  OR model_id IN (
    'gpt-3.5-turbo',
    'gpt-3.5-turbo-1106',
    'gpt-3.5-turbo-0125',
    'gpt-3.5-turbo-16k'
  )
  
  -- Claude 3 family (all variants)
  OR model_id IN (
    'claude-3-opus-20240229',
    'claude-3-sonnet-20240229',
    'claude-3-haiku-20240307',
    'claude-3-5-sonnet-20241022',
    'claude-2.1',
    'claude-instant-1.2'
  )
  
  -- Google Gemini series
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
    'llama-2-70b-chat',
    'mixtral-8x7b-instruct',
    'mixtral-8x22b-instruct',
    'mistral-7b-instruct',
    'mistral-large',
    'deepseek-coder-v2',
    'qwen2-72b-instruct',
    'qwen2-7b-instruct'
  )
  
  -- Other popular models
  OR model_id IN (
    'command-r-plus',
    'command-r',
    'yi-34b-chat'
  )
  
  -- Image generation models
  OR model_id IN (
    'dall-e-3',
    'dall-e-2',
    'stable-diffusion-xl'
  )
  
  -- Embedding models
  OR model_id IN (
    'text-embedding-3-small',
    'text-embedding-3-large',
    'text-embedding-ada-002'
  );

-- Step 3: Set appropriate tier levels using allowed values (free, pro, max)
-- Set 'max' tier for the most expensive/advanced models
UPDATE models 
SET tier_required = 'max'
WHERE is_active = true 
AND tier_required != 'max'  -- Don't override existing max tier
AND model_id IN (
  'gpt-4-turbo-2024-04-09',
  'gpt-4o',
  'claude-3-opus-20240229',
  'gemini-1.5-pro'
);

-- Set 'pro' tier for mid-range models
UPDATE models 
SET tier_required = 'pro'
WHERE is_active = true 
AND tier_required = 'free'  -- Only update if currently free
AND model_id IN (
  'gpt-4',
  'gpt-4-32k',
  'claude-3-sonnet-20240229',
  'claude-3-5-sonnet-20241022',
  'gemini-pro',
  'mixtral-8x22b-instruct',
  'llama-3-70b-instruct',
  'command-r-plus'
);

-- Everything else remains 'free' tier

-- Step 4: Show results
SELECT 'After Optimization' as status;
SELECT 
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  ROUND((COUNT(*) FILTER (WHERE is_active = true)::numeric / COUNT(*)::numeric) * 100, 2) as active_percentage
FROM models;

-- Show tier distribution of active models
SELECT 
  tier_required,
  COUNT(*) as model_count,
  ARRAY_AGG(model_id ORDER BY model_id) FILTER (WHERE ROW_NUMBER() OVER (PARTITION BY tier_required ORDER BY model_id) <= 5) as example_models
FROM models
WHERE is_active = true
GROUP BY tier_required
ORDER BY 
  CASE tier_required
    WHEN 'free' THEN 1
    WHEN 'pro' THEN 2
    WHEN 'max' THEN 3
  END;

-- List all active models grouped by tier
SELECT 
  model_id,
  display_name,
  tier_required,
  is_featured
FROM models 
WHERE is_active = true
ORDER BY 
  CASE tier_required
    WHEN 'max' THEN 0
    WHEN 'pro' THEN 1
    WHEN 'free' THEN 2
    ELSE 3
  END,
  model_id;

COMMIT;