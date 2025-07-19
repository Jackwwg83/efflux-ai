-- 修复用户注册错误（使用正确的字段名）

-- 1. 修复 handle_new_user 函数
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

  -- 插入 user_quotas 表（使用正确的字段名）
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used_today,
    tokens_used_month,
    requests_today,
    requests_month,
    cost_today,
    cost_month,
    last_reset_daily,
    last_reset_monthly
  )
  VALUES (
    NEW.id,
    0,    -- tokens_used_today
    0,    -- tokens_used_month
    0,    -- requests_today
    0,    -- requests_month
    0,    -- cost_today
    0,    -- cost_month
    CURRENT_DATE,                                    -- last_reset_daily
    date_trunc('month', CURRENT_DATE)                -- last_reset_monthly
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- 记录错误但不阻止用户创建
    RAISE WARNING 'Error in handle_new_user: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 2. 更新 create_user_from_profile 函数
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

  -- 确保 user_quotas 存在
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used_today,
    tokens_used_month,
    requests_today,
    requests_month,
    cost_today,
    cost_month,
    last_reset_daily,
    last_reset_monthly
  )
  VALUES (
    NEW.id,
    0,
    0,
    0,
    0,
    0,
    0,
    CURRENT_DATE,
    date_trunc('month', CURRENT_DATE)
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- 3. 修复现有用户缺失的 user_quotas 记录
INSERT INTO public.user_quotas (
  user_id,
  tokens_used_today,
  tokens_used_month,
  requests_today,
  requests_month,
  cost_today,
  cost_month,
  last_reset_daily,
  last_reset_monthly
)
SELECT 
  au.id,
  0,
  0,
  0,
  0,
  0,
  0,
  CURRENT_DATE,
  date_trunc('month', CURRENT_DATE)
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_quotas uq WHERE uq.user_id = au.id
)
ON CONFLICT (user_id) DO NOTHING;

-- 4. 添加额外的安全网触发器
CREATE OR REPLACE FUNCTION ensure_user_quotas()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used_today,
    tokens_used_month,
    requests_today,
    requests_month,
    cost_today,
    cost_month,
    last_reset_daily,
    last_reset_monthly
  )
  VALUES (
    NEW.user_id,
    0,
    0,
    0,
    0,
    0,
    0,
    CURRENT_DATE,
    date_trunc('month', CURRENT_DATE)
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- 创建触发器
DROP TRIGGER IF EXISTS ensure_user_quotas_on_tier ON user_tiers;
CREATE TRIGGER ensure_user_quotas_on_tier
  AFTER INSERT ON user_tiers
  FOR EACH ROW
  EXECUTE FUNCTION ensure_user_quotas();

-- 5. 验证修复
DO $$
DECLARE
  missing_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO missing_count
  FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1 FROM user_quotas uq WHERE uq.user_id = au.id
  );
  
  RAISE NOTICE 'Users without quotas: %', missing_count;
  
  -- 也检查其他表
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