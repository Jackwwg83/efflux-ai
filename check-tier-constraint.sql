-- Check the tier_required constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'models'::regclass
AND conname LIKE '%tier%';

-- Check current tier values
SELECT DISTINCT tier_required, COUNT(*) 
FROM models 
GROUP BY tier_required 
ORDER BY tier_required;