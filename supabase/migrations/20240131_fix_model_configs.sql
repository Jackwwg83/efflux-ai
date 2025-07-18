-- Fix model_configs table to ensure proper model mapping

-- 1. First check if model_configs table exists and has Google models
DO $$
BEGIN
  -- Create model_configs table if it doesn't exist
  IF NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'model_configs') THEN
    CREATE TABLE model_configs (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      model text NOT NULL UNIQUE,
      provider text NOT NULL,
      provider_model_id text,
      display_name text NOT NULL,
      description text,
      max_tokens integer DEFAULT 4096,
      default_temperature numeric(3,2) DEFAULT 1.0,
      input_price numeric(10,6) DEFAULT 0,
      output_price numeric(10,6) DEFAULT 0,
      is_active boolean DEFAULT true,
      created_at timestamptz DEFAULT now(),
      updated_at timestamptz DEFAULT now()
    );
    
    -- Enable RLS
    ALTER TABLE model_configs ENABLE ROW LEVEL SECURITY;
    
    -- Create policy
    CREATE POLICY "Anyone can view model configs"
    ON model_configs FOR SELECT
    TO authenticated
    USING (true);
  END IF;
END $$;

-- 2. Delete old Google model configs if they exist
DELETE FROM model_configs WHERE provider = 'google';

-- 3. Insert correct Google Gemini 2.5 model configs
INSERT INTO model_configs (model, provider, provider_model_id, display_name, description, max_tokens, default_temperature, input_price, output_price, is_active) VALUES
-- Gemini 2.5 系列
('gemini-2.5-pro', 'google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google 旗下最强大的思考型模型', 8192, 1.0, 0.00125, 0.005, true),
('gemini-2.5-flash', 'google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', '在性价比方面表现出色的模型', 8192, 1.0, 0.000075, 0.0003, true),
('gemini-2.5-flash-lite-preview', 'google', 'gemini-2.5-flash-lite-preview-06-17', 'Gemini 2.5 Flash-Lite Preview', '经过优化，提高了成本效益', 8192, 1.0, 0.00005, 0.00015, true),

-- Gemini 2.0 系列
('gemini-2.0-flash', 'google', 'gemini-2.0-flash', 'Gemini 2.0 Flash', '新一代功能、速度和实时流式传输', 8192, 1.0, 0.000075, 0.0003, true)

ON CONFLICT (model) DO UPDATE SET
  provider = EXCLUDED.provider,
  provider_model_id = EXCLUDED.provider_model_id,
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  max_tokens = EXCLUDED.max_tokens,
  default_temperature = EXCLUDED.default_temperature,
  input_price = EXCLUDED.input_price,
  output_price = EXCLUDED.output_price,
  is_active = EXCLUDED.is_active,
  updated_at = now();

-- 4. Also add other providers if missing
INSERT INTO model_configs (model, provider, provider_model_id, display_name, description, max_tokens, default_temperature, input_price, output_price, is_active) VALUES
-- OpenAI
('gpt-4o', 'openai', 'gpt-4o', 'GPT-4o', 'Most advanced multimodal model', 16384, 1.0, 0.005, 0.015, true),
('gpt-4o-mini', 'openai', 'gpt-4o-mini', 'GPT-4o Mini', 'Affordable small model', 16384, 1.0, 0.00015, 0.0006, true),
('gpt-4-turbo', 'openai', 'gpt-4-turbo', 'GPT-4 Turbo', 'Latest GPT-4 Turbo model', 4096, 1.0, 0.01, 0.03, true),
('gpt-3.5-turbo', 'openai', 'gpt-3.5-turbo', 'GPT-3.5 Turbo', 'Fast and inexpensive', 4096, 1.0, 0.0005, 0.0015, true),

-- Anthropic
('claude-3-5-sonnet', 'anthropic', 'claude-3-5-sonnet-latest', 'Claude 3.5 Sonnet', 'Most intelligent Claude model', 8192, 1.0, 0.003, 0.015, true),
('claude-3-5-haiku', 'anthropic', 'claude-3-5-haiku-latest', 'Claude 3.5 Haiku', 'Fast and affordable', 8192, 1.0, 0.0008, 0.004, true),
('claude-3-opus', 'anthropic', 'claude-3-opus-latest', 'Claude 3 Opus', 'Powerful for complex tasks', 4096, 1.0, 0.015, 0.075, true)

ON CONFLICT (model) DO UPDATE SET
  provider = EXCLUDED.provider,
  provider_model_id = EXCLUDED.provider_model_id,
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  max_tokens = EXCLUDED.max_tokens,
  default_temperature = EXCLUDED.default_temperature,
  input_price = EXCLUDED.input_price,
  output_price = EXCLUDED.output_price,
  is_active = EXCLUDED.is_active,
  updated_at = now();

-- 5. Grant permissions
GRANT SELECT ON model_configs TO authenticated, service_role;

-- 6. Verify setup
SELECT 
  'Model configs fixed' as status,
  COUNT(*) as total_models,
  COUNT(*) FILTER (WHERE provider = 'google') as google_models
FROM model_configs;