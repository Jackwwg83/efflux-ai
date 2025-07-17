# 应用数据库迁移

## 步骤 1: 执行数据库迁移

1. 打开 Supabase SQL Editor:
   https://app.supabase.com/project/lzvwduadnunbtxqaqhkg/sql/new

2. 复制 `supabase/migrations/20250117_api_gateway_enhancement.sql` 文件的全部内容

3. 粘贴到 SQL Editor 中

4. 点击 "Run" 执行

## 步骤 2: 部署新的 Edge Function

在 Supabase Dashboard 中：

1. 进入 Functions 页面: https://app.supabase.com/project/lzvwduadnunbtxqaqhkg/functions

2. 创建新函数，名称: `v1-chat`

3. 复制 `supabase/functions/v1-chat/index.ts` 的内容

4. 粘贴并部署

## 步骤 3: 更新前端代码

代码已经准备好了新版本：

1. `lib/ai/gateway-client.ts` - 新的 AI Gateway 客户端
2. `components/chat/chat-container-v2.tsx` - 更新的聊天界面，支持配额显示
3. `app/(admin)/admin/api-keys/page-v2.tsx` - 增强的 API Key 管理界面

## 步骤 4: 切换到新版本

### 更新聊天页面
编辑 `app/(dashboard)/chat/page.tsx`，将导入改为：
```tsx
import { ChatContainer } from '@/components/chat/chat-container-v2'
```

### 更新 API Keys 管理页面
1. 删除旧文件: `app/(admin)/admin/api-keys/page.tsx`
2. 重命名: `page-v2.tsx` → `page.tsx`

## 步骤 5: 提交并部署

```bash
git add .
git commit -m "Implement API Gateway with load balancing and quota management"
git push
```

## 新功能说明

### 1. API Gateway
- 所有 AI 请求通过我们的服务转发
- 自动选择可用的 API Key（负载均衡）
- 错误自动切换到备用 Key

### 2. 配额管理
- 实时显示用户使用量
- 自动阻止超额请求
- 每日自动重置（需要配置定时任务）

### 3. API Key 池
- 支持多个 Key 轮换使用
- 自动监控 Key 健康状态
- 连续错误自动禁用

### 4. 使用统计
- 详细的请求日志
- Token 使用追踪
- 成本计算

## 注意事项

1. **添加 API Keys**：部署后需要在管理面板添加至少一个 API Key

2. **配置定时任务**（可选）：
   ```sql
   -- 在 Supabase SQL Editor 执行
   SELECT cron.schedule(
     'reset-daily-quotas',
     '0 0 * * *',
     $$UPDATE user_quotas SET tokens_used_today = 0, requests_today = 0$$
   );
   ```

3. **监控**：定期检查 API Key 状态和错误日志