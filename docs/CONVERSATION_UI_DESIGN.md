# 会话管理 UI 设计方案

## 1. 整体布局

```
┌─────────────────┬──────────────────────────────────────┐
│                 │         顶部栏 (模型选择器等)          │
│   会话列表       ├──────────────────────────────────────┤
│   (左侧边栏)     │                                      │
│                 │         聊天区域                      │
│   - 搜索框       │                                      │
│   - 新建按钮     │                                      │
│   - 会话分组     │                                      │
│     - 收藏       │                                      │
│     - 今天       │                                      │
│     - 昨天       │                                      │
│     - 更早       │                                      │
│                 │                                      │
│                 ├──────────────────────────────────────┤
│                 │  [上下文: ████████░░ 76%] 输入框     │
└─────────────────┴──────────────────────────────────────┘
```

## 2. 组件设计

### 2.1 会话列表组件 (ConversationList)
```typescript
interface ConversationListProps {
  conversations: Conversation[]
  currentConversationId: string
  onSelectConversation: (id: string) => void
  onNewConversation: () => void
  onDeleteConversation: (id: string) => void
  onToggleFavorite: (id: string) => void
  onRenameConversation: (id: string, title: string) => void
}

// 功能特性
- 搜索框：实时搜索会话标题和内容
- 分组显示：收藏、今天、昨天、本周、更早
- 右键菜单：重命名、删除、导出、复制链接
- 拖拽排序：收藏会话可拖拽排序
```

### 2.2 上下文指示器 (ContextIndicator)
```typescript
interface ContextIndicatorProps {
  currentTokens: number
  maxTokens: number
  warningThreshold: number  // 默认 0.7
  criticalThreshold: number // 默认 0.85
}

// 显示样式
- 正常 (< 70%)：绿色进度条
- 警告 (70-85%)：黄色进度条 + 提示
- 危险 (> 85%)：红色进度条 + 警告
- 点击展开：显示详细 token 分布
```

### 2.3 会话项组件 (ConversationItem)
```typescript
interface ConversationItemProps {
  conversation: {
    id: string
    title: string
    lastMessage: string
    updatedAt: Date
    isFavorite: boolean
    messageCount: number
    totalTokens: number
  }
  isActive: boolean
  onSelect: () => void
  onAction: (action: string) => void
}

// 显示内容
- 标题（可编辑）
- 最后一条消息预览
- 时间戳
- 收藏星标
- 悬停显示操作按钮
```

## 3. 交互设计

### 3.1 快捷键
- `Cmd/Ctrl + N`：新建会话
- `Cmd/Ctrl + K`：搜索会话
- `Cmd/Ctrl + D`：删除当前会话
- `Cmd/Ctrl + E`：导出当前会话
- `Cmd/Ctrl + R`：重命名当前会话
- `Cmd/Ctrl + 数字`：快速切换到第 N 个会话

### 3.2 拖拽功能
- 拖拽会话到收藏区
- 收藏区内拖拽排序
- 拖拽到垃圾桶删除

### 3.3 批量操作
- 按住 Shift 多选
- 批量删除
- 批量导出

## 4. 响应式设计

### 4.1 移动端适配
- 侧边栏可收起
- 滑动手势切换会话
- 底部标签栏导航

### 4.2 断点设计
- < 768px：隐藏侧边栏，使用底部导航
- 768px - 1024px：可收起的侧边栏
- > 1024px：固定侧边栏

## 5. 状态管理

### 5.1 Zustand Store 设计
```typescript
interface ConversationStore {
  // 状态
  conversations: Conversation[]
  currentConversationId: string | null
  searchQuery: string
  isLoading: boolean
  
  // 会话操作
  createConversation: () => Promise<void>
  deleteConversation: (id: string) => Promise<void>
  updateConversation: (id: string, data: Partial<Conversation>) => Promise<void>
  toggleFavorite: (id: string) => Promise<void>
  
  // 搜索和过滤
  searchConversations: (query: string) => void
  getFilteredConversations: () => Conversation[]
  
  // 上下文管理
  getContextUsage: (conversationId: string) => Promise<ContextUsage>
  truncateMessages: (conversationId: string) => Promise<void>
}
```

### 5.2 实时更新
- Supabase Realtime 订阅会话更新
- 乐观更新提升响应速度
- 离线支持（使用 localStorage 缓存）

## 6. 性能优化

### 6.1 虚拟滚动
- 会话列表超过 50 个时启用虚拟滚动
- 使用 react-window 或 @tanstack/react-virtual

### 6.2 懒加载
- 消息历史按需加载
- 图片和附件延迟加载

### 6.3 缓存策略
- 最近 10 个会话缓存在内存
- IndexedDB 存储离线数据
- Service Worker 缓存静态资源

## 7. 实现步骤

### 第一阶段：基础功能
1. 会话列表组件
2. 新建/删除会话
3. 基础搜索功能
4. 上下文使用显示

### 第二阶段：增强功能  
1. 收藏和分组
2. 拖拽排序
3. 导出功能
4. 快捷键支持

### 第三阶段：高级功能
1. 批量操作
2. 高级搜索（正则、标签）
3. 会话模板
4. 协作功能（分享会话）