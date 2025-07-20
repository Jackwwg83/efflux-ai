# 会话管理系统实施指南

## 概述

本指南详细说明如何实现完整的会话管理系统，包括 System Prompt 设计、聊天记录组装和上下文窗口管理。

## 1. 前端实现步骤

### 1.1 创建 Token 计算工具
```typescript
// lib/utils/token-counter.ts
export class TokenCounter {
  // 简单的 token 估算
  static estimate(text: string): number {
    if (!text) return 0;
    
    // 检测中文字符
    const chineseChars = (text.match(/[\u4e00-\u9fa5]/g) || []).length;
    const totalChars = text.length;
    const englishChars = totalChars - chineseChars;
    
    // 中文约 2 字符/token，英文约 4 字符/token
    return Math.ceil(chineseChars / 2 + englishChars / 4);
  }
  
  // 批量计算消息 tokens
  static calculateMessages(messages: Message[]): number {
    return messages.reduce((total, msg) => {
      // 角色标记也占用 tokens
      const roleTokens = 4; // 约 "role: " 
      const contentTokens = this.estimate(msg.content);
      return total + roleTokens + contentTokens;
    }, 0);
  }
  
  // 获取模型的 token 限制
  static getModelLimit(model: string): number {
    const limits: Record<string, number> = {
      'gpt-3.5-turbo': 16385,
      'gpt-4-turbo': 128000,
      'gpt-4o': 128000,
      'claude-3-opus': 200000,
      'claude-3-sonnet': 200000,
      'claude-3-haiku': 200000,
      'gemini-2.0-flash': 1048576,
      'gemini-2.5-pro': 1048576,
      // ... 其他模型
    };
    
    return limits[model] || 4096; // 默认值
  }
}
```

### 1.2 创建上下文指示器组件
```typescript
// components/chat/context-indicator.tsx
'use client'

import { useEffect, useState } from 'react'
import { Progress } from '@/components/ui/progress'
import { AlertCircle, Info } from 'lucide-react'
import { TokenCounter } from '@/lib/utils/token-counter'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'

interface ContextIndicatorProps {
  messages: Message[]
  currentInput: string
  model: string
}

export function ContextIndicator({ 
  messages, 
  currentInput, 
  model 
}: ContextIndicatorProps) {
  const [usage, setUsage] = useState({
    current: 0,
    max: 0,
    percentage: 0,
    status: 'normal' as 'normal' | 'warning' | 'critical'
  })

  useEffect(() => {
    const messageTokens = TokenCounter.calculateMessages(messages)
    const inputTokens = TokenCounter.estimate(currentInput)
    const totalTokens = messageTokens + inputTokens + 500 // 预留响应空间
    const maxTokens = TokenCounter.getModelLimit(model)
    const percentage = (totalTokens / maxTokens) * 100

    setUsage({
      current: totalTokens,
      max: maxTokens,
      percentage: Math.min(percentage, 100),
      status: 
        percentage > 85 ? 'critical' : 
        percentage > 70 ? 'warning' : 
        'normal'
    })
  }, [messages, currentInput, model])

  const getColor = () => {
    switch (usage.status) {
      case 'critical': return 'bg-red-500'
      case 'warning': return 'bg-yellow-500'
      default: return 'bg-green-500'
    }
  }

  return (
    <div className="flex items-center gap-2 px-4 py-2 border-t">
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="flex items-center gap-2 flex-1">
              <Progress 
                value={usage.percentage} 
                className="h-2"
                indicatorClassName={getColor()}
              />
              <span className="text-xs text-muted-foreground whitespace-nowrap">
                {(usage.current / 1000).toFixed(1)}k / {(usage.max / 1000).toFixed(0)}k
              </span>
              {usage.status !== 'normal' && (
                <AlertCircle className={`h-4 w-4 ${
                  usage.status === 'critical' ? 'text-red-500' : 'text-yellow-500'
                }`} />
              )}
            </div>
          </TooltipTrigger>
          <TooltipContent>
            <div className="space-y-1 text-sm">
              <p>上下文使用情况</p>
              <div className="text-xs space-y-1">
                <p>历史消息: {(TokenCounter.calculateMessages(messages) / 1000).toFixed(1)}k tokens</p>
                <p>当前输入: ~{TokenCounter.estimate(currentInput)} tokens</p>
                <p>剩余空间: {((usage.max - usage.current) / 1000).toFixed(1)}k tokens</p>
                {usage.status === 'warning' && (
                  <p className="text-yellow-500">接近上限，旧消息可能被截断</p>
                )}
                {usage.status === 'critical' && (
                  <p className="text-red-500">已达上限，将自动截断历史消息</p>
                )}
              </div>
            </div>
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    </div>
  )
}
```

### 1.3 创建会话列表组件
```typescript
// components/chat/conversation-list.tsx
'use client'

import { useState, useEffect } from 'react'
import { formatDistanceToNow } from 'date-fns'
import { zhCN } from 'date-fns/locale'
import { 
  Search, 
  Plus, 
  Star, 
  MoreVertical,
  MessageSquare,
  Trash2,
  Edit2,
  Download
} from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useConversationStore } from '@/lib/stores/conversation'
import { cn } from '@/lib/utils'

export function ConversationList() {
  const [searchQuery, setSearchQuery] = useState('')
  const {
    conversations,
    currentConversationId,
    createConversation,
    deleteConversation,
    updateConversation,
    setCurrentConversation,
    searchConversations
  } = useConversationStore()

  // 分组会话
  const groupedConversations = groupConversations(conversations)
  
  // 搜索
  useEffect(() => {
    if (searchQuery) {
      searchConversations(searchQuery)
    }
  }, [searchQuery, searchConversations])

  return (
    <div className="w-64 border-r flex flex-col h-full">
      {/* 搜索和新建 */}
      <div className="p-4 space-y-2">
        <Button 
          onClick={createConversation}
          className="w-full"
        >
          <Plus className="h-4 w-4 mr-2" />
          新建对话
        </Button>
        
        <div className="relative">
          <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="搜索对话..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-8"
          />
        </div>
      </div>

      {/* 会话列表 */}
      <ScrollArea className="flex-1">
        <div className="px-2 pb-2">
          {Object.entries(groupedConversations).map(([group, convs]) => (
            <div key={group} className="mb-4">
              <h3 className="px-2 py-1 text-xs font-semibold text-muted-foreground">
                {group}
              </h3>
              {convs.map((conv) => (
                <ConversationItem
                  key={conv.id}
                  conversation={conv}
                  isActive={conv.id === currentConversationId}
                  onSelect={() => setCurrentConversation(conv.id)}
                  onDelete={() => deleteConversation(conv.id)}
                  onRename={(title) => updateConversation(conv.id, { title })}
                  onToggleFavorite={() => 
                    updateConversation(conv.id, { is_favorite: !conv.is_favorite })
                  }
                />
              ))}
            </div>
          ))}
        </div>
      </ScrollArea>
    </div>
  )
}

// 会话分组逻辑
function groupConversations(conversations: Conversation[]) {
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)
  const weekAgo = new Date(today)
  weekAgo.setDate(weekAgo.getDate() - 7)

  const groups: Record<string, Conversation[]> = {
    '收藏': [],
    '今天': [],
    '昨天': [],
    '过去7天': [],
    '更早': []
  }

  conversations.forEach(conv => {
    const updatedAt = new Date(conv.updated_at)
    
    if (conv.is_favorite) {
      groups['收藏'].push(conv)
    } else if (updatedAt >= today) {
      groups['今天'].push(conv)
    } else if (updatedAt >= yesterday) {
      groups['昨天'].push(conv)
    } else if (updatedAt >= weekAgo) {
      groups['过去7天'].push(conv)
    } else {
      groups['更早'].push(conv)
    }
  })

  // 移除空分组
  return Object.fromEntries(
    Object.entries(groups).filter(([_, convs]) => convs.length > 0)
  )
}

// 会话项组件
function ConversationItem({ 
  conversation, 
  isActive, 
  onSelect, 
  onDelete,
  onRename,
  onToggleFavorite
}: ConversationItemProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [title, setTitle] = useState(conversation.title)

  const handleRename = () => {
    if (title.trim() && title !== conversation.title) {
      onRename(title)
    }
    setIsEditing(false)
  }

  return (
    <div
      className={cn(
        "group flex items-center px-2 py-1.5 rounded-md cursor-pointer",
        isActive ? "bg-accent" : "hover:bg-accent/50"
      )}
      onClick={onSelect}
    >
      <MessageSquare className="h-4 w-4 mr-2 flex-shrink-0" />
      
      <div className="flex-1 min-w-0">
        {isEditing ? (
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={handleRename}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleRename()
              if (e.key === 'Escape') setIsEditing(false)
            }}
            className="h-6 px-1"
            autoFocus
            onClick={(e) => e.stopPropagation()}
          />
        ) : (
          <>
            <p className="text-sm truncate">{conversation.title}</p>
            <p className="text-xs text-muted-foreground truncate">
              {conversation.last_message_preview}
            </p>
          </>
        )}
      </div>

      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100">
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={(e) => {
            e.stopPropagation()
            onToggleFavorite()
          }}
        >
          <Star className={cn(
            "h-3 w-3",
            conversation.is_favorite && "fill-current"
          )} />
        </Button>
        
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={(e) => e.stopPropagation()}
            >
              <MoreVertical className="h-3 w-3" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => setIsEditing(true)}>
              <Edit2 className="h-4 w-4 mr-2" />
              重命名
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => exportConversation(conversation.id)}>
              <Download className="h-4 w-4 mr-2" />
              导出
            </DropdownMenuItem>
            <DropdownMenuItem 
              onClick={onDelete}
              className="text-red-600"
            >
              <Trash2 className="h-4 w-4 mr-2" />
              删除
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}
```

## 2. 后端集成

### 2.1 更新 Edge Function
```typescript
// supabase/functions/v1-chat/index.ts
// 在处理聊天请求时，使用新的消息组装函数

// 获取组装好的消息
const { data: assembledData } = await supabase.rpc(
  'assemble_conversation_messages',
  {
    p_conversation_id: conversationId,
    p_model: model,
    p_max_tokens: null
  }
);

const messages = assembledData[0].messages;
const truncated = assembledData[0].truncated;

// 如果消息被截断，在响应中包含提示
if (truncated) {
  // 在流式响应最后添加提示
  controller.enqueue(encoder.encode(
    `data: ${JSON.stringify({ 
      type: 'system', 
      message: '注意：由于上下文限制，部分历史消息已被截断' 
    })}\n\n`
  ));
}
```

### 2.2 创建消息置顶功能
```typescript
// lib/api/messages.ts
export async function togglePinMessage(
  messageId: string,
  isPinned: boolean
) {
  const { error } = await supabase
    .from('messages')
    .update({ is_pinned: !isPinned })
    .eq('id', messageId)
    
  if (error) throw error
}
```

## 3. 性能优化

### 3.1 虚拟滚动
```typescript
// 使用 @tanstack/react-virtual 优化长会话列表
import { useVirtualizer } from '@tanstack/react-virtual'

export function VirtualConversationList({ conversations }) {
  const parentRef = useRef<HTMLDivElement>(null)
  
  const virtualizer = useVirtualizer({
    count: conversations.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 60, // 估计每个会话项的高度
    overscan: 5
  })
  
  return (
    <div ref={parentRef} className="h-full overflow-auto">
      <div
        style={{
          height: `${virtualizer.getTotalSize()}px`,
          width: '100%',
          position: 'relative',
        }}
      >
        {virtualizer.getVirtualItems().map((virtualItem) => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${virtualItem.size}px`,
              transform: `translateY(${virtualItem.start}px)`,
            }}
          >
            <ConversationItem
              conversation={conversations[virtualItem.index]}
            />
          </div>
        ))}
      </div>
    </div>
  )
}
```

### 3.2 缓存策略
```typescript
// lib/cache/conversation-cache.ts
class ConversationCache {
  private cache = new Map<string, CachedConversation>()
  private maxSize = 10 // 最多缓存10个会话
  
  get(id: string): CachedConversation | null {
    const item = this.cache.get(id)
    if (item && Date.now() - item.timestamp < 300000) { // 5分钟有效期
      return item
    }
    this.cache.delete(id)
    return null
  }
  
  set(id: string, data: Conversation) {
    // LRU 策略
    if (this.cache.size >= this.maxSize) {
      const firstKey = this.cache.keys().next().value
      this.cache.delete(firstKey)
    }
    
    this.cache.set(id, {
      ...data,
      timestamp: Date.now()
    })
  }
}
```

## 4. 测试建议

### 4.1 单元测试
```typescript
// __tests__/token-counter.test.ts
describe('TokenCounter', () => {
  it('should estimate English text correctly', () => {
    const text = 'Hello world'
    const tokens = TokenCounter.estimate(text)
    expect(tokens).toBeCloseTo(3, 0) // ~11 chars / 4 = 2.75
  })
  
  it('should estimate Chinese text correctly', () => {
    const text = '你好世界'
    const tokens = TokenCounter.estimate(text)
    expect(tokens).toBe(2) // 4 chars / 2 = 2
  })
})
```

### 4.2 集成测试
- 测试消息截断是否正确保留系统消息
- 测试模型切换时的上下文重算
- 测试搜索功能的准确性
- 测试并发更新的处理

## 5. 部署检查清单

- [ ] 执行所有数据库迁移脚本
- [ ] 更新 Edge Functions
- [ ] 配置环境变量
- [ ] 测试各个模型的上下文限制
- [ ] 验证 RLS 策略
- [ ] 监控 token 使用情况
- [ ] 设置备份策略