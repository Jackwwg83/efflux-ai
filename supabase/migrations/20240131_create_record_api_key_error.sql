-- 创建记录 API Key 错误的函数

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

-- 授予 service_role 执行权限
GRANT EXECUTE ON FUNCTION record_api_key_error(uuid, text) TO service_role;