-- Fix user signup error by creating necessary triggers and functions

-- 1. Create function to handle new user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insert into users table (profiles)
  INSERT INTO public.users (id, email, created_at, updated_at)
  VALUES (NEW.id, NEW.email, NOW(), NOW())
  ON CONFLICT (id) DO NOTHING;
  
  -- Create user tier (default to free)
  INSERT INTO public.user_tiers (user_id, tier, created_at, updated_at)
  VALUES (NEW.id, 'free', NOW(), NOW())
  ON CONFLICT (user_id) DO NOTHING;
  
  -- Create user quota
  INSERT INTO public.user_quotas (
    user_id,
    tokens_used,
    tokens_limit,
    requests_count,
    requests_limit,
    last_reset,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    0,
    100000,  -- 100k tokens for free tier
    0,
    100,     -- 100 requests for free tier
    NOW(),
    NOW(),
    NOW()
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- 2. Create trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();

-- 3. Also handle user deletion (cleanup)
CREATE OR REPLACE FUNCTION handle_user_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete from all related tables
  DELETE FROM public.users WHERE id = OLD.id;
  DELETE FROM public.user_tiers WHERE user_id = OLD.id;
  DELETE FROM public.user_quotas WHERE user_id = OLD.id;
  DELETE FROM public.conversations WHERE user_id = OLD.id;
  DELETE FROM public.messages WHERE id IN (
    SELECT m.id FROM messages m
    JOIN conversations c ON m.conversation_id = c.id
    WHERE c.user_id = OLD.id
  );
  
  RETURN OLD;
END;
$$;

-- 4. Create trigger for user deletion
DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
CREATE TRIGGER on_auth_user_deleted
  BEFORE DELETE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_user_delete();

-- 5. Grant necessary permissions
GRANT USAGE ON SCHEMA auth TO postgres, service_role;
GRANT ALL ON auth.users TO postgres, service_role;

-- 6. Fix any existing users that might not have been properly set up
INSERT INTO public.users (id, email, created_at, updated_at)
SELECT id, email, created_at, NOW()
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_tiers (user_id, tier, created_at, updated_at)
SELECT id, 'free', created_at, NOW()
FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_tiers)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.user_quotas (
  user_id,
  tokens_used,
  tokens_limit,
  requests_count,
  requests_limit,
  last_reset,
  created_at,
  updated_at
)
SELECT 
  id,
  0,
  100000,
  0,
  100,
  NOW(),
  created_at,
  NOW()
FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_quotas)
ON CONFLICT (user_id) DO NOTHING;