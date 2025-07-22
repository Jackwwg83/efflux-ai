# 📋 API Aggregator Implementation Plan

## Overview

Step-by-step implementation guide for adding API aggregator provider support to Efflux AI, enabling integration with services like AiHubMix.

## 📅 Timeline: 4 Weeks

### Week 1: Backend Foundation

#### Day 1-2: Database Setup
- [ ] Run migration: `20250122_api_aggregator_provider.sql`
- [ ] Verify tables and indexes created
- [ ] Test RLS policies
- [ ] Insert initial provider data

#### Day 3-4: Provider Client Library
```typescript
// lib/ai/providers/aggregator-provider.ts
interface AggregatorProvider {
  name: string
  fetchModels(): Promise<Model[]>
  createChatCompletion(request: ChatRequest): Promise<Response>
  validateApiKey(apiKey: string): Promise<boolean>
}

// lib/ai/providers/aihubmix-provider.ts
export class AiHubMixProvider implements AggregatorProvider {
  // Implementation
}
```

#### Day 5: Edge Function Updates
- [ ] Update `v1-chat` function to support aggregators
- [ ] Add provider routing logic
- [ ] Test streaming with AiHubMix API

### Week 2: Frontend Integration

#### Day 1-2: Provider Management UI
```typescript
// app/(dashboard)/settings/providers/page.tsx
- Provider list page
- Add provider modal
- Provider configuration form

// components/providers/provider-card.tsx
- Display provider info
- Show available models count
- Usage statistics
```

#### Day 3-4: Model Selector Updates
- [ ] Update `ModelSelector` component
- [ ] Add provider badges
- [ ] Group models by provider
- [ ] Show aggregator indicator

#### Day 5: API Key Management
- [ ] Encryption/decryption utilities
- [ ] Secure storage in Supabase
- [ ] Key validation UI

### Week 3: Integration & Testing

#### Day 1-2: Model Sync Service
```typescript
// app/api/sync-models/route.ts
- Scheduled model sync
- Manual sync trigger
- Error handling

// lib/services/model-sync-service.ts
- Fetch models from aggregator
- Update database
- Handle removed models
```

#### Day 3-4: Testing Suite
- [ ] Unit tests for provider clients
- [ ] Integration tests with mock API
- [ ] E2E tests for full flow
- [ ] Load testing with multiple providers

#### Day 5: Error Handling
- [ ] Provider-specific error codes
- [ ] Fallback mechanisms
- [ ] User-friendly error messages

### Week 4: Polish & Advanced Features

#### Day 1-2: Usage Analytics
```typescript
// components/providers/usage-dashboard.tsx
- Token usage charts
- Cost breakdown
- Model popularity
- Performance metrics
```

#### Day 3-4: Cost Management
- [ ] Budget alerts
- [ ] Usage limits
- [ ] Cost estimation
- [ ] Provider comparison

#### Day 5: Documentation
- [ ] User guide for providers
- [ ] API documentation updates
- [ ] Migration guide
- [ ] Troubleshooting guide

## 🛠️ Technical Implementation Details

### 1. Database Operations

```typescript
// lib/db/providers.ts
export async function addUserProvider(
  userId: string,
  providerId: string,
  apiKey: string,
  settings?: any
) {
  const encrypted = await encryptApiKey(apiKey)
  const hash = await hashApiKey(apiKey)
  
  return supabase
    .from('user_api_providers')
    .insert({
      user_id: userId,
      provider_id: providerId,
      api_key_encrypted: encrypted,
      api_key_hash: hash,
      settings
    })
}

export async function getUserProviders(userId: string) {
  return supabase
    .from('user_api_providers')
    .select(`
      *,
      api_providers (*)
    `)
    .eq('user_id', userId)
    .eq('is_active', true)
}
```

### 2. API Client Implementation

```typescript
// lib/ai/providers/base-aggregator.ts
export abstract class BaseAggregatorProvider {
  constructor(
    protected config: APIProviderConfig,
    protected apiKey: string
  ) {}
  
  protected async makeRequest(
    endpoint: string,
    body: any,
    stream = false
  ): Promise<Response> {
    return fetch(`${this.config.base_url}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
        ...this.getAdditionalHeaders()
      },
      body: JSON.stringify(body)
    })
  }
  
  abstract getAdditionalHeaders(): Record<string, string>
}
```

### 3. UI Components Structure

```
app/(dashboard)/settings/providers/
├── page.tsx                    # Main providers page
├── loading.tsx                 # Loading skeleton
└── components/
    ├── provider-list.tsx      # List of providers
    ├── add-provider-modal.tsx # Add new provider
    ├── provider-details.tsx   # Provider config
    └── model-explorer.tsx     # Browse models

components/providers/
├── provider-card.tsx          # Provider display card
├── usage-stats.tsx           # Usage statistics
├── cost-tracker.tsx          # Cost monitoring
└── model-search.tsx          # Model search/filter
```

### 4. Edge Function Integration

```typescript
// supabase/functions/v1-chat/providers.ts
export async function routeToProvider(
  model: string,
  userId: string,
  request: ChatCompletionRequest
): Promise<Response> {
  // Check aggregator models first
  const providerConfig = await getModelProviderConfig(model, userId)
  
  if (providerConfig?.provider_type === 'aggregator') {
    const client = createAggregatorClient(
      providerConfig.provider_name,
      providerConfig.api_key_encrypted,
      providerConfig.base_url
    )
    
    return client.createChatCompletion(request)
  }
  
  // Fall back to direct providers
  return routeToDirectProvider(model, userId, request)
}
```

## 🧪 Testing Strategy

### Unit Tests
```typescript
// __tests__/providers/aihubmix.test.ts
describe('AiHubMixProvider', () => {
  it('should fetch models successfully', async () => {
    const provider = new AiHubMixProvider(config, 'test-key')
    const models = await provider.fetchModels()
    expect(models).toHaveLength(150)
  })
  
  it('should handle streaming responses', async () => {
    // Test streaming
  })
})
```

### Integration Tests
- Mock API responses
- Test error scenarios
- Validate response parsing
- Check rate limiting

### E2E Tests
- Full user flow
- Add provider → Select model → Send message
- Verify billing/usage tracking

## 🚀 Deployment Steps

1. **Database Migration**
   ```bash
   npx supabase db push
   ```

2. **Deploy Edge Functions**
   ```bash
   npm run deploy:functions
   ```

3. **Frontend Deployment**
   ```bash
   git push origin main
   # Vercel auto-deploys
   ```

4. **Feature Flag (Optional)**
   ```typescript
   // Enable gradually
   const AGGREGATOR_ENABLED = process.env.NEXT_PUBLIC_FEATURE_AGGREGATOR === 'true'
   ```

## 📊 Success Metrics

1. **Technical Metrics**
   - API response time <500ms
   - Model sync success rate >99%
   - Zero downtime deployment

2. **User Metrics**
   - Provider adoption rate
   - Models used via aggregators
   - Cost savings achieved

3. **Business Metrics**
   - New user signups
   - User retention improvement
   - Revenue impact

## 🔄 Rollback Plan

1. **Database Rollback**
   ```sql
   -- Disable aggregator features
   UPDATE api_providers SET is_active = false WHERE provider_type = 'aggregator';
   ```

2. **Code Rollback**
   - Feature flag to disable
   - Revert git commits
   - Keep database tables (no data loss)

## 📝 Post-Launch Tasks

1. **Monitoring**
   - Set up alerts for API failures
   - Track usage patterns
   - Monitor costs

2. **Optimization**
   - Cache model lists
   - Optimize database queries
   - Improve UI performance

3. **User Feedback**
   - Collect feature feedback
   - Address pain points
   - Plan improvements

---

This implementation plan provides a structured approach to adding API aggregator support while maintaining system stability and user experience.