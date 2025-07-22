-- 🔍 DATABASE STRUCTURE ANALYSIS & FIX
-- ============================================

-- 📋 问题分析：
-- 1. user_tiers.credits_limit 没有默认值，导致插入失败
-- 2. 两套配额系统并存造成混乱：
--    - 旧系统：user_tiers (credits_balance/credits_limit) 扣费模式
--    - 新系统：user_quotas + tier_definitions 累计使用模式
-- 3. jackwwg@gmail.com 的 tokens_used_today=6623 但 daily_limit 应该基于 tier_definitions

-- ============================================
-- STEP 1: 修复 credits_limit 默认值问题
-- ============================================
-- 添加默认值，基于tier类型
ALTER TABLE user_tiers 
ALTER COLUMN credits_limit SET DEFAULT 5000.00;

-- 更新现有NULL值（如果有）
UPDATE user_tiers 
SET credits_limit = CASE 
    WHEN tier = 'free' THEN 5000.00
    WHEN tier = 'pro' THEN 50000.00 
    WHEN tier = 'max' THEN 200000.00
    ELSE 5000.00
END
WHERE credits_limit IS NULL;

-- ============================================
-- STEP 2: 插入缺失的 tier_definitions 数据
-- ============================================
INSERT INTO tier_definitions (tier, display_name, daily_token_limit, monthly_token_limit, credits_per_month, rate_limit_per_minute, price_per_month)
VALUES 
    ('free', 'Free', 10000, 100000, 5000.00, 5, 0),
    ('pro', 'Pro', 100000, 2000000, 50000.00, 20, 19.99),
    ('max', 'Max', 500000, 10000000, 200000.00, 60, 99.99)
ON CONFLICT (tier) 
DO UPDATE SET
    daily_token_limit = EXCLUDED.daily_token_limit,
    monthly_token_limit = EXCLUDED.monthly_token_limit,
    credits_per_month = EXCLUDED.credits_per_month,
    rate_limit_per_minute = EXCLUDED.rate_limit_per_minute;

-- ============================================
-- STEP 3: 创建触发器自动同步 credits_limit
-- ============================================
CREATE OR REPLACE FUNCTION sync_user_tier_limits()
RETURNS TRIGGER AS $$
BEGIN
    -- 从 tier_definitions 自动设置 credits_limit
    NEW.credits_limit := COALESCE(
        (SELECT credits_per_month FROM tier_definitions WHERE tier = NEW.tier),
        5000.00
    );
    
    -- 如果是新用户或tier变更，重置credits_balance
    IF TG_OP = 'INSERT' OR OLD.tier IS DISTINCT FROM NEW.tier THEN
        NEW.credits_balance := NEW.credits_limit;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
DROP TRIGGER IF EXISTS sync_tier_limits_trigger ON user_tiers;
CREATE TRIGGER sync_tier_limits_trigger
BEFORE INSERT OR UPDATE OF tier ON user_tiers
FOR EACH ROW
EXECUTE FUNCTION sync_user_tier_limits();

-- ============================================
-- STEP 4: 修复 jackwwg@gmail.com 的配额问题
-- ============================================
-- 重置今日使用量（因为已超限）
UPDATE user_quotas 
SET tokens_used_today = 0,
    last_reset_daily = CURRENT_DATE
WHERE user_id = '76443a23-7734-4500-9cd2-89d685eba7d3'
  AND tokens_used_today > (
    SELECT daily_token_limit 
    FROM tier_definitions td
    JOIN user_tiers ut ON ut.tier = td.tier
    WHERE ut.user_id = '76443a23-7734-4500-9cd2-89d685eba7d3'
  );

-- 确保 credits_balance 不为0
UPDATE user_tiers
SET credits_balance = 5000.00
WHERE user_id = '76443a23-7734-4500-9cd2-89d685eba7d3'
  AND credits_balance = 0;

-- ============================================
-- STEP 5: 创建统一的配额检查函数
-- ============================================
CREATE OR REPLACE FUNCTION get_user_quota_status_v2(p_user_id UUID)
RETURNS TABLE (
    is_admin BOOLEAN,
    tier user_tier,
    daily_tokens_used BIGINT,
    daily_tokens_limit INTEGER,
    monthly_tokens_used BIGINT,
    monthly_tokens_limit INTEGER,
    can_use BOOLEAN,
    quota_percentage NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH user_status AS (
        SELECT 
            EXISTS(SELECT 1 FROM admin_users WHERE user_id = p_user_id) as is_admin,
            ut.tier,
            COALESCE(uq.tokens_used_today, 0) as daily_used,
            COALESCE(uq.tokens_used_month, 0) as monthly_used,
            td.daily_token_limit,
            td.monthly_token_limit
        FROM user_tiers ut
        LEFT JOIN user_quotas uq ON ut.user_id = uq.user_id
        LEFT JOIN tier_definitions td ON ut.tier = td.tier
        WHERE ut.user_id = p_user_id
    )
    SELECT 
        us.is_admin,
        us.tier,
        us.daily_used,
        us.daily_token_limit,
        us.monthly_used,
        us.monthly_token_limit,
        -- Admin bypass OR within limits
        us.is_admin OR (us.daily_used < us.daily_token_limit AND us.monthly_used < us.monthly_token_limit),
        -- Calculate percentage (use higher of daily or monthly)
        GREATEST(
            (us.daily_used::NUMERIC / NULLIF(us.daily_token_limit, 0) * 100),
            (us.monthly_used::NUMERIC / NULLIF(us.monthly_token_limit, 0) * 100)
        )
    FROM user_status us;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STEP 6: 添加管理员用户（如果需要）
-- ============================================
-- 确保 jackwwg@gmail.com 是管理员
INSERT INTO admin_users (user_id, created_at)
VALUES ('76443a23-7734-4500-9cd2-89d685eba7d3', NOW())
ON CONFLICT (user_id) DO NOTHING;

-- ============================================
-- STEP 7: 创建数据一致性检查
-- ============================================
CREATE OR REPLACE FUNCTION ensure_user_quota_consistency()
RETURNS TRIGGER AS $$
BEGIN
    -- 确保 user_quotas 记录存在
    INSERT INTO user_quotas (user_id)
    VALUES (NEW.user_id)
    ON CONFLICT (user_id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器确保数据一致性
DROP TRIGGER IF EXISTS ensure_quota_exists ON user_tiers;
CREATE TRIGGER ensure_quota_exists
AFTER INSERT ON user_tiers
FOR EACH ROW
EXECUTE FUNCTION ensure_user_quota_consistency();

-- ============================================
-- STEP 8: 清理和优化
-- ============================================
-- 确保所有用户都有 user_quotas 记录
INSERT INTO user_quotas (user_id)
SELECT ut.user_id 
FROM user_tiers ut
LEFT JOIN user_quotas uq ON ut.user_id = uq.user_id
WHERE uq.user_id IS NULL;

-- ============================================
-- 验证修复结果
-- ============================================
-- 检查 jackwwg@gmail.com 的状态
SELECT * FROM get_user_quota_status_v2('76443a23-7734-4500-9cd2-89d685eba7d3');

-- 检查所有表结构是否正确
SELECT 
    'After Fix Check' as status,
    COUNT(*) as user_count,
    COUNT(CASE WHEN credits_limit IS NULL THEN 1 END) as null_credits_count,
    COUNT(CASE WHEN credits_balance < 0 THEN 1 END) as negative_balance_count
FROM user_tiers;