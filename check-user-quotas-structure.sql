-- 检查 user_quotas 表的实际结构
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'user_quotas'
ORDER BY ordinal_position;