import { create } from 'zustand'
import { Database } from '@/types/database'

type Conversation = Database['public']['Tables']['conversations']['Row']
type Message = Database['public']['Tables']['messages']['Row']

interface ConversationStore {
  conversations: Conversation[]
  currentConversation: Conversation | null
  messages: Message[]
  
  setConversations: (conversations: Conversation[] | ((prev: Conversation[]) => Conversation[])) => void
  setCurrentConversation: (conversation: Conversation | null) => void
  setMessages: (messages: Message[]) => void
  addMessage: (message: Message) => void
  updateMessage: (id: string, content: string) => void
}

export const useConversationStore = create<ConversationStore>((set) => ({
  conversations: [],
  currentConversation: null,
  messages: [],
  
  setConversations: (conversations) => 
    set((state) => ({
      conversations: typeof conversations === 'function' 
        ? conversations(state.conversations) 
        : conversations
    })),
  
  setCurrentConversation: (conversation) => 
    set({ currentConversation: conversation, messages: [] }),
  
  setMessages: (messages) => 
    set({ messages }),
  
  addMessage: (message) => 
    set((state) => ({ messages: [...state.messages, message] })),
  
  updateMessage: (id, content) => 
    set((state) => ({
      messages: state.messages.map((msg) =>
        msg.id === id ? { ...msg, content } : msg
      ),
    })),
}))