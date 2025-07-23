import { createClient } from '@/lib/supabase/client'
import { AggregatorProviderFactory, APIProviderConfig } from '@/lib/ai/providers/aggregator'

interface SyncResult {
  success: boolean
  modelCount?: number
  error?: string
}

export class ModelSyncService {
  private supabase = createClient()

  /**
   * Sync models for an aggregator API key
   */
  async syncAggregatorModels(apiKeyId: string, providerName: string): Promise<SyncResult> {
    try {
      // Get the API key
      const { data: apiKey, error: keyError } = await this.supabase
        .from('api_key_pool')
        .select('*')
        .eq('id', apiKeyId)
        .single()

      if (keyError || !apiKey) {
        throw new Error('API key not found')
      }

      // Get the provider configuration
      const { data: provider, error: providerError } = await this.supabase
        .from('api_providers')
        .select('*')
        .eq('name', providerName)
        .single()

      if (providerError || !provider) {
        throw new Error('Provider configuration not found')
      }

      // Create provider instance
      const providerConfig: APIProviderConfig = {
        id: provider.id,
        name: provider.name,
        display_name: provider.display_name,
        provider_type: provider.provider_type,
        base_url: provider.base_url,
        api_standard: provider.api_standard,
        features: provider.features || {}
      }

      const aggregatorProvider = AggregatorProviderFactory.create(
        provider.name,
        providerConfig,
        apiKey.api_key
      )

      // Fetch models from the provider
      const models = await aggregatorProvider.fetchModels()

      // Delete existing models for this provider
      const { error: deleteError } = await this.supabase
        .from('aggregator_models')
        .delete()
        .eq('provider_id', provider.id)

      if (deleteError) {
        console.error('Error deleting old models:', deleteError)
      }

      // Insert new models
      if (models.length > 0) {
        const modelsToInsert = models.map(model => ({
          provider_id: provider.id,
          model_id: model.model_id,
          model_name: model.model_name,
          display_name: model.display_name,
          model_type: model.model_type,
          capabilities: model.capabilities || {},
          pricing: model.pricing || {},
          context_window: model.context_window,
          max_output_tokens: model.max_output_tokens,
          training_cutoff: model.training_cutoff,
          is_available: model.is_available
        }))

        const { error: insertError } = await this.supabase
          .from('aggregator_models')
          .insert(modelsToInsert)

        if (insertError) {
          console.error('Error inserting models:', insertError)
          throw new Error('Failed to save models')
        }
      }

      // Update the API key with model count
      const { error: updateError } = await this.supabase
        .from('api_key_pool')
        .update({ 
          provider_config: {
            ...apiKey.provider_config,
            last_sync: new Date().toISOString(),
            model_count: models.length
          }
        })
        .eq('id', apiKeyId)

      if (updateError) {
        console.error('Error updating sync info:', updateError)
      }

      return {
        success: true,
        modelCount: models.length
      }
    } catch (error) {
      console.error('Model sync error:', error)
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred'
      }
    }
  }

  /**
   * Get aggregator model statistics
   */
  async getModelStats(providerId: string) {
    try {
      const { data, count, error } = await this.supabase
        .from('aggregator_models')
        .select('*', { count: 'exact' })
        .eq('provider_id', providerId)
        .eq('is_available', true)

      if (error) throw error

      const modelsByType = data?.reduce((acc, model) => {
        acc[model.model_type] = (acc[model.model_type] || 0) + 1
        return acc
      }, {} as Record<string, number>)

      return {
        total: count || 0,
        byType: modelsByType || {},
        models: data || []
      }
    } catch (error) {
      console.error('Error getting model stats:', error)
      return {
        total: 0,
        byType: {},
        models: []
      }
    }
  }
}