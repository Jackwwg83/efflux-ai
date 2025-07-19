import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ChatRequest {
  model: string
  messages: Array<{
    role: 'system' | 'user' | 'assistant'
    content: string
  }>
  stream?: boolean
  temperature?: number
  max_tokens?: number
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // 1. Parse request
    const body: ChatRequest = await req.json()
    const { model, messages, stream = true, temperature, max_tokens } = body

    // 2. Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }), 
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 3. Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 4. Get user from token
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabase.auth.getUser(token)
    
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }), 
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 5. Check user quota
    const { data: quotaCheck, error: quotaError } = await supabase.rpc('check_and_update_user_quota', {
      p_user_id: user.id,
      p_model: model,
      p_estimated_tokens: estimateTokens(messages)
    })

    if (quotaError || !quotaCheck || quotaCheck.length === 0) {
      console.error('Quota check error:', quotaError)
      return new Response(
        JSON.stringify({ error: 'Failed to check quota' }), 
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    const quota = quotaCheck[0]
    if (!quota.can_use) {
      return new Response(
        JSON.stringify({ 
          error: 'Quota exceeded',
          details: {
            daily_limit: quota.daily_limit,
            used_today: quota.used_today,
            remaining: quota.remaining
          }
        }), 
        { 
          status: 429, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 6. Get model configuration
    const { data: modelConfig } = await supabase
      .from('model_configs')
      .select('*')
      .eq('model', model)
      .eq('is_active', true)
      .single()

    if (!modelConfig) {
      return new Response(
        JSON.stringify({ error: 'Model not available' }), 
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 7. Get available API key
    const { data: apiKeyData, error: keyError } = await supabase.rpc('get_available_api_key', {
      p_provider: modelConfig.provider
    })

    if (keyError || !apiKeyData || apiKeyData.length === 0) {
      console.error('API key error:', keyError)
      return new Response(
        JSON.stringify({ error: 'No available API key' }), 
        { 
          status: 503, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    const apiKey = apiKeyData[0]
    const startTime = Date.now()

    // 8. Forward request to provider
    try {
      const providerResponse = await forwardToProvider({
        provider: modelConfig.provider,
        apiKey: apiKey.api_key,
        model: modelConfig.provider_model_id || model,
        messages,
        stream,
        temperature: temperature ?? modelConfig.default_temperature,
        max_tokens: max_tokens ?? modelConfig.max_tokens
      })

      if (!providerResponse.ok) {
        // Record API key error
        await supabase.rpc('record_api_key_error', {
          p_api_key_id: apiKey.id,
          p_error_message: `HTTP ${providerResponse.status}: ${providerResponse.statusText}`
        })
        
        const errorText = await providerResponse.text()
        return new Response(
          JSON.stringify({ 
            error: 'Provider API error', 
            details: errorText 
          }), 
          { 
            status: providerResponse.status, 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
          }
        )
      }

      // 9. Handle response based on streaming
      if (stream) {
        // For streaming, we need to intercept and count tokens
        return handleStreamResponse({
          response: providerResponse,
          userId: user.id,
          model,
          apiKeyId: apiKey.id,
          provider: modelConfig.provider,
          startTime,
          modelConfig,
          supabase
        })
      } else {
        // For non-streaming, parse and record usage
        const result = await providerResponse.json()
        const latency = Date.now() - startTime
        
        // Extract token usage based on provider
        const usage = extractUsage(result, modelConfig.provider)
        
        // Record usage
        await recordUsage({
          supabase,
          userId: user.id,
          model,
          provider: modelConfig.provider,
          apiKeyId: apiKey.id,
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          totalTokens: usage.totalTokens,
          cost: calculateCost(usage, modelConfig),
          latency,
          status: 'success'
        })

        // Record API key success
        await supabase.rpc('record_api_key_success', {
          p_api_key_id: apiKey.id,
          p_tokens_used: usage.totalTokens
        })

        return new Response(JSON.stringify(result), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }
    } catch (error) {
      // Record API key error
      await supabase.rpc('record_api_key_error', {
        p_api_key_id: apiKey.id,
        p_error_message: error.message
      })
      throw error
    }

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }), 
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})

// Forward request to different providers
async function forwardToProvider(params: any) {
  const { provider, apiKey, model, messages, stream, temperature, max_tokens } = params
  
  switch (provider) {
    case 'openai':
      return fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + apiKey
        },
        body: JSON.stringify({
          model,
          messages,
          stream,
          temperature,
          max_tokens
        })
      })
      
    case 'anthropic':
      // Transform messages format for Anthropic
      const anthropicMessages = messages
        .filter(m => m.role !== 'system')
        .map(m => ({
          role: m.role,
          content: m.content
        }))
      
      const systemMessage = messages.find(m => m.role === 'system')
      
      return fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01'
        },
        body: JSON.stringify({
          model,
          messages: anthropicMessages,
          ...(systemMessage && { system: systemMessage.content }),
          max_tokens: max_tokens || 4096,
          temperature,
          stream
        })
      })
      
    case 'google':
      // Transform for Gemini API
      // Convert messages to contents array format
      const geminiContents = messages
        .filter(m => m.role !== 'system')
        .map(m => ({
          role: m.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: m.content }]
        }))
      
      // Add system message to the first user message if exists
      const geminiSystemMessage = messages.find(m => m.role === 'system')
      if (geminiSystemMessage && geminiContents.length > 0 && geminiContents[0].role === 'user') {
        geminiContents[0].parts[0].text = geminiSystemMessage.content + '\n\n' + geminiContents[0].parts[0].text
      }
      
      // Use v1 API endpoint with streaming support
      const endpoint = stream ? 'streamGenerateContent' : 'generateContent'
      const geminiUrl = `https://generativelanguage.googleapis.com/v1/models/${model}:${endpoint}?key=${apiKey}${stream ? '&alt=sse' : ''}`
      
      return fetch(geminiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: geminiContents,
          generationConfig: {
            temperature: temperature || 1.0,
            maxOutputTokens: max_tokens || 8192,
            candidateCount: 1
          }
        })
      })
      
    default:
      throw new Error('Unsupported provider: ' + provider)
  }
}

// Handle streaming responses
async function handleStreamResponse(params: any) {
  const { response, userId, model, apiKeyId, provider, startTime, modelConfig, supabase } = params
  
  const encoder = new TextEncoder()
  const decoder = new TextDecoder()
  
  let totalTokens = 0
  let responseContent = ''
  
  // Create transform stream to intercept and forward
  const transformStream = new TransformStream({
    async transform(chunk, controller) {
      // Forward chunk to client
      controller.enqueue(chunk)
      
      // Decode and accumulate for token counting
      const text = decoder.decode(chunk, { stream: true })
      responseContent += text
    },
    
    async flush() {
      // Stream ended, record usage
      const latency = Date.now() - startTime
      
      // Estimate tokens (provider-specific parsing would be more accurate)
      const estimatedTokens = Math.ceil(responseContent.length / 4)
      const promptTokens = estimateTokens(params.messages || [])
      totalTokens = promptTokens + estimatedTokens
      
      // Send token usage info to client
      const usageData = {
        promptTokens,
        completionTokens: estimatedTokens,
        totalTokens,
        model: params.model,
        provider
      }
      
      controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'usage', usage: usageData })}\n\n`))
      
      // Record usage
      await recordUsage({
        supabase,
        userId,
        model,
        provider,
        apiKeyId,
        promptTokens,
        completionTokens: estimatedTokens,
        totalTokens,
        cost: calculateCost({
          promptTokens,
          completionTokens: estimatedTokens,
          totalTokens
        }, modelConfig),
        latency,
        status: 'success'
      })
      
      // Record API key success
      await supabase.rpc('record_api_key_success', {
        p_api_key_id: apiKeyId,
        p_tokens_used: totalTokens
      })
    }
  })
  
  return new Response(response.body.pipeThrough(transformStream), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    }
  })
}

// Estimate tokens for messages
function estimateTokens(messages: any[]): number {
  if (!messages || messages.length === 0) return 0
  
  const text = messages.map(m => m.content || '').join(' ')
  // Simple estimation: ~4 chars per token for English, ~2 for Chinese
  const englishChars = (text.match(/[a-zA-Z0-9\s]/g) || []).length
  const chineseChars = (text.match(/[\u4e00-\u9fa5]/g) || []).length
  
  return Math.ceil(englishChars / 4 + chineseChars / 2)
}

// Extract usage from provider response
function extractUsage(response: any, provider: string) {
  switch (provider) {
    case 'openai':
      return {
        promptTokens: response.usage?.prompt_tokens || 0,
        completionTokens: response.usage?.completion_tokens || 0,
        totalTokens: response.usage?.total_tokens || 0
      }
      
    case 'anthropic':
      return {
        promptTokens: response.usage?.input_tokens || 0,
        completionTokens: response.usage?.output_tokens || 0,
        totalTokens: (response.usage?.input_tokens || 0) + (response.usage?.output_tokens || 0)
      }
      
    case 'google':
      // Gemini doesn't provide token counts in response
      // Would need to estimate based on content
      return {
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0
      }
      
    default:
      return { promptTokens: 0, completionTokens: 0, totalTokens: 0 }
  }
}

// Calculate cost based on usage and model config
function calculateCost(usage: any, modelConfig: any): number {
  const promptCost = (usage.promptTokens / 1000000) * (modelConfig.input_price || 0)
  const completionCost = (usage.completionTokens / 1000000) * (modelConfig.output_price || 0)
  return promptCost + completionCost
}

// Record usage to database
async function recordUsage(params: any) {
  const { supabase, userId, model, provider, apiKeyId, promptTokens, completionTokens, totalTokens, cost, latency, status } = params
  
  // Insert usage log
  await supabase.from('usage_logs').insert({
    user_id: userId,
    model,
    provider,
    api_key_id: apiKeyId,
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
    estimated_cost: cost,
    latency_ms: latency,
    status
  })
  
  // Update user usage
  await supabase.rpc('update_user_usage', {
    p_user_id: userId,
    p_tokens: totalTokens,
    p_cost: cost
  })
}