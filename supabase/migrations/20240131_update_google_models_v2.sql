-- 更新 Google Gemini 模型配置为最新版本

-- 删除旧的 Google 模型
DELETE FROM models WHERE provider = 'google';

-- 插入最新的 Gemini 模型
INSERT INTO models (provider, model_id, display_name, description, context_window, max_tokens, input_price_per_1k, output_price_per_1k, supports_streaming, supports_functions, supports_vision, default_temperature, provider_model_id) VALUES
-- Gemini 2.0 系列
('google', 'gemini-2.0-flash-exp', 'Gemini 2.0 Flash (Experimental)', 'Newest experimental model, fastest with multimodal capabilities', 1048576, 8192, 0.0, 0.0, true, true, true, 1.0, 'gemini-2.0-flash-exp'),
('google', 'gemini-2.0-flash-thinking-exp', 'Gemini 2.0 Flash Thinking (Experimental)', 'Experimental model with enhanced reasoning', 1048576, 8192, 0.0, 0.0, true, true, true, 1.0, 'gemini-2.0-flash-thinking-exp-1219'),

-- Gemini 1.5 系列（仍然支持）
('google', 'gemini-1.5-pro', 'Gemini 1.5 Pro', 'Advanced model for complex tasks', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-1.5-pro'),
('google', 'gemini-1.5-flash', 'Gemini 1.5 Flash', 'Fast model for high-volume tasks', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-1.5-flash'),
('google', 'gemini-1.5-flash-8b', 'Gemini 1.5 Flash 8B', 'Smaller, faster variant', 1048576, 8192, 0.0000375, 0.00015, true, true, true, 1.0, 'gemini-1.5-flash-8b'),

-- Gemini 1.0 Pro (legacy)
('google', 'gemini-1.0-pro', 'Gemini 1.0 Pro', 'Legacy model', 32768, 8192, 0.0005, 0.0015, true, true, false, 0.9, 'gemini-1.0-pro');

-- 验证更新
SELECT * FROM models WHERE provider = 'google' ORDER BY display_name;