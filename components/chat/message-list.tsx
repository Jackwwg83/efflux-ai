'use client'

import { useEffect, useRef } from 'react'
import { MessageItem } from './message-item'
import { Database } from '@/types/database'

type Message = Database['public']['Tables']['messages']['Row']

interface MessageListProps {
  messages: Message[]
  streamingMessageId?: string | null
}

export function MessageList({ messages, streamingMessageId }: MessageListProps) {
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  if (messages.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="text-center max-w-md">
          <h3 className="text-lg font-medium mb-2">Start a conversation</h3>
          <p className="text-muted-foreground">
            Choose a model and send a message to begin chatting with AI
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="flex-1 overflow-y-auto px-4 py-6">
      <div className="max-w-3xl mx-auto space-y-6">
        {messages.map((message) => (
          <MessageItem
            key={message.id}
            message={message}
            isStreaming={message.id === streamingMessageId}
          />
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}