'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { 
  MessageSquare, 
  Settings, 
  CreditCard, 
  LogOut, 
  Plus, 
  Search,
  Star,
  MoreVertical,
  Trash2,
  Edit2
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import { useConversationStore } from '@/lib/stores/conversation'
import { formatDistanceToNow } from 'date-fns'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Database } from '@/types/database'

type Conversation = Database['public']['Tables']['conversations']['Row']

const navigation = [
  { name: 'Billing', href: '/billing', icon: CreditCard },
  { name: 'Settings', href: '/settings', icon: Settings },
]

export function ConversationSidebar() {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [loading, setLoading] = useState(true)
  const { currentConversation, setCurrentConversation } = useConversationStore()

  useEffect(() => {
    loadConversations()
    
    // Subscribe to conversation changes
    const channel = supabase
      .channel('conversations-changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'conversations',
        },
        () => {
          loadConversations()
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
        },
        (payload) => {
          // Update conversation with latest message preview
          if (payload.new && payload.new.conversation_id) {
            const message = payload.new as Database['public']['Tables']['messages']['Row']
            setConversations(prev => 
              prev.map(conv => 
                conv.id === message.conversation_id
                  ? {
                      ...conv,
                      last_message_preview: message.content.slice(0, 100) + (message.content.length > 100 ? '...' : ''),
                      message_count: (conv.message_count || 0) + 1,
                      updated_at: new Date().toISOString()
                    }
                  : conv
              ).sort((a, b) => {
                // Keep favorites at top
                if (a.is_favorite !== b.is_favorite) return a.is_favorite ? -1 : 1
                // Then sort by updated_at
                return new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
              })
            )
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [])

  const loadConversations = async () => {
    try {
      const { data, error } = await supabase
        .from('conversations')
        .select('*')
        .order('is_favorite', { ascending: false })
        .order('updated_at', { ascending: false })

      if (error) throw error
      setConversations(data || [])
    } catch (error) {
      console.error('Error loading conversations:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  const handleNewChat = async () => {
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
        router.push('/chat')
      }
    } catch (error) {
      console.error('Error creating conversation:', error)
    }
  }

  const toggleFavorite = async (conversation: Conversation) => {
    try {
      await supabase
        .from('conversations')
        .update({ is_favorite: !conversation.is_favorite })
        .eq('id', conversation.id)
    } catch (error) {
      console.error('Error toggling favorite:', error)
    }
  }

  const deleteConversation = async (id: string) => {
    try {
      await supabase
        .from('conversations')
        .delete()
        .eq('id', id)
      
      if (currentConversation?.id === id) {
        setCurrentConversation(null)
        router.push('/chat')
      }
    } catch (error) {
      console.error('Error deleting conversation:', error)
    }
  }

  const filteredConversations = conversations.filter(conv => 
    conv.title?.toLowerCase().includes(searchQuery.toLowerCase()) ||
    conv.last_message_preview?.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const groupedConversations = {
    favorites: filteredConversations.filter(c => c.is_favorite),
    today: filteredConversations.filter(c => !c.is_favorite && 
      new Date(c.updated_at).toDateString() === new Date().toDateString()
    ),
    yesterday: filteredConversations.filter(c => !c.is_favorite && 
      new Date(c.updated_at).toDateString() === 
      new Date(Date.now() - 86400000).toDateString()
    ),
    older: filteredConversations.filter(c => !c.is_favorite && 
      new Date(c.updated_at) < new Date(Date.now() - 86400000)
    )
  }

  return (
    <div className="flex h-full w-80 flex-col bg-muted/50 border-r">
      {/* Header */}
      <div className="flex h-16 items-center justify-between border-b px-4">
        <h1 className="text-xl font-bold">Efflux AI</h1>
        <Button
          size="icon"
          variant="ghost"
          onClick={handleNewChat}
          className="h-8 w-8"
        >
          <Plus className="h-4 w-4" />
        </Button>
      </div>
      
      {/* Search */}
      <div className="p-4">
        <div className="relative">
          <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search conversations..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-8"
          />
        </div>
      </div>

      {/* Conversations List */}
      <div className="flex-1 overflow-y-auto px-2">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
          </div>
        ) : (
          <>
            {/* Favorites */}
            {groupedConversations.favorites.length > 0 && (
              <div className="mb-4">
                <h3 className="px-2 py-1 text-xs font-semibold text-muted-foreground">
                  Favorites
                </h3>
                {groupedConversations.favorites.map((conversation) => (
                  <ConversationItem
                    key={conversation.id}
                    conversation={conversation}
                    isActive={currentConversation?.id === conversation.id}
                    onToggleFavorite={toggleFavorite}
                    onDelete={deleteConversation}
                  />
                ))}
              </div>
            )}

            {/* Today */}
            {groupedConversations.today.length > 0 && (
              <div className="mb-4">
                <h3 className="px-2 py-1 text-xs font-semibold text-muted-foreground">
                  Today
                </h3>
                {groupedConversations.today.map((conversation) => (
                  <ConversationItem
                    key={conversation.id}
                    conversation={conversation}
                    isActive={currentConversation?.id === conversation.id}
                    onToggleFavorite={toggleFavorite}
                    onDelete={deleteConversation}
                  />
                ))}
              </div>
            )}

            {/* Yesterday */}
            {groupedConversations.yesterday.length > 0 && (
              <div className="mb-4">
                <h3 className="px-2 py-1 text-xs font-semibold text-muted-foreground">
                  Yesterday
                </h3>
                {groupedConversations.yesterday.map((conversation) => (
                  <ConversationItem
                    key={conversation.id}
                    conversation={conversation}
                    isActive={currentConversation?.id === conversation.id}
                    onToggleFavorite={toggleFavorite}
                    onDelete={deleteConversation}
                  />
                ))}
              </div>
            )}

            {/* Older */}
            {groupedConversations.older.length > 0 && (
              <div className="mb-4">
                <h3 className="px-2 py-1 text-xs font-semibold text-muted-foreground">
                  Older
                </h3>
                {groupedConversations.older.map((conversation) => (
                  <ConversationItem
                    key={conversation.id}
                    conversation={conversation}
                    isActive={currentConversation?.id === conversation.id}
                    onToggleFavorite={toggleFavorite}
                    onDelete={deleteConversation}
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>
      
      {/* Navigation */}
      <nav className="border-t p-2">
        {navigation.map((item) => {
          const isActive = pathname.startsWith(item.href)
          return (
            <Link
              key={item.name}
              href={item.href}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <item.icon className="h-4 w-4" />
              {item.name}
            </Link>
          )
        })}
      </nav>
      
      {/* Sign Out */}
      <div className="border-t p-4">
        <Button
          variant="ghost"
          className="w-full justify-start"
          onClick={handleSignOut}
        >
          <LogOut className="mr-2 h-4 w-4" />
          Sign out
        </Button>
      </div>
    </div>
  )
}

function ConversationItem({
  conversation,
  isActive,
  onToggleFavorite,
  onDelete,
}: {
  conversation: Conversation
  isActive: boolean
  onToggleFavorite: (conversation: Conversation) => void
  onDelete: (id: string) => void
}) {
  const router = useRouter()
  const { setCurrentConversation } = useConversationStore()

  const handleClick = () => {
    setCurrentConversation(conversation)
    router.push('/chat')
  }

  return (
    <div
      className={cn(
        'group relative flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-muted cursor-pointer',
        isActive && 'bg-muted'
      )}
      onClick={handleClick}
    >
      <MessageSquare className="h-4 w-4 text-muted-foreground" />
      
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">
          {conversation.title || 'New Chat'}
        </p>
        {conversation.last_message_preview && (
          <p className="text-xs text-muted-foreground truncate">
            {conversation.last_message_preview}
          </p>
        )}
      </div>

      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100">
        <Button
          size="icon"
          variant="ghost"
          className="h-6 w-6"
          onClick={(e) => {
            e.stopPropagation()
            onToggleFavorite(conversation)
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
              size="icon"
              variant="ghost"
              className="h-6 w-6"
              onClick={(e) => e.stopPropagation()}
            >
              <MoreVertical className="h-3 w-3" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              onClick={(e) => {
                e.stopPropagation()
                onDelete(conversation.id)
              }}
              className="text-destructive"
            >
              <Trash2 className="mr-2 h-4 w-4" />
              Delete
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}