-- 修复 api_key_pool 表的 provider check constraint
-- 这个约束限制了 provider 只能是特定的值，需要更新它

-- 1. 查看当前的约束
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'api_key_pool'::regclass
AND contype = 'c';

-- 2. 删除旧的 check constraint
ALTER TABLE api_key_pool 
DROP CONSTRAINT IF EXISTS api_key_pool_provider_check;

-- 3. 添加新的 check constraint，包含所有聚合器
ALTER TABLE api_key_pool 
ADD CONSTRAINT api_key_pool_provider_check 
CHECK (provider IN (
    'openai', 'anthropic', 'google', 'bedrock',  -- 原有的直接提供商
    'aihubmix', 'openrouter', 'novitaai', 'siliconflow',  -- 聚合器
    'togetherai', 'deepinfra', 'groq', 'anyscale',
    'perplexity', 'fireworks'
));

-- 4. 验证约束已更新
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'api_key_pool'::regclass
AND contype = 'c';