import { Message, ChatOptions, ChatResponse } from './google.ts'
import { createHash, createHmac } from 'https://deno.land/std@0.208.0/node/crypto.ts'

export class BedrockProvider {
  private accessKeyId: string
  private secretAccessKey: string
  private region: string
  private service = 'bedrock-runtime'

  constructor(accessKeyId: string, secretAccessKey: string, region: string) {
    this.accessKeyId = accessKeyId
    this.secretAccessKey = secretAccessKey
    this.region = region
  }

  async chat(model: string, messages: Message[], options: ChatOptions = {}): Promise<ChatResponse> {
    const endpoint = `https://bedrock-runtime.${this.region}.amazonaws.com/model/${model}/invoke`
    const body = this.prepareRequestBody(model, messages, options)
    
    const response = await this.makeRequest(endpoint, body)
    
    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Bedrock API error: ${error}`)
    }

    const data = await response.json()
    return this.parseResponse(model, data)
  }

  async *streamChat(model: string, messages: Message[], options: ChatOptions = {}) {
    const endpoint = `https://bedrock-runtime.${this.region}.amazonaws.com/model/${model}/invoke-with-response-stream`
    const body = this.prepareRequestBody(model, messages, options)
    
    const response = await this.makeRequest(endpoint, body)
    
    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Bedrock API error: ${error}`)
    }

    const reader = response.body?.getReader()
    if (!reader) throw new Error('No response body')

    const decoder = new TextDecoder()
    let totalUsage = {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
    }

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      const chunk = decoder.decode(value)
      const parsed = this.parseStreamChunk(model, chunk)
      
      if (parsed.content) {
        yield {
          content: parsed.content,
          usage: totalUsage,
        }
      }
      
      if (parsed.usage) {
        totalUsage = parsed.usage
      }
    }
  }

  private prepareRequestBody(model: string, messages: Message[], options: ChatOptions) {
    // Different models require different request formats
    if (model.includes('claude')) {
      const anthropicMessages = this.convertMessagesToAnthropic(messages)
      return JSON.stringify({
        anthropic_version: 'bedrock-2023-05-31',
        messages: anthropicMessages.messages,
        system: anthropicMessages.system,
        max_tokens: options.max_tokens || 4096,
        temperature: options.temperature || 0.7,
        top_p: options.top_p || 1,
      })
    } else {
      // Generic format for other models
      return JSON.stringify({
        messages: messages,
        max_tokens: options.max_tokens || 4096,
        temperature: options.temperature || 0.7,
        top_p: options.top_p || 1,
      })
    }
  }

  private parseResponse(model: string, data: any): ChatResponse {
    if (model.includes('claude')) {
      return {
        content: data.content[0].text,
        usage: {
          prompt_tokens: data.usage.input_tokens,
          completion_tokens: data.usage.output_tokens,
          total_tokens: data.usage.input_tokens + data.usage.output_tokens,
        },
      }
    } else {
      // Generic parsing for other models
      return {
        content: data.completion || data.content || '',
        usage: {
          prompt_tokens: data.usage?.prompt_tokens || 0,
          completion_tokens: data.usage?.completion_tokens || 0,
          total_tokens: data.usage?.total_tokens || 0,
        },
      }
    }
  }

  private parseStreamChunk(model: string, chunk: string): { content?: string; usage?: any } {
    try {
      // AWS Bedrock uses a specific event stream format
      const lines = chunk.split('\n')
      for (const line of lines) {
        if (line.includes(':chunk')) {
          const data = JSON.parse(line.split(':chunk')[1])
          if (model.includes('claude')) {
            if (data.type === 'content_block_delta') {
              return { content: data.delta?.text }
            }
          }
        }
      }
    } catch (e) {
      console.error('Failed to parse stream chunk:', e)
    }
    return {}
  }

  private convertMessagesToAnthropic(messages: Message[]) {
    let system = ''
    const filteredMessages = messages.filter(msg => {
      if (msg.role === 'system') {
        system = msg.content
        return false
      }
      return true
    })

    const anthropicMessages = filteredMessages.map(msg => ({
      role: msg.role === 'assistant' ? 'assistant' : 'user',
      content: msg.content,
    }))

    return { messages: anthropicMessages, system }
  }

  private async makeRequest(endpoint: string, body: string) {
    const now = new Date()
    const dateStamp = now.toISOString().slice(0, 10).replace(/-/g, '')
    const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '')
    
    const headers = {
      'Content-Type': 'application/json',
      'X-Amz-Date': amzDate,
      'Host': new URL(endpoint).host,
    }

    // Create canonical request
    const canonicalHeaders = Object.entries(headers)
      .sort(([a], [b]) => a.toLowerCase().localeCompare(b.toLowerCase()))
      .map(([k, v]) => `${k.toLowerCase()}:${v}`)
      .join('\n')
    
    const signedHeaders = Object.keys(headers)
      .map(k => k.toLowerCase())
      .sort()
      .join(';')
    
    const payloadHash = await this.sha256(body)
    
    const canonicalRequest = [
      'POST',
      new URL(endpoint).pathname,
      '',
      canonicalHeaders,
      '',
      signedHeaders,
      payloadHash,
    ].join('\n')

    // Create string to sign
    const algorithm = 'AWS4-HMAC-SHA256'
    const credentialScope = `${dateStamp}/${this.region}/${this.service}/aws4_request`
    const stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      await this.sha256(canonicalRequest),
    ].join('\n')

    // Calculate signature
    const signingKey = await this.getSignatureKey(dateStamp)
    const signature = await this.hmacHex(signingKey, stringToSign)

    // Add authorization header
    headers['Authorization'] = `${algorithm} Credential=${this.accessKeyId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`

    return fetch(endpoint, {
      method: 'POST',
      headers,
      body,
    })
  }

  private async sha256(data: string): Promise<string> {
    const hash = createHash('sha256')
    hash.update(data)
    return hash.digest('hex')
  }

  private async hmacHex(key: Uint8Array, data: string): Promise<string> {
    const hmac = createHmac('sha256', key)
    hmac.update(data)
    return hmac.digest('hex')
  }

  private async getSignatureKey(dateStamp: string): Promise<Uint8Array> {
    const kDate = await this.hmac(`AWS4${this.secretAccessKey}`, dateStamp)
    const kRegion = await this.hmac(kDate, this.region)
    const kService = await this.hmac(kRegion, this.service)
    const kSigning = await this.hmac(kService, 'aws4_request')
    return kSigning
  }

  private async hmac(key: string | Uint8Array, data: string): Promise<Uint8Array> {
    const keyData = typeof key === 'string' ? new TextEncoder().encode(key) : key
    const hmac = createHmac('sha256', keyData)
    hmac.update(data)
    return new Uint8Array(hmac.digest())
  }
}