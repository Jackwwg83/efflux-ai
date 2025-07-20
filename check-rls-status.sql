-- 检查各表的 RLS 状态

SELECT 
    schemaname,
    tablename,
    rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN ('model_configs', 'api_key_pool', 'users', 'user_tiers', 'user_quotas')
ORDER BY tablename;