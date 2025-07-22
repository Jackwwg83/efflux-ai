# 🔍 Database Issues Analysis & Solutions

## 📊 Current Database State Analysis

### 1. **Primary Issue: credits_limit Missing Default Value**
```sql
-- Current state:
column_name: credits_limit
is_nullable: NO
column_default: null  ❌ This is the root cause!
```
- When creating new users, INSERT fails with: `null value in column "credits_limit"`
- Other fields have defaults, but credits_limit doesn't

### 2. **Dual Quota Systems Conflict**
The system has TWO parallel quota tracking mechanisms:

#### Old System (user_tiers table):
- `credits_balance`: 扣费模式 (deduction-based)
- `credits_limit`: Monthly credit limit
- Problem: Legacy design, not aligned with token-based billing

#### New System (user_quotas + tier_definitions):
- `tokens_used_today/month`: 累计使用模式 (accumulation-based)
- `daily_token_limit`: From tier_definitions table
- Better design: Tracks actual usage, supports daily/monthly limits

### 3. **User Data Inconsistency (jackwwg@gmail.com)**
```
Database values:
- tokens_used_today: 6623
- tier: free
- daily_token_limit (from tier_definitions): 10000

Frontend hardcoded values:
- free tier limit: 5000 ❌ (should be 10000)
```
This mismatch caused the input box to be disabled incorrectly!

### 4. **Missing Data Relationships**
- tier_definitions data exists but wasn't inserted
- No automatic sync between user_tiers and tier_definitions
- No trigger to ensure user_quotas record exists

## 🛠️ Solution Implementation

### Phase 1: Immediate Fixes (Run first)
```sql
-- Fix 1: Add default value for credits_limit
ALTER TABLE user_tiers 
ALTER COLUMN credits_limit SET DEFAULT 5000.00;

-- Fix 2: Insert tier definitions
INSERT INTO tier_definitions (...) VALUES 
    ('free', 'Free', 10000, 100000, ...),
    ('pro', 'Pro', 100000, 2000000, ...),
    ('max', 'Max', 500000, 10000000, ...);

-- Fix 3: Reset jackwwg@gmail.com quota
UPDATE user_quotas 
SET tokens_used_today = 0
WHERE user_id = '76443a23-7734-4500-9cd2-89d685eba7d3';
```

### Phase 2: System Improvements
1. **Auto-sync trigger**: Automatically set credits_limit from tier_definitions
2. **Consistency trigger**: Ensure user_quotas record exists for every user
3. **Unified quota function**: Single source of truth for quota checks

### Phase 3: Frontend Alignment
- Updated getDailyLimit() to match database values
- Fixed hardcoded limits that didn't match tier_definitions

## 📋 Action Items

1. **Run database fix script**:
   ```bash
   # In Supabase SQL Editor, run:
   /home/ubuntu/jack/projects/efflux/efflux-ai/database-analysis-and-fix.sql
   ```

2. **Deploy frontend changes**:
   ```bash
   git add -A
   git commit -m "fix: align frontend quota limits with database tier_definitions"
   git push
   ```

3. **Deploy Edge Function** (if quota logic was changed):
   ```bash
   npm run deploy:functions
   ```

## 🎯 Expected Results

After fixes:
- ✅ New users can be created without credits_limit error
- ✅ jackwwg@gmail.com can use chat (10K daily limit, not 5K)
- ✅ Frontend shows correct quota percentages
- ✅ Automatic data consistency between tables
- ✅ Admin bypass works correctly

## 🔄 Migration Path

The system is transitioning from:
- Old: credits-based billing (user_tiers.credits_balance)
- New: token-based tracking (user_quotas.tokens_used_*)

Both systems coexist for backward compatibility, but the new system should be the primary quota mechanism.