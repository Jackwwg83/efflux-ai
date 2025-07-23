-- Add aggregator providers to api_providers table
-- Run this in Supabase SQL Editor

INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features, is_enabled) VALUES
('aihubmix', 'AiHubMix', 'aggregator', 'https://api.aihubmix.com/v1', 'openai', 
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb, true)
ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  provider_type = EXCLUDED.provider_type,
  base_url = EXCLUDED.base_url,
  api_standard = EXCLUDED.api_standard,
  features = EXCLUDED.features,
  is_enabled = EXCLUDED.is_enabled;