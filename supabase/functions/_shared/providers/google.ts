export interface Message {
  role: 'user' | 'assistant' | 'system'
  content: string
}

export interface ChatOptions {
  max_tokens?: number
  temperature?: number
  top_p?: number
  top_k?: number
}

export interface ChatResponse {
  content: string
  usage: {
    prompt_tokens: number
    completion_tokens: number
    total_tokens: number
  }
}

export class GoogleProvider {
  private apiKey: string
  private baseUrl = 'https://generativelanguage.googleapis.com/v1/models'

  constructor(apiKey: string) {
    this.apiKey = apiKey
  }

  async chat(model: string, messages: Message[], options: ChatOptions = {}): Promise<ChatResponse> {
    const geminiModel = this.mapModelName(model)
    
    const response = await fetch(`${this.baseUrl}/${geminiModel}:generateContent?key=${this.apiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: this.convertMessages(messages),
        generationConfig: {
          temperature: options.temperature || 0.7,
          topK: options.top_k || 40,
          topP: options.top_p || 0.95,
          maxOutputTokens: options.max_tokens || 8192,
        },
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Google API error: ${error}`)
    }

    const data = await response.json()
    const content = data.candidates[0].content.parts[0].text
    const usage = data.usageMetadata

    return {
      content,
      usage: {
        prompt_tokens: usage.promptTokenCount || 0,
        completion_tokens: usage.candidatesTokenCount || 0,
        total_tokens: usage.totalTokenCount || 0,
      },
    }
  }

  async *streamChat(model: string, messages: Message[], options: ChatOptions = {}) {
    const geminiModel = this.mapModelName(model)
    
    const response = await fetch(`${this.baseUrl}/${geminiModel}:streamGenerateContent?key=${this.apiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: this.convertMessages(messages),
        generationConfig: {
          temperature: options.temperature || 0.7,
          topK: options.top_k || 40,
          topP: options.top_p || 0.95,
          maxOutputTokens: options.max_tokens || 8192,
        },
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Google API error: ${error}`)
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
        if (line.trim() === '') continue
        
        try {
          const data = JSON.parse(line)
          if (data.candidates && data.candidates[0].content) {
            const content = data.candidates[0].content.parts[0].text
            
            // Update usage if available
            if (data.usageMetadata) {
              totalUsage = {
                prompt_tokens: data.usageMetadata.promptTokenCount || totalUsage.prompt_tokens,
                completion_tokens: data.usageMetadata.candidatesTokenCount || totalUsage.completion_tokens,
                total_tokens: data.usageMetadata.totalTokenCount || totalUsage.total_tokens,
              }
            }
            
            yield {
              content,
              usage: totalUsage,
            }
          }
        } catch (e) {
          // Skip invalid JSON lines
          console.error('Failed to parse line:', line, e)
        }
      }
    }
  }

  private mapModelName(model: string): string {
    const modelMap: Record<string, string> = {
      'gemini-2.5-flash': 'gemini-2.5-flash',
      'gemini-2.5-pro': 'gemini-2.5-pro',
      'gemini-1.5-pro': 'gemini-1.5-pro',
      'gemini-1.5-flash': 'gemini-1.5-flash',
    }
    return modelMap[model] || model
  }

  private convertMessages(messages: Message[]) {
    return messages.map(msg => ({
      role: msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: msg.content }],
    }))
  }
}