-- 检查约束的详细信息

-- 1. 查看具体的约束定义
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint
WHERE conrelid = 'auth.users'::regclass
AND contype = 'c';

-- 2. 检查 auth 相关的配置表
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'auth'
ORDER BY table_name;

-- 3. 检查是否有 auth.config 或类似的配置
SELECT *
FROM auth.config
LIMIT 10;

-- 4. 检查 instance_id 的实际使用情况
SELECT 
    COUNT(*) as total_users,
    COUNT(DISTINCT instance_id) as distinct_instances,
    COUNT(*) FILTER (WHERE instance_id IS NULL) as null_instances,
    COUNT(*) FILTER (WHERE instance_id = '00000000-0000-0000-0000-000000000000'::uuid) as zero_instances
FROM auth.users;

-- 5. 查看最简单的用户记录，了解必需字段
SELECT 
    column_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'auth' 
AND table_name = 'users'
AND is_nullable = 'NO'
AND column_default IS NULL
ORDER BY ordinal_position;