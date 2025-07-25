-- 检查 model_configs 表的确切列名
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'model_configs'
AND column_name LIKE '%support%' OR column_name LIKE '%vision%' OR column_name LIKE '%function%'
ORDER BY ordinal_position;

-- 查看前5行数据了解内容
SELECT * FROM model_configs LIMIT 5;