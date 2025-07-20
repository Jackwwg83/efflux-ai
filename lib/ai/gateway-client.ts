import { createClient } from '@/lib/supabase/client'

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface ChatParams {
  model: string
  messages: ChatMessage[]
  temperature?: number
  maxTokens?: number
  onUpdate?: (content: string) => void
  onFinish?: (usage?: { promptTokens: number; completionTokens: number; totalTokens: number }) => void
  onError?: (error: Error) => void
}

export class AIGatewayClient {
  private supabase = createClient()
  
  async chat(params: ChatParams): Promise<Response> {
    // Get current session
    const { data: { session } } = await this.supabase.auth.getSession()
    
    if (!session) {
      throw new Error('Not authenticated')
    }
    
    // Call our API Gateway instead of direct provider APIs
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/v1-chat`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          model: params.model,
          messages: params.messages,
          temperature: params.temperature,
          max_tokens: params.maxTokens,
          stream: true
        })
      }
    )
    
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error || 'API request failed')
    }
    
    return response
  }
  
  async streamChat(params: ChatParams): Promise<void> {
    try {
      const response = await this.chat(params)
      
      if (!response.body) {
        throw new Error('No response body')
      }
      
      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      let usage: { promptTokens: number; completionTokens: number; totalTokens: number } | undefined
      
      while (true) {
        const { done, value } = await reader.read()
        
        if (done) {
          params.onFinish?.(usage)
          break
        }
        
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() || ''
        
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6)
            
            if (data === '[DONE]') {
              params.onFinish?.(usage)
              return
            }
            
            try {
              const parsed = JSON.parse(data)
              
              // Handle usage message
              if (parsed.type === 'usage' && parsed.usage) {
                usage = {
                  promptTokens: parsed.usage.promptTokens,
                  completionTokens: parsed.usage.completionTokens,
                  totalTokens: parsed.usage.totalTokens
                }
                continue
              }
              
              // Handle different provider formats
              let content = ''
              
              // OpenAI format
              if (parsed.choices?.[0]?.delta?.content) {
                content = parsed.choices[0].delta.content
              }
              // Anthropic format
              else if (parsed.delta?.text) {
                content = parsed.delta.text
              }
              // Google format
              else if (parsed.candidates?.[0]?.content?.parts?.[0]?.text) {
                content = parsed.candidates[0].content.parts[0].text
              }
              
              if (content) {
                params.onUpdate?.(content)
              }
            } catch (e) {
              console.error('Error parsing SSE data:', e)
            }
          }
        }
      }
    } catch (error) {
      params.onError?.(error as Error)
      throw error
    }
  }
  
  // Get user's current quota status
  async getQuotaStatus() {
    const { data: { user } } = await this.supabase.auth.getUser()
    
    if (!user) {
      throw new Error('Not authenticated')
    }
    
    // Use the new function that handles automatic resets
    const { data, error } = await this.supabase
      .rpc('get_user_quota_status', { p_user_id: user.id })
      .single()
    
    if (error) {
      console.error('Error fetching quota:', error)
      return null
    }
    
    return data
  }
  
  // Get available models for the user
  async getAvailableModels() {
    const { data: { user } } = await this.supabase.auth.getUser()
    
    if (!user) {
      return []
    }
    
    // Get user tier
    const { data: userTier } = await this.supabase
      .from('user_tiers')
      .select('tier')
      .eq('user_id', user.id)
      .single()
    
    const tier = userTier?.tier || 'free'
    
    // Get models available for user's tier
    const { data: models } = await this.supabase
      .from('model_configs')
      .select('*')
      .eq('is_active', true)
      .order('provider', { ascending: true })
      .order('display_name', { ascending: true })
    
    // Filter based on tier
    const tierOrder: Record<string, number> = { free: 0, pro: 1, max: 2 }
    return models?.filter(model => {
      const requiredTier = model.tier_required || 'free'
      return tierOrder[tier] >= tierOrder[requiredTier]
    }) || []
  }
}