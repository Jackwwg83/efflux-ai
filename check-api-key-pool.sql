-- 检查 api_key_pool 表的结构

-- 1. 查看 api_key_pool 表的所有列
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'api_key_pool'
  AND table_schema = 'public'
ORDER BY ordinal_position;

-- 2. 查看 api_providers 表的结构
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'api_providers'
  AND table_schema = 'public'
ORDER BY ordinal_position
LIMIT 10;

-- 3. 查看一些 api_key_pool 数据样本
SELECT * FROM api_key_pool LIMIT 3;

-- 4. 查看一些 api_providers 数据样本
SELECT id, name, provider_type FROM api_providers LIMIT 5;