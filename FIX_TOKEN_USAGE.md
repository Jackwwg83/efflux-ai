# 修复 Token 使用量追踪问题

## 问题描述

1. **流式响应不自动结束**：Edge Function 没有发送 `[DONE]` 信号，导致客户端一直等待流结束。
2. **Daily Usage token 计数不更新**：`update_user_usage` 函数在每日重置时会将 tokens 清零，导致新的使用量没有正确累加。

## 已完成的修复

### 1. 修复流式响应结束信号（已完成）

在 `supabase/functions/v1-chat/index.ts` 文件的第 377 行添加了发送 `[DONE]` 信号的代码：

```typescript
// Send [DONE] signal to properly end the stream
controller.enqueue(encoder.encode('data: [DONE]\n\n'))
```

### 2. 修复 Token 使用量追踪

创建了新的数据库迁移文件 `supabase/migrations/20240203_fix_token_usage_tracking.sql`，包含：

- 修复了 `update_user_usage` 函数的逻辑
- 添加了新的 `get_user_quota_status` 函数，自动处理每日/每月重置
- 更新了客户端代码，使用新的 RPC 函数

## 部署步骤

### 1. 部署 Edge Function

```bash
cd /home/ubuntu/jack/projects/efflux/efflux-ai
npx supabase functions deploy v1-chat
```

### 2. 应用数据库迁移

在 Supabase Dashboard 中执行以下 SQL：

```sql
-- 复制 supabase/migrations/20240203_fix_token_usage_tracking.sql 的内容并执行
```

或使用 CLI（需要数据库密码）：

```bash
npx supabase db push
```

### 3. 测试验证

1. 发送一条消息，检查是否能正常结束流式响应
2. 检查 Daily Usage 是否正确更新
3. 等到第二天，验证每日配额是否正确重置

## 技术细节

### 问题原因

1. **流式响应问题**：客户端的 `streamChat` 函数期望接收 `[DONE]` 信号来结束流，但 Edge Function 只发送了 usage 数据。

2. **Token 计数问题**：原来的 `update_user_usage` 函数在检测到需要重置时，会先将 `tokens_used_today` 设为 0，然后再加上新的使用量。但是 SQL 更新是原子操作，导致实际上只是将值设为了 0。

### 解决方案

1. **流式响应**：在发送 usage 数据后，立即发送 `[DONE]` 信号。

2. **Token 计数**：
   - 分离重置逻辑和更新逻辑
   - 如果需要重置，直接将今日使用量设为传入的值
   - 如果不需要重置，则累加使用量
   - 创建专门的查询函数，在返回数据前自动处理重置逻辑