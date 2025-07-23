import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'

dotenv.config({ path: '.env.production' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
)

const aggregatorProviders = [
  {
    name: 'aihubmix',
    display_name: 'AiHubMix',
    provider_type: 'aggregator',
    base_url: 'https://api.aihubmix.com/v1',
    api_standard: 'openai',
    features: {
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      model_list_endpoint: '/models',
      header_format: 'Bearer'
    }
  },
  {
    name: 'openrouter',
    display_name: 'OpenRouter',
    provider_type: 'aggregator',
    base_url: 'https://openrouter.ai/api/v1',
    api_standard: 'openai',
    features: {
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      model_list_endpoint: '/models',
      header_format: 'Bearer',
      requires_referer: true,
      requires_site_name: true
    }
  },
  {
    name: 'novitaai',
    display_name: 'NovitaAI',
    provider_type: 'aggregator',
    base_url: 'https://api.novita.ai/v3/openai',
    api_standard: 'openai',
    features: {
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      model_list_endpoint: '/models',
      header_format: 'Bearer'
    }
  },
  {
    name: 'siliconflow',
    display_name: 'Siliconflow',
    provider_type: 'aggregator',
    base_url: 'https://api.siliconflow.cn/v1',
    api_standard: 'openai',
    features: {
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      model_list_endpoint: '/models',
      header_format: 'Bearer'
    }
  },
  {
    name: 'togetherai',
    display_name: 'TogetherAI',
    provider_type: 'aggregator',
    base_url: 'https://api.together.xyz/v1',
    api_standard: 'openai',
    features: {
      supports_streaming: true,
      supports_functions: true,
      supports_vision: false,
      model_list_endpoint: '/models',
      header_format: 'Bearer'
    }
  }
]

async function addAggregators() {
  for (const provider of aggregatorProviders) {
    console.log(`Adding ${provider.display_name}...`)
    
    const { error } = await supabase
      .from('api_providers')
      .upsert(provider, { onConflict: 'name' })
    
    if (error) {
      console.error(`Error adding ${provider.display_name}:`, error)
    } else {
      console.log(`✓ Added ${provider.display_name}`)
    }
  }
}

addAggregators()
  .then(() => console.log('Done!'))
  .catch(console.error)