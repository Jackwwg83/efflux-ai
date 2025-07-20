# 上下文窗口管理策略设计

## 1. 核心原则

### 1.1 Token 计算
- **实时计算**：每条消息发送前后精确计算 token 数
- **预估机制**：用户输入时实时预估 token 使用量
- **多语言支持**：英文约 4 字符/token，中文约 2 字符/token

### 1.2 上下文保留策略
优先级从高到低：
1. **系统消息**（System Message）- 始终保留
2. **最新的用户输入** - 必须保留
3. **最近的 N 轮对话** - 保持连贯性
4. **重要标记的消息** - 用户可标记重要消息
5. **较早的对话** - 可被截断或总结

## 2. 截断策略

### 2.1 渐进式警告
- **50% 使用**：显示进度条，无警告
- **70% 使用**：进度条变黄，提示信息
- **85% 使用**：进度条变橙，警告即将达到限制
- **95% 使用**：进度条变红，强制截断旧消息

### 2.2 截断算法
```typescript
interface TruncationStrategy {
  // 保留最近 N 轮完整对话
  keepRecentRounds: number;
  
  // 保留系统消息
  keepSystemMessage: boolean;
  
  // 保留标记的重要消息
  keepPinnedMessages: boolean;
  
  // 是否总结被截断的内容
  summarizeTruncated: boolean;
}

// 默认策略
const defaultStrategy: TruncationStrategy = {
  keepRecentRounds: 10,      // 保留最近 10 轮对话
  keepSystemMessage: true,    // 始终保留系统消息
  keepPinnedMessages: true,   // 保留用户标记的消息
  summarizeTruncated: false   // 暂不实现自动总结
};
```

### 2.3 模型切换处理
当用户切换模型时：
1. **重新计算**上下文使用情况
2. **如果超限**：
   - 提示用户新模型的上下文窗口较小
   - 询问是否继续（会截断部分历史）
   - 或建议切换到上下文更大的模型

## 3. 用户界面设计

### 3.1 上下文使用指示器
```
[====||||||||||||||||----] 15.2k / 20k tokens (76%)
                            ↑ 实时更新
```

### 3.2 详细信息悬浮提示
鼠标悬停时显示：
- 系统消息：500 tokens
- 对话历史：14,200 tokens  
- 当前输入：约 500 tokens
- 剩余空间：4,800 tokens

### 3.3 消息级别 Token 显示
每条消息可选显示：
- 输入 tokens
- 输出 tokens
- 累计使用

## 4. 高级功能

### 4.1 会话分支
当上下文即将满时，提供选项：
- **新建分支**：基于当前会话创建新分支
- **导出历史**：将当前会话导出后清空
- **智能压缩**：移除冗余信息（未来功能）

### 4.2 上下文预设
用户可保存常用的系统提示词：
- 编程助手
- 写作助手
- 翻译助手
等预设模板

### 4.3 Token 预算管理
- 设置每个会话的 token 预算
- 接近预算时警告
- 统计 token 使用趋势

## 5. 实现优先级

### Phase 1（MVP）
1. ✅ 基础 token 计算和显示
2. ✅ 简单的截断策略（保留最近 N 条）
3. ✅ 上下文使用进度条
4. ✅ 模型切换时的重新计算

### Phase 2（增强）
1. 消息置顶/标记功能
2. 会话搜索和过滤
3. 导出功能
4. 更智能的截断算法

### Phase 3（高级）
1. 自动总结被截断的内容
2. 会话分支管理
3. Token 使用分析
4. 上下文压缩算法

## 6. API 设计

### 6.1 前端 API
```typescript
// 获取当前上下文使用情况
getContextUsage(conversationId: string, model: string): ContextUsage

// 预估消息 token 数
estimateTokens(message: string, model: string): number

// 获取截断后的消息列表
getTruncatedMessages(
  messages: Message[], 
  model: string, 
  strategy: TruncationStrategy
): Message[]
```

### 6.2 后端 RPC
```sql
-- 获取会话上下文使用情况
get_conversation_context_usage(conversation_id, model)

-- 智能截断消息
truncate_conversation_messages(conversation_id, model, keep_recent)
```