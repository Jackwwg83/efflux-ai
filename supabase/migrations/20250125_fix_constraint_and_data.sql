-- Fix the constraint and data issues

BEGIN;

-- First, let's see the current constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'models'::regclass
AND conname = 'models_tier_required_check';

-- Update all non-standard tier values to allowed ones
-- First, let's see what values we have
SELECT DISTINCT tier_required, COUNT(*) 
FROM models 
GROUP BY tier_required 
ORDER BY tier_required;

-- Based on the error, it seems the constraint might only allow 'free' and 'pro'
-- Let's update all tier values to match the current constraint
UPDATE models 
SET tier_required = CASE
  WHEN tier_required IN ('free', 'pro') THEN tier_required
  WHEN tier_required IN ('premium', 'max', 'enterprise') THEN 'pro'
  WHEN tier_required IS NULL THEN NULL
  ELSE 'free'
END;

-- Now optimize model activation
-- Disable all models first
UPDATE models SET is_active = false;

-- Enable only the most popular and recent models
UPDATE models SET is_active = true
WHERE 
  -- Featured models
  is_featured = true
  
  -- Latest GPT models
  OR model_id IN (
    'gpt-4-turbo-2024-04-09', 
    'gpt-4o', 
    'gpt-4o-mini', 
    'gpt-4',
    'gpt-3.5-turbo',
    'gpt-3.5-turbo-1106'
  )
  
  -- Claude models
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
    'gemini-1.5-pro'
  )
  
  -- Popular open-source models
  OR model_id IN (
    'llama-3-70b-instruct',
    'llama-3-8b-instruct',
    'mixtral-8x7b-instruct',
    'mistral-7b-instruct',
    'deepseek-coder-v2'
  )
  
  -- Essential tools
  OR model_id IN (
    'dall-e-3',
    'text-embedding-3-small',
    'text-embedding-3-large'
  );

-- Set appropriate tiers (using only allowed values)
UPDATE models 
SET tier_required = 'pro'
WHERE is_active = true 
AND model_id IN (
  'gpt-4-turbo-2024-04-09',
  'gpt-4o',
  'gpt-4',
  'claude-3-opus-20240229',
  'gemini-1.5-pro'
);

-- Show results
SELECT 
  'Activation Summary' as report,
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models,
  ROUND((COUNT(*) FILTER (WHERE is_active = true)::numeric / COUNT(*)::numeric) * 100, 2) as active_percentage
FROM models;

-- Show tier distribution
SELECT 
  COALESCE(tier_required, 'free') as tier,
  COUNT(*) as total_count,
  COUNT(*) FILTER (WHERE is_active = true) as active_count
FROM models
GROUP BY tier_required
ORDER BY tier_required;

-- Show some active models
SELECT model_id, display_name, tier_required, is_featured
FROM models 
WHERE is_active = true
ORDER BY 
  CASE WHEN tier_required = 'pro' THEN 0 ELSE 1 END,
  model_id
LIMIT 20;

COMMIT;