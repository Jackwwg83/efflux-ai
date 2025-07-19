import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Model sync configuration
const SYNC_CONFIG = {
  // How often to sync (in hours)
  syncInterval: 24,
  
  // Providers to sync
  providers: ['openai', 'anthropic', 'google']
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Check if this is a manual trigger or scheduled run
    const { manual = false } = await req.json().catch(() => ({}))
    
    // Check last sync time if not manual
    if (!manual) {
      const { data: lastSync } = await supabase
        .from('system_settings')
        .select('value')
        .eq('key', 'last_model_sync')
        .single()
      
      if (lastSync) {
        const lastSyncTime = new Date(lastSync.value)
        const hoursSinceSync = (Date.now() - lastSyncTime.getTime()) / (1000 * 60 * 60)
        
        if (hoursSinceSync < SYNC_CONFIG.syncInterval) {
          return new Response(
            JSON.stringify({ 
              message: 'Sync not needed yet',
              lastSync: lastSync.value,
              nextSync: new Date(lastSyncTime.getTime() + SYNC_CONFIG.syncInterval * 60 * 60 * 1000)
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }
    }

    // Get API keys for each provider
    const { data: apiKeys } = await supabase
      .from('api_key_pool')
      .select('provider, api_key')
      .in('provider', SYNC_CONFIG.providers)
      .eq('is_active', true)
    
    if (!apiKeys || apiKeys.length === 0) {
      throw new Error('No API keys found for model sync')
    }

    const results = {
      openai: { success: false, models: [], error: null },
      anthropic: { success: false, models: [], error: null },
      google: { success: false, models: [], error: null }
    }

    // Sync each provider
    for (const provider of SYNC_CONFIG.providers) {
      const apiKey = apiKeys.find(k => k.provider === provider)?.api_key
      if (!apiKey) {
        results[provider].error = 'No API key found'
        continue
      }

      try {
        switch (provider) {
          case 'openai':
            results.openai = await syncOpenAIModels(apiKey, supabase)
            break
          case 'anthropic':
            results.anthropic = await syncAnthropicModels(apiKey, supabase)
            break
          case 'google':
            results.google = await syncGoogleModels(apiKey, supabase)
            break
        }
      } catch (error) {
        results[provider].error = error.message
      }
    }

    // Update last sync time
    await supabase
      .from('system_settings')
      .upsert({
        key: 'last_model_sync',
        value: new Date().toISOString(),
        updated_at: new Date().toISOString()
      })

    // Log sync results
    await supabase
      .from('sync_logs')
      .insert({
        sync_type: 'models',
        results,
        triggered_by: manual ? 'manual' : 'scheduled',
        created_at: new Date().toISOString()
      })

    return new Response(
      JSON.stringify({ 
        message: 'Model sync completed',
        results 
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Sync error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})

// Sync OpenAI models
async function syncOpenAIModels(apiKey: string, supabase: any) {
  const response = await fetch('https://api.openai.com/v1/models', {
    headers: {
      'Authorization': `Bearer ${apiKey}`
    }
  })

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status}`)
  }

  const data = await response.json()
  const models = data.data.filter((model: any) => 
    model.id.includes('gpt') || model.id.includes('o1')
  )

  const syncedModels = []
  
  for (const model of models) {
    const modelConfig = {
      provider: 'openai',
      model: model.id,
      provider_model_id: model.id,
      display_name: formatModelName(model.id),
      // OpenAI doesn't provide these in API, use defaults
      max_tokens: model.id.includes('gpt-4') ? 4096 : 16384,
      context_window: 128000,
      input_price: getOpenAIPricing(model.id).input,
      output_price: getOpenAIPricing(model.id).output,
      supports_streaming: true,
      supports_functions: model.id.includes('gpt'),
      is_active: true,
      tier_required: model.id.includes('gpt-4') ? 'pro' : 'free'
    }

    const { error } = await supabase
      .from('model_configs')
      .upsert(modelConfig, { onConflict: 'model' })
    
    if (!error) {
      syncedModels.push(model.id)
    }
  }

  return { success: true, models: syncedModels }
}

// Sync Anthropic models
async function syncAnthropicModels(apiKey: string, supabase: any) {
  // Anthropic doesn't have a models endpoint, so we use a predefined list
  // that we update periodically based on their documentation
  const anthropicModels = [
    {
      id: 'claude-3-5-sonnet-latest',
      name: 'Claude 3.5 Sonnet',
      context: 200000,
      maxTokens: 8192,
      inputPrice: 0.003,
      outputPrice: 0.015
    },
    {
      id: 'claude-3-5-haiku-latest',
      name: 'Claude 3.5 Haiku',
      context: 200000,
      maxTokens: 8192,
      inputPrice: 0.0008,
      outputPrice: 0.004
    },
    {
      id: 'claude-3-opus-latest',
      name: 'Claude 3 Opus',
      context: 200000,
      maxTokens: 4096,
      inputPrice: 0.015,
      outputPrice: 0.075
    }
  ]

  const syncedModels = []

  for (const model of anthropicModels) {
    const modelConfig = {
      provider: 'anthropic',
      model: model.id.replace('-latest', ''),
      provider_model_id: model.id,
      display_name: model.name,
      max_tokens: model.maxTokens,
      context_window: model.context,
      input_price: model.inputPrice,
      output_price: model.outputPrice,
      supports_streaming: true,
      supports_functions: true,
      is_active: true,
      tier_required: model.id.includes('opus') ? 'pro' : 'free'
    }

    const { error } = await supabase
      .from('model_configs')
      .upsert(modelConfig, { onConflict: 'model' })
    
    if (!error) {
      syncedModels.push(model.id)
    }
  }

  return { success: true, models: syncedModels }
}

// Sync Google models
async function syncGoogleModels(apiKey: string, supabase: any) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1/models?key=${apiKey}`
  )

  if (!response.ok) {
    throw new Error(`Google API error: ${response.status}`)
  }

  const data = await response.json()
  const models = data.models.filter((model: any) => 
    model.supportedGenerationMethods?.includes('generateContent') &&
    model.name.includes('gemini')
  )

  const syncedModels = []

  for (const model of models) {
    const modelId = model.name.replace('models/', '')
    
    // Skip deprecated models
    if (model.description?.toLowerCase().includes('deprecated')) {
      continue
    }

    const modelConfig = {
      provider: 'google',
      model: modelId,
      provider_model_id: modelId,
      display_name: model.displayName,
      max_tokens: model.outputTokenLimit || 8192,
      context_window: model.inputTokenLimit || 1048576,
      input_price: getGooglePricing(modelId).input,
      output_price: getGooglePricing(modelId).output,
      supports_streaming: model.supportedGenerationMethods.includes('streamGenerateContent'),
      supports_functions: true,
      is_active: true,
      tier_required: modelId.includes('pro') ? 'pro' : 'free',
      // Store additional metadata
      description: model.description,
      version: model.version
    }

    const { error } = await supabase
      .from('model_configs')
      .upsert(modelConfig, { onConflict: 'model' })
    
    if (!error) {
      syncedModels.push(modelId)
    }
  }

  // Mark models not in the API response as inactive
  const { data: existingModels } = await supabase
    .from('model_configs')
    .select('model')
    .eq('provider', 'google')
    .eq('is_active', true)

  if (existingModels) {
    const modelsToDeactivate = existingModels
      .filter(m => !syncedModels.includes(m.model))
      .map(m => m.model)
    
    if (modelsToDeactivate.length > 0) {
      await supabase
        .from('model_configs')
        .update({ is_active: false })
        .in('model', modelsToDeactivate)
    }
  }

  return { success: true, models: syncedModels }
}

// Helper functions
function formatModelName(modelId: string): string {
  return modelId
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}

function getOpenAIPricing(modelId: string) {
  const pricing = {
    'gpt-4o': { input: 0.005, output: 0.015 },
    'gpt-4o-mini': { input: 0.00015, output: 0.0006 },
    'gpt-4-turbo': { input: 0.01, output: 0.03 },
    'gpt-3.5-turbo': { input: 0.0005, output: 0.0015 },
    'o1-preview': { input: 0.015, output: 0.06 },
    'o1-mini': { input: 0.003, output: 0.012 }
  }
  
  return pricing[modelId] || { input: 0.001, output: 0.002 }
}

function getGooglePricing(modelId: string) {
  const pricing = {
    'gemini-2.5-pro': { input: 0.00125, output: 0.005 },
    'gemini-2.5-flash': { input: 0.000075, output: 0.0003 },
    'gemini-2.0-flash': { input: 0.000075, output: 0.0003 },
    'gemini-2.0-flash-lite': { input: 0.00005, output: 0.00015 },
    'gemini-1.5-pro': { input: 0.00125, output: 0.005 },
    'gemini-1.5-flash': { input: 0.000075, output: 0.0003 },
    'gemini-1.5-flash-8b': { input: 0.000037, output: 0.00015 }
  }
  
  return pricing[modelId] || { input: 0.0001, output: 0.0002 }
}