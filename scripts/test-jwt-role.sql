-- 测试 JWT 中的角色信息
-- 在 Supabase SQL Editor 中以你的用户身份运行

-- 1. 测试 auth.jwt() 函数是否能正确获取角色
SELECT 
    auth.jwt() as full_jwt,
    auth.jwt() -> 'raw_user_meta_data' as raw_meta,
    auth.jwt() -> 'user_metadata' as user_meta,
    auth.jwt() -> 'app_metadata' as app_meta,
    (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text as extracted_role,
    (auth.jwt() -> 'raw_user_meta_data' ->> 'role')::text = 'admin' as is_admin;

-- 2. 直接测试插入是否会成功（使用一个测试 provider_id）
-- 先获取一个 provider_id 用于测试
WITH test_provider AS (
    SELECT id FROM api_providers WHERE name = 'aihubmix' LIMIT 1
)
SELECT 
    id as provider_id,
    'aihubmix' as provider_name
FROM test_provider;

-- 3. 检查当前的 RLS 策略具体内容
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'aggregator_models'
AND cmd = 'INSERT';

-- 4. 尝试一个简化的插入测试（请用上面查询得到的 provider_id 替换）
-- INSERT INTO aggregator_models (
--     provider_id,
--     model_id,
--     model_name,
--     display_name,
--     model_type
-- ) VALUES (
--     'PROVIDER_ID_HERE',
--     'test-model-1',
--     'test-model-1',
--     'Test Model 1',
--     'chat'
-- );