-- Debug and test API key retrieval

-- 1. First, let's verify the table exists and has data
SELECT 
  'Checking api_key_pool table' as step,
  COUNT(*) as total_keys,
  COUNT(*) FILTER (WHERE provider = 'google') as google_keys,
  COUNT(*) FILTER (WHERE provider = 'google' AND is_active = true) as active_google_keys
FROM api_key_pool;

-- 2. Check the actual Google API key data
SELECT 
  id,
  provider,
  name,
  is_active,
  rate_limit_remaining,
  rate_limit_reset,
  last_used_at,
  error_count
FROM api_key_pool
WHERE provider = 'google';

-- 3. Test the function directly
SELECT 'Testing get_available_api_key function' as step;
SELECT * FROM get_available_api_key('google'::text);

-- 4. Check if there's an api_keys view or table that might be confusing things
SELECT 
  table_name,
  table_type
FROM information_schema.tables 
WHERE table_name LIKE '%api_key%'
  AND table_schema = 'public';

-- 5. Check all functions related to api keys
SELECT 
  routine_name,
  routine_type,
  routine_definition
FROM information_schema.routines
WHERE routine_name LIKE '%api_key%'
  AND routine_schema = 'public';