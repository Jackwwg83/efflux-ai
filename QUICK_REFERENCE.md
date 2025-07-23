# Efflux-AI 快速参考卡

## 🚀 一句话说明关键概念

- **项目定位**: SaaS 平台，管理员提供 AI 能力给用户使用
- **双提供商系统**: 直接提供商（OpenAI等）+ 聚合器（AiHubMix等）
- **核心原则**: 所有 API 密钥由管理员管理，用户只是使用者

## 📁 关键文件位置

### 数据库函数
- 主要函数: `/supabase/migrations/20250123_api_aggregator_admin.sql`
- 用户管理: `/supabase/migrations/20240131_fix_user_signup_complete.sql`
- API管理: `/supabase/migrations/20250117_api_gateway_enhancement.sql`

### 前端核心
- 聊天界面: `/app/(dashboard)/chat/page.tsx`
- 模型选择: `/components/chat/model-selector.tsx`
- 管理后台: `/app/(admin)/admin/`

### API 端点
- 聊天API: `/supabase/functions/v1-chat/index.ts`
- 模型同步: `/supabase/functions/sync-models/index.ts`

### 配置服务
- 聚合器工厂: `/lib/ai/providers/aggregator/provider-factory.ts`
- AiHubMix: `/lib/ai/providers/aggregator/aihubmix-provider.ts`

## 🔑 核心函数速查

```sql
-- 获取所有可用模型（直接+聚合器）
get_all_available_models()

-- 获取模型提供商配置
get_model_provider_config_v2(p_model_id TEXT)

-- 获取可用API密钥
get_available_api_key(p_provider TEXT)

-- 检查用户配额
check_and_update_user_quota(p_user_id UUID, p_tokens INTEGER)
```

```typescript
// 同步聚合器模型
ModelSyncService.syncAggregatorModels(apiKeyId, providerName)

// 发送聊天消息
ChatContainer.sendMessage(content)

// 加载模型列表
ModelSelector.loadModelsAndUserTier()
```

## 🚨 已知关键问题

1. **模型显示问题** ✅ 已修复
   - `/admin/models` 页面现在显示聚合器模型

2. **RLS 策略不一致**
   - 使用 `admin_users` 表，不是 JWT

3. **硬编码逻辑**
   - 上下文窗口推断在 `aihubmix-provider.ts`

## 💻 常用命令

```bash
# 部署到 Vercel（自动）
git push

# 部署 Edge Function（手动）
SUPABASE_ACCESS_TOKEN="sbp_df5ff67c1b111b4a15a9b1d38b42cc80e16c1381" npx supabase functions deploy v1-chat --no-verify-jwt

# 本地开发
npm run dev

# 查看日志
npx supabase functions logs v1-chat
```

## 🔄 数据流简图

```
用户选择模型 → 发送消息 → Edge Function 路由
                              ↓
                   聚合器模型? → Yes → aggregator_models表
                              ↓ No
                         model_configs表
```

## 📊 数据库关系

```
users ←→ user_quotas
  ↓        ↓
conversations → messages
  ↓
presets

api_providers → aggregator_models
       ↓
api_key_pool (provider_type: 'direct'|'aggregator')
```

## ⚡ 紧急修复指南

### 如果聊天不工作
1. 检查 Edge Function 日志
2. 验证 `get_model_provider_config_v2` 返回值
3. 确认 API 密钥状态

### 如果模型不显示
1. 检查 `get_all_available_models` 函数
2. 验证 RLS 策略
3. 确认用户权限

### 如果同步失败
1. 检查聚合器 API 密钥
2. 查看 `ModelSyncService` 错误日志
3. 验证网络连接

---
*使用 `/read ARCHITECTURE_ANALYSIS.md` 和 `/read FUNCTION_INDEX.md` 获取详细信息*