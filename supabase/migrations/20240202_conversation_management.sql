-- 会话管理系统数据库升级

-- 1. 更新 conversations 表
ALTER TABLE conversations 
ADD COLUMN IF NOT EXISTS title text,
ADD COLUMN IF NOT EXISTS is_favorite boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS last_message_preview text,
ADD COLUMN IF NOT EXISTS message_count integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_tokens integer DEFAULT 0;

-- 创建索引优化搜索性能
CREATE INDEX IF NOT EXISTS idx_conversations_user_favorite ON conversations(user_id, is_favorite);
CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);

-- 2. 更新 model_configs 表，添加上下文窗口信息
-- 注意：context_window 字段已存在，但我们需要确保数据正确
UPDATE model_configs SET context_window = CASE
  -- OpenAI
  WHEN model = 'gpt-3.5-turbo' THEN 16385
  WHEN model = 'gpt-4-turbo' THEN 128000
  WHEN model = 'gpt-4o' THEN 128000
  WHEN model = 'gpt-4o-mini' THEN 128000
  WHEN model = 'gpt-4.1' THEN 1000000  -- 假设的未来模型
  
  -- Anthropic
  WHEN model LIKE 'claude-3%' THEN 200000
  WHEN model LIKE 'claude-3.5%' THEN 200000
  
  -- Google
  WHEN model LIKE 'gemini-2.0%' THEN 1048576  -- 1M tokens
  WHEN model LIKE 'gemini-2.5%' THEN 1048576
  
  -- Bedrock
  WHEN provider = 'bedrock' THEN 200000  -- 同 Claude
  
  ELSE context_window  -- 保持原值
END;

-- 3. 创建会话搜索函数
CREATE OR REPLACE FUNCTION search_conversations(
  p_user_id uuid,
  p_query text
)
RETURNS TABLE (
  id uuid,
  title text,
  last_message_preview text,
  updated_at timestamptz,
  is_favorite boolean,
  message_count integer,
  relevance real
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH message_search AS (
    SELECT 
      m.conversation_id,
      MAX(ts_rank(to_tsvector('english', m.content), plainto_tsquery('english', p_query))) as rank
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE c.user_id = p_user_id
      AND to_tsvector('english', m.content) @@ plainto_tsquery('english', p_query)
    GROUP BY m.conversation_id
  )
  SELECT 
    c.id,
    c.title,
    c.last_message_preview,
    c.updated_at,
    c.is_favorite,
    c.message_count,
    COALESCE(ms.rank, 0) + 
    CASE WHEN c.title ILIKE '%' || p_query || '%' THEN 1 ELSE 0 END as relevance
  FROM conversations c
  LEFT JOIN message_search ms ON ms.conversation_id = c.id
  WHERE c.user_id = p_user_id
    AND (
      ms.rank IS NOT NULL 
      OR c.title ILIKE '%' || p_query || '%'
    )
  ORDER BY relevance DESC, c.updated_at DESC
  LIMIT 50;
END;
$$;

-- 4. 创建自动生成标题的函数
CREATE OR REPLACE FUNCTION generate_conversation_title(
  p_conversation_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_first_message text;
  v_title text;
BEGIN
  -- 获取第一条用户消息
  SELECT content INTO v_first_message
  FROM messages
  WHERE conversation_id = p_conversation_id
    AND role = 'user'
  ORDER BY created_at ASC
  LIMIT 1;
  
  IF v_first_message IS NULL THEN
    RETURN 'New Conversation';
  END IF;
  
  -- 截取前50个字符作为标题
  v_title := SUBSTRING(v_first_message FROM 1 FOR 50);
  
  -- 如果被截断，添加省略号
  IF LENGTH(v_first_message) > 50 THEN
    v_title := v_title || '...';
  END IF;
  
  RETURN v_title;
END;
$$;

-- 5. 创建更新会话统计的触发器
CREATE OR REPLACE FUNCTION update_conversation_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- 更新会话统计信息
  UPDATE conversations
  SET 
    message_count = (
      SELECT COUNT(*) FROM messages WHERE conversation_id = NEW.conversation_id
    ),
    total_tokens = (
      SELECT COALESCE(SUM(total_tokens), 0) 
      FROM messages 
      WHERE conversation_id = NEW.conversation_id
    ),
    last_message_preview = CASE 
      WHEN NEW.role = 'assistant' THEN SUBSTRING(NEW.content FROM 1 FOR 100)
      ELSE last_message_preview
    END,
    updated_at = NOW()
  WHERE id = NEW.conversation_id;
  
  -- 如果是第一条消息且没有标题，自动生成
  IF NEW.role = 'user' AND NOT EXISTS (
    SELECT 1 FROM conversations 
    WHERE id = NEW.conversation_id AND title IS NOT NULL
  ) THEN
    UPDATE conversations
    SET title = generate_conversation_title(NEW.conversation_id)
    WHERE id = NEW.conversation_id;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 创建触发器
DROP TRIGGER IF EXISTS update_conversation_stats_trigger ON messages;
CREATE TRIGGER update_conversation_stats_trigger
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION update_conversation_stats();

-- 6. 创建获取会话上下文使用情况的函数
CREATE OR REPLACE FUNCTION get_conversation_context_usage(
  p_conversation_id uuid,
  p_model text
)
RETURNS TABLE (
  total_tokens integer,
  context_window integer,
  usage_percentage numeric,
  remaining_tokens integer,
  should_truncate boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH current_usage AS (
    SELECT COALESCE(SUM(m.total_tokens), 0) as tokens
    FROM messages m
    WHERE m.conversation_id = p_conversation_id
  ),
  model_limit AS (
    SELECT mc.context_window
    FROM model_configs mc
    WHERE mc.model = p_model
    LIMIT 1
  )
  SELECT 
    cu.tokens::integer as total_tokens,
    ml.context_window::integer,
    ROUND((cu.tokens::numeric / ml.context_window::numeric) * 100, 2) as usage_percentage,
    (ml.context_window - cu.tokens)::integer as remaining_tokens,
    (cu.tokens::numeric / ml.context_window::numeric) > 0.9 as should_truncate
  FROM current_usage cu, model_limit ml;
END;
$$;

-- 7. 授予权限
GRANT EXECUTE ON FUNCTION search_conversations(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION generate_conversation_title(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_conversation_context_usage(uuid, text) TO authenticated;

-- 8. 为现有会话生成标题
UPDATE conversations c
SET title = generate_conversation_title(c.id)
WHERE title IS NULL
  AND EXISTS (
    SELECT 1 FROM messages m 
    WHERE m.conversation_id = c.id 
    AND m.role = 'user'
  );

-- 9. 验证更新
SELECT 
  'Conversations with titles' as metric,
  COUNT(*) FILTER (WHERE title IS NOT NULL) as count
FROM conversations
UNION ALL
SELECT 
  'Model context windows updated' as metric,
  COUNT(*) as count
FROM model_configs
WHERE context_window > 0;