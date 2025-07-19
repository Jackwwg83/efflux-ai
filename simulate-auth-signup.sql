-- 模拟 Supabase Auth 注册过程

-- 1. 先检查 instances 表
SELECT * FROM auth.instances;

-- 2. 如果 instances 表为空，插入默认实例
INSERT INTO auth.instances (id, uuid, raw_base_config, created_at, updated_at)
SELECT 
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    '{}'::jsonb,
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM auth.instances 
    WHERE id = '00000000-0000-0000-0000-000000000000'::uuid
);

-- 3. 创建测试注册函数
CREATE OR REPLACE FUNCTION test_auth_signup(
    test_email text,
    test_password text
)
RETURNS TABLE(step text, result text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_user_id uuid;
    encrypted_pw text;
BEGIN
    -- 生成用户ID
    new_user_id := gen_random_uuid();
    
    -- 加密密码
    encrypted_pw := crypt(test_password, gen_salt('bf'));
    
    -- Step 1: 检查邮箱是否已存在
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = test_email) THEN
        RETURN QUERY SELECT 'email_check'::text, 'EMAIL_ALREADY_EXISTS'::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'email_check'::text, 'EMAIL_AVAILABLE'::text;
    
    -- Step 2: 插入用户（模拟 Supabase Auth 的完整插入）
    BEGIN
        INSERT INTO auth.users (
            instance_id,
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            invited_at,
            confirmation_token,
            confirmation_sent_at,
            raw_app_meta_data,
            raw_user_meta_data,
            is_super_admin,
            created_at,
            updated_at,
            last_sign_in_at,
            is_sso_user,
            is_anonymous
        ) VALUES (
            COALESCE(
                (SELECT id FROM auth.instances LIMIT 1),
                '00000000-0000-0000-0000-000000000000'::uuid
            ),
            new_user_id,
            'authenticated',
            'authenticated',
            test_email,
            encrypted_pw,
            NULL, -- email_confirmed_at (NULL = 需要确认)
            NULL,
            encode(gen_random_bytes(32), 'hex'), -- confirmation_token
            NOW(), -- confirmation_sent_at
            jsonb_build_object(
                'provider', 'email',
                'providers', ARRAY['email']
            ),
            jsonb_build_object(),
            false,
            NOW(),
            NOW(),
            NULL,
            false,
            false
        );
        
        RETURN QUERY SELECT 'user_insert'::text, 'SUCCESS'::text;
        
        -- 检查触发器是否工作
        IF EXISTS (SELECT 1 FROM profiles WHERE id = new_user_id) THEN
            RETURN QUERY SELECT 'trigger_check'::text, 'TRIGGER_WORKED'::text;
        ELSE
            RETURN QUERY SELECT 'trigger_check'::text, 'TRIGGER_FAILED'::text;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'user_insert'::text, SQLERRM::text;
        RETURN;
    END;
    
    -- Step 3: 记录到 audit log（如果需要）
    BEGIN
        INSERT INTO auth.audit_log_entries (
            instance_id,
            id,
            payload,
            created_at,
            ip_address
        ) VALUES (
            COALESCE(
                (SELECT id FROM auth.instances LIMIT 1),
                '00000000-0000-0000-0000-000000000000'::uuid
            ),
            gen_random_uuid(),
            jsonb_build_object(
                'action', 'user_signedup',
                'actor_id', new_user_id,
                'actor_username', test_email,
                'actor_via_sso', false,
                'type', 'signup',
                'traits', jsonb_build_object('provider', 'email')
            ),
            NOW(),
            '127.0.0.1'
        );
        RETURN QUERY SELECT 'audit_log'::text, 'LOGGED'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'audit_log'::text, 'LOG_FAILED: ' || SQLERRM::text;
    END;
    
    RETURN QUERY SELECT 'signup_complete'::text, new_user_id::text;
END;
$$;

-- 4. 测试注册
SELECT * FROM test_auth_signup(
    'test_' || substring(gen_random_uuid()::text, 1, 8) || '@example.com',
    'TestPassword123!'
);

-- 5. 检查 Email 确认设置
-- 看看最近创建的用户是否需要邮箱确认
SELECT 
    email,
    email_confirmed_at,
    confirmation_token IS NOT NULL as has_confirmation_token,
    created_at
FROM auth.users
WHERE created_at > NOW() - INTERVAL '5 minutes'
ORDER BY created_at DESC;

-- 清理
DROP FUNCTION IF EXISTS test_auth_signup(text, text);