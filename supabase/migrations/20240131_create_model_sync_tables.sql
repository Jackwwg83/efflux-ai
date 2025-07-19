-- Create tables for model sync functionality

-- 1. Create system_settings table for storing sync metadata
CREATE TABLE IF NOT EXISTS system_settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. Create sync_logs table for tracking sync history
CREATE TABLE IF NOT EXISTS sync_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sync_type text NOT NULL,
  results jsonb,
  triggered_by text,
  error_message text,
  created_at timestamptz DEFAULT now()
);

-- 3. Add description and version columns to model_configs if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'model_configs' AND column_name = 'description') THEN
    ALTER TABLE model_configs ADD COLUMN description text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'model_configs' AND column_name = 'version') THEN
    ALTER TABLE model_configs ADD COLUMN version text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'model_configs' AND column_name = 'last_synced_at') THEN
    ALTER TABLE model_configs ADD COLUMN last_synced_at timestamptz;
  END IF;
END $$;

-- 4. Enable RLS
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies
-- System settings - only admins can modify
CREATE POLICY "Admins can manage system settings"
ON system_settings FOR ALL
TO authenticated
USING (auth_is_admin());

CREATE POLICY "Service role can manage system settings"
ON system_settings FOR ALL
TO service_role
USING (true);

-- Sync logs - admins can view, service role can insert
CREATE POLICY "Admins can view sync logs"
ON sync_logs FOR SELECT
TO authenticated
USING (auth_is_admin());

CREATE POLICY "Service role can manage sync logs"
ON sync_logs FOR ALL
TO service_role
USING (true);

-- 6. Grant permissions
GRANT SELECT ON system_settings TO authenticated;
GRANT ALL ON system_settings TO service_role;

GRANT SELECT ON sync_logs TO authenticated;
GRANT ALL ON sync_logs TO service_role;

-- 7. Create indexes
CREATE INDEX IF NOT EXISTS idx_sync_logs_created_at ON sync_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_logs_sync_type ON sync_logs(sync_type);

-- 8. Fix the existing model configs - remove gemini-2.5-flash-lite-preview
DELETE FROM model_configs WHERE model = 'gemini-2.5-flash-lite-preview';

-- 9. Update existing Google models with correct names
UPDATE model_configs SET 
  provider_model_id = 'gemini-2.0-flash-lite',
  display_name = 'Gemini 2.0 Flash-Lite'
WHERE model = 'gemini-2.5-flash-lite-preview';

-- 10. Insert correct Google models if they don't exist
INSERT INTO model_configs (
  model, provider, provider_model_id, display_name, 
  max_tokens, context_window, input_price, output_price,
  supports_streaming, supports_functions, is_active, tier_required
) VALUES
  ('gemini-2.0-flash-lite', 'google', 'gemini-2.0-flash-lite', 'Gemini 2.0 Flash-Lite', 
   8192, 1048576, 0.00005, 0.00015, true, true, true, 'free'),
  ('gemini-1.5-flash-8b', 'google', 'gemini-1.5-flash-8b', 'Gemini 1.5 Flash-8B', 
   8192, 1000000, 0.000037, 0.00015, true, true, true, 'free')
ON CONFLICT (model) DO UPDATE SET
  provider_model_id = EXCLUDED.provider_model_id,
  display_name = EXCLUDED.display_name,
  is_active = true;

-- 11. Initialize last sync time
INSERT INTO system_settings (key, value, description)
VALUES ('last_model_sync', '2024-01-01T00:00:00Z', 'Last time models were synced from provider APIs')
ON CONFLICT (key) DO NOTHING;