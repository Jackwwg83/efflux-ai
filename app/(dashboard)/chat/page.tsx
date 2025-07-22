'use client'

import { useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { ChatContainer } from '@/components/chat/chat-container-v2'
import { ChatErrorBoundary } from '@/components/chat/chat-error-boundary'
import { useConversationStore } from '@/lib/stores/conversation'
import { Database } from '@/types/database'
import { logger } from '@/lib/utils/logger'

type Conversation = Database['public']['Tables']['conversations']['Row']

export default function ChatPage() {
  const router = useRouter()
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const { setCurrentConversation, setConversations } = useConversationStore()

  useEffect(() => {
    loadConversations()
  }, [])

  const loadConversations = async () => {
    try {
      const { data: conversations, error } = await supabase
        .from('conversations')
        .select('*')
        .order('updated_at', { ascending: false })

      if (error) throw error

      if (conversations && conversations.length > 0) {
        setConversations(conversations)
        setCurrentConversation(conversations[0])
      } else {
        // Create a new conversation if none exists
        await createNewConversation()
      }
    } catch (error) {
      logger.error('Error loading conversations', { error })
    } finally {
      setLoading(false)
    }
  }

  const createNewConversation = async () => {
    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) return

      const { data: conversation, error } = await supabase
        .from('conversations')
        .insert({
          user_id: user.user.id,
          title: 'New Chat',
          model: 'gemini-2.5-flash',
          provider: 'google',
        })
        .select()
        .single()

      if (error) throw error

      if (conversation) {
        setCurrentConversation(conversation)
        setConversations((prev) => [conversation, ...prev])
      }
    } catch (error) {
      logger.error('Error creating conversation', { error })
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    )
  }

  return (
    <ChatErrorBoundary conversationId={useConversationStore.getState().currentConversation?.id}>
      <ChatContainer onNewChat={createNewConversation} />
    </ChatErrorBoundary>
  )
}