-- 创建获取可用 API Key 的函数

CREATE OR REPLACE FUNCTION get_available_api_key(
  p_provider text,
  p_model text
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

-- 创建更新 API Key 使用统计的函数
CREATE OR REPLACE FUNCTION update_api_key_usage(
  p_key_id uuid,
  p_success boolean,
  p_error_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_success THEN
    -- 成功：重置连续错误计数，增加请求计数
    UPDATE api_key_pool
    SET 
      last_used_at = NOW(),
      total_requests = total_requests + 1,
      consecutive_errors = 0,
      last_error = NULL
    WHERE id = p_key_id;
  ELSE
    -- 失败：增加错误计数
    UPDATE api_key_pool
    SET 
      last_used_at = NOW(),
      total_requests = total_requests + 1,
      error_count = error_count + 1,
      consecutive_errors = consecutive_errors + 1,
      last_error = p_error_message
    WHERE id = p_key_id;
  END IF;
END;
$$;

-- 授予 service_role 执行权限
GRANT EXECUTE ON FUNCTION update_api_key_usage(uuid, boolean, text) TO service_role;

-- 测试函数
SELECT * FROM get_available_api_key('openai', 'gpt-4');