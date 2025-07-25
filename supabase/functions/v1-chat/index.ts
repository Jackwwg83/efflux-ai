import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { UnifiedModelRouter } from './unified-router.ts'

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

    // Initialize unified router
    const router = new UnifiedModelRouter(
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
      const { data: presetData, error: presetError } = await supabase.rpc('get_preset_for_conversation', {
        p_conversation_id: conversationId,
        p_user_id: user.id
      })
      
      if (!presetError && presetData && presetData.length > 0) {
        const preset = presetData[0]
        if (preset.system_prompt) {
          // Ensure system message is at the beginning
          finalMessages = [
            { role: 'system', content: preset.system_prompt },
            ...messages.filter((m: any) => m.role !== 'system')
          ]
        }
      }
    }

    // Use unified router to get optimal provider
    const startTime = Date.now()
    
    try {
      // Get optimal route for the model
      const route = await router.getOptimalRoute(model, user.id)
      
      // Forward request using unified router
      const providerResponse = await router.forwardRequest({
        route,
        model,
        messages: finalMessages,
        stream,
        temperature,
        max_tokens
      })

      // Handle response based on streaming
      if (stream) {
        // For streaming, we need to intercept and count tokens
        return handleUnifiedStreamResponse({
          response: providerResponse,
          userId: user.id,
          model,
          route,
          startTime,
          supabase,
          router,
          messages: finalMessages
        })
      } else {
        // For non-streaming, parse and record usage
        const result = await providerResponse.json()
        const latency = Date.now() - startTime
        
        // Extract token usage
        const usage = {
          promptTokens: result.usage?.prompt_tokens || 0,
          completionTokens: result.usage?.completion_tokens || 0,
          totalTokens: result.usage?.total_tokens || 0
        }
        
        // Record usage through unified router
        await router.recordUsage({
          userId: user.id,
          modelId: model,
          sourceId: route.source.source_id,
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          latency,
          status: 'success'
        })

        return new Response(JSON.stringify(result), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }
    } catch (error) {
      // Let unified router handle provider errors
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

// Handle streaming responses with unified router
async function handleUnifiedStreamResponse(params: any) {
  const { response, userId, model, route, startTime, supabase, router, messages } = params
  
  const encoder = new TextEncoder()
  const decoder = new TextDecoder()
  
  let totalTokens = 0
  let responseContent = ''
  let usageData: any = null
  
  const stream = new ReadableStream({
    async start(controller) {
      const reader = response.body.getReader()
      
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          
          // Forward the chunk to client
          controller.enqueue(value)
          
          // Decode and parse for token counting
          const chunk = decoder.decode(value)
          const lines = chunk.split('\n')
          
          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6)
              if (data === '[DONE]') continue
              
              try {
                const parsed = JSON.parse(data)
                
                // Accumulate content for token counting
                if (parsed.choices?.[0]?.delta?.content) {
                  responseContent += parsed.choices[0].delta.content
                }
                
                // Extract usage if provided
                if (parsed.usage) {
                  usageData = parsed.usage
                }
              } catch (e) {
                // Ignore parse errors
              }
            }
          }
        }
        
        // Estimate tokens if not provided
        if (!usageData) {
          // Simple estimation: ~4 characters per token
          const promptTokens = JSON.stringify(messages).length / 4
          const completionTokens = responseContent.length / 4
          totalTokens = Math.round(promptTokens + completionTokens)
          
          usageData = {
            prompt_tokens: Math.round(promptTokens),
            completion_tokens: Math.round(completionTokens),
            total_tokens: totalTokens
          }
        }
        
        // Record usage through unified router
        const latency = Date.now() - startTime
        await router.recordUsage({
          userId,
          modelId: model,
          sourceId: route.source.source_id,
          promptTokens: usageData.prompt_tokens,
          completionTokens: usageData.completion_tokens,
          latency,
          status: 'success'
        })
        
      } catch (error) {
        console.error('Stream processing error:', error)
        controller.error(error)
      } finally {
        controller.close()
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