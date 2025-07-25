-- 检查 model_sources 表的确切结构

-- 1. 查看 model_sources 表的 model_id 列类型
SELECT 
  column_name,
  data_type,
  udt_name
FROM information_schema.columns
WHERE table_name = 'model_sources'
  AND column_name = 'model_id'
  AND table_schema = 'public';

-- 2. 查看 models 表的 id 列类型
SELECT 
  column_name,
  data_type,
  udt_name
FROM information_schema.columns
WHERE table_name = 'models'
  AND column_name = 'id'
  AND table_schema = 'public';

-- 3. 查看一些 model_sources 数据样本
SELECT 
  id,
  model_id,
  provider_name,
  provider_type
FROM model_sources
LIMIT 5;

-- 4. 查看一些 models 数据样本
SELECT 
  id,
  model_id,
  display_name
FROM models
LIMIT 5;

-- 5. 测试如何正确关联这两个表
-- 看看 model_sources.model_id 存储的是什么
SELECT 
  ms.model_id as ms_model_id,
  m.id as m_id,
  m.model_id as m_model_id
FROM model_sources ms
LEFT JOIN models m ON m.id::text = ms.model_id::text
LIMIT 5;