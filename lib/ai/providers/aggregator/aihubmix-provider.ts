// AiHubMix Provider Implementation

import { BaseAggregatorProvider } from './base-aggregator'
import { 
  AggregatorModel, 
  ChatRequest, 
  APIError,
  ModelCapabilities,
  ModelPricing 
} from './types'

export class AiHubMixProvider extends BaseAggregatorProvider {
  async fetchModels(): Promise<AggregatorModel[]> {
    const response = await this.makeRequest('/models', {
      method: 'GET'
    })
    
    const data = await response.json()
    return this.mapModelsToSchema(data.data || data)
  }
  
  async createChatCompletion(request: ChatRequest): Promise<Response> {
    // AiHubMix uses OpenAI-compatible format
    const body = {
      model: request.model,
      messages: request.messages,
      temperature: request.temperature,
      max_tokens: request.max_tokens,
      stream: request.stream ?? true,
      top_p: request.top_p,
      frequency_penalty: request.frequency_penalty,
      presence_penalty: request.presence_penalty,
      response_format: request.response_format,
      seed: request.seed,
      user: request.user
    }
    
    // Include functions if provided
    if (request.functions) {
      body['functions'] = request.functions
      if (request.function_call) {
        body['function_call'] = request.function_call
      }
    }
    
    const response = await this.makeRequest('/chat/completions', {
      method: 'POST',
      body: JSON.stringify(body)
    })
    
    // For streaming responses, return the raw response
    if (request.stream) {
      return new Response(this.createStreamingResponse(response), {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        }
      })
    }
    
    // For non-streaming, return the JSON response
    return response
  }
  
  async validateApiKey(): Promise<boolean> {
    try {
      const response = await this.makeRequest('/models', {
        method: 'GET'
      })
      return response.ok
    } catch {
      return false
    }
  }
  
  formatError(error: any): APIError {
    const apiError = new Error(error.message || 'Unknown error') as APIError
    apiError.status = error.status
    apiError.code = error.code
    apiError.type = error.type || 'api_error'
    return apiError
  }
  
  protected getAdditionalHeaders(): Record<string, string> {
    return {
      'X-Provider': 'aihubmix',
      'X-Client': 'efflux-ai'
    }
  }
  
  protected async handleErrorResponse(response: Response): Promise<Error> {
    try {
      const errorData = await response.json()
      const error = new Error(errorData.error?.message || 'Request failed') as APIError
      error.status = response.status
      error.code = errorData.error?.code
      error.type = errorData.error?.type
      return error
    } catch {
      return new Error(`Request failed with status ${response.status}`)
    }
  }
  
  private mapModelsToSchema(models: any[]): AggregatorModel[] {
    return models.map(model => ({
      model_id: model.id,
      model_name: model.id,
      display_name: model.name || this.formatModelName(model.id),
      model_type: this.inferModelType(model.id),
      capabilities: this.inferCapabilities(model),
      context_window: model.context_length || this.inferContextWindow(model.id),
      max_output_tokens: model.max_tokens || this.inferMaxTokens(model.id),
      pricing: this.extractPricing(model),
      training_cutoff: model.training_cutoff,
      is_available: model.is_available ?? true
    }))
  }
  
  private formatModelName(modelId: string): string {
    // Convert model IDs to display names
    const parts = modelId.split('-')
    return parts.map(part => 
      part.charAt(0).toUpperCase() + part.slice(1)
    ).join(' ')
  }
  
  private inferModelType(modelId: string): AggregatorModel['model_type'] {
    const id = modelId.toLowerCase()
    if (id.includes('embed')) return 'embedding'
    if (id.includes('tts') || id.includes('speech')) return 'audio'
    if (id.includes('dall-e') || id.includes('image')) return 'image'
    if (id.includes('moderation')) return 'moderation'
    return 'chat'
  }
  
  private inferCapabilities(model: any): ModelCapabilities {
    const modelId = model.id.toLowerCase()
    
    return {
      vision: modelId.includes('vision') || 
              modelId.includes('4o') || 
              modelId.includes('gemini-pro-vision') ||
              model.supports_vision === true,
      functions: !modelId.includes('instruct') && 
                 !modelId.includes('base') &&
                 model.supports_functions !== false,
      streaming: model.supports_streaming !== false,
      json_mode: modelId.includes('gpt-4') || 
                 modelId.includes('gpt-3.5-turbo'),
      parallel_function_calling: modelId.includes('gpt-4-turbo') ||
                                modelId.includes('gpt-4-1106')
    }
  }
  
  private inferContextWindow(modelId: string): number {
    const id = modelId.toLowerCase()
    
    // Known context windows
    if (id.includes('gpt-4-turbo') || id.includes('gpt-4-1106')) return 128000
    if (id.includes('gpt-4-32k')) return 32768
    if (id.includes('gpt-4')) return 8192
    if (id.includes('gpt-3.5-turbo-16k')) return 16384
    if (id.includes('gpt-3.5')) return 4096
    if (id.includes('claude-3-opus')) return 200000
    if (id.includes('claude-3-sonnet')) return 200000
    if (id.includes('claude-3-haiku')) return 200000
    if (id.includes('claude-2')) return 100000
    if (id.includes('gemini-pro')) return 32768
    if (id.includes('deepseek')) return 32768
    
    // Default
    return 8192
  }
  
  private inferMaxTokens(modelId: string): number {
    const id = modelId.toLowerCase()
    
    // Known max tokens
    if (id.includes('gpt-4-turbo') || id.includes('gpt-4-1106')) return 4096
    if (id.includes('gpt-4')) return 8192
    if (id.includes('gpt-3.5')) return 4096
    if (id.includes('claude')) return 4096
    if (id.includes('gemini')) return 8192
    
    // Default
    return 4096
  }
  
  private extractPricing(model: any): ModelPricing | undefined {
    if (!model.pricing) return undefined
    
    return {
      input: model.pricing.prompt || model.pricing.input || 0,
      output: model.pricing.completion || model.pricing.output || 0,
      image: model.pricing.image,
      audio: model.pricing.audio
    }
  }
}