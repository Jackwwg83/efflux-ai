# 🔌 Efflux AI - API Documentation

## Overview

Efflux AI provides a unified API gateway for interacting with multiple AI providers through Supabase Edge Functions. All API calls require authentication via Supabase JWT tokens.

## Base URL

```
Production: https://lzvwduadnunbtxqaqhkg.supabase.co/functions/v1
```

## Authentication

All API requests must include a valid Supabase JWT token:

```typescript
headers: {
  'Authorization': 'Bearer <supabase_jwt_token>',
  'Content-Type': 'application/json'
}
```

## Endpoints

### 1. Chat Completion API

#### `POST /v1-chat`

Generate AI responses using various models.

**Request Body:**

```typescript
{
  // Required
  messages: Array<{
    role: 'system' | 'user' | 'assistant'
    content: string
  }>
  
  // Required - Model selection
  model: string  // e.g., 'gpt-4', 'claude-3-opus', 'gemini-pro'
  
  // Optional parameters
  temperature?: number      // 0.0 - 2.0, default: 0.7
  max_tokens?: number       // Max response length
  stream?: boolean          // Enable streaming, default: true
  top_p?: number           // Nucleus sampling
  frequency_penalty?: number // -2.0 to 2.0
  presence_penalty?: number  // -2.0 to 2.0
  
  // Preset system (optional)
  presetId?: string        // UUID of user preset
}
```

**Response (Streaming):**

When `stream: true` (default), returns Server-Sent Events:

```
data: {"id":"msg_123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"msg_123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

data: [DONE]
```

**Response (Non-streaming):**

When `stream: false`:

```json
{
  "id": "msg_123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-4",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I help you today?"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 15,
    "total_tokens": 25
  }
}
```

**Error Response:**

```json
{
  "error": {
    "message": "Error description",
    "type": "invalid_request_error",
    "code": "model_not_found"
  }
}
```

### 2. Model Information

#### Supported Models

**OpenAI Models:**
- `gpt-4-turbo-preview` - Latest GPT-4 Turbo
- `gpt-4` - GPT-4 
- `gpt-3.5-turbo` - GPT-3.5 Turbo
- `gpt-3.5-turbo-16k` - GPT-3.5 with 16k context

**Anthropic Models:**
- `claude-3-opus-20240229` - Claude 3 Opus
- `claude-3-sonnet-20240229` - Claude 3 Sonnet
- `claude-3-haiku-20240307` - Claude 3 Haiku

**Google Models:**
- `gemini-pro` - Gemini Pro
- `gemini-pro-vision` - Gemini Pro with vision

**AWS Bedrock Models:**
- `anthropic.claude-v2` - Claude 2
- `amazon.titan-text-express-v1` - Amazon Titan

**Azure OpenAI Models:**
- Deployment-specific names configured in settings

### 3. Usage & Quotas

#### Get User Quota Status

This is handled client-side via Supabase RPC:

```typescript
const { data } = await supabase.rpc('get_user_quota_status', {
  p_user_id: userId
})

// Response
{
  is_admin: boolean
  tier: 'free' | 'pro' | 'max'
  daily_tokens_used: number
  daily_tokens_limit: number
  monthly_tokens_used: number
  monthly_tokens_limit: number
  can_use: boolean
  quota_percentage: number
}
```

## Rate Limits

Rate limits are enforced based on user tier:

| Tier | Requests/min | Daily Tokens | Monthly Tokens |
|------|--------------|--------------|----------------|
| Free | 5 | 10,000 | 100,000 |
| Pro | 20 | 100,000 | 2,000,000 |
| Max | 60 | 500,000 | 10,000,000 |

## Error Codes

| Code | Description |
|------|-------------|
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid or missing token |
| 403 | Forbidden - Quota exceeded |
| 404 | Not Found - Model not available |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |
| 503 | Service Unavailable - Provider API down |

## Client SDK Usage

### TypeScript/JavaScript

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

// Chat completion with streaming
async function chat() {
  const { data: { session } } = await supabase.auth.getSession()
  
  const response = await fetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/v1-chat`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session?.access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          { role: 'user', content: 'Hello!' }
        ],
        model: 'gpt-3.5-turbo',
        stream: true
      })
    }
  )
  
  // Handle streaming response
  const reader = response.body?.getReader()
  const decoder = new TextDecoder()
  
  while (true) {
    const { done, value } = await reader!.read()
    if (done) break
    
    const chunk = decoder.decode(value)
    const lines = chunk.split('\n')
    
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const data = line.slice(6)
        if (data === '[DONE]') {
          console.log('Stream complete')
          break
        }
        
        try {
          const parsed = JSON.parse(data)
          console.log(parsed.choices[0].delta.content)
        } catch (e) {
          // Handle parsing error
        }
      }
    }
  }
}
```

### Using with Presets

```typescript
// First, fetch user's presets
const { data: presets } = await supabase
  .from('user_presets')
  .select('*')
  .eq('is_active', true)

// Use preset in chat
const response = await fetch('/functions/v1/v1-chat', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    messages: [{ role: 'user', content: 'Hello' }],
    model: 'gpt-4',
    presetId: presets[0].id  // Use first active preset
  })
})
```

## Best Practices

### 1. Token Management
- Monitor token usage to avoid hitting quotas
- Implement client-side quota checking before requests
- Use appropriate `max_tokens` to control costs

### 2. Error Handling
```typescript
try {
  const response = await fetch(...)
  
  if (!response.ok) {
    const error = await response.json()
    switch (response.status) {
      case 403:
        // Handle quota exceeded
        alert('Daily quota exceeded. Please upgrade or wait.')
        break
      case 429:
        // Handle rate limit
        await new Promise(r => setTimeout(r, 1000))
        // Retry request
        break
      default:
        throw new Error(error.error.message)
    }
  }
} catch (error) {
  console.error('Chat API error:', error)
}
```

### 3. Streaming Best Practices
- Always check for `[DONE]` signal
- Handle partial JSON chunks
- Implement timeout for stalled streams
- Clean up readers on component unmount

### 4. Model Selection
- Start with cheaper models (gpt-3.5-turbo)
- Use GPT-4 only when needed
- Consider Gemini Pro for long contexts
- Use Claude for complex reasoning

## API Changelog

### v1.0.0 (Current)
- Initial release with multi-model support
- Streaming and non-streaming responses
- Preset system integration
- Token-based quota management

---

*For additional support, please contact the development team or open an issue on GitHub.*