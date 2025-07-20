/**
 * Token 计算工具类
 * 用于估算文本的 token 数量，支持中英文混合
 */

export interface TokenUsage {
  promptTokens: number
  completionTokens: number
  totalTokens: number
}

export interface Message {
  role: 'system' | 'user' | 'assistant' | 'function'
  content: string
  name?: string
  metadata?: {
    timestamp?: Date
    tokens?: number
    pinned?: boolean
    summarized?: boolean
  }
}

export class TokenCounter {
  /**
   * 估算文本的 token 数量
   * 规则：中文字符约 2 字符/token，英文约 4 字符/token
   */
  static estimate(text: string): number {
    if (!text) return 0
    
    // 检测中文字符（包括中文标点）
    const chineseRegex = /[\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef]/g
    const chineseMatches = text.match(chineseRegex) || []
    const chineseChars = chineseMatches.length
    
    // 计算非中文字符
    const totalChars = text.length
    const nonChineseChars = totalChars - chineseChars
    
    // 估算 tokens
    // 中文：2 字符 = 1 token
    // 英文和其他：4 字符 = 1 token
    return Math.ceil(chineseChars / 2 + nonChineseChars / 4)
  }
  
  /**
   * 批量计算消息数组的总 token 数
   */
  static calculateMessages(messages: Message[]): number {
    if (!messages || messages.length === 0) return 0
    
    return messages.reduce((total, msg) => {
      // 每条消息的格式化开销（role: content）
      const roleTokens = 4 // 约 "role: "
      
      // 如果有缓存的 token 数，直接使用
      if (msg.metadata?.tokens) {
        return total + msg.metadata.tokens
      }
      
      // 否则估算
      const contentTokens = this.estimate(msg.content)
      const nameTokens = msg.name ? this.estimate(msg.name) : 0
      
      return total + roleTokens + contentTokens + nameTokens
    }, 0)
  }
  
  /**
   * 获取模型的 token 限制
   */
  static getModelLimit(model: string): number {
    const limits: Record<string, number> = {
      // OpenAI
      'gpt-3.5-turbo': 16385,
      'gpt-4-turbo': 128000,
      'gpt-4o': 128000,
      'gpt-4o-mini': 128000,
      'gpt-4.1': 1000000, // 假设的未来模型
      
      // Anthropic
      'claude-3-opus': 200000,
      'claude-3-sonnet': 200000,
      'claude-3-haiku': 200000,
      'claude-3.5-haiku': 200000,
      'claude-3.5-sonnet': 200000,
      
      // Google
      'gemini-2.0-flash': 1048576,
      'gemini-2.0-flash-lite': 1048576,
      'gemini-2.5-flash': 1048576,
      'gemini-2.5-pro': 1048576,
      
      // Bedrock (AWS 版本的 Claude 模型)
      'anthropic.claude-3-haiku-20240307-v1:0': 200000,
      'anthropic.claude-3-sonnet-20240229-v1:0': 200000,
      'anthropic.claude-3-opus-20240229-v1:0': 200000,
      'anthropic.claude-3-5-sonnet-20240620-v1:0': 200000,
    }
    
    // 返回对应限制，如果未找到则返回默认值
    return limits[model] || 4096
  }
  
  /**
   * 计算 token 使用百分比
   */
  static calculateUsagePercentage(currentTokens: number, model: string): number {
    const limit = this.getModelLimit(model)
    return Math.min((currentTokens / limit) * 100, 100)
  }
  
  /**
   * 获取 token 使用状态
   */
  static getUsageStatus(percentage: number): 'normal' | 'warning' | 'critical' {
    if (percentage > 85) return 'critical'
    if (percentage > 70) return 'warning'
    return 'normal'
  }
  
  /**
   * 计算剩余可用 token 数
   */
  static getRemainingTokens(currentTokens: number, model: string): number {
    const limit = this.getModelLimit(model)
    return Math.max(limit - currentTokens, 0)
  }
  
  /**
   * 预估需要为响应预留的 token 数
   */
  static estimateResponseTokens(model: string): number {
    // 不同模型的典型响应长度不同
    if (model.includes('gpt-3.5')) return 500
    if (model.includes('gpt-4')) return 1000
    if (model.includes('claude')) return 1500
    if (model.includes('gemini')) return 2000
    return 1000 // 默认值
  }
  
  /**
   * 智能截断消息列表以适应 token 限制
   */
  static truncateMessages(
    messages: Message[], 
    model: string,
    options: {
      keepSystemMessage?: boolean
      keepPinnedMessages?: boolean
      keepRecentCount?: number
      reserveTokens?: number
    } = {}
  ): Message[] {
    const {
      keepSystemMessage = true,
      keepPinnedMessages = true,
      keepRecentCount = 10,
      reserveTokens = 0
    } = options
    
    const modelLimit = this.getModelLimit(model)
    const responseTokens = this.estimateResponseTokens(model)
    const availableTokens = modelLimit - responseTokens - reserveTokens
    
    const result: Message[] = []
    let currentTokens = 0
    
    // 1. 始终保留系统消息
    const systemMessage = messages.find(m => m.role === 'system')
    if (systemMessage && keepSystemMessage) {
      const tokens = this.estimate(systemMessage.content) + 4
      if (currentTokens + tokens <= availableTokens) {
        result.push(systemMessage)
        currentTokens += tokens
      }
    }
    
    // 2. 保留置顶消息
    if (keepPinnedMessages) {
      const pinnedMessages = messages.filter(m => 
        m.metadata?.pinned && m.role !== 'system'
      )
      
      for (const msg of pinnedMessages) {
        const tokens = this.estimate(msg.content) + 4
        if (currentTokens + tokens <= availableTokens) {
          result.push(msg)
          currentTokens += tokens
        }
      }
    }
    
    // 3. 从最新开始添加消息
    const regularMessages = messages
      .filter(m => 
        m.role !== 'system' && 
        !(keepPinnedMessages && m.metadata?.pinned)
      )
      .slice(-keepRecentCount)
      .reverse()
    
    const recentMessages: Message[] = []
    for (const msg of regularMessages) {
      const tokens = this.estimate(msg.content) + 4
      if (currentTokens + tokens <= availableTokens) {
        recentMessages.unshift(msg)
        currentTokens += tokens
      } else {
        break
      }
    }
    
    result.push(...recentMessages)
    
    return result
  }
  
  /**
   * 格式化 token 数量显示
   */
  static formatTokenCount(tokens: number): string {
    if (tokens < 1000) return `${tokens}`
    if (tokens < 10000) return `${(tokens / 1000).toFixed(1)}k`
    return `${Math.round(tokens / 1000)}k`
  }
}