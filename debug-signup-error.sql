-- 1. 检查 user_tiers 表的约束
SELECT 
    column_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'user_tiers'
ORDER BY ordinal_position;

-- 2. 检查 user_quotas 表是否有触发器填充数据
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND action_statement LIKE '%user_quotas%';

-- 3. 测试 handle_new_user 函数是否能正常工作
-- 创建一个测试函数来模拟插入
CREATE OR REPLACE FUNCTION test_user_creation()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    test_id uuid := gen_random_uuid();
    test_email text := 'test_' || test_id || '@example.com';
BEGIN
    -- 模拟 handle_new_user 的插入操作
    BEGIN
        INSERT INTO public.profiles (id, email, full_name, avatar_url)
        VALUES (
            test_id,
            test_email,
            test_email,
            NULL
        );
        RAISE NOTICE 'profiles insert successful';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'profiles insert failed: %', SQLERRM;
    END;

    BEGIN
        INSERT INTO public.user_tiers (user_id, tier, credits_limit)
        VALUES (
            test_id,
            'free',
            5000
        );
        RAISE NOTICE 'user_tiers insert successful';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'user_tiers insert failed: %', SQLERRM;
    END;

    BEGIN
        INSERT INTO public.user_quotas (user_id)
        VALUES (test_id);
        RAISE NOTICE 'user_quotas insert successful';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'user_quotas insert failed: %', SQLERRM;
    END;

    -- 清理测试数据
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
END;
$$;

-- 运行测试
SELECT test_user_creation();

-- 4. 查看最近的错误日志（如果有）
SELECT 
    id,
    created_at,
    level,
    msg
FROM postgres_logs
WHERE created_at > NOW() - INTERVAL '10 minutes'
AND msg LIKE '%user%'
ORDER BY created_at DESC
LIMIT 10;