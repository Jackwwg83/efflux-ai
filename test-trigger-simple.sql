-- 简单测试触发器

-- 1. 首先测试 RAISE NOTICE 是否工作
DO $$
BEGIN
    RAISE NOTICE 'Test message: Can you see this?';
END $$;

-- 2. 创建一个临时函数来捕获触发器错误
CREATE OR REPLACE FUNCTION test_signup_with_logging()
RETURNS TABLE(message text)
LANGUAGE plpgsql
AS $$
DECLARE
    test_id uuid := gen_random_uuid();
    test_email text := 'signup_test_' || substring(test_id::text, 1, 8) || '@example.com';
    v_msg text;
BEGIN
    -- 记录开始
    RETURN QUERY SELECT 'Starting test with ID: ' || test_id::text;
    RETURN QUERY SELECT 'Email: ' || test_email;
    
    -- 插入到 auth.users
    BEGIN
        INSERT INTO auth.users (
            id, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, aud, role,
            created_at, updated_at, confirmed_at
        ) VALUES (
            test_id, test_email, crypt('Test123!', gen_salt('bf')), NOW(),
            '{"provider":"email"}'::jsonb, '{}'::jsonb,
            'authenticated', 'authenticated', NOW(), NOW(), NOW()
        );
        RETURN QUERY SELECT 'SUCCESS: Inserted into auth.users';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RETURN QUERY SELECT 'ERROR inserting auth.users: ' || v_msg;
        -- 继续执行，不返回
    END;
    
    -- 等待一下
    PERFORM pg_sleep(1);
    
    -- 检查各表
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_id) THEN
        RETURN QUERY SELECT 'CHECK: Profile exists';
    ELSE
        RETURN QUERY SELECT 'CHECK: Profile NOT found';
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_tiers WHERE user_id = test_id) THEN
        RETURN QUERY SELECT 'CHECK: User tier exists';
    ELSE
        RETURN QUERY SELECT 'CHECK: User tier NOT found';
    END IF;
    
    IF EXISTS (SELECT 1 FROM user_quotas WHERE user_id = test_id) THEN
        RETURN QUERY SELECT 'CHECK: User quota exists';
    ELSE
        RETURN QUERY SELECT 'CHECK: User quota NOT found';
    END IF;
    
    IF EXISTS (SELECT 1 FROM users WHERE id = test_id) THEN
        RETURN QUERY SELECT 'CHECK: Users entry exists';
    ELSE
        RETURN QUERY SELECT 'CHECK: Users entry NOT found';
    END IF;
    
    -- 清理
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_id);
    DELETE FROM conversations WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM auth.users WHERE id = test_id;
    
    RETURN QUERY SELECT 'Test completed and cleaned up';
END;
$$;

-- 运行测试
SELECT * FROM test_signup_with_logging();

-- 3. 直接测试 handle_new_user 函数
-- 创建一个模拟记录并手动调用函数
CREATE OR REPLACE FUNCTION test_handle_new_user_directly()
RETURNS TABLE(message text)
LANGUAGE plpgsql
AS $$
DECLARE
    test_record auth.users;
    result auth.users;
BEGIN
    -- 创建测试记录
    test_record.id := gen_random_uuid();
    test_record.email := 'direct_test_' || substring(test_record.id::text, 1, 8) || '@example.com';
    test_record.raw_user_meta_data := '{"full_name":"Direct Test"}'::jsonb;
    test_record.raw_app_meta_data := '{"provider":"email"}'::jsonb;
    
    RETURN QUERY SELECT 'Testing direct function call with ID: ' || test_record.id::text;
    
    -- 先插入到 auth.users 以满足外键约束
    INSERT INTO auth.users (id, email, created_at, updated_at)
    VALUES (test_record.id, test_record.email, NOW(), NOW());
    
    BEGIN
        -- 直接调用触发器函数
        result := handle_new_user() FROM (SELECT test_record.*) AS NEW;
        RETURN QUERY SELECT 'Direct function call: SUCCESS';
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'Direct function call ERROR: ' || SQLERRM;
    END;
    
    -- 检查结果
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_record.id) THEN
        RETURN QUERY SELECT 'Result: Profile created';
    ELSE
        RETURN QUERY SELECT 'Result: Profile NOT created';
    END IF;
    
    -- 清理
    DELETE FROM user_quotas WHERE user_id = test_record.id;
    DELETE FROM user_tiers WHERE user_id = test_record.id;
    DELETE FROM users WHERE id = test_record.id;
    DELETE FROM profiles WHERE id = test_record.id;
    DELETE FROM auth.users WHERE id = test_record.id;
    
    RETURN QUERY SELECT 'Cleanup completed';
END;
$$;

-- 运行直接测试
SELECT * FROM test_handle_new_user_directly();

-- 清理测试函数
DROP FUNCTION IF EXISTS test_signup_with_logging();
DROP FUNCTION IF EXISTS test_handle_new_user_directly();