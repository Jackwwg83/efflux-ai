-- 精确检查所有表的列名
-- 1. model_configs 表的所有列
SELECT 'model_configs columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'model_configs' 
ORDER BY ordinal_position;

-- 2. aggregator_models 表的所有列
SELECT 'aggregator_models columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'aggregator_models' 
ORDER BY ordinal_position;

-- 3. 查看 aggregator_models 的示例数据
SELECT 'aggregator_models sample data:' as info;
SELECT * FROM aggregator_models LIMIT 3;

-- 4. 查看 model_configs 的示例数据
SELECT 'model_configs sample data:' as info;
SELECT * FROM model_configs LIMIT 3;