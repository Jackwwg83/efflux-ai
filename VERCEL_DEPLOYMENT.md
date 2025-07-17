# Vercel 部署指南

## 步骤 1: 准备 GitHub 仓库

首先，你需要将 efflux-ai 项目推送到 GitHub：

```bash
cd /home/ubuntu/jack/projects/efflux/efflux-ai

# 初始化 Git 仓库
git init
git add .
git commit -m "Initial commit: Efflux AI SaaS platform"

# 创建 GitHub 仓库并推送
# 1. 访问 https://github.com/new
# 2. 创建名为 "efflux-ai" 的新仓库
# 3. 执行以下命令：
git remote add origin https://github.com/YOUR_USERNAME/efflux-ai.git
git branch -M main
git push -u origin main
```

## 步骤 2: 部署到 Vercel

### 方法 A: 通过 Vercel 网站（推荐）

1. 访问 https://vercel.com
2. 登录你的账户
3. 点击 "New Project"
4. 选择 "Import Git Repository"
5. 选择你刚创建的 efflux-ai 仓库
6. 配置环境变量：
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://lzvwduadnunbtxqaqhkg.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx6dndkdWFkbnVuYnR4cWFxaGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI3NDE0NzgsImV4cCI6MjA2ODMxNzQ3OH0.UgDX-GvnlG1XhOEBfFauCKYrRC9I4I5mmFhIoCptOlo
   SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx6dndkdWFkbnVuYnR4cWFxaGtnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1Mjc0MTQ3OCwiZXhwIjoyMDY4MzE3NDc4fQ.V6LCMLwvqstSyZToAz1QL44CxZU7s2adh4aL1Al4-tw
   ```
7. 点击 "Deploy"

### 方法 B: 使用 Vercel CLI

```bash
# 安装 Vercel CLI
npm i -g vercel

# 在项目目录中
cd /home/ubuntu/jack/projects/efflux/efflux-ai

# 部署
vercel

# 按照提示操作：
# - 选择你的 Vercel 账户
# - 确认项目设置
# - 等待部署完成
```

## 步骤 3: 配置生产环境变量

在 Vercel Dashboard 中：
1. 进入你的项目设置
2. 选择 "Environment Variables"
3. 添加所有环境变量（如上所示）
4. 重新部署以应用更改

## 步骤 4: 更新 Supabase 配置

1. 在 Supabase Dashboard 中，进入 Authentication → URL Configuration
2. 添加你的 Vercel 域名到 "Site URL"：
   ```
   https://your-app.vercel.app
   ```
3. 添加重定向 URL：
   ```
   https://your-app.vercel.app/**
   ```

## 步骤 5: 部署 Supabase Edge Functions

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录
supabase login

# 链接项目
supabase link --project-ref lzvwduadnunbtxqaqhkg

# 部署 Edge Functions
supabase functions deploy chat

# 设置环境变量（如果使用 AWS Bedrock）
supabase secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx AWS_REGION=us-east-1
```

## 重要提醒

1. **域名配置**：Vercel 会提供一个默认域名，如 `efflux-ai.vercel.app`
2. **环境变量**：确保所有环境变量都正确设置
3. **CORS 配置**：Edge Functions 已经配置了 CORS，应该能正常工作
4. **管理员设置**：部署后记得更新 `app/(admin)/admin/layout.tsx` 中的管理员邮箱

## 部署后检查清单

- [ ] 访问你的 Vercel URL
- [ ] 测试用户注册/登录
- [ ] 配置管理员邮箱
- [ ] 在管理面板添加 API Keys
- [ ] 测试聊天功能
- [ ] 检查 Edge Functions 是否正常工作

## 常见问题

### 构建失败？
- 检查 TypeScript 错误
- 确保所有依赖都已安装
- 查看 Vercel 构建日志

### Edge Functions 不工作？
- 确保已部署到 Supabase
- 检查 CORS 设置
- 查看 Supabase Functions 日志

需要帮助？告诉我具体遇到的问题！