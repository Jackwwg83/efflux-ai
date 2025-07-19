-- 查看最近的消息和使用的模型
SELECT 
    m.id,
    m.role,
    m.model,
    m.provider,
    m.total_tokens,
    LEFT(m.content, 50) as content_preview,
    m.created_at,
    c.title as conversation_title
FROM messages m
JOIN conversations c ON m.conversation_id = c.id
WHERE m.role = 'assistant'
ORDER BY m.created_at DESC
LIMIT 20;

-- 查看 API Key 使用记录
SELECT 
    akl.id,
    akl.api_key_id,
    ak.provider,
    akl.model_used,
    akl.tokens_used,
    akl.success,
    akl.error_message,
    akl.created_at
FROM api_key_logs akl
JOIN api_key_pool ak ON akl.api_key_id = ak.id
ORDER BY akl.created_at DESC
LIMIT 20;

-- 查看用户配额使用情况
SELECT 
    uq.user_id,
    uq.tokens_used,
    uq.tokens_limit,
    uq.requests_count,
    uq.last_reset,
    uq.updated_at
FROM user_quotas uq
ORDER BY uq.updated_at DESC
LIMIT 10;

-- 查看同步日志
SELECT 
    id,
    sync_type,
    results,
    triggered_by,
    error_message,
    created_at
FROM sync_logs
ORDER BY created_at DESC
LIMIT 5;