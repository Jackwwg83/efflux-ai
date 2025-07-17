import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { corsHeaders } from '../_shared/cors.ts'
import { GoogleProvider } from '../_shared/providers/google.ts'
import { OpenAIProvider } from '../_shared/providers/openai.ts'
import { AnthropicProvider } from '../_shared/providers/anthropic.ts'
import { BedrockProvider } from '../_shared/providers/bedrock.ts'

interface ChatRequest {
  message: string
  model: string
  conversationId?: string
  stream?: boolean
}

interface TokenUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

const TIER_LIMITS = {
  free: {
    daily_tokens: 5000,
    rate_limit: 5,
    models: ['gemini-2.5-flash', 'gpt-4o-mini', 'claude-3.5-haiku']
  },
  pro: {
    daily_tokens: 500000,
    rate_limit: 30,
    models: [
      'gemini-2.5-flash',
      'gpt-4o-mini', 
      'claude-3.5-haiku',
      'gpt-4o',
      'claude-3.5-sonnet'
    ]
  },
  max: {
    daily_tokens: 5000000,
    rate_limit: 100,
    models: '*'
  }
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get auth token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Verify user
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Parse request
    const { message, model, conversationId, stream = true }: ChatRequest = await req.json()

    // Get user tier and check credits
    const { data: userTier, error: tierError } = await supabase
      .from('user_tiers')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (tierError || !userTier) {
      return new Response(JSON.stringify({ error: 'User tier not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Check credits
    if (userTier.credits_balance <= 0) {
      return new Response(JSON.stringify({ error: 'Insufficient credits' }), {
        status: 402,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Check model access
    const allowedModels = TIER_LIMITS[userTier.tier as keyof typeof TIER_LIMITS].models
    if (allowedModels !== '*' && !allowedModels.includes(model)) {
      return new Response(JSON.stringify({ error: 'Model not allowed for your tier' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get model configuration
    const { data: modelConfig } = await supabase
      .from('model_configs')
      .select('*')
      .eq('model', model)
      .eq('is_active', true)
      .single()

    if (!modelConfig) {
      return new Response(JSON.stringify({ error: 'Model not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get API key for provider
    const { data: apiKeyData } = await supabase
      .from('api_keys')
      .select('api_key')
      .eq('provider', modelConfig.provider)
      .eq('is_active', true)
      .single()

    if (!apiKeyData) {
      return new Response(JSON.stringify({ error: 'API key not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get conversation history if conversationId provided
    let messages = []
    if (conversationId) {
      const { data: conversationMessages } = await supabase
        .from('messages')
        .select('role, content')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
        .limit(10) // Last 10 messages for context

      if (conversationMessages) {
        messages = conversationMessages.map(msg => ({
          role: msg.role,
          content: msg.content
        }))
      }
    }

    // Add current message
    messages.push({ role: 'user', content: message })

    // Call appropriate provider
    let provider
    switch (modelConfig.provider) {
      case 'google':
        provider = new GoogleProvider(apiKeyData.api_key)
        break
      case 'openai':
        provider = new OpenAIProvider(apiKeyData.api_key)
        break
      case 'anthropic':
        provider = new AnthropicProvider(apiKeyData.api_key)
        break
      case 'bedrock':
        provider = new BedrockProvider(
          Deno.env.get('AWS_ACCESS_KEY_ID')!,
          Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
          Deno.env.get('AWS_REGION')!
        )
        break
      default:
        return new Response(JSON.stringify({ error: 'Provider not supported' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }

    // If streaming is requested
    if (stream) {
      const encoder = new TextEncoder()
      const streamResponse = new TransformStream()
      const writer = streamResponse.writable.getWriter()

      // Start streaming in background
      (async () => {
        try {
          let totalTokens = 0
          let promptTokens = 0
          let completionTokens = 0
          let fullContent = ''

          const stream = await provider.streamChat(model, messages, {
            max_tokens: modelConfig.max_tokens,
            temperature: 0.7
          })

          for await (const chunk of stream) {
            fullContent += chunk.content || ''
            
            // Send chunk to client
            await writer.write(encoder.encode(`data: ${JSON.stringify({
              type: 'content',
              content: chunk.content
            })}\n\n`))

            // Update token counts if provided
            if (chunk.usage) {
              promptTokens = chunk.usage.prompt_tokens || promptTokens
              completionTokens = chunk.usage.completion_tokens || completionTokens
              totalTokens = chunk.usage.total_tokens || totalTokens
            }
          }

          // Calculate cost
          const cost = (promptTokens * modelConfig.input_price / 1000000) + 
                      (completionTokens * modelConfig.output_price / 1000000)

          // Deduct credits
          const { data: deductResult } = await supabase.rpc('deduct_credits', {
            p_user_id: user.id,
            p_tokens: totalTokens,
            p_cost: cost
          })

          // Save message to database if conversation exists
          if (conversationId && deductResult) {
            // Save user message
            await supabase.from('messages').insert({
              conversation_id: conversationId,
              role: 'user',
              content: message,
              model: model,
              provider: modelConfig.provider
            })

            // Save assistant message
            const { data: assistantMsg } = await supabase.from('messages').insert({
              conversation_id: conversationId,
              role: 'assistant',
              content: fullContent,
              model: model,
              provider: modelConfig.provider,
              prompt_tokens: promptTokens,
              completion_tokens: completionTokens,
              total_tokens: totalTokens
            }).select().single()

            // Log usage
            await supabase.from('usage_logs').insert({
              user_id: user.id,
              conversation_id: conversationId,
              message_id: assistantMsg?.id,
              model: model,
              provider: modelConfig.provider,
              prompt_tokens: promptTokens,
              completion_tokens: completionTokens,
              total_tokens: totalTokens,
              cost: cost
            })

            // Update conversation
            await supabase.from('conversations').update({
              last_message_at: new Date().toISOString(),
              updated_at: new Date().toISOString()
            }).eq('id', conversationId)
          }

          // Send completion signal
          await writer.write(encoder.encode(`data: ${JSON.stringify({
            type: 'done',
            usage: {
              prompt_tokens: promptTokens,
              completion_tokens: completionTokens,
              total_tokens: totalTokens
            }
          })}\n\n`))

        } catch (error) {
          await writer.write(encoder.encode(`data: ${JSON.stringify({
            type: 'error',
            error: error.message
          })}\n\n`))
        } finally {
          await writer.close()
        }
      })()

      return new Response(streamResponse.readable, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        }
      })
    } else {
      // Non-streaming response
      const response = await provider.chat(model, messages, {
        max_tokens: modelConfig.max_tokens,
        temperature: 0.7
      })

      // Calculate cost and deduct credits
      const cost = (response.usage.prompt_tokens * modelConfig.input_price / 1000000) + 
                  (response.usage.completion_tokens * modelConfig.output_price / 1000000)

      await supabase.rpc('deduct_credits', {
        p_user_id: user.id,
        p_tokens: response.usage.total_tokens,
        p_cost: cost
      })

      return new Response(JSON.stringify({
        content: response.content,
        usage: response.usage
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

  } catch (error) {
    console.error('Chat function error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})