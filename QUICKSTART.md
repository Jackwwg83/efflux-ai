# Efflux AI 快速启动指南

## 项目结构已完成！🎉

恭喜！Efflux AI 的完整代码已经生成完毕。现在你需要进行一些配置来运行项目。

## 立即开始

### 1. 创建 Supabase 项目

1. 访问 [Supabase](https://app.supabase.com)
2. 创建新项目
3. 记下以下信息：
   - Project URL
   - Anon Key
   - Service Role Key

### 2. 配置环境变量

创建 `.env.local` 文件：

```bash
cp .env.example .env.local
```

编辑 `.env.local`，填入你的 Supabase 凭据：

```env
NEXT_PUBLIC_SUPABASE_URL=你的_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=你的_anon_key
SUPABASE_SERVICE_KEY=你的_service_key
```

### 3. 初始化数据库

在 Supabase Dashboard 的 SQL Editor 中运行：

```sql
-- 复制 supabase/migrations/20250117000001_init_schema.sql 的内容
```

### 4. 安装依赖并运行

```bash
# 安装依赖
npm install

# 运行开发服务器
npm run dev
```

访问 http://localhost:3000

### 5. 配置 AI Provider API Keys（管理员）

1. 修改 `app/(admin)/admin/layout.tsx` 中的 `ADMIN_EMAILS`，添加你的邮箱
2. 登录后访问 `/admin/api-keys`
3. 添加至少一个 API Key（例如 Google Gemini）

## 获取 API Keys

### Google Gemini (推荐新手)
1. 访问 [Google AI Studio](https://makersuite.google.com/app/apikey)
2. 创建 API Key
3. 免费额度很大，适合测试

### OpenAI
1. 访问 [OpenAI Platform](https://platform.openai.com/api-keys)
2. 创建 API Key
3. 需要付费，但模型质量高

### Anthropic Claude
1. 访问 [Anthropic Console](https://console.anthropic.com/)
2. 创建 API Key
3. 需要付费，Claude 3.5 Sonnet 很强大

## 部署 Edge Functions

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录
supabase login

# 链接项目
supabase link --project-ref 你的项目ref

# 部署 chat function
supabase functions deploy chat

# 设置环境变量（如果使用 AWS Bedrock）
supabase secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx AWS_REGION=us-east-1
```

## 功能清单

✅ **已实现的功能：**
- 多 AI 模型支持（Google Gemini、OpenAI、Anthropic、AWS Bedrock）
- 用户认证（邮箱、Google、Apple）
- 用户分级系统（Free、Pro、Max）
- 实时流式对话
- 额度管理和使用追踪
- 管理员 API Key 管理
- 响应式 UI 设计
- 完整的类型安全（TypeScript）

🚧 **可扩展功能：**
- Stripe 支付集成
- 更多 AI 模型
- 对话历史搜索
- 导出对话功能
- 团队协作功能

## 测试账号等级

在 SQL Editor 中运行以下命令可以手动修改用户等级：

```sql
-- 升级到 Pro
UPDATE user_tiers 
SET tier = 'pro', credits_limit = 500000, rate_limit = 30 
WHERE user_id = (SELECT id FROM auth.users WHERE email = '你的邮箱');

-- 升级到 Max
UPDATE user_tiers 
SET tier = 'max', credits_limit = 5000000, rate_limit = 100 
WHERE user_id = (SELECT id FROM auth.users WHERE email = '你的邮箱');
```

## 常见问题

### Q: 为什么显示 "No API keys configured"？
A: 需要先在管理员界面添加 API Keys

### Q: 如何成为管理员？
A: 修改 `app/(admin)/admin/layout.tsx` 中的 `ADMIN_EMAILS` 数组

### Q: Edge Function 部署失败？
A: 确保已经正确链接 Supabase 项目，并且有正确的权限

## 下一步

1. **测试所有功能** - 确保聊天、模型切换、额度系统正常工作
2. **部署到 Vercel** - 参考 DEPLOYMENT.md
3. **集成支付** - 添加 Stripe 来实现付费升级
4. **自定义 UI** - 根据你的品牌调整颜色和样式

## 需要帮助？

- 查看详细部署文档：`DEPLOYMENT.md`
- 查看项目说明：`README.md`
- Supabase 文档：https://supabase.com/docs
- Next.js 文档：https://nextjs.org/docs

祝你使用愉快！🚀