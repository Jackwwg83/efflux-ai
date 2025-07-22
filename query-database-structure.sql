-- 🔍 DATABASE STRUCTURE ANALYSIS QUERIES
-- 请在Supabase SQL Editor中运行这些查询

-- =====================================
-- 1. 检查所有相关表是否存在
-- =====================================
SELECT 
  'Table Existence Check' as section,
  table_name,
  table_type
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('user_tiers', 'user_quotas', 'tier_definitions', 'api_key_pool', 'usage_logs')
ORDER BY table_name;

-- =====================================
-- 2. user_tiers 表结构详细信息
-- =====================================
SELECT 
  'user_tiers Structure' as section,
  column_name,
  data_type,
  is_nullable,
  column_default,
  character_maximum_length
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'user_tiers'
ORDER BY ordinal_position;

-- =====================================
-- 3. user_quotas 表结构（如果存在）
-- =====================================
SELECT 
  'user_quotas Structure' as section,
  column_name,
  data_type,
  is_nullable,
  column_default,
  character_maximum_length
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'user_quotas'
ORDER BY ordinal_position;

-- =====================================
-- 4. tier_definitions 表结构（如果存在）
-- =====================================
SELECT 
  'tier_definitions Structure' as section,
  column_name,
  data_type,
  is_nullable,
  column_default,
  character_maximum_length
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'tier_definitions'
ORDER BY ordinal_position;

-- =====================================
-- 5. 检查约束信息
-- =====================================
SELECT 
  'Constraints' as section,
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  cc.check_clause
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public' 
  AND tc.table_name IN ('user_tiers', 'user_quotas', 'tier_definitions')
ORDER BY tc.table_name, tc.constraint_type;

-- =====================================
-- 6. 检查索引信息
-- =====================================
SELECT 
  'Indexes' as section,
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND tablename IN ('user_tiers', 'user_quotas', 'tier_definitions', 'usage_logs')
ORDER BY tablename;

-- =====================================
-- 7. 检查函数存在性
-- =====================================
SELECT 
  'Functions' as section,
  routine_name,
  routine_type,
  data_type as return_type
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name IN ('get_user_quota_status', 'check_and_update_user_quota', 'get_available_api_key')
ORDER BY routine_name;

-- =====================================
-- 8. 检查用户数据（jackwwg@gmail.com）
-- =====================================
SELECT 
  'User Data Check' as section,
  u.id as user_id,
  u.email,
  u.created_at as user_created,
  ut.tier,
  ut.credits_balance,
  ut.credits_limit,
  ut.rate_limit,
  uq.tokens_used_today,
  uq.last_reset_daily
FROM auth.users u
LEFT JOIN user_tiers ut ON u.id = ut.user_id
LEFT JOIN user_quotas uq ON u.id = uq.user_id
WHERE u.email = 'jackwwg@gmail.com';

-- =====================================
-- 9. 检查 RLS 策略
-- =====================================
SELECT 
  'RLS Policies' as section,
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename IN ('user_tiers', 'user_quotas', 'tier_definitions')
ORDER BY tablename;

-- =====================================
-- 10. 枚举类型检查
-- =====================================
SELECT 
  'Enum Types' as section,
  t.typname as enum_name,
  e.enumlabel as enum_value,
  e.enumsortorder
FROM pg_type t 
JOIN pg_enum e ON t.oid = e.enumtypid 
WHERE t.typname IN ('user_tier', 'message_role')
ORDER BY t.typname, e.enumsortorder;