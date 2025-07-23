# Edge Function Aggregator Deployment Guide

## Overview
This guide explains how to deploy the updated Edge Function that supports API aggregator routing.

## Files Changed
- `/supabase/functions/v1-chat/index-aggregator.ts` - New version with aggregator support

## Key Changes
1. **Aggregator Detection**: Checks if a model belongs to an aggregator provider using `get_model_provider_config`
2. **Dynamic Routing**: Routes requests to either direct providers or aggregators
3. **Usage Tracking**: Records usage in `aggregator_usage_logs` table
4. **Streaming Support**: Handles streaming responses from aggregators

## Deployment Steps

### 1. Backup Current Function
```bash
# Save current function as backup
cp supabase/functions/v1-chat/index.ts supabase/functions/v1-chat/index-backup-$(date +%Y%m%d).ts
```

### 2. Replace with Aggregator Version
```bash
# Replace current function with aggregator version
cp supabase/functions/v1-chat/index-aggregator.ts supabase/functions/v1-chat/index.ts
```

### 3. Deploy to Supabase
```bash
# Deploy the updated function
SUPABASE_ACCESS_TOKEN="sbp_df5ff67c1b111b4a15a9b1d38b42cc80e16c1381" \
npx supabase functions deploy v1-chat --no-verify-jwt
```

### 4. Verify Deployment
- Check Supabase Dashboard: https://supabase.com/dashboard/project/lzvwduadnunbtxqaqhkg/functions
- Test with a simple request

## Testing

### Test Direct Provider (Existing Flow)
```bash
curl -X POST https://lzvwduadnunbtxqaqhkg.supabase.co/functions/v1/v1-chat \
  -H "Authorization: Bearer YOUR_USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'
```

### Test Aggregator Provider (New Flow)
```bash
# First, add an AiHubMix provider through the UI
# Then test with an aggregator model
curl -X POST https://lzvwduadnunbtxqaqhkg.supabase.co/functions/v1/v1-chat \
  -H "Authorization: Bearer YOUR_USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-opus-20240229",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'
```

## Rollback Plan
If issues occur, rollback to the previous version:
```bash
# Restore backup
cp supabase/functions/v1-chat/index-backup-YYYYMMDD.ts supabase/functions/v1-chat/index.ts

# Redeploy
SUPABASE_ACCESS_TOKEN="sbp_df5ff67c1b111b4a15a9b1d38b42cc80e16c1381" \
npx supabase functions deploy v1-chat --no-verify-jwt
```

## Monitoring
- Check Edge Function logs in Supabase Dashboard
- Monitor `aggregator_usage_logs` table for usage tracking
- Watch for errors in browser console during testing