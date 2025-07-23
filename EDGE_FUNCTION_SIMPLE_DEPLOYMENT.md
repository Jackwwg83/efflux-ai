# Edge Function 简化部署指南

## 🚀 快速部署方案

### 方案 1：使用 Supabase CLI（需要 Node.js）

如果你的电脑上有 Node.js，可以在终端执行：

```bash
# 1. 安装 Supabase CLI（如果还没安装）
npm install -g supabase

# 2. 登录到 Supabase
npx supabase login

# 3. 链接到你的项目
cd /home/ubuntu/jack/projects/efflux/efflux-ai
npx supabase link --project-ref lzvwduadnunbtxqaqhkg

# 4. 备份当前函数
cp supabase/functions/v1-chat/index.ts supabase/functions/v1-chat/index-backup.ts

# 5. 使用新版本
cp supabase/functions/v1-chat/index-aggregator.ts supabase/functions/v1-chat/index.ts

# 6. 部署
npx supabase functions deploy v1-chat --no-verify-jwt
```

### 方案 2：手动创建测试函数（推荐）

由于原始 Edge Function 文件很大，我建议先创建一个测试版本：

1. **登录 Supabase Dashboard**
   - https://supabase.com/dashboard/project/lzvwduadnunbtxqaqhkg/functions

2. **暂时跳过 Edge Function 部署**
   - 我们可以先完成前端开发
   - 前端可以先使用现有的 API
   - 等前端完成后再更新 Edge Function

## 🎯 下一步计划

既然数据库已经部署成功，我们可以：

1. **开发前端管理界面**
   - API Provider 管理页面
   - 添加 API Key 的界面
   - 模型选择器更新

2. **创建测试数据**
   - 手动添加一些测试用的 AiHubMix 模型数据
   - 这样可以先测试前端功能

3. **最后部署 Edge Function**
   - 等前端开发完成
   - 可以找开发人员帮忙部署

## 📝 临时测试方案

在 SQL Editor 中运行以下命令，添加一些测试模型：

```sql
-- 添加一些 AiHubMix 的测试模型
INSERT INTO aggregator_models (provider_id, model_id, model_name, display_name, model_type, capabilities, context_window, is_available)
VALUES 
  (
    (SELECT id FROM api_providers WHERE name = 'aihubmix'),
    'gpt-4-turbo-preview',
    'gpt-4-turbo-preview',
    'GPT-4 Turbo',
    'chat',
    '{"vision": true, "functions": true, "streaming": true}'::jsonb,
    128000,
    true
  ),
  (
    (SELECT id FROM api_providers WHERE name = 'aihubmix'),
    'claude-3-opus-20240229',
    'claude-3-opus-20240229',
    'Claude 3 Opus',
    'chat',
    '{"vision": true, "functions": true, "streaming": true}'::jsonb,
    200000,
    true
  ),
  (
    (SELECT id FROM api_providers WHERE name = 'aihubmix'),
    'gemini-1.5-pro-latest',
    'gemini-1.5-pro-latest',
    'Gemini 1.5 Pro',
    'chat',
    '{"vision": true, "functions": true, "streaming": true}'::jsonb,
    1000000,
    true
  );
```

这样我们就可以先开发和测试前端功能了。