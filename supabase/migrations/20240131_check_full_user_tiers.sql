-- Check complete user_tiers structure

-- 1. Full user_tiers structure
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'user_tiers'
ORDER BY ordinal_position;

-- 2. Sample data
SELECT * FROM user_tiers;