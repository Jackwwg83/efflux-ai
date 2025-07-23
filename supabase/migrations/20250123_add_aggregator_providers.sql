-- Migration: Add Common Aggregator Providers
-- Description: Insert common API aggregator providers for admin to configure

-- Insert common aggregator providers
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features) VALUES
-- AiHubMix
('aihubmix', 'AiHubMix', 'aggregator', 'https://api.aihubmix.com/v1', 'openai', 
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- OpenRouter
('openrouter', 'OpenRouter', 'aggregator', 'https://openrouter.ai/api/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer",
    "requires_referer": true,
    "requires_site_name": true
  }'::jsonb),

-- NovitaAI
('novitaai', 'NovitaAI', 'aggregator', 'https://api.novita.ai/v3/openai', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- Siliconflow
('siliconflow', 'Siliconflow', 'aggregator', 'https://api.siliconflow.cn/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- TogetherAI
('togetherai', 'TogetherAI', 'aggregator', 'https://api.together.xyz/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": false,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- DeepInfra
('deepinfra', 'DeepInfra', 'aggregator', 'https://api.deepinfra.com/v1/openai', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- Groq
('groq', 'Groq', 'aggregator', 'https://api.groq.com/openai/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": false,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- Anyscale
('anyscale', 'Anyscale', 'aggregator', 'https://api.endpoints.anyscale.com/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": false,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- Perplexity
('perplexity', 'Perplexity', 'aggregator', 'https://api.perplexity.ai', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": false,
    "supports_vision": false,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb),

-- Fireworks
('fireworks', 'Fireworks AI', 'aggregator', 'https://api.fireworks.ai/inference/v1', 'openai',
  '{
    "supports_streaming": true,
    "supports_functions": true,
    "supports_vision": true,
    "model_list_endpoint": "/models",
    "header_format": "Bearer"
  }'::jsonb)

ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  provider_type = EXCLUDED.provider_type,
  base_url = EXCLUDED.base_url,
  api_standard = EXCLUDED.api_standard,
  features = EXCLUDED.features,
  is_enabled = true;