-- 诊断用户注册问题

-- 1. 检查触发器是否启用
SELECT 
    n.nspname as schema_name,
    t.tgname as trigger_name,
    p.proname as function_name,
    t.tgenabled as is_enabled,
    CASE t.tgenabled
        WHEN 'O' THEN 'ENABLED'
        WHEN 'D' THEN 'DISABLED'
        WHEN 'R' THEN 'REPLICA ONLY'
        WHEN 'A' THEN 'ALWAYS'
    END as status
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE n.nspname = 'auth' 
AND c.relname = 'users'
AND t.tgname = 'on_auth_user_created';

-- 2. 测试外键约束
-- 查看 profiles 表的外键
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
AND tc.table_schema = 'public'
AND tc.table_name IN ('profiles', 'user_tiers', 'user_quotas', 'users');

-- 3. 查看最近创建的 auth.users 记录
SELECT 
    id,
    email,
    created_at,
    CASE 
        WHEN EXISTS (SELECT 1 FROM profiles p WHERE p.id = au.id) THEN '✓'
        ELSE '✗'
    END as has_profile,
    CASE 
        WHEN EXISTS (SELECT 1 FROM user_tiers ut WHERE ut.user_id = au.id) THEN '✓'
        ELSE '✗'
    END as has_tier,
    CASE 
        WHEN EXISTS (SELECT 1 FROM user_quotas uq WHERE uq.user_id = au.id) THEN '✓'
        ELSE '✗'
    END as has_quota,
    CASE 
        WHEN EXISTS (SELECT 1 FROM users u WHERE u.id = au.id) THEN '✓'
        ELSE '✗'
    END as has_user
FROM auth.users au
ORDER BY created_at DESC
LIMIT 10;

-- 4. 手动测试触发器函数
DO $$
DECLARE
    test_user RECORD;
    result TEXT;
BEGIN
    -- 创建一个模拟的 NEW 记录
    test_user := ROW(
        gen_random_uuid(),                    -- id
        NULL,                                 -- instance_id
        'authenticated',                      -- aud
        'authenticated',                      -- role
        'manual_test_' || gen_random_uuid()::text || '@example.com',  -- email
        NULL,                                 -- encrypted_password
        NOW(),                               -- email_confirmed_at
        NULL,                                -- invited_at
        NULL,                                -- confirmation_token
        NULL,                                -- confirmation_sent_at
        NULL,                                -- recovery_token
        NULL,                                -- recovery_sent_at
        NULL,                                -- email_change_token_new
        NULL,                                -- email_change
        NULL,                                -- email_change_sent_at
        NOW(),                               -- last_sign_in_at
        '{"provider":"email","providers":["email"]}'::jsonb,  -- raw_app_meta_data
        '{}'::jsonb,                         -- raw_user_meta_data
        false,                               -- is_super_admin
        NOW(),                               -- created_at
        NOW(),                               -- updated_at
        NULL,                                -- phone
        NULL,                                -- phone_confirmed_at
        NULL,                                -- phone_change
        NULL,                                -- phone_change_token
        NULL,                                -- phone_change_sent_at
        NOW(),                               -- confirmed_at
        NULL,                                -- email_change_token_current
        0,                                   -- email_change_confirm_status
        NULL,                                -- banned_until
        NULL,                                -- reauthentication_token
        NULL,                                -- reauthentication_sent_at
        false,                               -- is_sso_user
        NULL,                                -- deleted_at
        false                                -- is_anonymous
    );
    
    -- 先插入到 auth.users
    INSERT INTO auth.users (
        id, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, aud, role,
        created_at, updated_at, confirmed_at
    )
    VALUES (
        test_user.id,
        test_user.email,
        crypt('test_password_123', gen_salt('bf')),
        test_user.email_confirmed_at,
        test_user.raw_app_meta_data,
        test_user.raw_user_meta_data,
        test_user.aud,
        test_user.role,
        test_user.created_at,
        test_user.updated_at,
        test_user.confirmed_at
    );
    
    -- 等待一下让触发器执行
    PERFORM pg_sleep(1);
    
    -- 检查结果
    RAISE NOTICE 'Test user created with ID: %', test_user.id;
    RAISE NOTICE 'Email: %', test_user.email;
    
    -- 检查各表是否有数据
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_user.id) THEN
        RAISE NOTICE 'Profile created: YES';
    ELSE
        RAISE NOTICE 'Profile created: NO';
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_tiers WHERE user_id = test_user.id) THEN
        RAISE NOTICE 'User tier created: YES';
    ELSE
        RAISE NOTICE 'User tier created: NO';
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_quotas WHERE user_id = test_user.id) THEN
        RAISE NOTICE 'User quota created: YES';
    ELSE
        RAISE NOTICE 'User quota created: NO';
    END IF;
    
    IF EXISTS (SELECT 1 FROM users WHERE id = test_user.id) THEN
        RAISE NOTICE 'Users table entry created: YES';
    ELSE
        RAISE NOTICE 'Users table entry created: NO';
    END IF;
    
    -- 清理测试数据
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_user.id);
    DELETE FROM conversations WHERE user_id = test_user.id;
    DELETE FROM user_quotas WHERE user_id = test_user.id;
    DELETE FROM user_tiers WHERE user_id = test_user.id;
    DELETE FROM users WHERE id = test_user.id;
    DELETE FROM profiles WHERE id = test_user.id;
    DELETE FROM auth.users WHERE id = test_user.id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error occurred: %', SQLERRM;
        -- 尝试清理
        DELETE FROM auth.users WHERE email LIKE 'manual_test_%@example.com';
END;
$$;