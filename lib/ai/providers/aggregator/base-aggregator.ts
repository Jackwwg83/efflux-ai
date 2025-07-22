// Base class for API Aggregator Providers

import { 
  APIProviderConfig, 
  AggregatorModel, 
  ChatRequest, 
  ChatResponse,
  APIError,
  Usage 
} from './types'

export abstract class BaseAggregatorProvider {
  protected config: APIProviderConfig
  protected apiKey: string
  protected baseUrl: string
  
  constructor(config: APIProviderConfig, apiKey: string) {
    this.config = config
    this.apiKey = apiKey
    this.baseUrl = config.base_url
  }
  
  // Abstract methods that each provider must implement
  abstract fetchModels(): Promise<AggregatorModel[]>
  abstract createChatCompletion(request: ChatRequest): Promise<Response>
  abstract validateApiKey(): Promise<boolean>
  abstract formatError(error: any): APIError
  
  // Common request method with error handling
  protected async makeRequest(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<Response> {
    const url = `${this.baseUrl}${endpoint}`
    
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Authorization': `${this.getAuthorizationHeader()}`,
          'Content-Type': 'application/json',
          ...this.getAdditionalHeaders(),
          ...options.headers
        }
      })
      
      if (!response.ok) {
        throw await this.handleErrorResponse(response)
      }
      
      return response
    } catch (error) {
      throw this.formatError(error)
    }
  }
  
  // Get authorization header format
  protected getAuthorizationHeader(): string {
    const headerFormat = this.config.features.header_format || 'Bearer'
    return `${headerFormat} ${this.apiKey}`
  }
  
  // Provider-specific headers
  protected abstract getAdditionalHeaders(): Record<string, string>
  
  // Handle error responses
  protected abstract handleErrorResponse(response: Response): Promise<Error>
  
  // Common utility methods
  
  // Extract usage metrics from response
  protected extractUsageFromResponse(response: any): Usage | undefined {
    if (!response.usage) return undefined
    
    return {
      prompt_tokens: response.usage.prompt_tokens || 0,
      completion_tokens: response.usage.completion_tokens || 0,
      total_tokens: response.usage.total_tokens || 0
    }
  }
  
  // Calculate cost based on model pricing
  protected calculateCost(model: string, usage: Usage, pricing?: any): number {
    if (!pricing || !usage) return 0
    
    const inputCost = (usage.prompt_tokens / 1000) * (pricing.input || 0)
    const outputCost = (usage.completion_tokens / 1000) * (pricing.output || 0)
    
    return inputCost + outputCost
  }
  
  // Parse streaming response
  protected parseStreamChunk(chunk: string): any[] {
    const lines = chunk.split('\n').filter(line => line.trim())
    const results = []
    
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const data = line.slice(6)
        if (data === '[DONE]') {
          results.push({ done: true })
        } else {
          try {
            results.push(JSON.parse(data))
          } catch (e) {
            console.error('Failed to parse stream chunk:', e)
          }
        }
      }
    }
    
    return results
  }
  
  // Create a streaming response handler
  protected createStreamingResponse(response: Response): ReadableStream {
    const reader = response.body?.getReader()
    const decoder = new TextDecoder()
    const encoder = new TextEncoder()
    
    return new ReadableStream({
      async start(controller) {
        if (!reader) {
          controller.close()
          return
        }
        
        try {
          while (true) {
            const { done, value } = await reader.read()
            
            if (done) {
              // Send final [DONE] signal
              controller.enqueue(encoder.encode('data: [DONE]\n\n'))
              controller.close()
              break
            }
            
            // Forward the chunk as-is
            controller.enqueue(value)
          }
        } catch (error) {
          controller.error(error)
        }
      }
    })
  }
  
  // Validate model availability
  async isModelAvailable(modelId: string): Promise<boolean> {
    try {
      const models = await this.fetchModels()
      return models.some(m => m.model_id === modelId && m.is_available)
    } catch {
      return false
    }
  }
}