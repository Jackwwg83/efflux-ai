-- 测试真实的注册流程

-- 1. 先检查触发器函数的实际内容
SELECT pg_get_functiondef('handle_new_user'::regproc);

-- 2. 创建测试函数，模拟真实注册
CREATE OR REPLACE FUNCTION test_real_signup()
RETURNS TABLE(step text, result text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    test_id uuid := gen_random_uuid();
    test_email text := 'realtest_' || substring(test_id::text, 1, 8) || '@example.com';
    test_password text := 'TestPassword123!';
BEGIN
    -- Step 1: 模拟 Supabase Auth 的注册过程
    RETURN QUERY SELECT 'step1_email'::text, test_email::text;
    RETURN QUERY SELECT 'step1_id'::text, test_id::text;
    
    -- Step 2: 插入到 auth.users（这会触发 on_auth_user_created）
    BEGIN
        INSERT INTO auth.users (
            instance_id,
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            created_at,
            updated_at,
            confirmation_token,
            email_change,
            email_change_token_new,
            recovery_token,
            is_sso_user,
            is_anonymous
        ) VALUES (
            '00000000-0000-0000-0000-000000000000'::uuid,
            test_id,
            'authenticated',
            'authenticated', 
            test_email,
            crypt(test_password, gen_salt('bf')),
            NOW(), -- email_confirmed_at
            '{"provider": "email", "providers": ["email"]}'::jsonb,
            '{}'::jsonb,
            NOW(),
            NOW(),
            '',
            '',
            '',
            '',
            false,
            false
        );
        RETURN QUERY SELECT 'step2_auth_insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'step2_auth_insert'::text, ('ERROR: ' || SQLERRM)::text;
        -- 不要返回，继续检查
    END;
    
    -- Step 3: 等待触发器执行
    PERFORM pg_sleep(2);
    
    -- Step 4: 检查各表的数据
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_id) THEN
        RETURN QUERY SELECT 'step4_profiles'::text, 'EXISTS'::text;
    ELSE
        RETURN QUERY SELECT 'step4_profiles'::text, 'NOT_FOUND'::text;
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_tiers WHERE user_id = test_id) THEN
        RETURN QUERY SELECT 'step4_user_tiers'::text, 'EXISTS'::text;
    ELSE
        RETURN QUERY SELECT 'step4_user_tiers'::text, 'NOT_FOUND'::text;
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_quotas WHERE user_id = test_id) THEN
        RETURN QUERY SELECT 'step4_user_quotas'::text, 'EXISTS'::text;
    ELSE
        RETURN QUERY SELECT 'step4_user_quotas'::text, 'NOT_FOUND'::text;
    END IF;
    
    IF EXISTS (SELECT 1 FROM users WHERE id = test_id) THEN
        RETURN QUERY SELECT 'step4_users'::text, 'EXISTS'::text;
    ELSE
        RETURN QUERY SELECT 'step4_users'::text, 'NOT_FOUND'::text;
    END IF;
    
    -- Step 5: 如果 profiles 没创建，检查为什么
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = test_id) THEN
        -- 尝试手动执行触发器的逻辑
        BEGIN
            INSERT INTO profiles (id, email, full_name, avatar_url)
            VALUES (test_id, test_email, test_email, NULL);
            RETURN QUERY SELECT 'step5_manual_profile'::text, 'SUCCESS'::text;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT 'step5_manual_profile'::text, ('ERROR: ' || SQLERRM)::text;
        END;
    END IF;
    
    -- Step 6: 清理测试数据
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_id);
    DELETE FROM conversations WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM auth.users WHERE id = test_id;
    
    RETURN QUERY SELECT 'step6_cleanup'::text, 'COMPLETED'::text;
END;
$$;

-- 运行测试
SELECT * FROM test_real_signup();

-- 3. 检查是否有其他触发器可能干扰
SELECT 
    t.tgname as trigger_name,
    t.tgtype,
    t.tgenabled,
    p.proname as function_name,
    n.nspname as function_schema
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE t.tgrelid = 'auth.users'::regclass
ORDER BY t.tgname;

-- 清理
DROP FUNCTION IF EXISTS test_real_signup();