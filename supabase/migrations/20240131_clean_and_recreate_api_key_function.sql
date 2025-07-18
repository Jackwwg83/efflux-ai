-- 清理并重新创建 get_available_api_key 函数

-- 1. 删除所有版本的函数
DROP FUNCTION IF EXISTS get_available_api_key(text);
DROP FUNCTION IF EXISTS get_available_api_key(text, text);

-- 2. 创建新函数，支持可选的第二个参数
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

-- 3. 授予 service_role 执行权限（Edge Functions 使用）
GRANT EXECUTE ON FUNCTION get_available_api_key(text, text) TO service_role;

-- 4. 创建 record_api_key_error 函数（如果不存在）
CREATE OR REPLACE FUNCTION record_api_key_error(
  p_api_key_id uuid,
  p_error_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE api_key_pool
  SET 
    consecutive_errors = consecutive_errors + 1,
    error_count = error_count + 1,
    last_error = p_error_message,
    last_used_at = NOW()
  WHERE id = p_api_key_id;
END;
$$;

-- 5. 授予权限
GRANT EXECUTE ON FUNCTION record_api_key_error(uuid, text) TO service_role;

-- 6. 测试函数
SELECT * FROM get_available_api_key('google');
SELECT * FROM get_available_api_key('openai');
SELECT * FROM get_available_api_key('anthropic');