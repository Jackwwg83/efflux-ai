-- 深入诊断用户注册问题

-- 1. 查看触发器函数执行时的错误（如果有）
-- 先启用更详细的日志
SET client_min_messages TO NOTICE;

-- 2. 直接查看外键约束（使用pg_catalog）
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name,
    a.attname AS column_name,
    confrelid::regclass AS foreign_table,
    af.attname AS foreign_column
FROM pg_constraint c
JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
JOIN pg_attribute af ON af.attnum = ANY(c.confkey) AND af.attrelid = c.confrelid
WHERE c.contype = 'f'
AND conrelid::regclass::text IN ('profiles', 'user_tiers', 'user_quotas', 'users');

-- 3. 测试创建用户的每个步骤
DO $$
DECLARE
    test_id uuid := gen_random_uuid();
    test_email text := 'test_debug_' || substring(test_id::text, 1, 8) || '@example.com';
    v_error_msg text;
BEGIN
    RAISE NOTICE '=== Starting user creation test ===';
    RAISE NOTICE 'Test ID: %', test_id;
    RAISE NOTICE 'Test Email: %', test_email;
    
    -- Step 1: 插入到 auth.users
    BEGIN
        INSERT INTO auth.users (
            id, 
            email, 
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            aud,
            role,
            created_at,
            updated_at,
            confirmed_at
        ) VALUES (
            test_id,
            test_email,
            crypt('TestPassword123!', gen_salt('bf')),
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Test User"}'::jsonb,
            'authenticated',
            'authenticated',
            NOW(),
            NOW(),
            NOW()
        );
        RAISE NOTICE 'Step 1: auth.users insert - SUCCESS';
        
        -- 等待触发器执行
        PERFORM pg_sleep(0.5);
        
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'Step 1: auth.users insert - FAILED: %', v_error_msg;
        RETURN;
    END;
    
    -- Step 2: 检查触发器是否创建了记录
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_id) THEN
        RAISE NOTICE 'Step 2: Profile - CREATED by trigger';
    ELSE
        RAISE NOTICE 'Step 2: Profile - NOT created by trigger';
        -- 尝试手动创建
        BEGIN
            INSERT INTO profiles (id, email, full_name) 
            VALUES (test_id, test_email, 'Test User');
            RAISE NOTICE '  Manual profile insert - SUCCESS';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
            RAISE NOTICE '  Manual profile insert - FAILED: %', v_error_msg;
        END;
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_tiers WHERE user_id = test_id) THEN
        RAISE NOTICE 'Step 3: User tier - CREATED by trigger';
    ELSE
        RAISE NOTICE 'Step 3: User tier - NOT created by trigger';
        -- 尝试手动创建
        BEGIN
            INSERT INTO user_tiers (user_id, tier, credits_balance, credits_limit, rate_limit)
            VALUES (test_id, 'free', 1000, 5000, 5);
            RAISE NOTICE '  Manual user_tiers insert - SUCCESS';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
            RAISE NOTICE '  Manual user_tiers insert - FAILED: %', v_error_msg;
        END;
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_quotas WHERE user_id = test_id) THEN
        RAISE NOTICE 'Step 4: User quota - CREATED by trigger';
    ELSE
        RAISE NOTICE 'Step 4: User quota - NOT created by trigger';
        -- 尝试手动创建
        BEGIN
            INSERT INTO user_quotas (user_id) VALUES (test_id);
            RAISE NOTICE '  Manual user_quotas insert - SUCCESS';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
            RAISE NOTICE '  Manual user_quotas insert - FAILED: %', v_error_msg;
        END;
    END IF;
    
    IF EXISTS (SELECT 1 FROM users WHERE id = test_id) THEN
        RAISE NOTICE 'Step 5: Users table - CREATED';
    ELSE
        RAISE NOTICE 'Step 5: Users table - NOT created';
    END IF;
    
    -- 清理测试数据
    RAISE NOTICE '=== Cleaning up test data ===';
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_id);
    DELETE FROM conversations WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM auth.users WHERE id = test_id;
    
    RAISE NOTICE '=== Test completed ===';
    
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
    RAISE NOTICE 'Unexpected error: %', v_error_msg;
    -- 清理可能残留的数据
    DELETE FROM auth.users WHERE email LIKE 'test_debug_%@example.com';
END;
$$;

-- 4. 查看 Supabase 的 auth schema 权限
SELECT 
    nspname,
    usename,
    has_schema_privilege(usename, nspname, 'USAGE') as has_usage,
    has_schema_privilege(usename, nspname, 'CREATE') as has_create
FROM pg_namespace
CROSS JOIN pg_user
WHERE nspname IN ('auth', 'public')
AND usename IN ('postgres', 'authenticator', 'authenticated', 'anon', 'service_role')
ORDER BY nspname, usename;