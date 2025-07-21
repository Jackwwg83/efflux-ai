'use client'

import { useState, useEffect, useRef } from 'react'
import { MessageList } from './message-list'
import { MessageInput } from './message-input'
import { ModelSelector } from './model-selector'
import { createClient } from '@/lib/supabase/client'
import { useConversationStore } from '@/lib/stores/conversation'
import { useToast } from '@/hooks/use-toast'
import { Database } from '@/types/database'

type Message = Database['public']['Tables']['messages']['Row']

interface ChatContainerProps {
  onNewChat: () => void
}

export function ChatContainer({ onNewChat }: ChatContainerProps) {
  const supabase = createClient()
  const { toast } = useToast()
  const [isLoading, setIsLoading] = useState(false)
  const [streamingMessageId, setStreamingMessageId] = useState<string | null>(null)
  const abortControllerRef = useRef<AbortController | null>(null)
  
  const {
    currentConversation,
    messages,
    setMessages,
    addMessage,
    updateMessage,
  } = useConversationStore()

  useEffect(() => {
    if (currentConversation) {
      loadMessages()
    }
  }, [currentConversation])

  const loadMessages = async () => {
    if (!currentConversation) return

    try {
      const { data: messages, error } = await supabase
        .from('messages')
        .select('*')
        .eq('conversation_id', currentConversation.id)
        .order('created_at', { ascending: true })

      if (error) throw error

      setMessages(messages || [])
    } catch (error) {
      console.error('Error loading messages:', error)
      toast({
        title: 'Error',
        description: 'Failed to load messages',
        variant: 'destructive',
      })
    }
  }

  const sendMessage = async (content: string) => {
    if (!currentConversation || isLoading) return

    setIsLoading(true)
    abortControllerRef.current = new AbortController()

    try {
      // Get auth token
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')

      // Create temporary message ID for optimistic update
      const tempMessageId = crypto.randomUUID()
      const tempAssistantId = crypto.randomUUID()

      // Add user message optimistically
      const userMessage: Message = {
        id: tempMessageId,
        conversation_id: currentConversation.id,
        role: 'user',
        content,
        model: currentConversation.model,
        provider: currentConversation.provider,
        prompt_tokens: null,
        completion_tokens: null,
        total_tokens: null,
        created_at: new Date().toISOString(),
        metadata: null,
        is_pinned: null,
        is_summarized: null,
        summary_of: null,
      }
      addMessage(userMessage)

      // Add empty assistant message for streaming
      const assistantMessage: Message = {
        id: tempAssistantId,
        conversation_id: currentConversation.id,
        role: 'assistant',
        content: '',
        model: currentConversation.model,
        provider: currentConversation.provider,
        prompt_tokens: null,
        completion_tokens: null,
        total_tokens: null,
        created_at: new Date().toISOString(),
        metadata: null,
        is_pinned: null,
        is_summarized: null,
        summary_of: null,
      }
      addMessage(assistantMessage)
      setStreamingMessageId(tempAssistantId)

      // Call Edge Function
      const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          message: content,
          model: currentConversation.model,
          conversationId: currentConversation.id,
          stream: true,
        }),
        signal: abortControllerRef.current.signal,
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to send message')
      }

      // Handle streaming response
      const reader = response.body?.getReader()
      if (!reader) throw new Error('No response body')

      const decoder = new TextDecoder()
      let assistantContent = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        const chunk = decoder.decode(value)
        const lines = chunk.split('\n').filter(line => line.trim())

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6))
              
              if (data.type === 'content') {
                assistantContent += data.content
                updateMessage(tempAssistantId, assistantContent)
              } else if (data.type === 'done') {
                // Update with final token usage
                if (data.usage) {
                  // Token usage is handled by the Edge Function
                }
              } else if (data.type === 'error') {
                throw new Error(data.error)
              }
            } catch (e) {
              console.error('Error parsing SSE data:', e)
            }
          }
        }
      }

      // Update conversation title if it's the first message
      if (messages.length === 0) {
        const title = content.slice(0, 50) + (content.length > 50 ? '...' : '')
        await supabase
          .from('conversations')
          .update({ title })
          .eq('id', currentConversation.id)
      }

    } catch (error: any) {
      console.error('Error sending message:', error)
      
      if (error.name !== 'AbortError') {
        toast({
          title: 'Error',
          description: error.message || 'Failed to send message',
          variant: 'destructive',
        })
      }
    } finally {
      setIsLoading(false)
      setStreamingMessageId(null)
      abortControllerRef.current = null
    }
  }

  const stopStreaming = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort()
      setIsLoading(false)
      setStreamingMessageId(null)
    }
  }

  return (
    <div className="flex flex-col h-full">
      <div className="border-b px-4 py-3 flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <h2 className="text-lg font-semibold">
            {currentConversation?.title || 'New Chat'}
          </h2>
          <ModelSelector />
        </div>
        <button
          onClick={onNewChat}
          className="text-sm text-muted-foreground hover:text-foreground"
        >
          New Chat
        </button>
      </div>
      
      <MessageList
        messages={messages}
        streamingMessageId={streamingMessageId}
      />
      
      <MessageInput
        onSendMessage={sendMessage}
        isLoading={isLoading}
        onStopStreaming={stopStreaming}
      />
    </div>
  )
}