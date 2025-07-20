-- 1. 检查 model_configs 表的健康状态
SELECT 
  provider,
  model,
  display_name,
  health_status,
  health_message,
  consecutive_failures,
  is_active
FROM model_configs
WHERE is_active = true
ORDER BY provider, model;

-- 2. 检查 API key pool
SELECT 
  provider,
  COUNT(*) as total_keys,
  COUNT(*) FILTER (WHERE is_active = true) as active_keys
FROM api_key_pool
GROUP BY provider;

-- 3. 如果需要，更新所有模型的健康状态为默认值
UPDATE model_configs
SET 
  health_status = COALESCE(health_status, 'healthy'),
  consecutive_failures = COALESCE(consecutive_failures, 0),
  health_checked_at = COALESCE(health_checked_at, now())
WHERE health_status IS NULL;

-- 4. 测试：手动设置一些模型的健康状态（可选）
-- 设置 GPT-3.5 为降级状态
UPDATE model_configs
SET 
  health_status = 'degraded',
  health_message = '响应速度较慢',
  consecutive_failures = 3
WHERE model = 'gpt-3.5-turbo';

-- 设置某个 Anthropic 模型为维护状态
UPDATE model_configs
SET 
  health_status = 'maintenance',
  health_message = '正在进行系统维护'
WHERE model = 'claude-3-opus' AND provider = 'anthropic';

-- 5. 再次查看更新后的结果
SELECT 
  provider,
  model,
  display_name,
  health_status,
  health_message,
  consecutive_failures
FROM model_configs
WHERE is_active = true
  AND (health_status != 'healthy' OR health_status IS NOT NULL)
ORDER BY provider, model;