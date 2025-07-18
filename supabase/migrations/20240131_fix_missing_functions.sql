-- Fix missing database functions for Edge Function

-- 1. Drop existing functions if they exist
DROP FUNCTION IF EXISTS check_and_update_user_quota(uuid, text, integer);
DROP FUNCTION IF EXISTS get_available_api_key(text);
DROP FUNCTION IF EXISTS record_api_key_error(uuid, text);
DROP FUNCTION IF EXISTS record_api_key_success(uuid, integer);
DROP FUNCTION IF EXISTS update_user_usage(uuid, integer, numeric);

-- 2. Create check_and_update_user_quota function
CREATE OR REPLACE FUNCTION check_and_update_user_quota(
  p_user_id uuid,
  p_model text,
  p_estimated_tokens integer
)
RETURNS TABLE(
  can_use boolean,
  daily_limit integer,
  used_today integer,
  remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tier text;
  v_daily_limit integer;
  v_used_today integer;
  v_remaining integer;
BEGIN
  -- Get user tier and daily limit
  SELECT u.tier, t.daily_token_limit
  INTO v_tier, v_daily_limit
  FROM users u
  JOIN user_tiers t ON u.tier = t.tier
  WHERE u.id = p_user_id;
  
  -- Get tokens used today
  SELECT COALESCE(SUM(total_tokens), 0)::integer
  INTO v_used_today
  FROM usage_logs
  WHERE user_id = p_user_id
    AND created_at >= CURRENT_DATE
    AND status = 'success';
  
  -- Calculate remaining
  v_remaining := v_daily_limit - v_used_today;
  
  -- Check if user can use (has enough quota)
  RETURN QUERY
  SELECT 
    (v_remaining >= p_estimated_tokens) AS can_use,
    v_daily_limit,
    v_used_today,
    v_remaining;
END;
$$;

-- 3. Create get_available_api_key function
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
    AND (k.rate_limit_reset IS NULL OR k.rate_limit_reset < NOW())
  ORDER BY 
    k.last_used_at ASC NULLS FIRST,
    k.total_requests ASC
  LIMIT 1;
  
  -- Update last_used_at for the selected key
  IF FOUND THEN
    UPDATE api_key_pool
    SET last_used_at = NOW()
    WHERE api_key_pool.id = (SELECT id FROM api_key_pool WHERE provider = p_provider AND is_active = true ORDER BY last_used_at ASC NULLS FIRST, total_requests ASC LIMIT 1);
  END IF;
END;
$$;

-- 4. Create record_api_key_error function
CREATE OR REPLACE FUNCTION record_api_key_error(
  p_api_key_id uuid,
  p_error_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update API key statistics
  UPDATE api_key_pool
  SET 
    error_count = error_count + 1,
    last_error_at = NOW(),
    last_error_message = p_error_message,
    -- Disable key if too many errors
    is_active = CASE 
      WHEN error_count >= 5 THEN false 
      ELSE is_active 
    END
  WHERE id = p_api_key_id;
END;
$$;

-- 5. Create record_api_key_success function  
CREATE OR REPLACE FUNCTION record_api_key_success(
  p_api_key_id uuid,
  p_tokens_used integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update API key statistics
  UPDATE api_key_pool
  SET 
    total_requests = total_requests + 1,
    total_tokens = total_tokens + p_tokens_used,
    last_success_at = NOW(),
    -- Reset error count on success
    error_count = 0
  WHERE id = p_api_key_id;
END;
$$;

-- 6. Create update_user_usage function
CREATE OR REPLACE FUNCTION update_user_usage(
  p_user_id uuid,
  p_tokens integer,
  p_cost numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update user's total usage
  UPDATE users
  SET 
    total_tokens_used = total_tokens_used + p_tokens,
    total_cost = total_cost + p_cost,
    updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- 7. Grant necessary permissions
GRANT EXECUTE ON FUNCTION check_and_update_user_quota(uuid, text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_available_api_key(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_api_key_error(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_api_key_success(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION update_user_usage(uuid, integer, numeric) TO authenticated, service_role;

-- 8. Also ensure the models table exists and has data
-- Check if we have Google models
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM models WHERE provider = 'google' LIMIT 1) THEN
    -- Insert Google Gemini 2.5 models
    INSERT INTO models (provider, model_id, display_name, description, context_window, max_tokens, input_price_per_1k, output_price_per_1k, supports_streaming, supports_functions, supports_vision, default_temperature, provider_model_id) VALUES
    ('google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google 旗下最强大的思考型模型，回答准确性最高，性能出色', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-2.5-pro'),
    ('google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', '在性价比方面表现出色的模型，可提供全面的功能', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.5-flash'),
    ('google', 'gemini-2.5-flash-lite-preview', 'Gemini 2.5 Flash-Lite Preview', '经过优化，提高了成本效益并缩短了延迟时间', 1048576, 8192, 0.00005, 0.00015, true, true, true, 1.0, 'gemini-2.5-flash-lite-preview-06-17'),
    ('google', 'gemini-2.0-flash', 'Gemini 2.0 Flash', '新一代功能、速度和实时流式传输', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.0-flash');
  END IF;
END $$;

-- 9. Verify everything is set up
SELECT 'Functions created successfully' as status;