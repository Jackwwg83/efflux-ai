-- 临时解决方案：禁用 aggregator_models 的 RLS 以便测试

-- 选项 1：完全禁用 RLS（仅用于测试！）
ALTER TABLE aggregator_models DISABLE ROW LEVEL SECURITY;

-- 测试同步模型功能...

-- 测试完成后，重新启用 RLS：
-- ALTER TABLE aggregator_models ENABLE ROW LEVEL SECURITY;