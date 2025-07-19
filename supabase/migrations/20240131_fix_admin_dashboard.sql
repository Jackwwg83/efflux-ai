-- Fix admin dashboard errors

-- 1. Create users_view to show user information
CREATE OR REPLACE VIEW users_view AS
SELECT 
  id,
  email,
  created_at,
  updated_at,
  last_sign_in_at
FROM auth.users;

-- Grant permissions
GRANT SELECT ON users_view TO authenticated;

-- 2. Create get_provider_health_stats function
CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE (
  provider text,
  status text,
  active_keys bigint,
  total_keys bigint,
  error_rate numeric,
  last_error text
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH provider_stats AS (
    SELECT 
      ak.provider,
      COUNT(*) as total_keys,
      COUNT(*) FILTER (WHERE ak.is_active = true AND ak.consecutive_errors < 5) as active_keys,
      MAX(ak.last_error) as last_error,
      AVG(CASE WHEN ak.consecutive_errors > 0 THEN 1 ELSE 0 END) * 100 as error_rate
    FROM api_key_pool ak
    GROUP BY ak.provider
  )
  SELECT 
    ps.provider,
    CASE 
      WHEN ps.active_keys = 0 THEN 'down'
      WHEN ps.error_rate > 50 THEN 'degraded'
      ELSE 'healthy'
    END::text as status,
    ps.active_keys,
    ps.total_keys,
    ROUND(ps.error_rate, 2) as error_rate,
    ps.last_error
  FROM provider_stats ps;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;

-- 3. Create RLS policies for usage_logs if they don't exist
DO $$ 
BEGIN
  -- Drop existing policies if any
  DROP POLICY IF EXISTS "Admins can view usage logs" ON usage_logs;
  
  -- Create new policy
  CREATE POLICY "Admins can view usage logs"
  ON usage_logs FOR SELECT
  TO authenticated
  USING (auth_is_admin());
  
  -- Also allow users to see their own logs
  DROP POLICY IF EXISTS "Users can view own usage logs" ON usage_logs;
  
  CREATE POLICY "Users can view own usage logs"
  ON usage_logs FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
END $$;

-- 4. Create missing table if it doesn't exist
CREATE TABLE IF NOT EXISTS usage_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id),
  model text,
  provider text,
  api_key_id uuid REFERENCES api_key_pool(id),
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  estimated_cost numeric(10,6),
  latency_ms integer,
  status text,
  error_message text,
  created_at timestamptz DEFAULT now()
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_created_at ON usage_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_provider ON usage_logs(provider);

-- Enable RLS
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;

-- 5. Grant necessary permissions
GRANT SELECT ON usage_logs TO authenticated;
GRANT INSERT ON usage_logs TO service_role;