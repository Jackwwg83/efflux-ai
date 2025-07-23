-- 调试查询：检查实际的 API 调用
-- 我们需要在前端的同步代码中添加调试日志来查看 AiHubMix 返回的原始数据

-- 首先，让我们检查你的 AiHubMix API key 是否正确配置
SELECT 
    id,
    name,
    provider,
    provider_type,
    is_active,
    LEFT(api_key, 10) || '...' as api_key_preview
FROM api_key_pool 
WHERE provider = 'aihubmix';