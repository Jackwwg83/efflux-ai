-- Check detailed structure of user-related tables

-- 1. Check profiles table structure
SELECT 'profiles table structure:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'profiles'
ORDER BY ordinal_position;

-- 2. Check user_quotas table structure
SELECT 'user_quotas table structure:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'user_quotas'
ORDER BY ordinal_position;

-- 3. Check users_view definition
SELECT 'users_view definition:' as info;
SELECT 
    view_definition
FROM information_schema.views
WHERE table_name = 'users_view';

-- 4. Check if profiles has user tier information
SELECT 'Sample profiles data:' as info;
SELECT * FROM profiles LIMIT 1;

-- 5. Check if user_quotas has necessary data
SELECT 'Sample user_quotas data:' as info;
SELECT * FROM user_quotas LIMIT 1;

-- 6. Check the check_and_update_user_quota function definition
SELECT 'check_and_update_user_quota function:' as info;
SELECT 
    routine_definition
FROM information_schema.routines
WHERE routine_name = 'check_and_update_user_quota';