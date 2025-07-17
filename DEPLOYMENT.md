# Efflux AI 部署指南

## 前置要求

1. **Supabase 账号**
2. **Vercel 账号**
3. **Google OAuth 凭据**（可选）
4. **Apple Developer 账号**（可选）

## 第一步：设置 Supabase

### 1. 创建 Supabase 项目

1. 登录 [Supabase Dashboard](https://app.supabase.com)
2. 点击 "New Project"
3. 填写项目信息：
   - 项目名称：`efflux-ai`
   - 数据库密码：设置一个强密码
   - 区域：选择离你最近的区域

### 2. 配置数据库

1. 在 SQL Editor 中运行 `supabase/migrations/20250117000001_init_schema.sql`
2. 等待所有表创建完成

### 3. 配置认证

#### 启用邮箱登录
1. 进入 Authentication > Providers
2. 确保 Email 已启用

#### 配置 Google OAuth
1. 在 Google Cloud Console 创建 OAuth 2.0 凭据
2. 添加授权回调 URL：`https://yourproject.supabase.co/auth/v1/callback`
3. 在 Supabase 中配置 Google Provider：
   - Client ID
   - Client Secret

#### 配置 Apple Sign In（可选）
1. 在 Apple Developer 中创建 Sign In with Apple
2. 配置 Service ID 和 Key
3. 在 Supabase 中配置 Apple Provider

### 4. 获取项目凭据

在 Settings > API 中获取：
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

### 5. 部署 Edge Functions

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录
supabase login

# 链接项目
supabase link --project-ref your-project-ref

# 部署 Edge Functions
supabase functions deploy chat
```

### 6. 配置 API 密钥

在 Supabase Dashboard 的 SQL Editor 中运行：

```sql
-- 添加 API 密钥（管理员使用）
INSERT INTO api_keys (provider, api_key, is_active) VALUES
('google', 'your-google-api-key', true),
('openai', 'your-openai-api-key', true),
('anthropic', 'your-anthropic-api-key', true);
```

## 第二步：部署到 Vercel

### 1. 准备代码

```bash
# 克隆仓库
git clone https://github.com/yourusername/efflux-ai.git
cd efflux-ai

# 安装依赖
npm install
```

### 2. 创建环境变量文件

创建 `.env.local`：
```env
NEXT_PUBLIC_SUPABASE_URL=https://yourproject.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key
```

### 3. 部署到 Vercel

#### 方法一：通过 GitHub

1. 将代码推送到 GitHub
2. 在 [Vercel Dashboard](https://vercel.com) 导入项目
3. 配置环境变量
4. 部署

#### 方法二：使用 Vercel CLI

```bash
# 安装 Vercel CLI
npm i -g vercel

# 部署
vercel

# 设置环境变量
vercel env add NEXT_PUBLIC_SUPABASE_URL
vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY
vercel env add SUPABASE_SERVICE_KEY
```

## 第三步：配置 Edge Functions 环境变量

在 Supabase Dashboard > Edge Functions > 你的函数 > Secrets 中添加：

```env
# AWS Bedrock（如果使用）
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_REGION=us-east-1
```

## 第四步：测试部署

1. 访问你的 Vercel URL
2. 注册新账号
3. 测试聊天功能
4. 检查额度系统是否正常工作

## 生产环境配置

### 1. 自定义域名

在 Vercel 中配置自定义域名：
1. Settings > Domains
2. 添加你的域名
3. 配置 DNS

### 2. 更新 Supabase 配置

更新认证回调 URL：
```
https://yourdomain.com/auth/callback
```

### 3. 监控和日志

- **Vercel Analytics**：监控前端性能
- **Supabase Dashboard**：监控数据库和 API 使用
- **Edge Functions Logs**：查看函数执行日志

## 故障排查

### 常见问题

1. **"No API keys configured" 错误**
   - 检查 `api_keys` 表中是否有活跃的密钥
   - 确保 Edge Function 有正确的权限

2. **OAuth 登录失败**
   - 检查回调 URL 配置
   - 确保 OAuth 凭据正确

3. **Edge Function 超时**
   - 检查模型响应时间
   - 考虑增加超时限制

### 日志查看

```bash
# 查看 Edge Function 日志
supabase functions logs chat

# 查看实时日志
supabase functions logs chat --tail
```

## 安全建议

1. **定期轮换 API 密钥**
2. **监控异常使用模式**
3. **设置告警阈值**
4. **启用 2FA**
5. **定期备份数据库**

## 成本优化

1. **使用 Supabase 免费额度**
   - 500MB 数据库
   - 2GB 带宽
   - 50MB 文件存储

2. **Vercel 免费计划**
   - 100GB 带宽
   - 无限静态请求

3. **优化 Edge Function 调用**
   - 实现缓存策略
   - 批量处理请求