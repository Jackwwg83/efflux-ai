-- 修复权限问题的SQL脚本
-- 在 Supabase SQL Editor 中运行这个脚本

-- 1. 修复 api_providers 表的 RLS 策略
ALTER TABLE api_providers ENABLE ROW LEVEL SECURITY;

-- 删除旧策略
DROP POLICY IF EXISTS "api_providers_admin_all" ON api_providers;
DROP POLICY IF EXISTS "api_providers_select_all" ON api_providers;

-- 创建新策略：所有认证用户都可以读取
CREATE POLICY "api_providers_read_all" ON api_providers
    FOR SELECT TO authenticated
    USING (true);

-- 只有管理员可以写入
CREATE POLICY "api_providers_admin_write" ON api_providers
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "api_providers_admin_update" ON api_providers
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "api_providers_admin_delete" ON api_providers
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- 2. 修复 get_provider_health_stats 函数
CREATE OR REPLACE FUNCTION get_provider_health_stats()
RETURNS TABLE (
    provider TEXT,
    total_keys INTEGER,
    active_keys INTEGER,
    total_requests BIGINT,
    total_errors BIGINT,
    avg_latency NUMERIC
) 
SECURITY DEFINER
AS $$
BEGIN
    -- 检查是否是管理员
    IF NOT EXISTS (
        SELECT 1 FROM auth.users 
        WHERE id = auth.uid() 
        AND raw_user_meta_data->>'role' = 'admin'
    ) THEN
        RAISE EXCEPTION 'Access denied: Admin role required';
    END IF;

    RETURN QUERY
    SELECT 
        akp.provider,
        COUNT(*)::INTEGER as total_keys,
        SUM(CASE WHEN akp.is_active THEN 1 ELSE 0 END)::INTEGER as active_keys,
        COALESCE(SUM(akp.total_requests), 0) as total_requests,
        COALESCE(SUM(akp.error_count), 0) as total_errors,
        COALESCE(AVG(akp.average_latency_ms), 0) as avg_latency
    FROM api_key_pool akp
    GROUP BY akp.provider;
END;
$$ LANGUAGE plpgsql;

-- 3. 添加 AiHubMix 聚合器（如果还没有的话）
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features, is_enabled) VALUES
('aihubmix', 'AiHubMix', 'aggregator', 'https://api.aihubmix.com/v1', 'openai', 
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb, true)
ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  provider_type = EXCLUDED.provider_type,
  base_url = EXCLUDED.base_url,
  api_standard = EXCLUDED.api_standard,
  features = EXCLUDED.features,
  is_enabled = EXCLUDED.is_enabled;

-- 4. 确认数据已插入
SELECT name, display_name, provider_type, is_enabled 
FROM api_providers 
WHERE provider_type = 'aggregator';