-- 调试新用户无法看到模型的问题

-- 1. 比较两个用户的数据
SELECT 
    'jackwwg@gmail.com' as user_email,
    au.id,
    ut.tier,
    ut.credits_balance,
    ut.credits_limit
FROM auth.users au
JOIN user_tiers ut ON ut.user_id = au.id
WHERE au.email = 'jackwwg@gmail.com'
UNION ALL
SELECT 
    'kisslight@163.com' as user_email,
    au.id,
    ut.tier,
    ut.credits_balance,
    ut.credits_limit
FROM auth.users au
JOIN user_tiers ut ON ut.user_id = au.id
WHERE au.email = 'kisslight@163.com';

-- 2. 检查 model_configs 表的 RLS 策略
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'model_configs';

-- 3. 检查 api_key_pool 表的 RLS 策略
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'api_key_pool';

-- 4. 检查是否有活跃的 API keys
SELECT 
    provider,
    COUNT(*) as total_keys,
    COUNT(*) FILTER (WHERE is_active = true) as active_keys,
    COUNT(*) FILTER (WHERE is_active = true AND consecutive_errors < 5) as healthy_keys
FROM api_key_pool
GROUP BY provider;

-- 5. 检查模型配置
SELECT 
    provider,
    model,
    display_name,
    tier_required,
    is_active
FROM model_configs
WHERE is_active = true
ORDER BY provider, model;

-- 6. 模拟新用户获取可用模型（检查 getAvailableModels 的逻辑）
-- 假设是 kisslight@163.com 用户
WITH user_info AS (
    SELECT 
        au.id as user_id,
        COALESCE(ut.tier, 'free') as user_tier
    FROM auth.users au
    LEFT JOIN user_tiers ut ON ut.user_id = au.id
    WHERE au.email = 'kisslight@163.com'
)
SELECT 
    mc.*,
    ui.user_tier,
    CASE 
        WHEN mc.tier_required = 'free' THEN 'ACCESSIBLE'
        WHEN mc.tier_required = 'pro' AND ui.user_tier IN ('pro', 'max') THEN 'ACCESSIBLE'
        WHEN mc.tier_required = 'max' AND ui.user_tier = 'max' THEN 'ACCESSIBLE'
        ELSE 'NOT_ACCESSIBLE'
    END as access_status
FROM model_configs mc
CROSS JOIN user_info ui
WHERE mc.is_active = true
ORDER BY mc.provider, mc.model;