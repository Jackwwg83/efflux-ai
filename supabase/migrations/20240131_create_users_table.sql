-- Create users table to store user tier information

-- 1. Create users table
CREATE TABLE IF NOT EXISTS users (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  email text NOT NULL,
  tier user_tier DEFAULT 'free',
  total_tokens_used bigint DEFAULT 0,
  total_cost numeric(10,6) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- 3. Create RLS policies
CREATE POLICY "Users can view own record"
ON users FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Service role can manage all"
ON users FOR ALL
TO service_role
USING (true);

-- 4. Create indexes
CREATE INDEX IF NOT EXISTS idx_users_tier ON users(tier);

-- 5. Grant permissions
GRANT SELECT ON users TO authenticated, service_role;
GRANT INSERT, UPDATE ON users TO service_role;

-- 6. Populate users table from existing data
INSERT INTO users (id, email, tier)
SELECT 
  p.id,
  p.email,
  'free'::user_tier
FROM profiles p
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  updated_at = now();

-- 7. Create trigger to automatically create user record when profile is created
CREATE OR REPLACE FUNCTION create_user_from_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO users (id, email, tier)
  VALUES (NEW.id, NEW.email, 'free'::user_tier)
  ON CONFLICT (id) DO UPDATE SET
    email = NEW.email,
    updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS create_user_on_profile_insert ON profiles;

-- Create trigger
CREATE TRIGGER create_user_on_profile_insert
AFTER INSERT OR UPDATE ON profiles
FOR EACH ROW
EXECUTE FUNCTION create_user_from_profile();

-- 8. Also update the record_api_key_success function to handle the total_tokens column
CREATE OR REPLACE FUNCTION record_api_key_success(
  p_api_key_id uuid,
  p_tokens_used integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update API key statistics
  UPDATE api_key_pool
  SET 
    total_requests = total_requests + 1,
    total_tokens_used = total_tokens_used + p_tokens_used,
    last_used_at = NOW(),
    -- Reset error count on success
    error_count = 0,
    consecutive_errors = 0
  WHERE id = p_api_key_id;
END;
$$;

-- 9. Verify the setup
SELECT 
  'Users table created' as status,
  COUNT(*) as user_count
FROM users;

-- 10. Test the quota check function
SELECT * FROM check_and_update_user_quota(
  (SELECT id FROM users WHERE email = 'jackwwg@gmail.com'),
  'gemini-2.5-flash',
  100
);