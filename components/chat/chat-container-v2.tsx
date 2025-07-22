'use client'

import { useState, useEffect, useRef } from 'react'
import { MessageList } from './message-list'
import { MessageInput } from './message-input'
import { logger } from '@/lib/utils/logger'
import { ModelSelector } from './model-selector'
import { ContextIndicator } from './context-indicator'
import { PresetSelector } from './preset-selector'
import { createClient } from '@/lib/supabase/client'
import { useConversationStore } from '@/lib/stores/conversation'
import { useToast } from '@/hooks/use-toast'
import { Database } from '@/types/database'
import { AIGatewayClient } from '@/lib/ai/gateway-client'
import { Progress } from '@/components/ui/progress'
import { AlertCircle } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'

type Message = Database['public']['Tables']['messages']['Row']

interface QuotaStatus {
  tokens_used_today: number
  tokens_used_month: number
  requests_today: number
  requests_month: number
  cost_today: number
  cost_month: number
  tier: 'free' | 'pro' | 'max'
  daily_limit: number
}

interface ChatContainerProps {
  onNewChat: () => void
}

export function ChatContainer({ onNewChat }: ChatContainerProps) {
  const supabase = createClient()
  const { toast } = useToast()
  const [isLoading, setIsLoading] = useState(false)
  const [streamingMessageId, setStreamingMessageId] = useState<string | null>(null)
  const [quotaStatus, setQuotaStatus] = useState<QuotaStatus | null>(null)
  const [currentInput, setCurrentInput] = useState('')
  const abortControllerRef = useRef<AbortController | null>(null)
  const aiClient = useRef(new AIGatewayClient())
  
  const {
    currentConversation,
    messages,
    setMessages,
    addMessage,
    updateMessage,
    updateMessageTokens,
  } = useConversationStore()

  useEffect(() => {
    if (currentConversation) {
      loadMessages()
    }
    loadQuotaStatus()
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
      logger.error('Error loading messages', { error, conversationId: currentConversation?.id })
      toast({
        title: 'Error',
        description: 'Failed to load messages',
        variant: 'destructive',
      })
    }
  }

  const loadQuotaStatus = async () => {
    try {
      const status = await aiClient.current.getQuotaStatus()
      setQuotaStatus(status)
    } catch (error) {
      logger.error('Error loading quota', { error })
    }
  }

  const sendMessage = async (content: string) => {
    if (!currentConversation || isLoading) return

    setIsLoading(true)
    abortControllerRef.current = new AbortController()

    try {
      // Create temporary message IDs
      const tempMessageId = crypto.randomUUID()
      const tempAssistantId = crypto.randomUUID()

      // Add user message
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

      // Build messages array for API
      const apiMessages = messages
        .filter(m => m.role !== 'system')
        .map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content
        }))
      apiMessages.push({ role: 'user', content })

      // Track accumulated content
      let accumulatedContent = ''

      // Call AI Gateway
      await aiClient.current.streamChat({
        model: currentConversation.model || 'gpt-3.5-turbo',
        messages: apiMessages,
        conversationId: currentConversation.id,
        signal: abortControllerRef.current.signal,
        onUpdate: (chunk) => {
          accumulatedContent += chunk
          updateMessage(tempAssistantId, accumulatedContent)
        },
        onFinish: async (usage) => {
          // Update temporary message with token usage
          if (usage) {
            updateMessageTokens(tempAssistantId, {
              prompt_tokens: usage.promptTokens,
              completion_tokens: usage.completionTokens,
              total_tokens: usage.totalTokens,
            })
          }
          
          // Save messages to database
          try {
            // Save user message
            await supabase.from('messages').insert({
              conversation_id: currentConversation.id,
              role: 'user',
              content,
              model: currentConversation.model,
              provider: currentConversation.provider,
            })

            // Get final assistant content
            const finalContent = accumulatedContent
            
            // Save assistant message with token usage
            await supabase.from('messages').insert({
              conversation_id: currentConversation.id,
              role: 'assistant',
              content: finalContent,
              model: currentConversation.model,
              provider: currentConversation.provider,
              prompt_tokens: usage?.promptTokens || null,
              completion_tokens: usage?.completionTokens || null,
              total_tokens: usage?.totalTokens || null,
            })

            // Update conversation
            const updateData: any = { 
              last_message_at: new Date().toISOString(),
              last_message_preview: finalContent.slice(0, 100) + (finalContent.length > 100 ? '...' : ''),
              message_count: messages.length + 2 // Add 2 for user and assistant messages
            }
            
            // Only update title if it's the first message
            if (messages.length === 0 && content.length > 0) {
              updateData.title = content.slice(0, 50) + (content.length > 50 ? '...' : '')
            }
            
            await supabase
              .from('conversations')
              .update(updateData)
              .eq('id', currentConversation.id)

            // Reload quota status
            loadQuotaStatus()
          } catch (error) {
            logger.error('Error saving messages', { error, conversationId: currentConversation.id })
          } finally {
            // Reset loading state after streaming completes
            setIsLoading(false)
            setStreamingMessageId(null)
            abortControllerRef.current = null
          }
        },
        onError: (error) => {
          logger.error('Streaming error', { error, model: currentConversation.model, conversationId: currentConversation.id })
          toast({
            title: 'Error',
            description: error.message,
            variant: 'destructive',
          })
          // Reset loading state on error
          setIsLoading(false)
          setStreamingMessageId(null)
          abortControllerRef.current = null
        }
      })

    } catch (error: any) {
      logger.error('Error sending message', { error, model: currentConversation?.model })
      
      if (error.name !== 'AbortError') {
        toast({
          title: 'Error',
          description: error.message || 'Failed to send message',
          variant: 'destructive',
        })
      }
      // Reset loading state on error
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

  // Calculate quota percentage
  const quotaPercentage = quotaStatus 
    ? Math.round((quotaStatus.tokens_used_today / getDailyLimit()) * 100)
    : 0

  function getDailyLimit() {
    // This should match the database function logic
    const tier = quotaStatus?.tier || 'free'
    switch (tier) {
      case 'free': return 5000
      case 'pro': return 50000
      case 'max': return 500000
      default: return 5000
    }
  }

  return (
    <div className="flex flex-col h-full">
      <div className="border-b px-4 py-3">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center space-x-4">
            <h2 className="text-lg font-semibold">
              {currentConversation?.title || 'New Chat'}
            </h2>
            <ModelSelector />
            <PresetSelector />
          </div>
          <div className="flex items-center space-x-2">
            {isLoading && (
              <button
                onClick={stopStreaming}
                className="text-sm px-3 py-1 bg-red-500 text-white rounded hover:bg-red-600"
              >
                Stop Generating
              </button>
            )}
            <button
              onClick={onNewChat}
              className="text-sm px-3 py-1 bg-primary text-primary-foreground rounded hover:bg-primary/90"
            >
              New Chat
            </button>
          </div>
        </div>
        
        {/* Quota Status */}
        {quotaStatus && (
          <div className="space-y-1">
            <div className="flex justify-between text-xs text-muted-foreground">
              <span>Daily Usage</span>
              <span>{quotaStatus.tokens_used_today} / {getDailyLimit()} tokens</span>
            </div>
            <Progress value={quotaPercentage} className="h-1" />
            {quotaPercentage > 90 && (
              <Alert className="mt-2 py-2">
                <AlertCircle className="h-3 w-3" />
                <AlertDescription className="text-xs">
                  You've used {quotaPercentage}% of your daily quota
                </AlertDescription>
              </Alert>
            )}
          </div>
        )}
      </div>
      
      <MessageList
        messages={messages}
        streamingMessageId={streamingMessageId}
      />
      
      {/* 上下文使用指示器 */}
      <ContextIndicator
        messages={messages}
        currentInput={currentInput}
        model={currentConversation?.model || 'gpt-3.5-turbo'}
      />
      
      <MessageInput
        onSendMessage={sendMessage}
        isLoading={isLoading}
        onStopStreaming={stopStreaming}
        disabled={quotaPercentage >= 100}
        onInputChange={setCurrentInput}
      />
    </div>
  )
}