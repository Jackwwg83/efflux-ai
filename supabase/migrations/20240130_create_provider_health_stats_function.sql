-- Create function to get provider health stats
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
  SELECT 
    p.provider::text,
    CASE 
      WHEN COUNT(CASE WHEN p.is_active AND p.consecutive_errors < 5 THEN 1 END) = 0 THEN 'down'
      WHEN (SUM(p.error_count)::numeric / NULLIF(SUM(p.total_requests), 0) * 100) > 10 THEN 'degraded'
      ELSE 'healthy'
    END::text AS status,
    COUNT(CASE WHEN p.is_active AND p.consecutive_errors < 5 THEN 1 END) AS active_keys,
    COUNT(*)::bigint AS total_keys,
    COALESCE((SUM(p.error_count)::numeric / NULLIF(SUM(p.total_requests), 0) * 100), 0) AS error_rate,
    MAX(p.last_error)::text AS last_error
  FROM api_key_pool p
  GROUP BY p.provider;
END;
$$;

-- Grant execute permission to authenticated users (for admin)
GRANT EXECUTE ON FUNCTION get_provider_health_stats() TO authenticated;