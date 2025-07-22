-- Preset System Migration
-- 预设系统：管理员配置，用户使用

-- 1. 创建预设分类表
CREATE TABLE IF NOT EXISTS preset_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  description TEXT,
  icon TEXT, -- lucide icon name
  color TEXT, -- hex color
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 创建预设表（替代原来的 prompt_templates）
CREATE TABLE IF NOT EXISTS presets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES preset_categories(id),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  description TEXT,
  icon TEXT, -- lucide icon name
  color TEXT, -- hex color or tailwind class
  
  -- AI 配置
  system_prompt TEXT NOT NULL,
  model_preference TEXT, -- 可以是具体模型或模型类型
  temperature DECIMAL(3,2) DEFAULT 0.7,
  max_tokens INTEGER,
  
  -- 元数据
  is_active BOOLEAN DEFAULT true,
  is_default BOOLEAN DEFAULT false,
  sort_order INTEGER DEFAULT 0,
  usage_count INTEGER DEFAULT 0,
  
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 创建用户预设选择表
CREATE TABLE IF NOT EXISTS user_preset_selections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  preset_id UUID REFERENCES presets(id),
  selected_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, conversation_id)
);

-- 4. 创建索引
CREATE INDEX IF NOT EXISTS idx_presets_category ON presets(category_id);
CREATE INDEX IF NOT EXISTS idx_presets_active ON presets(is_active);
CREATE INDEX IF NOT EXISTS idx_presets_sort ON presets(sort_order);
CREATE INDEX IF NOT EXISTS idx_user_preset_selections_user ON user_preset_selections(user_id);

-- 5. 插入默认分类
INSERT INTO preset_categories (name, slug, description, icon, color, sort_order) VALUES
('General', 'general', 'General purpose AI assistants', 'MessageSquare', '#6366f1', 1),
('Productivity', 'productivity', 'Boost your productivity', 'Zap', '#f59e0b', 2),
('Creative', 'creative', 'Creative writing and ideation', 'Sparkles', '#ec4899', 3),
('Technical', 'technical', 'Programming and technical tasks', 'Code2', '#10b981', 4),
('Learning', 'learning', 'Educational and research', 'GraduationCap', '#3b82f6', 5);

-- 6. 插入默认预设
INSERT INTO presets (category_id, name, slug, description, icon, color, system_prompt, model_preference, temperature, is_default, sort_order) VALUES
-- General
((SELECT id FROM preset_categories WHERE slug = 'general'), 
 'General Assistant', 
 'general-assistant', 
 'A helpful AI assistant for everyday tasks', 
 'Bot', 
 '#6366f1',
 'You are a helpful, harmless, and honest AI assistant. Be concise and clear in your responses. If you''re unsure about something, say so rather than making things up.',
 'general',
 0.7,
 true,
 1),

-- Productivity
((SELECT id FROM preset_categories WHERE slug = 'productivity'), 
 'Email Writer', 
 'email-writer', 
 'Professional email composition', 
 'Mail', 
 '#f59e0b',
 'You are an expert email writer. Help compose professional, clear, and concise emails. Consider tone, audience, and purpose. Format emails properly with appropriate greetings and closings.',
 'gpt-4',
 0.5,
 false,
 1),

((SELECT id FROM preset_categories WHERE slug = 'productivity'), 
 'Meeting Notes', 
 'meeting-notes', 
 'Summarize and organize meeting notes', 
 'FileText', 
 '#f59e0b',
 'You are an expert at organizing and summarizing meeting notes. Extract key points, action items, decisions made, and follow-ups. Present information in a clear, structured format.',
 'general',
 0.3,
 false,
 2),

-- Creative
((SELECT id FROM preset_categories WHERE slug = 'creative'), 
 'Creative Writer', 
 'creative-writer', 
 'Creative writing and storytelling', 
 'PenTool', 
 '#ec4899',
 'You are a creative writing assistant with expertise in storytelling, narrative structure, and engaging prose. Help with creative writing, story development, character creation, and world-building. Be imaginative and inspiring.',
 'claude-3-opus',
 0.9,
 false,
 1),

((SELECT id FROM preset_categories WHERE slug = 'creative'), 
 'Brainstorming', 
 'brainstorming', 
 'Generate creative ideas and solutions', 
 'Lightbulb', 
 '#ec4899',
 'You are a creative brainstorming partner. Generate diverse, innovative ideas. Think outside the box and make unexpected connections. Present ideas in an organized, actionable format.',
 'general',
 0.8,
 false,
 2),

-- Technical
((SELECT id FROM preset_categories WHERE slug = 'technical'), 
 'Code Expert', 
 'code-expert', 
 'Programming assistance and code review', 
 'Terminal', 
 '#10b981',
 'You are an expert programmer proficient in multiple languages and frameworks. Provide clean, efficient, well-documented code. Explain complex concepts clearly. Follow best practices and consider edge cases.',
 'gpt-4',
 0.2,
 false,
 1),

((SELECT id FROM preset_categories WHERE slug = 'technical'), 
 'Debug Assistant', 
 'debug-assistant', 
 'Help debug code and fix errors', 
 'Bug', 
 '#10b981',
 'You are a debugging expert. Analyze error messages, identify root causes, and provide clear solutions. Explain what went wrong and how to prevent similar issues. Be systematic in your debugging approach.',
 'claude-3-opus',
 0.1,
 false,
 2),

-- Learning
((SELECT id FROM preset_categories WHERE slug = 'learning'), 
 'Tutor', 
 'tutor', 
 'Personal learning assistant', 
 'BookOpen', 
 '#3b82f6',
 'You are a patient, knowledgeable tutor. Explain concepts clearly, use examples, and adapt to the learner''s level. Ask clarifying questions and check understanding. Make learning engaging and effective.',
 'general',
 0.5,
 false,
 1),

((SELECT id FROM preset_categories WHERE slug = 'learning'), 
 'Research Assistant', 
 'research-assistant', 
 'Help with research and fact-finding', 
 'Search', 
 '#3b82f6',
 'You are a thorough research assistant. Find accurate, relevant information from reliable sources. Synthesize findings clearly. Always cite sources when possible. Be objective and comprehensive.',
 'gpt-4',
 0.3,
 false,
 2);

-- 7. 创建获取预设的函数
CREATE OR REPLACE FUNCTION get_preset_for_conversation(
  p_conversation_id UUID,
  p_user_id UUID
)
RETURNS TABLE (
  preset_id UUID,
  system_prompt TEXT,
  temperature DECIMAL,
  max_tokens INTEGER,
  model_preference TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.system_prompt,
    p.temperature,
    p.max_tokens,
    p.model_preference
  FROM presets p
  LEFT JOIN user_preset_selections ups ON ups.preset_id = p.id 
    AND ups.conversation_id = p_conversation_id 
    AND ups.user_id = p_user_id
  WHERE p.is_active = true
    AND (ups.preset_id IS NOT NULL OR p.is_default = true)
  ORDER BY ups.selected_at DESC NULLS LAST, p.is_default DESC
  LIMIT 1;
END;
$$;

-- 8. 更新使用统计的触发器
CREATE OR REPLACE FUNCTION update_preset_usage_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.preset_id IS NOT NULL THEN
    UPDATE presets 
    SET usage_count = usage_count + 1,
        updated_at = NOW()
    WHERE id = NEW.preset_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_preset_usage
AFTER INSERT ON user_preset_selections
FOR EACH ROW
EXECUTE FUNCTION update_preset_usage_count();

-- 9. 设置权限
ALTER TABLE preset_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preset_selections ENABLE ROW LEVEL SECURITY;

-- 分类：所有人可读
CREATE POLICY "Everyone can read preset categories" ON preset_categories
  FOR SELECT USING (true);

-- 分类：只有管理员可以管理
CREATE POLICY "Admins can manage preset categories" ON preset_categories
  FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
  );

-- 预设：所有人可读激活的预设
CREATE POLICY "Everyone can read active presets" ON presets
  FOR SELECT USING (is_active = true);

-- 预设：只有管理员可以管理
CREATE POLICY "Admins can manage presets" ON presets
  FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
  );

-- 用户选择：用户可以管理自己的选择
CREATE POLICY "Users can manage own preset selections" ON user_preset_selections
  FOR ALL USING (user_id = auth.uid());

-- 10. 授予权限
GRANT SELECT ON preset_categories TO authenticated;
GRANT SELECT ON presets TO authenticated;
GRANT ALL ON user_preset_selections TO authenticated;
GRANT EXECUTE ON FUNCTION get_preset_for_conversation(UUID, UUID) TO authenticated;

-- 11. 迁移旧数据（如果需要）
DO $$
BEGIN
  -- 将旧的 prompt_templates 数据迁移到 presets
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'prompt_templates') THEN
    INSERT INTO presets (name, slug, description, system_prompt, is_active, created_by, created_at, updated_at)
    SELECT 
      name,
      LOWER(REPLACE(name, ' ', '-')),
      description,
      template,
      is_active,
      created_by,
      created_at,
      updated_at
    FROM prompt_templates
    ON CONFLICT DO NOTHING;
  END IF;
END $$;