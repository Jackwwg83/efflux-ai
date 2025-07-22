import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get auth token from request
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('No authorization header')
    }

    // Verify user
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    
    if (authError || !user) {
      throw new Error('Unauthorized')
    }

    // Parse request body
    const { model, messages, stream = true, temperature, max_tokens, conversationId } = await req.json()

    if (!model || !messages) {
      throw new Error('Missing required parameters: model and messages')
    }

    // Get preset configuration if conversationId is provided
    let finalMessages = messages
    if (conversationId) {
      const { data: presetData } = await supabase.rpc('get_preset_for_conversation', {
        p_conversation_id: conversationId,
        p_user_id: user.id
      })
      
      if (presetData && presetData.system_prompt) {
        // Ensure system message is at the beginning
        finalMessages = [
          { role: 'system', content: presetData.system_prompt },
          ...messages.filter((m: any) => m.role !== 'system')
        ]
      }
    }

    // Get model configuration
    const { data: modelConfig, error: modelError } = await supabase
      .from('model_configs')
      .select('*')
      .eq('model', model)
      .eq('is_active', true)
      .single()

    if (modelError || !modelConfig) {
      throw new Error('Model not found or not active')
    }

    // Get available API key using the RPC function
    const { data: apiKeyData, error: apiKeyError } = await supabase.rpc('get_available_api_key', {
      p_provider: modelConfig.provider
    })

    if (apiKeyError || !apiKeyData || apiKeyData.length === 0) {
      console.error('API key error:', apiKeyError)
      throw new Error(`No available API key for provider: ${modelConfig.provider}`)
    }

    const apiKey = apiKeyData[0]

    const startTime = Date.now()

    try {
      // Forward request to provider
      const providerResponse = await forwardToProvider({
        provider: modelConfig.provider,
        apiKey: apiKey.api_key,
        model,
        messages: finalMessages,
        stream,
        temperature,
        max_tokens
      })

      // Handle response based on streaming
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
          supabase,
          messages: finalMessages
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
      // Convert messages format for Anthropic
      const anthropicMessages = messages
        .filter((m: any) => m.role !== 'system')
        .map((m: any) => ({
          role: m.role,
          content: m.content
        }))
      
      const systemMessage = messages.find((m: any) => m.role === 'system')
      
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
          system: systemMessage?.content,
          stream,
          temperature,
          max_tokens: max_tokens || 4096
        })
      })
      
    case 'google':
      // Convert messages for Google format
      const googleMessages = messages.map((m: any) => ({
        role: m.role === 'assistant' ? 'model' : m.role,
        parts: [{ text: m.content }]
      }))
      
      return fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?key=${apiKey}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: messages.map((m: any) => ({
            role: m.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: m.content }]
          })),
          generationConfig: {
            temperature: temperature || 0.7,
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
  const { response, userId, model, apiKeyId, provider, startTime, modelConfig, supabase, messages } = params
  
  const encoder = new TextEncoder()
  const decoder = new TextDecoder()
  
  let totalTokens = 0
  let responseContent = ''
  let usageData: any = null
  
  // Create a new readable stream that processes the provider's stream
  const stream = new ReadableStream({
    async start(controller) {
      const reader = response.body.getReader()
      
      try {
        while (true) {
          const { done, value } = await reader.read()
          
          if (done) {
            // Stream ended - send usage data and [DONE] signal
            const latency = Date.now() - startTime
            
            // Estimate tokens if we don't have actual usage
            if (!usageData) {
              const estimatedTokens = Math.ceil(responseContent.length / 4)
              const promptTokens = estimateTokens(messages || [])
              totalTokens = promptTokens + estimatedTokens
              
              usageData = {
                promptTokens,
                completionTokens: estimatedTokens,
                totalTokens,
                model,
                provider
              }
            }
            
            // Send usage data
            controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'usage', usage: usageData })}\n\n`))
            
            // Send [DONE] signal
            controller.enqueue(encoder.encode('data: [DONE]\n\n'))
            
            // Record usage in database
            await recordUsage({
              supabase,
              userId,
              model,
              provider,
              apiKeyId,
              promptTokens: usageData.promptTokens,
              completionTokens: usageData.completionTokens,
              totalTokens: usageData.totalTokens,
              cost: calculateCost(usageData, modelConfig),
              latency,
              status: 'success'
            })
            
            // Record API key success
            await supabase.rpc('record_api_key_success', {
              p_api_key_id: apiKeyId,
              p_tokens_used: usageData.totalTokens
            })
            
            controller.close()
            break
          }
          
          // Forward the chunk to client
          controller.enqueue(value)
          
          // Decode and accumulate for token counting
          const text = decoder.decode(value, { stream: true })
          responseContent += text
          
          // Try to parse usage from the stream (some providers include it)
          // This is provider-specific parsing
          if (provider === 'openai' && text.includes('"usage"')) {
            try {
              const lines = text.split('\n')
              for (const line of lines) {
                if (line.startsWith('data: ') && line.includes('"usage"')) {
                  const data = JSON.parse(line.slice(6))
                  if (data.usage) {
                    usageData = {
                      promptTokens: data.usage.prompt_tokens || 0,
                      completionTokens: data.usage.completion_tokens || 0,
                      totalTokens: data.usage.total_tokens || 0,
                      model,
                      provider
                    }
                  }
                }
              }
            } catch (e) {
              // Ignore parsing errors
            }
          }
        }
      } catch (error) {
        console.error('Stream processing error:', error)
        controller.error(error)
      }
    }
  })
  
  return new Response(stream, {
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
      return {
        promptTokens: response.usageMetadata?.promptTokenCount || 0,
        completionTokens: response.usageMetadata?.candidatesTokenCount || 0,
        totalTokens: response.usageMetadata?.totalTokenCount || 0
      }
      
    default:
      return {
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0
      }
  }
}

// Calculate cost based on usage and model config
function calculateCost(usage: any, modelConfig: any): number {
  const promptCost = (usage.promptTokens / 1000) * (modelConfig.input_cost_per_1k || 0)
  const completionCost = (usage.completionTokens / 1000) * (modelConfig.output_cost_per_1k || 0)
  return promptCost + completionCost
}

// Record usage to database
async function recordUsage(params: any) {
  const { supabase, userId, model, provider, apiKeyId, promptTokens, completionTokens, totalTokens, cost, latency, status } = params
  
  try {
    // Record in token_usage table
    await supabase
      .from('token_usage')
      .insert({
        user_id: userId,
        model,
        provider,
        api_key_id: apiKeyId,
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
        total_tokens: totalTokens,
        cost,
        latency,
        status
      })
    
    // Update user usage
    await supabase.rpc('update_user_usage', {
      p_user_id: userId,
      p_tokens: totalTokens,
      p_cost: cost
    })
  } catch (error) {
    console.error('Error recording usage:', error)
  }
}