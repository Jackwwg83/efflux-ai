# 🔄 API Aggregator Provider Design

## Overview

This design document outlines the implementation of an API aggregator provider system for Efflux AI, enabling integration with services like AiHubMix that provide unified access to multiple AI models through a single API endpoint.

## 🎯 Design Goals

1. **Unified Interface**: Single API key to access multiple AI models
2. **Provider Flexibility**: Support multiple aggregator services (AiHubMix, OpenRouter, etc.)
3. **Seamless Integration**: Minimal changes to existing chat infrastructure
4. **Cost Optimization**: Leverage aggregator's pricing and routing
5. **Model Discovery**: Dynamic model list from aggregator APIs

## 🏗️ Architecture

### System Components

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Frontend UI   │────▶│  Edge Function   │────▶│  Aggregator API │
│  (Provider UI)  │     │  (v1-chat)       │     │  (AiHubMix)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                        │                         │
         │                        │                         │
         ▼                        ▼                         ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Supabase DB    │     │  Provider Config │     │  Model Registry │
│  (providers)    │     │  (api_providers) │     │  (models cache) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### Data Flow

1. **Provider Setup**: User adds aggregator API key and selects provider type
2. **Model Discovery**: System fetches available models from aggregator
3. **Chat Request**: Frontend sends model name to Edge Function
4. **Provider Routing**: Edge Function determines if model uses aggregator
5. **API Translation**: Request formatted for aggregator's API standard
6. **Response Streaming**: Aggregator response streamed back to user

## 📊 Database Schema

### New Tables

```sql
-- API Provider Registry
CREATE TABLE api_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    provider_type TEXT NOT NULL, -- 'aggregator', 'direct'
    base_url TEXT NOT NULL,
    api_standard TEXT NOT NULL, -- 'openai', 'anthropic', 'custom'
    features JSONB DEFAULT '{}', -- supported features
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User API Provider Configurations
CREATE TABLE user_api_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users NOT NULL,
    provider_id UUID REFERENCES api_providers NOT NULL,
    api_key_encrypted TEXT NOT NULL,
    api_key_hash TEXT NOT NULL,
    endpoint_override TEXT, -- custom endpoint if needed
    settings JSONB DEFAULT '{}', -- provider-specific settings
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, provider_id)
);

-- Aggregator Model Registry
CREATE TABLE aggregator_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID REFERENCES api_providers NOT NULL,
    model_id TEXT NOT NULL,
    model_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    model_type TEXT NOT NULL, -- 'chat', 'image', 'audio', 'embedding'
    capabilities JSONB DEFAULT '{}',
    pricing JSONB DEFAULT '{}', -- input/output token costs
    context_window INTEGER,
    max_tokens INTEGER,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    is_available BOOLEAN DEFAULT true,
    UNIQUE(provider_id, model_id)
);

-- Model Usage Analytics
CREATE TABLE aggregator_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users NOT NULL,
    provider_id UUID REFERENCES api_providers NOT NULL,
    model_id TEXT NOT NULL,
    request_id TEXT,
    tokens_used INTEGER,
    cost_estimate DECIMAL(10, 6),
    latency_ms INTEGER,
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Initial Provider Data

```sql
-- Insert AiHubMix as first aggregator
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features)
VALUES (
    'aihubmix',
    'AiHubMix',
    'aggregator',
    'https://api.aihubmix.com/v1',
    'openai',
    '{
        "supports_streaming": true,
        "supports_functions": true,
        "supports_vision": true,
        "supports_audio": true,
        "supports_embeddings": true,
        "model_list_endpoint": "/models",
        "requires_model_prefix": false
    }'::jsonb
);

-- Insert OpenRouter as another aggregator option
INSERT INTO api_providers (name, display_name, provider_type, base_url, api_standard, features)
VALUES (
    'openrouter',
    'OpenRouter',
    'aggregator',
    'https://openrouter.ai/api/v1',
    'openai',
    '{
        "supports_streaming": true,
        "supports_functions": true,
        "supports_vision": true,
        "requires_referer": true,
        "model_list_endpoint": "/models"
    }'::jsonb
);
```

## 🎨 UI Design

### Provider Management Page

```typescript
// New route: /settings/providers
interface ProviderManagementProps {
  providers: APIProvider[]
  userProviders: UserAPIProvider[]
}

// Components needed:
1. ProviderList - Show available aggregators
2. ProviderCard - Individual provider with features
3. AddProviderModal - Add new provider configuration
4. ModelExplorer - Browse available models per provider
5. UsageStats - Show usage per provider
```

### UI Flow

```
Settings → API Providers
├── Available Providers
│   ├── AiHubMix [Add]
│   ├── OpenRouter [Add]
│   └── Custom Provider [Configure]
├── Active Providers
│   └── AiHubMix
│       ├── API Key: ****mix_123
│       ├── Models: 150+ available
│       ├── Usage: $12.34 this month
│       └── [Manage] [Remove]
└── Model Explorer
    ├── Search models
    ├── Filter by type
    └── Model details
```

## 🔧 Implementation Details

### 1. Provider Integration Layer

```typescript
// lib/ai/providers/aggregator-client.ts
interface AggregatorProvider {
  name: string
  fetchModels(): Promise<Model[]>
  formatRequest(request: ChatRequest): any
  parseResponse(response: any): ChatResponse
  validateApiKey(apiKey: string): Promise<boolean>
}

class AiHubMixProvider implements AggregatorProvider {
  async fetchModels() {
    const response = await fetch(`${this.baseUrl}/models`, {
      headers: { 'Authorization': `Bearer ${this.apiKey}` }
    })
    return this.parseModels(response)
  }
  
  formatRequest(request: ChatRequest) {
    // AiHubMix uses OpenAI format directly
    return {
      model: request.model,
      messages: request.messages,
      stream: request.stream,
      temperature: request.temperature,
      max_tokens: request.maxTokens
    }
  }
}
```

### 2. Edge Function Updates

```typescript
// supabase/functions/v1-chat/index.ts
async function getModelProvider(model: string, userId: string) {
  // Check if model belongs to an aggregator
  const { data: aggregatorModel } = await supabase
    .from('aggregator_models')
    .select('*, api_providers(*)')
    .eq('model_id', model)
    .single()
  
  if (aggregatorModel) {
    // Get user's API key for this aggregator
    const { data: userProvider } = await supabase
      .from('user_api_providers')
      .select('*')
      .eq('user_id', userId)
      .eq('provider_id', aggregatorModel.provider_id)
      .single()
    
    return {
      type: 'aggregator',
      provider: aggregatorModel.api_providers,
      apiKey: await decryptApiKey(userProvider.api_key_encrypted),
      endpoint: userProvider.endpoint_override || aggregatorModel.api_providers.base_url
    }
  }
  
  // Fall back to direct provider logic
  return getDirectProvider(model, userId)
}
```

### 3. Model Sync Service

```typescript
// lib/services/model-sync.ts
export async function syncAggregatorModels(providerId: string, apiKey: string) {
  const provider = await getProviderConfig(providerId)
  const client = createAggregatorClient(provider, apiKey)
  
  try {
    const models = await client.fetchModels()
    
    // Upsert models to database
    for (const model of models) {
      await supabase
        .from('aggregator_models')
        .upsert({
          provider_id: providerId,
          model_id: model.id,
          model_name: model.name,
          display_name: model.display_name || model.name,
          model_type: model.type || 'chat',
          capabilities: model.capabilities || {},
          pricing: model.pricing || {},
          context_window: model.context_length,
          max_tokens: model.max_tokens,
          is_available: true,
          last_updated: new Date()
        })
    }
    
    return { success: true, count: models.length }
  } catch (error) {
    console.error('Model sync failed:', error)
    return { success: false, error: error.message }
  }
}
```

### 4. Frontend Model Selector Update

```typescript
// components/chat/model-selector.tsx
export function ModelSelector({ onModelChange, currentModel }) {
  const [providers, setProviders] = useState<GroupedModels>({})
  
  useEffect(() => {
    loadAvailableModels()
  }, [])
  
  async function loadAvailableModels() {
    // Load direct provider models (existing)
    const directModels = await getDirectModels()
    
    // Load aggregator models
    const { data: aggregatorModels } = await supabase
      .from('aggregator_models')
      .select('*, api_providers(*)')
      .eq('is_available', true)
      .order('display_name')
    
    // Group by provider
    const grouped = groupModelsByProvider([
      ...directModels,
      ...aggregatorModels
    ])
    
    setProviders(grouped)
  }
  
  return (
    <Select value={currentModel} onValueChange={onModelChange}>
      <SelectTrigger>
        <SelectValue placeholder="Select model" />
      </SelectTrigger>
      <SelectContent>
        {Object.entries(providers).map(([provider, models]) => (
          <SelectGroup key={provider}>
            <SelectLabel>{provider}</SelectLabel>
            {models.map(model => (
              <SelectItem key={model.id} value={model.id}>
                <div className="flex items-center gap-2">
                  <span>{model.display_name}</span>
                  {model.is_aggregator && (
                    <Badge variant="secondary" className="text-xs">
                      via {model.provider_name}
                    </Badge>
                  )}
                </div>
              </SelectItem>
            ))}
          </SelectGroup>
        ))}
      </SelectContent>
    </Select>
  )
}
```

## 🚀 Implementation Plan

### Phase 1: Database & Backend (Week 1)
1. Create database migrations for new tables
2. Implement provider configuration API
3. Update Edge Function for aggregator routing
4. Add model sync functionality

### Phase 2: Frontend Integration (Week 2)
1. Create provider management UI
2. Update model selector component
3. Add provider-specific settings
4. Implement usage tracking

### Phase 3: Testing & Optimization (Week 3)
1. Test with AiHubMix integration
2. Add support for OpenRouter
3. Performance optimization
4. Error handling improvements

### Phase 4: Advanced Features (Week 4)
1. Cost tracking and budgets
2. Model recommendation engine
3. Provider fallback logic
4. Usage analytics dashboard

## 🔒 Security Considerations

1. **API Key Encryption**: Use same encryption as existing system
2. **Provider Validation**: Verify provider endpoints before use
3. **Rate Limiting**: Respect aggregator rate limits
4. **Usage Monitoring**: Track unusual usage patterns
5. **Secure Headers**: Hide sensitive headers from client

## 📈 Benefits

1. **Model Variety**: Access 100+ models with single integration
2. **Cost Savings**: Leverage aggregator's volume pricing
3. **Simplified Management**: One API key for multiple providers
4. **Reliability**: Automatic failover between providers
5. **Future-Proof**: Easy to add new aggregators

## 🎯 Success Metrics

1. Number of aggregator providers integrated
2. Models available through aggregators
3. User adoption rate of aggregator providers
4. Cost reduction compared to direct APIs
5. System reliability and uptime

---

This design provides a flexible foundation for integrating API aggregators while maintaining compatibility with existing direct provider integrations.