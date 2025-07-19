-- 最终测试：返回结果而不是 NOTICE

CREATE OR REPLACE FUNCTION final_signup_test()
RETURNS TABLE(test_name text, test_result text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    test_email text := 'final_test_' || substring(gen_random_uuid()::text, 1, 8) || '@example.com';
    test_id uuid := gen_random_uuid();
    v_count integer;
BEGIN
    -- 测试1: 最简单的插入
    BEGIN
        INSERT INTO auth.users (id, email) VALUES (test_id, test_email);
        RETURN QUERY SELECT 'simple_insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'simple_insert'::text, SQLERRM::text;
        RETURN; -- 如果失败就停止
    END;
    
    -- 测试2: 检查触发器结果
    SELECT COUNT(*) INTO v_count FROM profiles WHERE id = test_id;
    RETURN QUERY SELECT 'profile_created'::text, 
                       CASE WHEN v_count > 0 THEN 'YES' ELSE 'NO' END::text;
    
    SELECT COUNT(*) INTO v_count FROM user_tiers WHERE user_id = test_id;
    RETURN QUERY SELECT 'user_tier_created'::text, 
                       CASE WHEN v_count > 0 THEN 'YES' ELSE 'NO' END::text;
    
    SELECT COUNT(*) INTO v_count FROM user_quotas WHERE user_id = test_id;
    RETURN QUERY SELECT 'user_quota_created'::text, 
                       CASE WHEN v_count > 0 THEN 'YES' ELSE 'NO' END::text;
    
    -- 测试3: 通过 crypt 函数测试密码
    BEGIN
        UPDATE auth.users 
        SET encrypted_password = crypt('TestPassword123!', gen_salt('bf'))
        WHERE id = test_id;
        RETURN QUERY SELECT 'password_update'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'password_update'::text, SQLERRM::text;
    END;
    
    -- 测试4: 模拟完整的 Auth 注册数据
    DELETE FROM auth.users WHERE id = test_id; -- 先删除
    
    BEGIN
        INSERT INTO auth.users (
            id,
            instance_id,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            aud,
            role,
            created_at,
            updated_at
        ) VALUES (
            test_id,
            '00000000-0000-0000-0000-000000000000'::uuid,
            test_email,
            crypt('TestPassword123!', gen_salt('bf')),
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb,
            'authenticated',
            'authenticated',
            NOW(),
            NOW()
        );
        RETURN QUERY SELECT 'full_insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'full_insert'::text, SQLERRM::text;
    END;
    
    -- 清理
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_id);
    DELETE FROM conversations WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM auth.users WHERE id = test_id;
    
    RETURN QUERY SELECT 'cleanup'::text, 'COMPLETED'::text;
END;
$$;

-- 执行测试
SELECT * FROM final_signup_test();

-- 清理函数
DROP FUNCTION final_signup_test();