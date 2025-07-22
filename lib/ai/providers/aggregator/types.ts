// Types for API Aggregator Providers

export interface APIProviderConfig {
  id: string
  name: string
  display_name: string
  provider_type: 'aggregator' | 'direct'
  base_url: string
  api_standard: 'openai' | 'anthropic' | 'google' | 'custom'
  features: ProviderFeatures
  documentation_url?: string
}

export interface ProviderFeatures {
  supports_streaming: boolean
  supports_functions: boolean
  supports_vision: boolean
  supports_audio?: boolean
  supports_embeddings?: boolean
  supports_image_generation?: boolean
  model_list_endpoint?: string
  requires_model_prefix?: boolean
  requires_referer?: boolean
  requires_site_name?: boolean
  header_format?: string
}

export interface AggregatorModel {
  model_id: string
  model_name: string
  display_name: string
  model_type: 'chat' | 'completion' | 'image' | 'audio' | 'embedding' | 'moderation'
  capabilities: ModelCapabilities
  context_window?: number
  max_output_tokens?: number
  pricing?: ModelPricing
  training_cutoff?: string
  is_available: boolean
}

export interface ModelCapabilities {
  vision?: boolean
  functions?: boolean
  streaming?: boolean
  json_mode?: boolean
  parallel_function_calling?: boolean
}

export interface ModelPricing {
  input: number  // Cost per 1K tokens
  output: number // Cost per 1K tokens
  image?: number // Cost per image
  audio?: number // Cost per minute
}

export interface ChatRequest {
  model: string
  messages: ChatMessage[]
  temperature?: number
  max_tokens?: number
  top_p?: number
  frequency_penalty?: number
  presence_penalty?: number
  stream?: boolean
  functions?: any[]
  function_call?: any
  response_format?: { type: 'json_object' | 'text' }
  seed?: number
  user?: string
}

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant' | 'function'
  content: string
  name?: string
  function_call?: any
}

export interface ChatResponse {
  id: string
  object: string
  created: number
  model: string
  choices: ChatChoice[]
  usage?: Usage
}

export interface ChatChoice {
  index: number
  message?: ChatMessage
  delta?: Partial<ChatMessage>
  finish_reason: string | null
}

export interface Usage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

export interface APIError extends Error {
  status?: number
  code?: string
  type?: string
}

export interface ProviderUsageLog {
  user_id: string
  provider_id: string
  model_id: string
  conversation_id?: string
  message_id?: string
  request_id?: string
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
  cost_estimate: number
  latency_ms: number
  status: 'success' | 'error' | 'timeout' | 'cancelled'
  error_code?: string
  error_message?: string
  metadata?: Record<string, any>
}