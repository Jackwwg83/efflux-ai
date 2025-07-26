-- Update to latest AI models only (2025)
-- Remove old models and keep only the newest generation

BEGIN;

-- First, disable ALL models
UPDATE models SET is_active = false;

-- Now activate ONLY the latest models based on search results

-- OpenAI Latest Models (2025)
UPDATE models SET is_active = true, tier_required = 
  CASE 
    -- O-series (most expensive reasoning models)
    WHEN model_id IN ('o3', 'o3-pro') THEN 'max'
    WHEN model_id = 'o4-mini' THEN 'pro'  -- $1.10/$4.40 per million
    
    -- GPT-4.1 series (new in 2025)
    WHEN model_id LIKE 'gpt-4.1%' THEN 'pro'
    WHEN model_id LIKE 'gpt-4.1-nano%' THEN 'free'
    
    -- GPT-4o series (keep latest only)
    WHEN model_id = 'gpt-4o' THEN 'pro'  -- $3/$10 per million
    WHEN model_id = 'gpt-4o-mini' THEN 'free'  -- $0.15/$0.60 per million
    
    ELSE tier_required
  END
WHERE model_id IN (
  -- O-series
  'o3', 'o3-pro', 'o4-mini',
  -- GPT-4.1 series
  'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano',
  -- GPT-4o (latest only)
  'gpt-4o', 'gpt-4o-mini'
);

-- Anthropic Claude Latest Models (2025)
UPDATE models SET is_active = true, tier_required = 
  CASE 
    -- Claude 4 series (newest, most expensive)
    WHEN model_id LIKE '%opus-4%' OR model_id = 'claude-4-opus' THEN 'max'  -- $15/$75 per million
    WHEN model_id LIKE '%sonnet-4%' OR model_id = 'claude-4-sonnet' THEN 'pro'  -- $3/$15 per million
    
    -- Claude 3.7 (latest thinking model)
    WHEN model_id LIKE '%3-7-sonnet%' OR model_id = 'claude-3.7-sonnet' THEN 'pro'  -- $3/$15 per million
    
    -- Claude 3.5 Haiku (cheapest current model)
    WHEN model_id LIKE '%3-5-haiku%' OR model_id = 'claude-3.5-haiku' THEN 'free'  -- $0.80/$4 per million
    
    ELSE tier_required
  END
WHERE model_id IN (
  -- Claude 4 series
  'claude-4-opus', 'claude-4-opus-20250501', 'claude-opus-4',
  'claude-4-sonnet', 'claude-4-sonnet-20250501', 'claude-sonnet-4',
  -- Claude 3.7
  'claude-3.7-sonnet', 'claude-3-7-sonnet-20250224',
  -- Claude 3.5 Haiku (cheapest)
  'claude-3.5-haiku', 'claude-3-5-haiku', 'claude-3.5-haiku-20241022'
);

-- Google Gemini Latest Models (2025)
UPDATE models SET is_active = true, tier_required = 
  CASE 
    -- Gemini 2.5 Pro (most expensive)
    WHEN model_id LIKE '%2-5-pro%' OR model_id = 'gemini-2.5-pro' THEN 'max'  -- $1.25-$2.50 input
    
    -- Gemini 2.5/2.0 Flash (mid-tier)
    WHEN model_id LIKE '%2-5-flash' AND model_id NOT LIKE '%lite%' THEN 'pro'
    WHEN model_id LIKE '%2-0-flash' AND model_id NOT LIKE '%lite%' THEN 'pro'
    
    -- Gemini Flash-Lite (cheapest)
    WHEN model_id LIKE '%flash-lite%' THEN 'free'  -- $0.10/$0.40 per million
    
    ELSE tier_required
  END
WHERE model_id IN (
  -- Gemini 2.5
  'gemini-2.5-pro', 'gemini-2-5-pro',
  'gemini-2.5-flash', 'gemini-2-5-flash',
  'gemini-2.5-flash-lite', 'gemini-2-5-flash-lite',
  -- Gemini 2.0
  'gemini-2.0-pro', 'gemini-2-0-pro', 'gemini-2-pro',
  'gemini-2.0-flash', 'gemini-2-0-flash',
  'gemini-2.0-flash-lite', 'gemini-2-0-flash-lite'
);

-- Add any specialized models (e.g., embedding, image generation)
UPDATE models SET is_active = true, tier_required = 'free'
WHERE model_id IN (
  -- OpenAI embeddings (latest)
  'text-embedding-3-small',
  'text-embedding-3-large',
  -- Image generation (latest)
  'dall-e-3'
);

-- Feature the most popular/recommended models
UPDATE models SET is_featured = true
WHERE is_active = true 
AND model_id IN (
  'gpt-4o',           -- OpenAI flagship
  'o4-mini',          -- OpenAI reasoning
  'claude-4-opus',    -- Claude flagship
  'claude-3.7-sonnet',-- Claude thinking
  'gemini-2.5-pro',   -- Gemini flagship
  'gemini-2.5-flash'  -- Gemini efficient
);

-- Clean up any models that don't match our patterns but might exist
-- This catches variations in naming
UPDATE models SET is_active = true, tier_required = 
  CASE
    WHEN display_name LIKE '%O3%' OR display_name LIKE '%o3%' THEN 'max'
    WHEN display_name LIKE '%O4%mini%' OR display_name LIKE '%o4%mini%' THEN 'pro'
    WHEN display_name LIKE '%GPT%4.1%' THEN 'pro'
    WHEN display_name LIKE '%Claude%4%Opus%' THEN 'max'
    WHEN display_name LIKE '%Claude%4%Sonnet%' THEN 'pro'
    WHEN display_name LIKE '%Claude%3.7%' THEN 'pro'
    WHEN display_name LIKE '%Gemini%2.5%Pro%' THEN 'max'
    WHEN display_name LIKE '%Gemini%2.5%Flash%' AND display_name NOT LIKE '%Lite%' THEN 'pro'
    WHEN display_name LIKE '%Flash%Lite%' THEN 'free'
    ELSE tier_required
  END
WHERE is_active = false
AND (
  display_name LIKE '%O3%' OR display_name LIKE '%O4%' OR
  display_name LIKE '%GPT%4.1%' OR display_name LIKE '%GPT-4.1%' OR
  display_name LIKE '%Claude%4%' OR display_name LIKE '%Claude%3.7%' OR
  display_name LIKE '%Gemini%2.5%' OR display_name LIKE '%Gemini%2.0%'
);

-- Show results
SELECT 'Model Update Summary' as report;

-- Count by provider
SELECT 
  CASE 
    WHEN model_id LIKE 'o%' OR model_id LIKE 'gpt%' THEN 'OpenAI'
    WHEN model_id LIKE 'claude%' THEN 'Anthropic'
    WHEN model_id LIKE 'gemini%' THEN 'Google'
    ELSE 'Other'
  END as provider,
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE is_active = true) as active_models
FROM models
GROUP BY provider
ORDER BY provider;

-- Show tier distribution
SELECT 
  tier_required,
  COUNT(*) as active_count,
  STRING_AGG(model_id, ', ' ORDER BY model_id) as models
FROM models
WHERE is_active = true
GROUP BY tier_required
ORDER BY 
  CASE tier_required
    WHEN 'max' THEN 1
    WHEN 'pro' THEN 2
    WHEN 'free' THEN 3
    ELSE 4
  END;

-- List all active models with details
SELECT 
  model_id,
  display_name,
  tier_required,
  is_featured,
  CASE 
    WHEN model_id LIKE 'o%' OR model_id LIKE 'gpt%' THEN 'OpenAI'
    WHEN model_id LIKE 'claude%' THEN 'Anthropic'
    WHEN model_id LIKE 'gemini%' THEN 'Google'
    ELSE 'Other'
  END as provider
FROM models 
WHERE is_active = true
ORDER BY 
  provider,
  CASE tier_required
    WHEN 'max' THEN 1
    WHEN 'pro' THEN 2
    WHEN 'free' THEN 3
  END,
  model_id;

COMMIT;