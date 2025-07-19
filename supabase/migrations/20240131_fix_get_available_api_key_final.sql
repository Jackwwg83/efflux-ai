-- Fix get_available_api_key function with correct column names

-- 1. Drop existing functions
DROP FUNCTION IF EXISTS get_available_api_key(text);
DROP FUNCTION IF EXISTS get_available_api_key(text, text);

-- 2. Create the correct version with proper column names
CREATE OR REPLACE FUNCTION get_available_api_key(p_provider text)
RETURNS TABLE(
  id uuid,
  api_key text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Select an active API key with the lowest recent usage
  -- This provides basic load balancing
  RETURN QUERY
  SELECT k.id, k.api_key
  FROM api_key_pool k
  WHERE k.provider = p_provider
    AND k.is_active = true
    AND k.rate_limit_remaining > 0
    AND (k.rate_limit_reset_at IS NULL OR k.rate_limit_reset_at < NOW())
  ORDER BY 
    k.last_used_at ASC NULLS FIRST,
    k.total_requests ASC
  LIMIT 1;
  
  -- Update last_used_at for the selected key
  IF FOUND THEN
    UPDATE api_key_pool
    SET last_used_at = NOW()
    WHERE api_key_pool.id = (
      SELECT k.id 
      FROM api_key_pool k
      WHERE k.provider = p_provider 
        AND k.is_active = true 
        AND k.rate_limit_remaining > 0
        AND (k.rate_limit_reset_at IS NULL OR k.rate_limit_reset_at < NOW())
      ORDER BY k.last_used_at ASC NULLS FIRST, k.total_requests ASC 
      LIMIT 1
    );
  END IF;
END;
$$;

-- 3. Grant permissions
GRANT EXECUTE ON FUNCTION get_available_api_key(text) TO authenticated, service_role, anon;

-- 4. Test the function
SELECT * FROM get_available_api_key('google');

-- 5. Also check the table structure to understand all columns
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'api_key_pool'
ORDER BY ordinal_position;