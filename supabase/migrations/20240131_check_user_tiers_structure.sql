-- Check user_tiers table structure and data

-- 1. Check user_tiers columns
SELECT 'user_tiers columns:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'user_tiers'
ORDER BY ordinal_position;

-- 2. Check sample data from user_tiers
SELECT 'user_tiers data:' as info;
SELECT * FROM user_tiers LIMIT 5;

-- 3. Check if there are any token/limit related columns
SELECT 'Token/limit related columns in user_tiers:' as info;
SELECT 
    column_name
FROM information_schema.columns 
WHERE table_name = 'user_tiers'
  AND (column_name LIKE '%token%' 
       OR column_name LIKE '%limit%'
       OR column_name LIKE '%quota%'
       OR column_name LIKE '%daily%'
       OR column_name LIKE '%monthly%');