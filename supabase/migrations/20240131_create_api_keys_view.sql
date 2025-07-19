-- Create api_keys view for backward compatibility if needed

-- 1. Drop view if exists
DROP VIEW IF EXISTS api_keys;

-- 2. Create api_keys view that maps to api_key_pool
CREATE VIEW api_keys AS
SELECT 
  id,
  provider,
  name,
  api_key,
  is_active,
  rate_limit_remaining,
  rate_limit_reset_at,
  last_used_at,
  last_error_at,
  last_success_at,
  total_requests,
  total_tokens,
  error_count,
  created_at,
  updated_at,
  created_by
FROM api_key_pool;

-- 3. Grant permissions on the view
GRANT SELECT ON api_keys TO authenticated, service_role, anon;

-- 4. Test both access methods
SELECT 'Testing direct table access' as test;
SELECT id, provider, name, is_active FROM api_key_pool WHERE provider = 'google' LIMIT 1;

SELECT 'Testing view access' as test;
SELECT id, provider, name, is_active FROM api_keys WHERE provider = 'google' LIMIT 1;