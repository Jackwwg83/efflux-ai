-- 最终修复用户注册错误

-- 1. 修复 handle_new_user 函数（简化版）
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 插入 profiles 表
  INSERT INTO public.profiles (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;

  -- 插入 user_tiers 表
  INSERT INTO public.user_tiers (
    user_id, 
    tier, 
    credits_balance,
    credits_limit,
    rate_limit
  )
  VALUES (
    NEW.id,
    'free',
    1000,    -- 初始余额
    5000,    -- 免费层级限额
    5        -- 速率限制
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- 插入 user_quotas 表（大部分字段使用默认值）
  INSERT INTO public.user_quotas (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- 记录错误但不阻止用户创建
    RAISE WARNING 'Error in handle_new_user: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 2. 更新 create_user_from_profile 函数（简化版）
CREATE OR REPLACE FUNCTION public.create_user_from_profile()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- 插入 users 表
  INSERT INTO users (id, email, tier)
  VALUES (NEW.id, NEW.email, 'free'::user_tier)
  ON CONFLICT (id) DO UPDATE SET
    email = NEW.email,
    updated_at = now();

  -- 确保 user_quotas 存在（使用默认值）
  INSERT INTO public.user_quotas (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error in create_user_from_profile: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 3. 修复现有用户缺失的 user_quotas 记录（简化版）
INSERT INTO public.user_quotas (user_id)
SELECT au.id
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_quotas uq WHERE uq.user_id = au.id
)
ON CONFLICT (user_id) DO NOTHING;

-- 4. 测试函数是否正常工作
CREATE OR REPLACE FUNCTION test_user_creation_v2()
RETURNS TABLE(step text, status text)
LANGUAGE plpgsql
AS $$
DECLARE
    test_id uuid := gen_random_uuid();
    test_email text := 'test_' || substring(test_id::text, 1, 8) || '@example.com';
BEGIN
    -- 测试 profiles 插入
    BEGIN
        INSERT INTO public.profiles (id, email, full_name, avatar_url)
        VALUES (test_id, test_email, test_email, NULL);
        RETURN QUERY SELECT 'profiles insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'profiles insert'::text, SQLERRM::text;
    END;

    -- 测试 user_tiers 插入
    BEGIN
        INSERT INTO public.user_tiers (user_id, tier, credits_balance, credits_limit, rate_limit)
        VALUES (test_id, 'free', 1000, 5000, 5);
        RETURN QUERY SELECT 'user_tiers insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'user_tiers insert'::text, SQLERRM::text;
    END;

    -- 测试 user_quotas 插入
    BEGIN
        INSERT INTO public.user_quotas (user_id) VALUES (test_id);
        RETURN QUERY SELECT 'user_quotas insert'::text, 'SUCCESS'::text;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'user_quotas insert'::text, SQLERRM::text;
    END;

    -- 清理测试数据
    DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = test_id);
    DELETE FROM conversations WHERE user_id = test_id;
    DELETE FROM user_quotas WHERE user_id = test_id;
    DELETE FROM user_tiers WHERE user_id = test_id;
    DELETE FROM users WHERE id = test_id;
    DELETE FROM profiles WHERE id = test_id;
END;
$$;

-- 运行测试
SELECT * FROM test_user_creation_v2();

-- 5. 最终验证
DO $$
DECLARE
  missing_count INTEGER;
  total_users INTEGER;
BEGIN
  SELECT COUNT(*) INTO total_users FROM auth.users;
  RAISE NOTICE 'Total users in auth.users: %', total_users;
  
  SELECT COUNT(*)
  INTO missing_count
  FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1 FROM user_quotas uq WHERE uq.user_id = au.id
  );
  RAISE NOTICE 'Users without quotas: %', missing_count;
  
  SELECT COUNT(*)
  INTO missing_count
  FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = au.id
  );
  RAISE NOTICE 'Users without profiles: %', missing_count;
  
  SELECT COUNT(*)
  INTO missing_count
  FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1 FROM user_tiers ut WHERE ut.user_id = au.id
  );
  RAISE NOTICE 'Users without tiers: %', missing_count;
  
  SELECT COUNT(*)
  INTO missing_count
  FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = au.id
  );
  RAISE NOTICE 'Users without users table entry: %', missing_count;
END $$;

-- 清理测试函数
DROP FUNCTION IF EXISTS test_user_creation();
DROP FUNCTION IF EXISTS test_user_creation_v2();