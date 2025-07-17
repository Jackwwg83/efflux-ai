'use client'

import { useState, useEffect, useRef } from 'react'
import { MessageList } from './message-list'
import { MessageInput } from './message-input'
import { ModelSelector } from './model-selector'
import { createClient } from '@/lib/supabase/client'
import { useConversationStore } from '@/lib/stores/conversation'
import { useToast } from '@/hooks/use-toast'
import { Database } from '@/types/database'
import { AIGatewayClient } from '@/lib/ai/gateway-client'
import { Progress } from '@/components/ui/progress'
import { AlertCircle } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'

type Message = Database['public']['Tables']['messages']['Row']

interface ChatContainerProps {
  onNewChat: () => void
}

export function ChatContainer({ onNewChat }: ChatContainerProps) {
  const supabase = createClient()
  const { toast } = useToast()
  const [isLoading, setIsLoading] = useState(false)
  const [streamingMessageId, setStreamingMessageId] = useState<string | null>(null)
  const [quotaStatus, setQuotaStatus] = useState<any>(null)
  const abortControllerRef = useRef<AbortController | null>(null)
  const aiClient = useRef(new AIGatewayClient())
  
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
      console.error('Error loading messages:', error)
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
      console.error('Error loading quota:', error)
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

      // Call AI Gateway
      await aiClient.current.streamChat({
        model: currentConversation.model || 'gpt-3.5-turbo',
        messages: apiMessages,
        onUpdate: (chunk) => {
          updateMessage(tempAssistantId, (prev) => prev + chunk)
        },
        onFinish: async () => {
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
            const finalContent = messages.find(m => m.id === tempAssistantId)?.content || ''
            
            // Save assistant message
            await supabase.from('messages').insert({
              conversation_id: currentConversation.id,
              role: 'assistant',
              content: finalContent,
              model: currentConversation.model,
              provider: currentConversation.provider,
            })

            // Update conversation
            await supabase
              .from('conversations')
              .update({ 
                last_message_at: new Date().toISOString(),
                ...(messages.length === 0 && { 
                  title: content.slice(0, 50) + (content.length > 50 ? '...' : '') 
                })
              })
              .eq('id', currentConversation.id)

            // Reload quota status
            loadQuotaStatus()
          } catch (error) {
            console.error('Error saving messages:', error)
          }
        },
        onError: (error) => {
          console.error('Streaming error:', error)
          toast({
            title: 'Error',
            description: error.message,
            variant: 'destructive',
          })
        }
      })

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
          </div>
          <button
            onClick={onNewChat}
            className="text-sm text-muted-foreground hover:text-foreground"
          >
            New Chat
          </button>
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
      
      <MessageInput
        onSendMessage={sendMessage}
        isLoading={isLoading}
        onStopStreaming={stopStreaming}
        disabled={quotaPercentage >= 100}
      />
    </div>
  )
}