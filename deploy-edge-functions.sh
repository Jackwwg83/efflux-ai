#!/bin/bash

# Deploy Edge Functions to Supabase
# This script deploys the v1-chat Edge Function after code changes

echo "🚀 Deploying Edge Functions to Supabase..."

# Set the access token
export SUPABASE_ACCESS_TOKEN="sbp_df5ff67c1b111b4a15a9b1d38b42cc80e16c1381"

# Deploy v1-chat function
echo "📦 Deploying v1-chat function..."
npx supabase functions deploy v1-chat --no-verify-jwt

if [ $? -eq 0 ]; then
    echo "✅ Edge Function deployed successfully!"
    echo "🔗 View deployment: https://supabase.com/dashboard/project/lzvwduadnunbtxqaqhkg/functions"
else
    echo "❌ Deployment failed. Please check the error messages above."
    exit 1
fi