-- Check current database structure

-- 1. List all tables in public schema
SELECT 'Current Tables:' as info;
SELECT 
    table_name,
    table_type
FROM information_schema.tables 
WHERE table_schema = 'public'
ORDER BY table_name;

-- 2. Check if user-related tables exist
SELECT 'User-related tables:' as info;
SELECT 
    table_name
FROM information_schema.tables 
WHERE table_schema = 'public'
  AND table_name IN ('users', 'user_tiers', 'user_quotas', 'usage_logs')
ORDER BY table_name;

-- 3. Check existing types/enums
SELECT 'Custom Types:' as info;
SELECT 
    typname as type_name,
    typtype as type_type
FROM pg_type
WHERE typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND typtype IN ('e', 'c') -- enums and composite types
ORDER BY typname;

-- 4. Check columns of api_key_pool table
SELECT 'api_key_pool columns:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'api_key_pool'
ORDER BY ordinal_position;

-- 5. Check columns of model_configs table
SELECT 'model_configs columns:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'model_configs'
ORDER BY ordinal_position;

-- 6. Check if auth.users exists and has data
SELECT 'Auth users count:' as info;
SELECT COUNT(*) as user_count FROM auth.users;

-- 7. Check functions related to quota
SELECT 'Quota-related functions:' as info;
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%quota%'
ORDER BY routine_name;