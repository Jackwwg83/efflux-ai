// Unified Model Router for v1-chat Edge Function
// This module handles intelligent routing for the unified model system

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface ModelSource {
  source_id: string
  provider_type: 'direct' | 'aggregator'
  provider_name: string
  api_endpoint?: string
  api_standard: string
  custom_headers?: Record<string, string>
  api_key: string
  api_key_id: string
  input_price: number
  output_price: number
}

interface RouteDecision {
  source: ModelSource
  reason: 'priority' | 'availability' | 'load_balance' | 'cost'
}

export class UnifiedModelRouter {
  private supabase: any

  constructor(supabaseUrl: string, supabaseKey: string) {
    this.supabase = createClient(supabaseUrl, supabaseKey)
  }

  /**
   * Get the optimal provider for a model based on availability, priority, and load balancing
   */
  async getOptimalRoute(modelId: string, userId: string): Promise<RouteDecision> {
    // Call the new database function to get optimal source
    const { data, error } = await this.supabase.rpc('get_model_provider_config_v3', {
      p_model_id: modelId
    })

    if (error || !data || data.length === 0) {
      throw new Error(`No available provider for model: ${modelId}`)
    }

    const source = data[0]
    
    // Log routing decision for analytics
    await this.logRoutingDecision({
      model_id: modelId,
      user_id: userId,
      provider_name: source.provider_name,
      routing_reason: 'priority', // Could be enhanced with actual logic
      source_id: source.provider_id
    })

    return {
      source: {
        source_id: source.provider_id,
        provider_type: source.provider_type,
        provider_name: source.provider_name,
        api_endpoint: source.base_url,
        api_standard: source.api_standard,
        custom_headers: source.custom_headers || {},
        api_key: source.api_key,
        api_key_id: source.api_key_id,
        input_price: source.input_price,
        output_price: source.output_price
      },
      reason: 'priority'
    }
  }

  /**
   * Forward request to the selected provider
   */
  async forwardRequest(params: {
    route: RouteDecision
    model: string
    messages: any[]
    stream: boolean
    temperature?: number
    max_tokens?: number
  }): Promise<Response> {
    const { route, model, messages, stream, temperature, max_tokens } = params
    const { source } = route

    // Build request based on API standard
    const requestBody = this.buildRequestBody({
      api_standard: source.api_standard,
      model,
      messages,
      stream,
      temperature,
      max_tokens
    })

    // Determine endpoint
    const endpoint = this.getEndpoint(source)

    // Build headers
    const headers = this.buildHeaders(source)

    // Make the request
    const response = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(requestBody)
    })

    if (!response.ok) {
      await this.handleProviderError(source, response)
    }

    return response
  }

  /**
   * Build request body based on API standard
   */
  private buildRequestBody(params: any) {
    const { api_standard, model, messages, stream, temperature, max_tokens } = params

    switch (api_standard) {
      case 'openai':
        return {
          model,
          messages,
          stream,
          temperature,
          max_tokens
        }
      
      case 'anthropic':
        const anthropicMessages = messages
          .filter((m: any) => m.role !== 'system')
          .map((m: any) => ({
            role: m.role,
            content: m.content
          }))
        
        const systemMessage = messages.find((m: any) => m.role === 'system')
        
        return {
          model,
          messages: anthropicMessages,
          system: systemMessage?.content,
          stream,
          temperature,
          max_tokens: max_tokens || 4096
        }
      
      case 'google':
        return {
          contents: messages.map((m: any) => ({
            role: m.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: m.content }]
          })),
          generationConfig: {
            temperature: temperature || 0.7,
            maxOutputTokens: max_tokens || 8192,
            candidateCount: 1
          }
        }
      
      default:
        // Default to OpenAI format
        return {
          model,
          messages,
          stream,
          temperature,
          max_tokens
        }
    }
  }

  /**
   * Get the appropriate endpoint for the provider
   */
  private getEndpoint(source: ModelSource): string {
    if (source.api_endpoint) {
      return `${source.api_endpoint}/chat/completions`
    }

    // Default endpoints for known providers
    switch (source.provider_name) {
      case 'openai':
        return 'https://api.openai.com/v1/chat/completions'
      case 'anthropic':
        return 'https://api.anthropic.com/v1/messages'
      case 'google':
        return `https://generativelanguage.googleapis.com/v1beta/models/${source.provider_name}:streamGenerateContent`
      default:
        throw new Error(`Unknown provider endpoint: ${source.provider_name}`)
    }
  }

  /**
   * Build headers for the provider request
   */
  private buildHeaders(source: ModelSource): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }

    // Add authentication based on provider
    switch (source.provider_name) {
      case 'openai':
        headers['Authorization'] = `Bearer ${source.api_key}`
        break
      case 'anthropic':
        headers['x-api-key'] = source.api_key
        headers['anthropic-version'] = '2023-06-01'
        break
      case 'google':
        // Google uses API key in URL
        break
      default:
        // Default to Bearer token
        headers['Authorization'] = `Bearer ${source.api_key}`
    }

    // Add any custom headers
    if (source.custom_headers) {
      Object.assign(headers, source.custom_headers)
    }

    return headers
  }

  /**
   * Handle provider errors and update availability
   */
  private async handleProviderError(source: ModelSource, response: Response) {
    const errorData = await response.json().catch(() => ({ error: 'Unknown error' }))
    
    // Log the error
    await this.supabase
      .from('model_routing_logs')
      .insert({
        provider_name: source.provider_name,
        status: 'error',
        error_message: errorData.error?.message || `Provider error: ${response.status}`
      })

    // Update source availability if needed
    if (response.status >= 500 || response.status === 429) {
      await this.supabase.rpc('increment_source_failures', {
        p_source_id: source.source_id
      })
    }

    throw new Error(errorData.error?.message || `Provider request failed: ${response.status}`)
  }

  /**
   * Log routing decision for analytics
   */
  private async logRoutingDecision(params: {
    model_id: string
    user_id: string
    provider_name: string
    routing_reason: string
    source_id: string
  }) {
    try {
      await this.supabase
        .from('model_routing_logs')
        .insert({
          model_id: params.model_id,
          user_id: params.user_id,
          provider_name: params.provider_name,
          routing_reason: params.routing_reason,
          selected_source_id: params.source_id,
          status: 'routing'
        })
    } catch (error) {
      console.error('Failed to log routing decision:', error)
    }
  }

  /**
   * Record usage after successful completion
   */
  async recordUsage(params: {
    userId: string
    modelId: string
    sourceId: string
    promptTokens: number
    completionTokens: number
    latency: number
    status: 'success' | 'error'
  }) {
    const totalTokens = params.promptTokens + params.completionTokens
    
    // Get model pricing
    const { data: model } = await this.supabase
      .from('models')
      .select('input_price, output_price')
      .eq('model_id', params.modelId)
      .single()

    const cost = model ? 
      (params.promptTokens / 1000) * model.input_price + 
      (params.completionTokens / 1000) * model.output_price : 0

    // Update routing log
    await this.supabase
      .from('model_routing_logs')
      .update({
        latency_ms: params.latency,
        tokens_used: totalTokens,
        estimated_cost: cost,
        status: params.status
      })
      .eq('selected_source_id', params.sourceId)
      .order('created_at', { ascending: false })
      .limit(1)

    // Update user usage
    if (params.status === 'success') {
      await this.supabase.rpc('update_user_usage', {
        p_user_id: params.userId,
        p_tokens: totalTokens,
        p_cost: cost
      })
    }
  }
}

// Export for use in main Edge Function
export default UnifiedModelRouter