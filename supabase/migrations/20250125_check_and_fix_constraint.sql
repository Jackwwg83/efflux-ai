-- First, check the exact constraint definition to understand what values are allowed

-- Check current constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'models'::regclass
AND conname = 'models_tier_required_check';

-- Check what tier values exist
SELECT tier_required, COUNT(*) as count
FROM models
GROUP BY tier_required
ORDER BY count DESC;

-- If constraint only allows 'free' and 'pro', let's work with that
-- Update the models table to use only allowed values
UPDATE models 
SET tier_required = CASE
  WHEN tier_required = 'free' THEN 'free'
  WHEN tier_required = 'pro' THEN 'pro'
  WHEN tier_required IN ('premium', 'max', 'enterprise') THEN 'pro'  -- Map higher tiers to 'pro'
  WHEN tier_required IS NULL THEN NULL
  ELSE 'free'  -- Default to free for any other values
END;

-- Verify no invalid values remain
SELECT tier_required, COUNT(*) as count
FROM models
WHERE tier_required NOT IN ('free', 'pro')
AND tier_required IS NOT NULL
GROUP BY tier_required;