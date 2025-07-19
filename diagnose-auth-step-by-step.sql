-- ===== 第1步：检查 auth.users 的触发器 =====
SELECT 
    t.tgname as trigger_name,
    CASE 
        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END as timing,
    CASE
        WHEN t.tgtype & 4 = 4 THEN 'INSERT'
        WHEN t.tgtype & 8 = 8 THEN 'DELETE'
        WHEN t.tgtype & 16 = 16 THEN 'UPDATE'
    END as event,
    p.proname as function_name,
    t.tgenabled as enabled
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' 
AND c.relname = 'users'
AND t.tgname NOT LIKE 'RI_ConstraintTrigger%'
ORDER BY t.tgname;

-- ===== 第2步：检查 BEFORE INSERT 触发器 =====
SELECT 
    t.tgname,
    p.proname
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgrelid = 'auth.users'::regclass
AND t.tgtype & 2 = 2  -- BEFORE
AND t.tgtype & 4 = 4  -- INSERT
AND t.tgname NOT LIKE 'RI_ConstraintTrigger%';

-- ===== 第3步：检查系统设置 =====
SELECT 
    name,
    setting,
    category
FROM pg_settings
WHERE name IN (
    'row_security',
    'check_function_bodies',
    'default_transaction_isolation'
);

-- ===== 第4步：检查 RLS 策略 =====
SELECT
    pol.polname as policy_name,
    CASE pol.polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        ELSE 'ALL'
    END as operation
FROM pg_policy pol
WHERE pol.polrelid = 'auth.users'::regclass;

-- ===== 第5步：测试最小化插入（这步单独执行） =====
DO $$
DECLARE
    test_email text := 'minimal_test_' || substring(gen_random_uuid()::text, 1, 8) || '@example.com';
    test_id uuid := gen_random_uuid();
BEGIN
    -- 尝试最简单的插入
    INSERT INTO auth.users (id, email) VALUES (test_id, test_email);
    RAISE NOTICE 'Minimal insert SUCCESS';
    
    -- 检查触发器是否工作
    IF EXISTS (SELECT 1 FROM profiles WHERE id = test_id) THEN
        RAISE NOTICE 'Trigger created profile: YES';
    ELSE
        RAISE NOTICE 'Trigger created profile: NO';
    END IF;
    
    -- 清理
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
    DELETE FROM auth.users WHERE id = test_id;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Minimal insert FAILED: %', SQLERRM;
END $$;