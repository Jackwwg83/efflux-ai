-- 更新 Google Gemini 模型配置

-- 删除旧的 Google 模型
DELETE FROM models WHERE provider = 'google';

-- 插入新的 Gemini 模型
INSERT INTO models (provider, model_id, display_name, description, context_window, max_tokens, input_price_per_1k, output_price_per_1k, supports_streaming, supports_functions, supports_vision, default_temperature, provider_model_id) VALUES
-- Gemini 2.0 Flash (实验版)
('google', 'gemini-2.0-flash-exp', 'Gemini 2.0 Flash (Experimental)', 'Newest and fastest Gemini model with improved capabilities', 1048576, 8192, 0.0, 0.0, true, true, true, 1.0, 'gemini-2.0-flash-exp'),

-- Gemini 1.5 Pro
('google', 'gemini-1.5-pro-002', 'Gemini 1.5 Pro', 'Most capable Gemini model for complex tasks', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-1.5-pro-002'),
('google', 'gemini-1.5-pro', 'Gemini 1.5 Pro (Latest)', 'Latest version of Gemini 1.5 Pro', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-1.5-pro-latest'),

-- Gemini 1.5 Flash
('google', 'gemini-1.5-flash-002', 'Gemini 1.5 Flash', 'Fast and versatile model for various tasks', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-1.5-flash-002'),
('google', 'gemini-1.5-flash', 'Gemini 1.5 Flash (Latest)', 'Latest version of Gemini 1.5 Flash', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-1.5-flash-latest'),
('google', 'gemini-1.5-flash-8b', 'Gemini 1.5 Flash 8B', 'Smaller, faster variant of Flash model', 1048576, 8192, 0.0000375, 0.00015, true, true, true, 1.0, 'gemini-1.5-flash-8b-latest');

-- 验证更新
SELECT * FROM models WHERE provider = 'google' ORDER BY display_name;