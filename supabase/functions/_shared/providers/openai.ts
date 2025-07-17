import { Message, ChatOptions, ChatResponse } from './google.ts'

export class OpenAIProvider {
  private apiKey: string
  private baseUrl = 'https://api.openai.com/v1'

  constructor(apiKey: string) {
    this.apiKey = apiKey
  }

  async chat(model: string, messages: Message[], options: ChatOptions = {}): Promise<ChatResponse> {
    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: model,
        messages: messages,
        temperature: options.temperature || 0.7,
        max_tokens: options.max_tokens,
        top_p: options.top_p || 1,
        stream: false,
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`OpenAI API error: ${error}`)
    }

    const data = await response.json()
    
    return {
      content: data.choices[0].message.content,
      usage: {
        prompt_tokens: data.usage.prompt_tokens,
        completion_tokens: data.usage.completion_tokens,
        total_tokens: data.usage.total_tokens,
      },
    }
  }

  async *streamChat(model: string, messages: Message[], options: ChatOptions = {}) {
    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: model,
        messages: messages,
        temperature: options.temperature || 0.7,
        max_tokens: options.max_tokens,
        top_p: options.top_p || 1,
        stream: true,
        stream_options: {
          include_usage: true,
        },
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`OpenAI API error: ${error}`)
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
        if (trimmedLine === '' || trimmedLine === 'data: [DONE]') continue
        
        if (trimmedLine.startsWith('data: ')) {
          try {
            const data = JSON.parse(trimmedLine.slice(6))
            
            if (data.choices && data.choices[0].delta?.content) {
              yield {
                content: data.choices[0].delta.content,
                usage: totalUsage,
              }
            }
            
            // Update usage if available (GPT-4.1 and newer models)
            if (data.usage) {
              totalUsage = {
                prompt_tokens: data.usage.prompt_tokens || totalUsage.prompt_tokens,
                completion_tokens: data.usage.completion_tokens || totalUsage.completion_tokens,
                total_tokens: data.usage.total_tokens || totalUsage.total_tokens,
              }
            }
          } catch (e) {
            console.error('Failed to parse SSE data:', trimmedLine, e)
          }
        }
      }
    }
  }
}