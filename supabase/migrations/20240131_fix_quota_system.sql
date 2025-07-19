-- Fix the quota system to work with existing structure

-- 1. First, let's rename user_tiers to user_subscriptions for clarity (optional, but recommended)
-- ALTER TABLE user_tiers RENAME TO user_subscriptions;

-- 2. Create a tier_definitions table for tier configurations
CREATE TABLE IF NOT EXISTS tier_definitions (
  tier user_tier PRIMARY KEY,
  display_name text NOT NULL,
  daily_token_limit integer NOT NULL,
  monthly_token_limit integer NOT NULL,
  credits_per_month numeric(10,2) DEFAULT 0,
  rate_limit_per_minute integer DEFAULT 60,
  price_per_month numeric(10,2) DEFAULT 0
);

-- 3. Insert tier definitions
INSERT INTO tier_definitions (tier, display_name, daily_token_limit, monthly_token_limit, credits_per_month, rate_limit_per_minute, price_per_month) VALUES
('free', 'Free', 50000, 1000000, 5000, 5, 0),
('pro', 'Pro', 500000, 10000000, 50000, 60, 29.99),
('max', 'Max', 2000000, 50000000, 200000, 300, 99.99)
ON CONFLICT (tier) DO UPDATE SET
  daily_token_limit = EXCLUDED.daily_token_limit,
  monthly_token_limit = EXCLUDED.monthly_token_limit,
  credits_per_month = EXCLUDED.credits_per_month,
  rate_limit_per_minute = EXCLUDED.rate_limit_per_minute,
  price_per_month = EXCLUDED.price_per_month;

-- 4. Update the check_and_update_user_quota function to use the existing structure
CREATE OR REPLACE FUNCTION check_and_update_user_quota(
  p_user_id uuid,
  p_model text,
  p_estimated_tokens integer
)
RETURNS TABLE(
  can_use boolean,
  daily_limit integer,
  used_today integer,
  remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tier user_tier;
  v_daily_limit integer;
  v_used_today integer;
  v_remaining integer;
  v_credits_balance numeric;
  v_credits_limit numeric;
BEGIN
  -- Get user tier from user_tiers table (which contains individual user subscription info)
  SELECT ut.tier, ut.credits_balance, ut.credits_limit
  INTO v_tier, v_credits_balance, v_credits_limit
  FROM user_tiers ut
  WHERE ut.user_id = p_user_id;
  
  -- If no user_tiers record, use default free tier
  IF NOT FOUND THEN
    v_tier := 'free';
    v_credits_balance := 0;
    v_credits_limit := 5000;
  END IF;
  
  -- Get daily limit from tier definitions
  SELECT td.daily_token_limit
  INTO v_daily_limit
  FROM tier_definitions td
  WHERE td.tier = v_tier;
  
  -- If no tier definition found, use a default
  IF NOT FOUND THEN
    v_daily_limit := 50000; -- Default for free tier
  END IF;
  
  -- Get tokens used today
  SELECT COALESCE(SUM(total_tokens), 0)::integer
  INTO v_used_today
  FROM usage_logs
  WHERE user_id = p_user_id
    AND created_at >= CURRENT_DATE
    AND status = 'success';
  
  -- Calculate remaining
  v_remaining := v_daily_limit - v_used_today;
  
  -- Check if user can use (has enough quota AND credits)
  -- For now, we'll just check daily token limit
  -- You can add credits check later if needed
  RETURN QUERY
  SELECT 
    (v_remaining >= p_estimated_tokens) AS can_use,
    v_daily_limit,
    v_used_today,
    v_remaining;
END;
$$;

-- 5. Grant permissions
GRANT SELECT ON tier_definitions TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION check_and_update_user_quota(uuid, text, integer) TO authenticated, service_role;

-- 6. Test the function
SELECT * FROM check_and_update_user_quota(
  '76443a23-7734-4500-9cd2-89d685eba7d3'::uuid,
  'gemini-2.5-flash',
  100
);