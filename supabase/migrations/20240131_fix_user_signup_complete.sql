-- 修复用户注册错误

-- 1. 修复 handle_new_user 函数，确保正确插入所有必需的表
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

  -- 插入 user_tiers 表，确保提供所有必需字段
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

  -- 插入 user_quotas 表（这是缺失的部分！）
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used,
    tokens_limit,
    requests_count,
    requests_limit,
    last_reset
  )
  VALUES (
    NEW.id,
    0,       -- 初始使用量
    100000,  -- 10万 tokens 限制
    0,       -- 初始请求数
    100,     -- 100个请求限制
    NOW()
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

-- 2. 确保 create_user_from_profile 函数也处理 user_quotas
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
    tokens_used,
    tokens_limit,
    requests_count,
    requests_limit,
    last_reset
  )
  VALUES (
    NEW.id,
    0,
    100000,
    0,
    100,
    NOW()
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- 3. 修复现有用户缺失的 user_quotas 记录
INSERT INTO public.user_quotas (
  user_id,
  tokens_used,
  tokens_limit,
  requests_count,
  requests_limit,
  last_reset
)
SELECT 
  au.id,
  0,
  100000,
  0,
  100,
  NOW()
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_quotas uq WHERE uq.user_id = au.id
)
ON CONFLICT (user_id) DO NOTHING;

-- 4. 添加一个额外的安全网：在 user_tiers 插入后自动创建 user_quotas
CREATE OR REPLACE FUNCTION ensure_user_quotas()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used,
    tokens_limit,
    requests_count,
    requests_limit,
    last_reset
  )
  VALUES (
    NEW.user_id,
    0,
    100000,
    0,
    100,
    NOW()
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
END $$;