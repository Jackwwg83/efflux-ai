#!/bin/bash

# 🛠️ Run Database Schema Fix
echo "🔧 Running database schema repair..."

SUPABASE_ACCESS_TOKEN="sbp_df5ff67c1b111b4a15a9b1d38b42cc80e16c1381"

# Execute the database fix script
npx supabase db push --password="$SUPABASE_ACCESS_TOKEN" --file fix-database-schema.sql

echo "✅ Database schema repair completed!"
echo "📋 Next: Test quota system in the app"