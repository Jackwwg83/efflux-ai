import { Message, ChatOptions, ChatResponse } from './google.ts'

export class AnthropicProvider {
  private apiKey: string
  private baseUrl = 'https://api.anthropic.com/v1'

  constructor(apiKey: string) {
    this.apiKey = apiKey
  }

  async chat(model: string, messages: Message[], options: ChatOptions = {}): Promise<ChatResponse> {
    const anthropicMessages = this.convertMessages(messages)
    
    const response = await fetch(`${this.baseUrl}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: model,
        messages: anthropicMessages.messages,
        system: anthropicMessages.system,
        max_tokens: options.max_tokens || 4096,
        temperature: options.temperature || 0.7,
        top_p: options.top_p || 1,
        stream: false,
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Anthropic API error: ${error}`)
    }

    const data = await response.json()
    
    return {
      content: data.content[0].text,
      usage: {
        prompt_tokens: data.usage.input_tokens,
        completion_tokens: data.usage.output_tokens,
        total_tokens: data.usage.input_tokens + data.usage.output_tokens,
      },
    }
  }

  async *streamChat(model: string, messages: Message[], options: ChatOptions = {}) {
    const anthropicMessages = this.convertMessages(messages)
    
    const response = await fetch(`${this.baseUrl}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: model,
        messages: anthropicMessages.messages,
        system: anthropicMessages.system,
        max_tokens: options.max_tokens || 4096,
        temperature: options.temperature || 0.7,
        top_p: options.top_p || 1,
        stream: true,
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Anthropic API error: ${error}`)
    }

    const reader = response.body?.getReader()
    if (!reader) throw new Error('No response body')

    const decoder = new TextDecoder()
    let buffer = ''
    let totalUsage = {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
    }

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''

      for (const line of lines) {
        const trimmedLine = line.trim()
        if (trimmedLine === '') continue
        
        if (trimmedLine.startsWith('data: ')) {
          try {
            const data = JSON.parse(trimmedLine.slice(6))
            
            if (data.type === 'content_block_delta' && data.delta?.text) {
              yield {
                content: data.delta.text,
                usage: totalUsage,
              }
            } else if (data.type === 'message_start' && data.message?.usage) {
              totalUsage.prompt_tokens = data.message.usage.input_tokens
            } else if (data.type === 'message_delta' && data.usage) {
              totalUsage.completion_tokens = data.usage.output_tokens
              totalUsage.total_tokens = totalUsage.prompt_tokens + totalUsage.completion_tokens
            }
          } catch (e) {
            console.error('Failed to parse SSE data:', trimmedLine, e)
          }
        }
      }
    }
  }

  private convertMessages(messages: Message[]) {
    // Extract system message if present
    let system = ''
    const filteredMessages = messages.filter(msg => {
      if (msg.role === 'system') {
        system = msg.content
        return false
      }
      return true
    })

    // Convert to Anthropic format
    const anthropicMessages = filteredMessages.map(msg => ({
      role: msg.role === 'assistant' ? 'assistant' : 'user',
      content: msg.content,
    }))

    return { messages: anthropicMessages, system }
  }
}