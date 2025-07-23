import { createClient } from '@/lib/supabase/client'
import { VaultClient } from '@/lib/crypto/vault'
import { AggregatorProviderFactory, APIProviderConfig } from '@/lib/ai/providers/aggregator'

interface SyncResult {
  success: boolean
  modelCount?: number
  error?: string
}

export class ModelSyncService {
  private supabase = createClient()

  /**
   * Sync models for a specific user provider
   */
  async syncProviderModels(userProviderId: string, userId: string): Promise<SyncResult> {
    try {
      // Get the user provider configuration
      const { data: userProvider, error: userProviderError } = await this.supabase
        .from('user_api_providers')
        .select(`
          *,
          provider:api_providers(*)
        `)
        .eq('id', userProviderId)
        .eq('user_id', userId)
        .single()

      if (userProviderError || !userProvider) {
        throw new Error('Provider configuration not found')
      }

      // Initialize vault and decrypt API key
      const vault = new VaultClient(userId)
      await vault.initialize()
      const apiKey = await vault.decryptData(userProvider.api_key_encrypted)

      // Create provider instance
      const providerConfig: APIProviderConfig = {
        id: userProvider.provider.id,
        name: userProvider.provider.name,
        display_name: userProvider.provider.display_name,
        provider_type: userProvider.provider.provider_type,
        base_url: userProvider.endpoint_override || userProvider.provider.base_url,
        api_standard: userProvider.provider.api_standard,
        features: userProvider.provider.features || {}
      }

      const provider = AggregatorProviderFactory.create(
        userProvider.provider.name,
        providerConfig,
        apiKey
      )

      // Fetch models from the provider
      const models = await provider.fetchModels()

      // Delete existing models for this provider
      const { error: deleteError } = await this.supabase
        .from('aggregator_models')
        .delete()
        .eq('provider_id', userProvider.provider_id)

      if (deleteError) {
        console.error('Error deleting old models:', deleteError)
      }

      // Insert new models
      if (models.length > 0) {
        const modelsToInsert = models.map(model => ({
          provider_id: userProvider.provider_id,
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

      // Update last sync timestamp
      const { error: updateError } = await this.supabase
        .from('user_api_providers')
        .update({ 
          updated_at: new Date().toISOString(),
          settings: {
            ...userProvider.settings,
            last_sync: new Date().toISOString(),
            last_sync_model_count: models.length
          }
        })
        .eq('id', userProviderId)

      if (updateError) {
        console.error('Error updating sync timestamp:', updateError)
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
   * Sync all providers for a user
   */
  async syncAllUserProviders(userId: string): Promise<Map<string, SyncResult>> {
    const results = new Map<string, SyncResult>()

    try {
      // Get all active providers for the user
      const { data: userProviders, error } = await this.supabase
        .from('user_api_providers')
        .select('id, provider:api_providers(display_name)')
        .eq('user_id', userId)
        .eq('is_active', true)

      if (error || !userProviders) {
        throw new Error('Failed to fetch user providers')
      }

      // Sync each provider
      for (const userProvider of userProviders) {
        const result = await this.syncProviderModels(userProvider.id, userId)
        results.set(userProvider.provider.display_name, result)
      }
    } catch (error) {
      console.error('Error syncing all providers:', error)
    }

    return results
  }

  /**
   * Check if a provider needs syncing (hasn't been synced in 24 hours)
   */
  async needsSync(userProviderId: string): Promise<boolean> {
    try {
      const { data, error } = await this.supabase
        .from('user_api_providers')
        .select('settings')
        .eq('id', userProviderId)
        .single()

      if (error || !data) return true

      const lastSync = data.settings?.last_sync
      if (!lastSync) return true

      const lastSyncDate = new Date(lastSync)
      const hoursSinceSync = (Date.now() - lastSyncDate.getTime()) / (1000 * 60 * 60)
      
      return hoursSinceSync > 24
    } catch {
      return true
    }
  }
}