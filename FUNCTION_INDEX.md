# Efflux-AI Function Index (函数索引)

本文档包含 Efflux-AI 项目中所有主要函数和方法的完整索引。

## 目录

1. [Database Functions (数据库函数)](#database-functions)
2. [TypeScript/React Functions (前端函数)](#typescript-react-functions)
3. [API Endpoints & Edge Functions (API 端点)](#api-endpoints--edge-functions)
4. [Utility Functions (工具函数)](#utility-functions)

---

## Database Functions (数据库函数)

### 用户管理函数

#### `handle_new_user()`
- **文件**: `20240131_fix_user_signup_complete.sql`
- **作用**: 处理新用户注册，创建相关记录
- **触发器**: `auth.users` INSERT 后触发
- **操作**:
  - 创建 `users` 表记录
  - 创建 `user_quotas` 记录（10,000 tokens 初始配额）
  - 创建 `user_tiers` 记录（默认 'free' 层级）

#### `is_admin(user_id uuid)`
- **文件**: `20240131_production_admin_system.sql`
- **作用**: 检查指定用户是否为管理员
- **返回**: BOOLEAN
- **使用**: RLS 策略中的权限验证

#### `is_current_user_admin()`
- **文件**: `20240131_production_admin_system.sql`
- **作用**: 检查当前登录用户是否为管理员
- **返回**: BOOLEAN
- **使用**: 视图和查询中的权限检查

### API 密钥管理函数

#### `get_available_api_key(p_provider TEXT)`
- **文件**: `20250117_api_gateway_enhancement.sql`
- **作用**: 获取可用的 API 密钥（轮询机制）
- **返回**: TABLE (id UUID, api_key TEXT)
- **逻辑**:
  - 按 `last_used_at` 排序（最久未使用优先）
  - 跳过达到速率限制的密钥
  - 检查 `is_active` 状态

#### `record_api_key_error(p_api_key_id UUID, p_error_message TEXT)`
- **文件**: `20250117_api_gateway_enhancement.sql`
- **作用**: 记录 API 密钥错误
- **操作**:
  - 增加 `error_count` 和 `consecutive_errors`
  - 连续错误超过 5 次自动禁用密钥

#### `record_api_key_success(p_api_key_id UUID, p_tokens_used INTEGER)`
- **文件**: `20250117_api_gateway_enhancement.sql`
- **作用**: 记录 API 密钥成功使用
- **操作**:
  - 重置 `consecutive_errors`
  - 更新 `total_tokens_used`
  - 更新 `last_used_at`

### 模型管理函数

#### `get_all_available_models()`
- **文件**: `20250123_api_aggregator_admin.sql`
- **作用**: 获取所有可用模型（直接 + 聚合器）
- **返回**: 
  ```sql
  TABLE (
    model_id TEXT,
    display_name TEXT,
    provider_name TEXT,
    model_type TEXT,
    context_window INTEGER,
    is_aggregator BOOLEAN,
    capabilities JSONB,
    tier_required TEXT
  )
  ```
- **逻辑**:
  - UNION 直接提供商模型（model_configs）
  - UNION 聚合器模型（aggregator_models）

#### `get_model_provider_config_v2(p_model_id TEXT)`
- **文件**: `20250123_api_aggregator_admin.sql`
- **作用**: 获取模型的提供商配置（支持聚合器）
- **返回**: 提供商配置信息
- **使用**: Edge Function 中路由请求

### 对话管理函数

#### `search_conversations(p_user_id UUID, p_search_term TEXT)`
- **文件**: `20240202_conversation_management.sql`
- **作用**: 搜索用户对话
- **功能**:
  - 全文搜索标题
  - 搜索消息内容
  - 返回相关度排序

#### `generate_conversation_title(p_messages JSONB)`
- **文件**: `20240202_conversation_management.sql`
- **作用**: 从消息生成对话标题
- **逻辑**:
  - 提取前 3 条用户消息
  - 截取前 100 个字符
  - 清理特殊字符

#### `assemble_conversation_messages(p_conversation_id UUID, p_max_messages INTEGER)`
- **文件**: `20240203_system_prompt_management.sql`
- **作用**: 组装对话消息历史
- **功能**:
  - 获取最近 N 条消息
  - 保持系统提示在最前
  - 估算 token 使用量

### 配额管理函数

#### `check_and_update_user_quota(p_user_id UUID, p_tokens_to_use INTEGER)`
- **文件**: `20250117_api_gateway_enhancement.sql`
- **作用**: 检查并更新用户配额
- **返回**: TABLE (has_quota BOOLEAN, remaining_quota INTEGER)
- **逻辑**:
  - 检查剩余配额
  - 扣除使用量
  - 原子操作防止并发问题

#### `update_user_usage(p_user_id UUID, p_tokens_used INTEGER, p_provider TEXT, p_model TEXT)`
- **文件**: `20240203_fix_token_usage_tracking.sql`
- **作用**: 更新用户使用统计
- **操作**:
  - 更新 `user_quotas` 使用量
  - 插入 `usage_logs` 记录
  - 增加请求计数

### 审计函数

#### `log_admin_action(p_action TEXT, p_resource_type TEXT, p_resource_id TEXT, p_details JSONB)`
- **文件**: `20240131_admin_audit_system.sql`
- **作用**: 记录管理员操作
- **使用**: 所有管理员操作的审计跟踪

#### `audit_api_key_changes()`
- **文件**: `20240131_admin_audit_system.sql`
- **作用**: API 密钥变更触发器函数
- **触发**: INSERT/UPDATE/DELETE on `api_key_pool`

### 健康状态函数

#### `record_model_failure(p_model TEXT, p_provider TEXT, p_error_message TEXT)`
- **文件**: `20240201_add_model_health_status.sql`
- **作用**: 记录模型失败
- **操作**:
  - 增加失败计数
  - 更新健康状态
  - 3 次失败后标记为 'degraded'
  - 10 次失败后标记为 'unavailable'

#### `get_provider_health_stats()`
- **文件**: `20250123_fix_api_providers_rls.sql`
- **作用**: 获取提供商健康统计
- **返回**: 每个提供商的健康指标

### 预设管理函数

#### `get_preset_for_conversation(p_conversation_id UUID, p_user_id UUID)`
- **文件**: `20240204_presets_system.sql`
- **作用**: 获取对话的预设配置
- **返回**: 预设信息（system_prompt, temperature 等）

---

## TypeScript/React Functions (前端函数)

### 核心服务类

#### `ModelSyncService` 类
- **文件**: `/lib/services/model-sync-admin.ts`
- **方法**:
  - `syncAggregatorModels(apiKeyId: string, providerName: string)` - 同步聚合器模型
  - `getModelStats(providerId: string)` - 获取模型统计

#### `AggregatorProviderFactory` 类
- **文件**: `/lib/ai/providers/aggregator/provider-factory.ts`
- **方法**:
  - `create(providerName: string, config: APIProviderConfig, apiKey: string)` - 创建聚合器实例

#### `AiHubMixProvider` 类
- **文件**: `/lib/ai/providers/aggregator/aihubmix-provider.ts`
- **方法**:
  - `fetchModels()` - 获取模型列表
  - `createChatCompletion(request: ChatRequest)` - 创建聊天完成
  - `validateApiKey()` - 验证 API 密钥
  - `mapModelsToSchema(models: any[])` - 转换模型格式

### React 组件函数

#### `ModelSelector` 组件
- **文件**: `/components/chat/model-selector.tsx`
- **主要函数**:
  - `loadModelsAndUserTier()` - 加载模型和用户层级
  - `handleModelChange(modelId: string)` - 处理模型选择

#### `ChatContainer` 组件
- **文件**: `/components/chat/chat-container.tsx`
- **主要函数**:
  - `sendMessage(content: string)` - 发送消息
  - `handleStreamResponse(response: Response)` - 处理流式响应
  - `updateConversation(updates: Partial<Conversation>)` - 更新对话

#### `ConversationSidebar` 组件
- **文件**: `/components/layout/conversation-sidebar.tsx`
- **主要函数**:
  - `loadConversations()` - 加载对话列表
  - `createNewConversation()` - 创建新对话
  - `deleteConversation(id: string)` - 删除对话

### Store 函数

#### `useConversationStore` Store
- **文件**: `/lib/stores/conversation.ts`
- **Actions**:
  - `setCurrentConversation(conversation: Conversation)`
  - `addMessage(message: Message)`
  - `updateMessage(id: string, updates: Partial<Message>)`
  - `clearConversation()`
  - `setStreaming(streaming: boolean)`

### Store 函数 (续)

#### `usePresetStore` Store
- **文件**: `/lib/stores/preset.ts`
- **Actions**:
  - `setPresets(presets: Preset[])`
  - `addPreset(preset: Preset)`
  - `updatePreset(id: string, updates: Partial<Preset>)`
  - `deletePreset(id: string)`
  - `setActivePreset(preset: Preset | null)`

### 工具函数

#### 加密工具
- **文件**: `/lib/crypto/vault.ts`
- **类**: `VaultClient`
- **方法**:
  - `encrypt(text: string)` - 使用用户密码加密文本
  - `decrypt(encryptedData: string)` - 解密文本
  - `generateKey()` - 生成加密密钥
  - `storeKey(key: string, value: string)` - 存储加密的 API 密钥
  - `retrieveKey(key: string)` - 获取解密的 API 密钥

#### Token 计数工具
- **文件**: `/lib/utils/token-counter.ts`
- **类**: `TokenCounter`
- **方法**:
  - `countTokens(text: string, model?: string)` - 计算文本 tokens
  - `estimateMessages(messages: Message[], model?: string)` - 估算消息 tokens
  - `getModelLimit(model: string)` - 获取模型 token 限制

#### 日志工具
- **文件**: `/lib/utils/logger.ts`
- **对象**: `logger`
- **方法**:
  - `info(message: string, data?: any)` - 信息日志
  - `error(message: string, error?: any)` - 错误日志
  - `warn(message: string, data?: any)` - 警告日志
  - `debug(message: string, data?: any)` - 调试日志

#### 通用工具
- **文件**: `/lib/utils.ts`
- **函数**:
  - `cn(...inputs: ClassValue[])` - 类名合并（使用 clsx + tailwind-merge）
  - `formatDate(date: Date, format?: string)` - 格式化日期
  - `truncateString(str: string, maxLength: number)` - 截断字符串
  - `generateId()` - 生成唯一 ID
  - `sleep(ms: number)` - 延迟函数

### AI 客户端类

#### `AIGatewayClient` 类
- **文件**: `/lib/ai/gateway-client.ts`
- **方法**:
  - `createChatCompletion(params: ChatCompletionParams)` - 创建聊天完成
  - `streamChatCompletion(params: ChatCompletionParams)` - 流式聊天完成
  - `handleStreamResponse(response: Response, onChunk: Function)` - 处理流响应
  - `parseSSEMessage(data: string)` - 解析 SSE 消息

#### `BaseAggregatorProvider` 抽象类
- **文件**: `/lib/ai/providers/aggregator/base-aggregator.ts`
- **抽象方法**:
  - `fetchModels()` - 获取模型列表
  - `createChatCompletion(request: ChatRequest)` - 创建聊天
  - `validateApiKey()` - 验证 API 密钥
  - `formatError(error: any)` - 格式化错误
- **通用方法**:
  - `makeRequest(endpoint: string, options: RequestInit)` - 发送请求
  - `getAuthorizationHeader()` - 获取认证头
  - `handleErrorResponse(response: Response)` - 处理错误响应
  - `createStreamingResponse(response: Response)` - 创建流式响应

---

## API Endpoints & Edge Functions (API 端点)

### Edge Functions

#### `/functions/v1-chat`
- **文件**: `/supabase/functions/v1-chat/index.ts`
- **方法**: POST
- **功能**: 处理聊天请求
- **请求体**:
  ```typescript
  {
    model: string
    messages: Message[]
    stream?: boolean
    temperature?: number
    max_tokens?: number
    conversationId?: string
  }
  ```
- **流程**:
  1. 验证用户认证
  2. 应用预设配置
  3. 检查聚合器模型
  4. 路由到相应提供商
  5. 处理流式/非流式响应
- **内部函数**:
  - `handleAggregatorRequest(params)` - 处理聚合器请求
  - `handleAggregatorStreamResponse(params)` - 处理聚合器流式响应
  - `handleStreamResponse(params)` - 处理直接提供商流式响应

#### `/functions/sync-models`
- **文件**: `/supabase/functions/sync-models/index.ts`
- **方法**: POST
- **功能**: 同步模型配置
- **权限**: 仅管理员

### API Routes

#### `/api/auth/callback`
- **文件**: `/app/auth/callback/route.ts`
- **方法**: GET
- **功能**: OAuth 回调处理

### Admin Pages Functions

#### 管理员 API 密钥页面
- **文件**: `/app/(admin)/admin/api-keys/page.tsx`
- **主要函数**:
  - `loadData()` - 加载 API 密钥和提供商
  - `handleAddKey()` - 添加新密钥
  - `handleDeleteKey(id: string)` - 删除密钥
  - `handleSyncModels(apiKeyId: string)` - 同步聚合器模型

#### 管理员模型页面
- **文件**: `/app/(admin)/admin/models/page.tsx`
- **主要函数**:
  - `loadModels()` - 加载直接和聚合器模型
  - `handleSaveModel()` - 保存模型配置
  - `toggleModelActive(model: ModelConfig)` - 切换模型状态
  - `handleSyncModels()` - 同步所有模型

#### 管理员用户页面
- **文件**: `/app/(admin)/admin/users/page.tsx`
- **主要函数**:
  - `loadUsers()` - 加载用户列表
  - `updateUserTier(userId: string, tier: string)` - 更新用户层级
  - `updateUserQuota(userId: string, quota: number)` - 更新用户配额

---

## 关键数据流

### 聊天请求流程
```
用户输入 → ModelSelector (选择模型) 
→ ChatContainer (发送消息) 
→ Edge Function v1-chat (路由请求)
→ get_model_provider_config_v2 (获取配置)
→ 聚合器/直接提供商 API
→ 流式响应 → 更新 UI
```

### 模型同步流程
```
管理员点击同步 → ModelSyncService.syncAggregatorModels()
→ AggregatorProviderFactory.create()
→ provider.fetchModels()
→ 删除旧模型 → 插入新模型
→ 更新 UI 显示
```

### 用户认证流程
```
用户登录 → Supabase Auth 
→ handle_new_user() 触发器
→ 创建 users/user_quotas/user_tiers 记录
→ 跳转到聊天界面
```

---

## 重要常量和配置

### 默认值
- 初始用户配额: 10,000 tokens
- 默认用户层级: 'free'
- API 密钥连续错误阈值: 5 次
- 模型健康状态阈值: 3 次失败 → 'degraded', 10 次 → 'unavailable'

### 提供商类型
- 直接提供商: 'openai', 'anthropic', 'google', 'bedrock'
- 聚合器: 'aihubmix' (更多待添加)

### 用户层级
- 'free': 基础功能
- 'pro': 高级模型访问
- 'max': 所有功能

---

## 快速查找索引

### 按功能分类

#### 认证相关
- `handle_new_user()` - 新用户注册处理
- `is_admin()`, `is_current_user_admin()` - 管理员验证
- `VaultClient.encrypt/decrypt()` - API 密钥加密

#### 模型管理
- `get_all_available_models()` - 获取所有可用模型
- `get_model_provider_config_v2()` - 获取模型配置
- `ModelSyncService.syncAggregatorModels()` - 同步聚合器模型
- `ModelSelector.loadModelsAndUserTier()` - 加载模型列表

#### API 密钥管理
- `get_available_api_key()` - 获取可用密钥（轮询）
- `record_api_key_error/success()` - 记录使用情况

#### 聊天功能
- `/functions/v1-chat` - 主聊天端点
- `ChatContainer.sendMessage()` - 发送消息
- `handleStreamResponse()` - 处理流式响应

#### 配额管理
- `check_and_update_user_quota()` - 检查并扣除配额
- `update_user_usage()` - 更新使用统计

#### 对话管理
- `search_conversations()` - 搜索对话
- `generate_conversation_title()` - 生成标题
- `assemble_conversation_messages()` - 组装消息历史

---

*此索引包含截至 2024-01-23 的所有主要函数。随着项目发展，请保持更新。*