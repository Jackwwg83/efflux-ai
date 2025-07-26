-- Cleanup and fix model activation
-- Remove old models and fix tier assignments

BEGIN;

-- First, disable ALL models
UPDATE models SET is_active = false;

-- Only activate the LATEST models with correct tiers

-- OpenAI Latest Models (2025)
UPDATE models SET is_active = true, is_featured = false, tier_required = 
  CASE 
    -- O-series (most expensive reasoning models)
    WHEN model_id IN ('o3', 'o3-pro') THEN 'max'
    WHEN model_id = 'o3-mini' THEN 'pro'  -- Note: search showed o4-mini, but db has o3-mini
    WHEN model_id = 'o4-mini' THEN 'pro'
    
    -- GPT-4.1 series (new in 2025) 
    WHEN model_id = 'gpt-4.1' THEN 'pro'
    WHEN model_id = 'gpt-4.1-mini' THEN 'free'
    WHEN model_id = 'gpt-4.1-nano' THEN 'free'
    
    -- GPT-4o series
    WHEN model_id = 'gpt-4o' THEN 'pro'
    WHEN model_id = 'gpt-4o-mini' THEN 'free'
    
    ELSE tier_required
  END
WHERE model_id IN (
  'o3', 'o3-pro', 'o3-mini', 'o4-mini',
  'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano',
  'gpt-4o', 'gpt-4o-mini'
);

-- Anthropic ONLY Latest Models (2025)
-- Remove ALL Claude 3.x models except 3.5 Haiku and 3.7 Sonnet
UPDATE models SET is_active = true, is_featured = false, tier_required = 
  CASE 
    -- Claude 4 series (fix tier from free to proper tier)
    WHEN model_id IN ('claude-opus-4-0', 'claude-opus-4-20250514', 'anthropic-claude-opus-4-0') THEN 'max'
    WHEN model_id IN ('claude-sonnet-4-0', 'claude-sonnet-4-20250514', 'anthropic-claude-sonnet-4-0') THEN 'pro'
    
    -- Claude 3.7 Sonnet (latest thinking model - not in results but should exist)
    WHEN model_id LIKE '%3-7-sonnet%' OR model_id = 'claude-3.7-sonnet' THEN 'pro'
    
    -- Claude 3.5 Haiku ONLY (cheapest, keep it)
    WHEN model_id IN ('claude-3.5-haiku', 'claude-3-5-haiku', 'claude-3-5-haiku-20241022') THEN 'free'
    
    ELSE tier_required
  END
WHERE model_id IN (
  -- Claude 4 series
  'claude-opus-4-0', 'claude-opus-4-20250514', 'anthropic-claude-opus-4-0',
  'claude-sonnet-4-0', 'claude-sonnet-4-20250514', 'anthropic-claude-sonnet-4-0',
  -- Claude 3.7 (if exists)
  'claude-3.7-sonnet', 'claude-3-7-sonnet-20250224',
  -- Claude 3.5 Haiku ONLY
  'claude-3.5-haiku', 'claude-3-5-haiku', 'claude-3-5-haiku-20241022'
);

-- Google Gemini Latest Models ONLY (2025)
-- Keep only stable versions, not previews/experiments
UPDATE models SET is_active = true, is_featured = false, tier_required = 
  CASE 
    -- Gemini 2.5 Pro (most expensive)
    WHEN model_id = 'gemini-2.5-pro' THEN 'max'
    
    -- Gemini 2.5 Flash (mid-tier) 
    WHEN model_id = 'gemini-2.5-flash' THEN 'pro'
    
    -- Gemini 2.5/2.0 Flash-Lite (cheapest)
    WHEN model_id IN ('gemini-2.5-flash-lite', 'gemini-2.0-flash-lite') THEN 'free'
    
    -- Gemini 2.0 Flash (budget)
    WHEN model_id = 'gemini-2.0-flash' THEN 'free'
    
    ELSE tier_required
  END
WHERE model_id IN (
  -- Only stable versions
  'gemini-2.5-pro',
  'gemini-2.5-flash', 
  'gemini-2.5-flash-lite',
  'gemini-2.0-flash',
  'gemini-2.0-flash-lite'
);

-- Specialized models
UPDATE models SET is_active = true, tier_required = 'free'
WHERE model_id IN (
  'text-embedding-3-small',
  'text-embedding-3-large',
  'dall-e-3'
);

-- Set featured models (one flagship per provider)
UPDATE models SET is_featured = true
WHERE is_active = true 
AND model_id IN (
  'gpt-4o',              -- OpenAI flagship
  'o4-mini',             -- OpenAI reasoning (or o3-mini if o4-mini doesn't exist)
  'claude-opus-4-0',     -- Claude flagship  
  'gemini-2.5-pro',      -- Gemini flagship
  'gemini-2.5-flash'     -- Gemini efficient
);

-- If o4-mini doesn't exist, feature o3-mini instead
UPDATE models SET is_featured = true
WHERE is_active = true 
AND model_id = 'o3-mini'
AND NOT EXISTS (SELECT 1 FROM models WHERE model_id = 'o4-mini' AND is_active = true);

-- Final cleanup: ensure NO old models are active
UPDATE models SET is_active = false
WHERE is_active = true
AND (
  -- Old OpenAI models
  model_id LIKE 'gpt-3.5%' OR
  model_id LIKE 'gpt-4-turbo%' OR
  model_id LIKE 'gpt-4-vision%' OR
  model_id = 'gpt-4' OR
  model_id = 'gpt-4-32k' OR
  
  -- Old Claude models (except allowed ones)
  (model_id LIKE 'claude-3%' AND 
   model_id NOT IN ('claude-3.5-haiku', 'claude-3-5-haiku', 'claude-3-5-haiku-20241022', 
                    'claude-3.7-sonnet', 'claude-3-7-sonnet-20250224')) OR
  model_id LIKE 'claude-2%' OR
  model_id LIKE 'claude-instant%' OR
  
  -- Old Gemini models
  model_id LIKE 'gemini-1.5%' OR
  model_id LIKE 'gemini-pro%' OR
  
  -- Preview/experimental versions
  model_id LIKE '%preview%' OR
  model_id LIKE '%exp%' OR
  model_id LIKE '%search%' OR
  model_id LIKE '%thinking%' OR
  model_id LIKE '%nothink%'
);

-- Show final results
SELECT 'Final Model Count' as report;

SELECT 
  COUNT(*) as total_active,
  COUNT(*) FILTER (WHERE tier_required = 'max') as max_tier,
  COUNT(*) FILTER (WHERE tier_required = 'pro') as pro_tier,
  COUNT(*) FILTER (WHERE tier_required = 'free') as free_tier,
  COUNT(*) FILTER (WHERE is_featured = true) as featured
FROM models
WHERE is_active = true;

-- Show active models by provider
SELECT 
  CASE 
    WHEN model_id LIKE 'o%' OR model_id LIKE 'gpt%' THEN 'OpenAI'
    WHEN model_id LIKE 'claude%' OR model_id LIKE 'anthropic%' THEN 'Anthropic'
    WHEN model_id LIKE 'gemini%' THEN 'Google'
    ELSE 'Other'
  END as provider,
  COUNT(*) as model_count,
  STRING_AGG(model_id || ' (' || tier_required || ')', ', ' ORDER BY 
    CASE tier_required
      WHEN 'max' THEN 1
      WHEN 'pro' THEN 2
      WHEN 'free' THEN 3
    END, model_id
  ) as models
FROM models
WHERE is_active = true
GROUP BY provider
ORDER BY provider;

-- List all active models
SELECT 
  model_id,
  display_name,
  tier_required,
  is_featured,
  CASE 
    WHEN model_id LIKE 'o%' OR model_id LIKE 'gpt%' THEN 'OpenAI'
    WHEN model_id LIKE 'claude%' OR model_id LIKE 'anthropic%' THEN 'Anthropic'
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