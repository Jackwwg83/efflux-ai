'use client'

import { useEffect, useState, useMemo } from 'react'
// Progress component removed - using custom implementation
import { AlertCircle, Info, ChevronDown, ChevronUp } from 'lucide-react'
import { TokenCounter } from '@/lib/utils/token-counter'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'

interface ContextIndicatorProps {
  messages: any[] // TODO: 使用正确的 Message 类型
  currentInput: string
  model: string
  className?: string
}

interface TokenBreakdown {
  system: number
  pinned: number
  conversation: number
  currentInput: number
  total: number
  responseReserve: number
}

export function ContextIndicator({ 
  messages = [], 
  currentInput = '', 
  model,
  className
}: ContextIndicatorProps) {
  const [isOpen, setIsOpen] = useState(false)
  
  // 计算 token 使用情况
  const usage = useMemo(() => {
    const systemMessages = messages.filter(m => m.role === 'system')
    const pinnedMessages = messages.filter(m => m.metadata?.pinned)
    const regularMessages = messages.filter(m => 
      m.role !== 'system' && !m.metadata?.pinned
    )
    
    const breakdown: TokenBreakdown = {
      system: TokenCounter.calculateMessages(systemMessages),
      pinned: TokenCounter.calculateMessages(pinnedMessages),
      conversation: TokenCounter.calculateMessages(regularMessages),
      currentInput: TokenCounter.estimate(currentInput),
      total: 0,
      responseReserve: TokenCounter.estimateResponseTokens(model)
    }
    
    breakdown.total = 
      breakdown.system + 
      breakdown.pinned + 
      breakdown.conversation + 
      breakdown.currentInput +
      breakdown.responseReserve
    
    const maxTokens = TokenCounter.getModelLimit(model)
    const percentage = TokenCounter.calculateUsagePercentage(breakdown.total, model)
    const status = TokenCounter.getUsageStatus(percentage)
    const remaining = TokenCounter.getRemainingTokens(breakdown.total, model)
    
    return {
      breakdown,
      maxTokens,
      percentage,
      status,
      remaining
    }
  }, [messages, currentInput, model])
  
  // 获取状态颜色
  const getStatusColor = () => {
    switch (usage.status) {
      case 'critical': return 'text-red-500'
      case 'warning': return 'text-yellow-500'
      default: return 'text-green-500'
    }
  }
  
  const getProgressColor = () => {
    switch (usage.status) {
      case 'critical': return 'bg-red-500'
      case 'warning': return 'bg-yellow-500'
      default: return 'bg-green-500'
    }
  }
  
  // 获取状态提示信息
  const getStatusMessage = () => {
    if (usage.status === 'critical') {
      return '上下文即将满，旧消息将被自动截断'
    }
    if (usage.status === 'warning') {
      return '上下文使用较高，请注意消息长度'
    }
    return '上下文使用正常'
  }
  
  return (
    <div className={cn("border-t", className)}>
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <div className="flex items-center gap-2 px-4 py-2">
          {/* 进度条和基础信息 */}
          <div className="flex-1 flex items-center gap-3">
            <div className="relative h-2 flex-1 overflow-hidden rounded-full bg-secondary">
              <div 
                className={cn("h-full w-full flex-1 transition-all", getProgressColor())}
                style={{ transform: `translateX(-${100 - (usage.percentage || 0)}%)` }}
              />
            </div>
            
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <div className="flex items-center gap-2">
                    <span className={cn(
                      "text-sm font-medium",
                      getStatusColor()
                    )}>
                      {TokenCounter.formatTokenCount(usage.breakdown.total)} / {TokenCounter.formatTokenCount(usage.maxTokens)}
                    </span>
                    
                    {usage.status !== 'normal' && (
                      <AlertCircle className={cn("h-4 w-4", getStatusColor())} />
                    )}
                  </div>
                </TooltipTrigger>
                <TooltipContent>
                  <p className="font-medium">{getStatusMessage()}</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    剩余: {TokenCounter.formatTokenCount(usage.remaining)} tokens
                  </p>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          </div>
          
          {/* 展开/收起按钮 */}
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="h-7 px-2">
              {isOpen ? (
                <ChevronUp className="h-4 w-4" />
              ) : (
                <ChevronDown className="h-4 w-4" />
              )}
            </Button>
          </CollapsibleTrigger>
        </div>
        
        {/* 详细信息 */}
        <CollapsibleContent>
          <div className="px-4 pb-3 space-y-2">
            <div className="text-sm space-y-1">
              <TokenBreakdownItem
                label="系统提示"
                tokens={usage.breakdown.system}
                percentage={(usage.breakdown.system / usage.maxTokens) * 100}
              />
              
              {usage.breakdown.pinned > 0 && (
                <TokenBreakdownItem
                  label="置顶消息"
                  tokens={usage.breakdown.pinned}
                  percentage={(usage.breakdown.pinned / usage.maxTokens) * 100}
                />
              )}
              
              <TokenBreakdownItem
                label="对话历史"
                tokens={usage.breakdown.conversation}
                percentage={(usage.breakdown.conversation / usage.maxTokens) * 100}
              />
              
              {usage.breakdown.currentInput > 0 && (
                <TokenBreakdownItem
                  label="当前输入"
                  tokens={usage.breakdown.currentInput}
                  percentage={(usage.breakdown.currentInput / usage.maxTokens) * 100}
                />
              )}
              
              <TokenBreakdownItem
                label="响应预留"
                tokens={usage.breakdown.responseReserve}
                percentage={(usage.breakdown.responseReserve / usage.maxTokens) * 100}
                className="opacity-60"
              />
            </div>
            
            {/* 状态提示 */}
            {usage.status !== 'normal' && (
              <div className={cn(
                "text-xs rounded-md p-2",
                usage.status === 'critical' ? 'bg-red-50 text-red-700' : 'bg-yellow-50 text-yellow-700'
              )}>
                <p className="font-medium">{getStatusMessage()}</p>
                {usage.status === 'critical' && (
                  <p className="mt-1">
                    系统将保留最新的对话，较早的消息可能被移除。
                    考虑开启新对话以获得最佳体验。
                  </p>
                )}
              </div>
            )}
          </div>
        </CollapsibleContent>
      </Collapsible>
    </div>
  )
}

// Token 分项显示组件
function TokenBreakdownItem({ 
  label, 
  tokens, 
  percentage,
  className 
}: { 
  label: string
  tokens: number
  percentage: number
  className?: string
}) {
  return (
    <div className={cn("flex items-center justify-between", className)}>
      <span className="text-muted-foreground">{label}</span>
      <div className="flex items-center gap-2">
        <span className="font-mono text-xs">
          {TokenCounter.formatTokenCount(tokens)}
        </span>
        <span className="text-xs text-muted-foreground">
          ({percentage.toFixed(1)}%)
        </span>
      </div>
    </div>
  )
}