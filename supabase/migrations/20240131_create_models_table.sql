-- 创建 models 表和插入所有模型数据

-- 1. 创建 models 表
CREATE TABLE IF NOT EXISTS models (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  provider text NOT NULL,
  model_id text NOT NULL,
  display_name text NOT NULL,
  description text,
  context_window integer DEFAULT 4096,
  max_tokens integer DEFAULT 4096,
  input_price_per_1k numeric(10, 6) DEFAULT 0,
  output_price_per_1k numeric(10, 6) DEFAULT 0,
  supports_streaming boolean DEFAULT true,
  supports_functions boolean DEFAULT false,
  supports_vision boolean DEFAULT false,
  default_temperature numeric(3, 2) DEFAULT 1.0,
  provider_model_id text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(provider, model_id)
);

-- 2. 创建索引
CREATE INDEX IF NOT EXISTS idx_models_provider ON models(provider);
CREATE INDEX IF NOT EXISTS idx_models_model_id ON models(model_id);

-- 3. 启用 RLS
ALTER TABLE models ENABLE ROW LEVEL SECURITY;

-- 4. 创建 RLS 策略 - 所有认证用户都可以查看模型
CREATE POLICY "Anyone can view models"
ON models FOR SELECT
TO authenticated
USING (true);

-- 5. 插入所有模型数据

-- Google Gemini 2.5 系列
INSERT INTO models (provider, model_id, display_name, description, context_window, max_tokens, input_price_per_1k, output_price_per_1k, supports_streaming, supports_functions, supports_vision, default_temperature, provider_model_id) VALUES
('google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google 旗下最强大的思考型模型，回答准确性最高，性能出色', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-2.5-pro'),
('google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', '在性价比方面表现出色的模型，可提供全面的功能', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.5-flash'),
('google', 'gemini-2.5-flash-lite-preview', 'Gemini 2.5 Flash-Lite Preview', '经过优化，提高了成本效益并缩短了延迟时间', 1048576, 8192, 0.00005, 0.00015, true, true, true, 1.0, 'gemini-2.5-flash-lite-preview-06-17'),
('google', 'gemini-2.0-flash', 'Gemini 2.0 Flash', '新一代功能、速度和实时流式传输', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.0-flash'),

-- OpenAI GPT 系列
('openai', 'gpt-4o', 'GPT-4o', 'Most advanced multimodal model', 128000, 16384, 0.005, 0.015, true, true, true, 1.0, 'gpt-4o'),
('openai', 'gpt-4o-mini', 'GPT-4o Mini', 'Affordable small model for fast tasks', 128000, 16384, 0.00015, 0.0006, true, true, true, 1.0, 'gpt-4o-mini'),
('openai', 'gpt-4-turbo', 'GPT-4 Turbo', 'Latest GPT-4 Turbo model with vision', 128000, 4096, 0.01, 0.03, true, true, true, 1.0, 'gpt-4-turbo'),
('openai', 'gpt-3.5-turbo', 'GPT-3.5 Turbo', 'Fast and inexpensive model for simple tasks', 16385, 4096, 0.0005, 0.0015, true, true, false, 1.0, 'gpt-3.5-turbo'),

-- Anthropic Claude 系列
('anthropic', 'claude-3-5-sonnet', 'Claude 3.5 Sonnet', 'Most intelligent Claude model', 200000, 8192, 0.003, 0.015, true, true, true, 1.0, 'claude-3-5-sonnet-latest'),
('anthropic', 'claude-3-5-haiku', 'Claude 3.5 Haiku', 'Fast and affordable Claude model', 200000, 8192, 0.0008, 0.004, true, true, true, 1.0, 'claude-3-5-haiku-latest'),
('anthropic', 'claude-3-opus', 'Claude 3 Opus', 'Powerful model for complex tasks', 200000, 4096, 0.015, 0.075, true, true, true, 1.0, 'claude-3-opus-latest'),

-- AWS Bedrock (需要配置区域)
('bedrock', 'anthropic.claude-3-5-sonnet-v2', 'Claude 3.5 Sonnet (Bedrock)', 'Claude on AWS Bedrock', 200000, 8192, 0.003, 0.015, true, true, true, 1.0, 'anthropic.claude-3-5-sonnet-20241022-v2:0'),
('bedrock', 'anthropic.claude-3-haiku', 'Claude 3 Haiku (Bedrock)', 'Fast Claude on AWS', 200000, 4096, 0.00025, 0.00125, true, true, true, 1.0, 'anthropic.claude-3-haiku-20240307-v1:0');

-- 6. 验证插入
SELECT provider, COUNT(*) as model_count 
FROM models 
GROUP BY provider 
ORDER BY provider;