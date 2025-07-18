-- 修复 get_available_api_key 函数，使 p_model 参数可选

DROP FUNCTION IF EXISTS get_available_api_key(text, text);

CREATE OR REPLACE FUNCTION get_available_api_key(
  p_provider text,
  p_model text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  api_key text,
  rate_limit_remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 返回可用的 API key（按照优先级排序）
  RETURN QUERY
  SELECT 
    ak.id,
    ak.api_key,
    ak.rate_limit_remaining
  FROM api_key_pool ak
  WHERE 
    ak.provider = p_provider
    AND ak.is_active = true
    AND ak.consecutive_errors < 5
    AND ak.rate_limit_remaining > 0
  ORDER BY 
    ak.rate_limit_remaining DESC,  -- 优先使用剩余配额多的
    ak.last_used_at ASC NULLS FIRST,  -- 优先使用最久未使用的
    ak.total_requests ASC  -- 优先使用请求次数少的
  LIMIT 1;
END;
$$;

-- 授予 service_role 执行权限（Edge Functions 使用）
GRANT EXECUTE ON FUNCTION get_available_api_key(text, text) TO service_role;

-- 测试函数（只传一个参数）
SELECT * FROM get_available_api_key('openai');