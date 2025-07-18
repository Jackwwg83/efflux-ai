-- Create function to get provider health stats
CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE(
  provider TEXT,
  active_keys INTEGER,
  total_keys INTEGER,
  total_requests BIGINT,
  total_errors BIGINT,
  error_rate DECIMAL(5,2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.provider,
    COUNT(CASE WHEN p.is_active = true AND p.consecutive_errors < 5 THEN 1 END)::INTEGER as active_keys,
    COUNT(*)::INTEGER as total_keys,
    COALESCE(SUM(p.total_requests), 0) as total_requests,
    COALESCE(SUM(p.error_count), 0) as total_errors,
    CASE 
      WHEN COALESCE(SUM(p.total_requests), 0) > 0 
      THEN ROUND((COALESCE(SUM(p.error_count), 0)::DECIMAL / SUM(p.total_requests)) * 100, 2)
      ELSE 0
    END as error_rate
  FROM api_key_pool p
  GROUP BY p.provider;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_usage_logs_created_at ON usage_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_model ON usage_logs(user_id, model);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO service_role;