'use client'

import { User, Bot } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Database } from '@/types/database'

type Message = Database['public']['Tables']['messages']['Row']

interface MessageItemProps {
  message: Message
  isStreaming?: boolean
}

export function MessageItem({ message, isStreaming }: MessageItemProps) {
  const isUser = message.role === 'user'

  return (
    <div className={cn('flex gap-3', isUser ? 'justify-end' : 'justify-start')}>
      {!isUser && (
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
          <Bot className="w-5 h-5 text-primary" />
        </div>
      )}
      
      <div
        className={cn(
          'rounded-lg px-4 py-2 max-w-[80%]',
          isUser
            ? 'bg-primary text-primary-foreground'
            : 'bg-muted'
        )}
      >
        <div className="whitespace-pre-wrap break-words">
          {message.content}
          {isStreaming && <span className="animate-pulse">▊</span>}
        </div>
        
        {message.total_tokens && (
          <div className="text-xs opacity-70 mt-2">
            {message.total_tokens} tokens
          </div>
        )}
      </div>
      
      {isUser && (
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary flex items-center justify-center">
          <User className="w-5 h-5 text-primary-foreground" />
        </div>
      )}
    </div>
  )
}