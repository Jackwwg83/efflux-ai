-- Check if tables exist
SELECT 
    'models' as table_name,
    EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'models') as exists,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'models') as column_count
UNION ALL
SELECT 
    'model_sources' as table_name,
    EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'model_sources') as exists,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'model_sources') as column_count
UNION ALL
SELECT 
    'model_routing_logs' as table_name,
    EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'model_routing_logs') as exists,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'model_routing_logs') as column_count;

-- Check model_sources structure if it exists
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'model_sources'
ORDER BY ordinal_position;