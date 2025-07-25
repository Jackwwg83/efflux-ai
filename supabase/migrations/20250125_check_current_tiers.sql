-- First check what tier values exist in the database
SELECT DISTINCT tier_required, COUNT(*) as count
FROM models 
GROUP BY tier_required 
ORDER BY count DESC;

-- Check the current constraint definition
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'models'::regclass
AND conname LIKE '%tier%';

-- Find any problematic rows
SELECT model_id, display_name, tier_required
FROM models
WHERE tier_required IS NOT NULL 
AND tier_required NOT IN ('free', 'pro', 'premium', 'enterprise')
LIMIT 10;