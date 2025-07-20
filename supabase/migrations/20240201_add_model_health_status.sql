-- 为 model_configs 表添加健康状态监控字段

-- 1. 添加健康状态相关字段
ALTER TABLE model_configs 
ADD COLUMN IF NOT EXISTS health_status text DEFAULT 'healthy' CHECK (health_status IN ('healthy', 'degraded', 'unavailable', 'maintenance')),
ADD COLUMN IF NOT EXISTS health_message text,
ADD COLUMN IF NOT EXISTS health_checked_at timestamptz DEFAULT now(),
ADD COLUMN IF NOT EXISTS consecutive_failures integer DEFAULT 0;

-- 2. 创建记录模型调用失败的 RPC 函数
CREATE OR REPLACE FUNCTION record_model_failure(
  p_model text,
  p_provider text,
  p_error_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_failures integer;
  v_model_id uuid;
BEGIN
  -- 获取模型ID和当前失败次数
  SELECT id, consecutive_failures INTO v_model_id, v_current_failures
  FROM model_configs
  WHERE model = p_model AND provider = p_provider;

  IF v_model_id IS NULL THEN
    RETURN;
  END IF;

  -- 增加失败次数
  v_current_failures := v_current_failures + 1;

  -- 根据失败次数更新健康状态
  UPDATE model_configs
  SET 
    consecutive_failures = v_current_failures,
    health_checked_at = now(),
    health_status = CASE
      WHEN v_current_failures >= 5 THEN 'unavailable'
      WHEN v_current_failures >= 3 THEN 'degraded'
      ELSE 'healthy'
    END,
    health_message = CASE
      WHEN v_current_failures >= 5 THEN 'Model temporarily unavailable due to repeated failures'
      WHEN v_current_failures >= 3 THEN 'Model experiencing issues, may be slow or unreliable'
      ELSE p_error_message
    END
  WHERE id = v_model_id;
END;
$$;

-- 3. 创建记录模型调用成功的 RPC 函数（重置失败计数）
CREATE OR REPLACE FUNCTION record_model_success(
  p_model text,
  p_provider text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE model_configs
  SET 
    consecutive_failures = 0,
    health_status = 'healthy',
    health_message = NULL,
    health_checked_at = now()
  WHERE model = p_model AND provider = p_provider;
END;
$$;

-- 4. 创建手动设置模型健康状态的 RPC 函数（管理员使用）
CREATE OR REPLACE FUNCTION set_model_health_status(
  p_model_id uuid,
  p_status text,
  p_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 只有管理员可以手动设置状态
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE model_configs
  SET 
    health_status = p_status,
    health_message = p_message,
    health_checked_at = now(),
    -- 如果手动设置为 healthy，重置失败计数
    consecutive_failures = CASE WHEN p_status = 'healthy' THEN 0 ELSE consecutive_failures END
  WHERE id = p_model_id;
END;
$$;

-- 5. 授予执行权限
GRANT EXECUTE ON FUNCTION record_model_failure(text, text, text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION record_model_success(text, text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION set_model_health_status(uuid, text, text) TO authenticated;

-- 6. 创建索引以优化查询
CREATE INDEX IF NOT EXISTS idx_model_configs_health_status ON model_configs(health_status);

-- 7. 验证字段添加成功
SELECT 
  column_name, 
  data_type,
  column_default
FROM information_schema.columns 
WHERE table_name = 'model_configs' 
  AND column_name IN ('health_status', 'health_message', 'health_checked_at', 'consecutive_failures')
ORDER BY ordinal_position;