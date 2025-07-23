// Provider Factory for API Aggregators

import { BaseAggregatorProvider } from './base-aggregator'
import { AiHubMixProvider } from './aihubmix-provider'
import { APIProviderConfig } from './types'

// Provider constructor type
type ProviderConstructor = new (config: APIProviderConfig, apiKey: string) => BaseAggregatorProvider

export class AggregatorProviderFactory {
  private static providers = new Map<string, ProviderConstructor>()
  
  static {
    // Register built-in providers
    this.register('aihubmix', AiHubMixProvider)
    // TODO: Add more providers as they are implemented
    // this.register('openrouter', OpenRouterProvider)
  }
  
  /**
   * Register a new provider
   */
  static register(name: string, provider: ProviderConstructor) {
    this.providers.set(name.toLowerCase(), provider)
  }
  
  /**
   * Create a provider instance
   */
  static create(
    providerName: string, 
    config: APIProviderConfig, 
    apiKey: string
  ): BaseAggregatorProvider {
    const Provider = this.providers.get(providerName.toLowerCase())
    
    if (!Provider) {
      throw new Error(`Unknown aggregator provider: ${providerName}`)
    }
    
    return new Provider(config, apiKey)
  }
  
  /**
   * Check if a provider is registered
   */
  static hasProvider(name: string): boolean {
    return this.providers.has(name.toLowerCase())
  }
  
  /**
   * Get list of registered providers
   */
  static getProviders(): string[] {
    return Array.from(this.providers.keys())
  }
  
  /**
   * Validate provider API key
   */
  static async validateProvider(
    providerName: string,
    config: APIProviderConfig,
    apiKey: string
  ): Promise<boolean> {
    try {
      const provider = this.create(providerName, config, apiKey)
      return await provider.validateApiKey()
    } catch (error) {
      console.error(`Provider validation failed for ${providerName}:`, error)
      return false
    }
  }
  
  /**
   * Fetch models from a provider
   */
  static async fetchProviderModels(
    providerName: string,
    config: APIProviderConfig,
    apiKey: string
  ) {
    try {
      const provider = this.create(providerName, config, apiKey)
      return await provider.fetchModels()
    } catch (error) {
      console.error(`Failed to fetch models from ${providerName}:`, error)
      throw error
    }
  }
}