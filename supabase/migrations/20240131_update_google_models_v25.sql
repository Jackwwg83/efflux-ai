-- 更新 Google Gemini 模型配置为最新的 2.5 系列

-- 删除旧的 Google 模型
DELETE FROM models WHERE provider = 'google';

-- 插入最新的 Gemini 2.5 模型
INSERT INTO models (provider, model_id, display_name, description, context_window, max_tokens, input_price_per_1k, output_price_per_1k, supports_streaming, supports_functions, supports_vision, default_temperature, provider_model_id) VALUES
-- Gemini 2.5 系列（最新）
('google', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google 旗下最强大的思考型模型，回答准确性最高，性能出色', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-2.5-pro'),
('google', 'gemini-2.5-flash', 'Gemini 2.5 Flash', '在性价比方面表现出色的模型，可提供全面的功能', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.5-flash'),
('google', 'gemini-2.5-flash-lite-preview', 'Gemini 2.5 Flash-Lite Preview', '经过优化，提高了成本效益并缩短了延迟时间', 1048576, 8192, 0.00005, 0.00015, true, true, true, 1.0, 'gemini-2.5-flash-lite-preview-06-17'),

-- Gemini 2.0 系列
('google', 'gemini-2.0-flash', 'Gemini 2.0 Flash', '新一代功能、速度和实时流式传输', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-2.0-flash'),
('google', 'gemini-2.0-flash-lite', 'Gemini 2.0 Flash-Lite', '成本效益和低延迟', 1048576, 8192, 0.00005, 0.00015, true, true, true, 1.0, 'gemini-2.0-flash-lite'),

-- Gemini 1.5 系列（已弃用但仍可用）
('google', 'gemini-1.5-pro', 'Gemini 1.5 Pro (Deprecated)', '需要更高智能的复杂推理任务', 2097152, 8192, 0.00125, 0.005, true, true, true, 1.0, 'gemini-1.5-pro'),
('google', 'gemini-1.5-flash', 'Gemini 1.5 Flash (Deprecated)', '在各种任务中提供快速而多样的性能', 1048576, 8192, 0.000075, 0.0003, true, true, true, 1.0, 'gemini-1.5-flash'),
('google', 'gemini-1.5-flash-8b', 'Gemini 1.5 Flash-8B (Deprecated)', '量大且智能程度较低的任务', 1048576, 8192, 0.0000375, 0.00015, true, true, true, 1.0, 'gemini-1.5-flash-8b');

-- 验证更新
SELECT * FROM models WHERE provider = 'google' ORDER BY display_name;