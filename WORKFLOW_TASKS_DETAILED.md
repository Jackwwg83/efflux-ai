# 📝 API Aggregator - Detailed Task Breakdown

## Epic 1: Database & Backend Foundation

### Story 1.1: Database Migration and Setup
**Estimated Time**: 8 hours  
**Dependencies**: None  
**Risk**: Low  

#### Task 1.1.1: Prepare Migration Environment
**Time**: 1 hour  
**Assignee**: Backend Developer  
```bash
# Actions:
1. Create database backup
   - Production: pg_dump production_db > backup_$(date +%Y%m%d).sql
   - Staging: pg_dump staging_db > backup_staging.sql

2. Review migration file
   - Check SQL syntax
   - Verify table relationships
   - Validate RLS policies

3. Set up rollback plan
   - Prepare rollback script
   - Document rollback procedure
```

#### Task 1.1.2: Execute Database Migration
**Time**: 2 hours  
**Assignee**: Backend Developer  
```sql
-- Run migration
npx supabase db push

-- Verify tables created
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('api_providers', 'user_api_providers', 
                   'aggregator_models', 'aggregator_usage_logs');

-- Test RLS policies
-- As authenticated user
SELECT * FROM api_providers WHERE is_active = true;
```

#### Task 1.1.3: Seed Initial Data
**Time**: 1 hour  
**Assignee**: Backend Developer  
```sql
-- Verify providers inserted
SELECT * FROM api_providers;

-- Test helper functions
SELECT * FROM get_user_available_models('test-user-id');
SELECT * FROM get_model_provider_config('gpt-4', 'test-user-id');
```

### Story 1.2: Provider Client Implementation
**Estimated Time**: 16 hours  
**Dependencies**: Database ready  
**Risk**: Medium  

#### Task 1.2.1: Base Aggregator Class
**Time**: 4 hours  
**Assignee**: Backend Developer  
```typescript
// lib/ai/providers/aggregator/base-aggregator.ts
export abstract class BaseAggregatorProvider {
  protected config: APIProviderConfig
  protected apiKey: string
  protected baseUrl: string
  
  constructor(config: APIProviderConfig, apiKey: string) {
    this.config = config
    this.apiKey = apiKey
    this.baseUrl = config.base_url
  }
  
  // Abstract methods
  abstract fetchModels(): Promise<AggregatorModel[]>
  abstract createChatCompletion(request: ChatRequest): Promise<Response>
  abstract validateApiKey(): Promise<boolean>
  abstract formatError(error: any): APIError
  
  // Common methods
  protected async makeRequest(
    endpoint: string,
    options: RequestInit
  ): Promise<Response> {
    const url = `${this.baseUrl}${endpoint}`
    
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
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
  
  protected abstract getAdditionalHeaders(): Record<string, string>
  protected abstract handleErrorResponse(response: Response): Promise<Error>
}
```

#### Task 1.2.2: AiHubMix Provider Implementation
**Time**: 6 hours  
**Assignee**: Backend Developer  
```typescript
// lib/ai/providers/aggregator/aihubmix-provider.ts
import { BaseAggregatorProvider } from './base-aggregator'

export class AiHubMixProvider extends BaseAggregatorProvider {
  async fetchModels(): Promise<AggregatorModel[]> {
    const response = await this.makeRequest('/models', {
      method: 'GET'
    })
    
    const data = await response.json()
    return this.mapModelsToSchema(data.data)
  }
  
  async createChatCompletion(request: ChatRequest): Promise<Response> {
    // AiHubMix uses OpenAI-compatible format
    const body = {
      model: request.model,
      messages: request.messages,
      temperature: request.temperature,
      max_tokens: request.maxTokens,
      stream: request.stream ?? true,
      top_p: request.topP,
      frequency_penalty: request.frequencyPenalty,
      presence_penalty: request.presencePenalty
    }
    
    return this.makeRequest('/chat/completions', {
      method: 'POST',
      body: JSON.stringify(body)
    })
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
  
  protected getAdditionalHeaders(): Record<string, string> {
    return {
      'X-Provider': 'aihubmix'
    }
  }
  
  private mapModelsToSchema(models: any[]): AggregatorModel[] {
    return models.map(model => ({
      model_id: model.id,
      model_name: model.id,
      display_name: model.name || model.id,
      model_type: this.inferModelType(model.id),
      capabilities: {
        vision: model.id.includes('vision') || model.id.includes('4o'),
        functions: !model.id.includes('instruct'),
        streaming: true
      },
      context_window: model.context_length || 8192,
      max_output_tokens: model.max_tokens || 4096,
      pricing: {
        input: model.pricing?.prompt || 0,
        output: model.pricing?.completion || 0
      }
    }))
  }
  
  private inferModelType(modelId: string): string {
    if (modelId.includes('embed')) return 'embedding'
    if (modelId.includes('tts')) return 'audio'
    if (modelId.includes('dall-e') || modelId.includes('image')) return 'image'
    return 'chat'
  }
}
```

#### Task 1.2.3: Provider Factory Pattern
**Time**: 3 hours  
**Assignee**: Backend Developer  
```typescript
// lib/ai/providers/aggregator/provider-factory.ts
export class AggregatorProviderFactory {
  private static providers = new Map<string, typeof BaseAggregatorProvider>()
  
  static {
    // Register providers
    this.register('aihubmix', AiHubMixProvider)
    this.register('openrouter', OpenRouterProvider)
  }
  
  static register(name: string, provider: typeof BaseAggregatorProvider) {
    this.providers.set(name, provider)
  }
  
  static create(
    providerName: string, 
    config: APIProviderConfig, 
    apiKey: string
  ): BaseAggregatorProvider {
    const Provider = this.providers.get(providerName)
    if (!Provider) {
      throw new Error(`Unknown provider: ${providerName}`)
    }
    
    return new Provider(config, apiKey)
  }
  
  static async validateProvider(
    providerName: string,
    config: APIProviderConfig,
    apiKey: string
  ): Promise<boolean> {
    try {
      const provider = this.create(providerName, config, apiKey)
      return await provider.validateApiKey()
    } catch {
      return false
    }
  }
}
```

#### Task 1.2.4: Integration Tests
**Time**: 3 hours  
**Assignee**: Backend Developer  
```typescript
// __tests__/providers/aihubmix.test.ts
describe('AiHubMixProvider', () => {
  let provider: AiHubMixProvider
  
  beforeEach(() => {
    provider = new AiHubMixProvider(mockConfig, 'test-key')
  })
  
  describe('fetchModels', () => {
    it('should fetch and map models correctly', async () => {
      // Mock fetch response
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockModels })
      })
      
      const models = await provider.fetchModels()
      
      expect(models).toHaveLength(mockModels.length)
      expect(models[0]).toHaveProperty('model_id')
      expect(models[0]).toHaveProperty('capabilities')
    })
  })
  
  describe('createChatCompletion', () => {
    it('should format request correctly', async () => {
      const request: ChatRequest = {
        model: 'gpt-4',
        messages: [{ role: 'user', content: 'Hello' }],
        temperature: 0.7
      }
      
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        body: mockStreamResponse()
      })
      
      await provider.createChatCompletion(request)
      
      expect(fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            'Authorization': 'Bearer test-key'
          })
        })
      )
    })
  })
})
```

### Story 1.3: Edge Function Enhancement
**Estimated Time**: 8 hours  
**Dependencies**: Provider clients ready  
**Risk**: High  

#### Task 1.3.1: Update Request Routing
**Time**: 4 hours  
**Assignee**: Backend Developer  
```typescript
// supabase/functions/v1-chat/index.ts
async function handleChatRequest(req: Request) {
  const { messages, model, ...params } = await req.json()
  const userId = getUserId(req)
  
  // Check if model uses aggregator
  const providerConfig = await getModelProviderConfig(model, userId)
  
  if (providerConfig?.provider_type === 'aggregator') {
    return handleAggregatorRequest(
      providerConfig,
      { messages, model, ...params },
      userId
    )
  }
  
  // Existing direct provider logic
  return handleDirectProviderRequest({ messages, model, ...params }, userId)
}

async function handleAggregatorRequest(
  config: ProviderConfig,
  request: ChatRequest,
  userId: string
): Promise<Response> {
  try {
    // Decrypt API key
    const apiKey = await decryptApiKey(config.api_key_encrypted)
    
    // Create provider instance
    const provider = AggregatorProviderFactory.create(
      config.provider_name,
      config,
      apiKey
    )
    
    // Make request
    const response = await provider.createChatCompletion(request)
    
    // Log usage asynchronously
    logAggregatorUsage(userId, config.provider_id, request.model, response)
    
    return response
  } catch (error) {
    console.error('Aggregator request failed:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
}
```

#### Task 1.3.2: Usage Tracking Implementation
**Time**: 2 hours  
**Assignee**: Backend Developer  
```typescript
// supabase/functions/v1-chat/usage-tracking.ts
async function logAggregatorUsage(
  userId: string,
  providerId: string,
  model: string,
  response: Response
) {
  try {
    // Parse usage from response headers or body
    const usage = await extractUsageMetrics(response)
    
    await supabase.from('aggregator_usage_logs').insert({
      user_id: userId,
      provider_id: providerId,
      model_id: model,
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      total_tokens: usage.total_tokens,
      cost_estimate: calculateCost(model, usage),
      latency_ms: usage.latency,
      status: 'success',
      metadata: {
        request_id: response.headers.get('x-request-id'),
        finish_reason: usage.finish_reason
      }
    })
  } catch (error) {
    console.error('Usage tracking failed:', error)
    // Don't throw - usage tracking should not break the request
  }
}

function calculateCost(model: string, usage: UsageMetrics): number {
  // Get model pricing from cache or database
  const pricing = getModelPricing(model)
  
  const inputCost = (usage.prompt_tokens / 1000) * pricing.input
  const outputCost = (usage.completion_tokens / 1000) * pricing.output
  
  return inputCost + outputCost
}
```

#### Task 1.3.3: Deployment and Testing
**Time**: 2 hours  
**Assignee**: DevOps + Backend  
```bash
# Build and test locally
npm run build:functions
npm run test:functions

# Deploy to staging
npx supabase functions deploy v1-chat --project-ref staging

# Test with curl
curl -X POST https://staging.supabase.co/functions/v1/v1-chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-opus-20240229",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": true
  }'

# Deploy to production
npx supabase functions deploy v1-chat --project-ref production
```

## Epic 2: Frontend Implementation

### Story 2.1: Provider Management UI
**Estimated Time**: 12 hours  
**Dependencies**: Backend API ready  
**Risk**: Low  

#### Task 2.1.1: Provider List Page
**Time**: 4 hours  
**Assignee**: Frontend Developer  
```typescript
// app/(dashboard)/settings/providers/page.tsx
import { ProviderList } from './components/provider-list'
import { ActiveProviders } from './components/active-providers'

export default async function ProvidersPage() {
  const supabase = createServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  
  // Fetch available providers
  const { data: providers } = await supabase
    .from('api_providers')
    .select('*')
    .eq('is_active', true)
    .order('display_name')
  
  // Fetch user's configured providers
  const { data: userProviders } = await supabase
    .from('user_api_providers')
    .select('*, api_providers(*)')
    .eq('user_id', user.id)
  
  return (
    <div className="container max-w-4xl py-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold">API Providers</h1>
        <p className="text-muted-foreground mt-2">
          Connect AI model aggregators to access hundreds of models with a single API key
        </p>
      </div>
      
      <div className="space-y-8">
        <section>
          <h2 className="text-xl font-semibold mb-4">Active Providers</h2>
          <ActiveProviders providers={userProviders} />
        </section>
        
        <section>
          <h2 className="text-xl font-semibold mb-4">Available Providers</h2>
          <ProviderList 
            providers={providers} 
            userProviders={userProviders}
          />
        </section>
      </div>
    </div>
  )
}
```

#### Task 2.1.2: Provider Card Component
**Time**: 3 hours  
**Assignee**: Frontend Developer  
```typescript
// components/providers/provider-card.tsx
interface ProviderCardProps {
  provider: APIProvider
  isConfigured?: boolean
  onAdd?: () => void
  onManage?: () => void
}

export function ProviderCard({ 
  provider, 
  isConfigured, 
  onAdd, 
  onManage 
}: ProviderCardProps) {
  const features = provider.features as ProviderFeatures
  
  return (
    <Card className="p-6">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-primary/20 to-primary/10 flex items-center justify-center">
            <Globe className="w-6 h-6 text-primary" />
          </div>
          
          <div>
            <h3 className="font-semibold text-lg">{provider.display_name}</h3>
            <p className="text-sm text-muted-foreground">
              {provider.provider_type === 'aggregator' ? 'API Aggregator' : 'Direct Provider'}
            </p>
          </div>
        </div>
        
        <div className="flex items-center gap-2">
          {isConfigured ? (
            <>
              <Badge variant="success">Active</Badge>
              <Button size="sm" variant="outline" onClick={onManage}>
                Manage
              </Button>
            </>
          ) : (
            <Button size="sm" onClick={onAdd}>
              <Plus className="w-4 h-4 mr-2" />
              Add
            </Button>
          )}
        </div>
      </div>
      
      <div className="mt-6 grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <p className="text-sm font-medium">Supported Features</p>
          <div className="flex flex-wrap gap-2">
            {features.supports_streaming && (
              <Badge variant="secondary" className="text-xs">Streaming</Badge>
            )}
            {features.supports_vision && (
              <Badge variant="secondary" className="text-xs">Vision</Badge>
            )}
            {features.supports_functions && (
              <Badge variant="secondary" className="text-xs">Functions</Badge>
            )}
            {features.supports_audio && (
              <Badge variant="secondary" className="text-xs">Audio</Badge>
            )}
          </div>
        </div>
        
        <div className="space-y-2">
          <p className="text-sm font-medium">API Standard</p>
          <Badge>{provider.api_standard.toUpperCase()}</Badge>
        </div>
      </div>
      
      {provider.documentation_url && (
        <div className="mt-4">
          <a
            href={provider.documentation_url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm text-primary hover:underline flex items-center gap-1"
          >
            View Documentation
            <ExternalLink className="w-3 h-3" />
          </a>
        </div>
      )}
    </Card>
  )
}
```

#### Task 2.1.3: Add Provider Modal
**Time**: 5 hours  
**Assignee**: Frontend Developer  
```typescript
// components/providers/add-provider-modal.tsx
export function AddProviderModal({ 
  provider, 
  open, 
  onOpenChange 
}: AddProviderModalProps) {
  const [apiKey, setApiKey] = useState('')
  const [isValidating, setIsValidating] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { toast } = useToast()
  
  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setIsValidating(true)
    
    try {
      // Validate API key
      const isValid = await validateProviderApiKey(provider.id, apiKey)
      
      if (!isValid) {
        throw new Error('Invalid API key. Please check and try again.')
      }
      
      // Encrypt and save
      const { error: saveError } = await saveProviderConfig(
        provider.id,
        apiKey
      )
      
      if (saveError) throw saveError
      
      toast({
        title: 'Provider added successfully',
        description: `You can now use ${provider.display_name} models`
      })
      
      onOpenChange(false)
      router.refresh()
    } catch (err) {
      setError(err.message)
    } finally {
      setIsValidating(false)
    }
  }
  
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Add {provider.display_name}</DialogTitle>
          <DialogDescription>
            Enter your API key to start using {provider.display_name} models
          </DialogDescription>
        </DialogHeader>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="api-key">API Key</Label>
            <div className="relative">
              <Input
                id="api-key"
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="sk-..."
                required
              />
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="absolute right-2 top-1/2 -translate-y-1/2"
                onClick={() => {
                  const input = document.getElementById('api-key') as HTMLInputElement
                  input.type = input.type === 'password' ? 'text' : 'password'
                }}
              >
                <Eye className="w-4 h-4" />
              </Button>
            </div>
            
            {provider.name === 'aihubmix' && (
              <p className="text-xs text-muted-foreground">
                Get your API key from{' '}
                <a
                  href="https://aihubmix.com/token"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:underline"
                >
                  AiHubMix Dashboard
                </a>
              </p>
            )}
          </div>
          
          {error && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          
          <DialogFooter className="flex gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={!apiKey || isValidating}>
              {isValidating ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Validating...
                </>
              ) : (
                'Add Provider'
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
```

### Story 2.2: Model Integration
**Estimated Time**: 8 hours  
**Dependencies**: Provider UI complete  
**Risk**: Medium  

#### Task 2.2.1: Update Model Selector
**Time**: 4 hours  
**Assignee**: Frontend Developer  
```typescript
// components/chat/model-selector.tsx
export function ModelSelector({ value, onChange }: ModelSelectorProps) {
  const [models, setModels] = useState<GroupedModels>({})
  const [isLoading, setIsLoading] = useState(true)
  
  useEffect(() => {
    loadAvailableModels()
  }, [])
  
  async function loadAvailableModels() {
    try {
      // Get user's available models (includes aggregator models)
      const { data: availableModels } = await supabase
        .rpc('get_user_available_models', {
          p_user_id: (await supabase.auth.getUser()).data.user?.id
        })
      
      // Group by provider
      const grouped = availableModels.reduce((acc, model) => {
        const provider = model.provider_name
        if (!acc[provider]) acc[provider] = []
        acc[provider].push(model)
        return acc
      }, {} as GroupedModels)
      
      setModels(grouped)
    } catch (error) {
      console.error('Failed to load models:', error)
    } finally {
      setIsLoading(false)
    }
  }
  
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-[300px]">
        <SelectValue placeholder="Select a model">
          {value && (
            <div className="flex items-center gap-2">
              <span>{getModelDisplayName(value, models)}</span>
              {isAggregatorModel(value, models) && (
                <Badge variant="secondary" className="text-xs ml-auto">
                  via {getModelProvider(value, models)}
                </Badge>
              )}
            </div>
          )}
        </SelectValue>
      </SelectTrigger>
      
      <SelectContent>
        {isLoading ? (
          <div className="p-4 text-center text-sm text-muted-foreground">
            Loading models...
          </div>
        ) : (
          Object.entries(models).map(([provider, providerModels]) => (
            <SelectGroup key={provider}>
              <SelectLabel className="flex items-center gap-2">
                {provider}
                {isAggregatorProvider(provider) && (
                  <Badge variant="outline" className="text-xs">
                    Aggregator
                  </Badge>
                )}
              </SelectLabel>
              
              {providerModels.map((model) => (
                <SelectItem key={model.model_id} value={model.model_id}>
                  <div className="flex items-center justify-between w-full">
                    <span>{model.display_name}</span>
                    <div className="flex items-center gap-2 ml-4">
                      {model.context_window && (
                        <span className="text-xs text-muted-foreground">
                          {formatTokenCount(model.context_window)} ctx
                        </span>
                      )}
                      {model.is_aggregator && (
                        <Badge variant="secondary" className="text-xs">
                          External
                        </Badge>
                      )}
                    </div>
                  </div>
                </SelectItem>
              ))}
            </SelectGroup>
          ))
        )}
      </SelectContent>
    </Select>
  )
}
```

#### Task 2.2.2: Model Sync UI
**Time**: 4 hours  
**Assignee**: Frontend Developer  
```typescript
// components/providers/model-sync-button.tsx
export function ModelSyncButton({ providerId }: { providerId: string }) {
  const [isSyncing, setIsSyncing] = useState(false)
  const { toast } = useToast()
  
  async function handleSync() {
    setIsSyncing(true)
    
    try {
      const response = await fetch('/api/sync-models', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ providerId })
      })
      
      if (!response.ok) {
        throw new Error('Sync failed')
      }
      
      const result = await response.json()
      
      toast({
        title: 'Models synced successfully',
        description: `Updated ${result.count} models`
      })
      
      // Refresh the page to show new models
      router.refresh()
    } catch (error) {
      toast({
        title: 'Sync failed',
        description: error.message,
        variant: 'destructive'
      })
    } finally {
      setIsSyncing(false)
    }
  }
  
  return (
    <Button
      size="sm"
      variant="outline"
      onClick={handleSync}
      disabled={isSyncing}
    >
      {isSyncing ? (
        <>
          <Loader2 className="w-4 h-4 mr-2 animate-spin" />
          Syncing...
        </>
      ) : (
        <>
          <RefreshCw className="w-4 h-4 mr-2" />
          Sync Models
        </>
      )}
    </Button>
  )
}
```

## Epic 3: Advanced Features

### Story 3.1: Usage Analytics
**Estimated Time**: 8 hours  
**Dependencies**: Core features complete  
**Risk**: Low  

#### Task 3.1.1: Usage Dashboard Component
**Time**: 6 hours  
**Assignee**: Frontend Developer  
```typescript
// components/providers/usage-dashboard.tsx
export function UsageDashboard({ providerId }: { providerId: string }) {
  const [timeRange, setTimeRange] = useState<'day' | 'week' | 'month'>('week')
  const [usage, setUsage] = useState<UsageData | null>(null)
  
  useEffect(() => {
    loadUsageData()
  }, [providerId, timeRange])
  
  async function loadUsageData() {
    const startDate = getStartDate(timeRange)
    
    const { data } = await supabase
      .from('aggregator_usage_logs')
      .select('*')
      .eq('provider_id', providerId)
      .gte('created_at', startDate.toISOString())
      .order('created_at', { ascending: true })
    
    const processed = processUsageData(data)
    setUsage(processed)
  }
  
  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">
              Total Tokens
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">
              {formatNumber(usage?.totalTokens || 0)}
            </p>
          </CardContent>
        </Card>
        
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">
              Total Cost
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">
              ${usage?.totalCost?.toFixed(2) || '0.00'}
            </p>
          </CardContent>
        </Card>
        
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">
              Requests
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">
              {formatNumber(usage?.requestCount || 0)}
            </p>
          </CardContent>
        </Card>
        
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">
              Avg Latency
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">
              {usage?.avgLatency || 0}ms
            </p>
          </CardContent>
        </Card>
      </div>
      
      {/* Usage Chart */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle>Usage Over Time</CardTitle>
            <Select value={timeRange} onValueChange={setTimeRange}>
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="day">24 Hours</SelectItem>
                <SelectItem value="week">7 Days</SelectItem>
                <SelectItem value="month">30 Days</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          <UsageChart data={usage?.chartData || []} />
        </CardContent>
      </Card>
      
      {/* Model Breakdown */}
      <Card>
        <CardHeader>
          <CardTitle>Model Usage</CardTitle>
        </CardHeader>
        <CardContent>
          <ModelUsageTable data={usage?.modelBreakdown || []} />
        </CardContent>
      </Card>
    </div>
  )
}
```

#### Task 3.1.2: Cost Tracking
**Time**: 2 hours  
**Assignee**: Backend Developer  
```typescript
// app/api/usage-stats/route.ts
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const providerId = searchParams.get('provider_id')
  const startDate = searchParams.get('start_date')
  const endDate = searchParams.get('end_date')
  
  const supabase = createRouteClient()
  const { data: { user } } = await supabase.auth.getUser()
  
  if (!user) {
    return new Response('Unauthorized', { status: 401 })
  }
  
  // Get usage data with cost calculations
  const { data, error } = await supabase
    .rpc('calculate_provider_costs', {
      p_user_id: user.id,
      p_provider_id: providerId,
      p_start_date: startDate,
      p_end_date: endDate
    })
  
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
  
  return new Response(JSON.stringify(data), {
    headers: { 'Content-Type': 'application/json' }
  })
}
```

## Milestone Validation Checklist

### Week 1 Complete ✓
- [ ] Database migration successful
- [ ] All tables and functions operational
- [ ] Provider client library tested
- [ ] Edge function routing works
- [ ] Can make successful API calls to AiHubMix

### Week 2 Complete ✓
- [ ] Provider management UI functional
- [ ] Users can add/remove providers
- [ ] Model selector shows aggregator models
- [ ] API key encryption working
- [ ] Models sync from aggregator

### Week 3 Complete ✓
- [ ] All unit tests passing
- [ ] Integration tests complete
- [ ] Production deployment ready
- [ ] Monitoring configured
- [ ] Documentation updated

### Week 4 Complete ✓
- [ ] Usage analytics dashboard live
- [ ] Cost tracking accurate
- [ ] Advanced features operational
- [ ] User documentation published
- [ ] Feature fully launched

---

*This detailed task breakdown ensures every aspect of the API Aggregator feature is implemented systematically with clear ownership and dependencies.*