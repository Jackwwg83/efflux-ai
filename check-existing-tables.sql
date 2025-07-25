-- 检查现有表结构
-- 1. 检查 model_configs 表结构
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'model_configs'
ORDER BY ordinal_position;

-- 2. 检查 aggregator_models 表结构
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'aggregator_models'
ORDER BY ordinal_position;

-- 3. 检查是否已存在 models 表
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'models'
);

-- 4. 检查是否已存在 model_sources 表
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'model_sources'
);