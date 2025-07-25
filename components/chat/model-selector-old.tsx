'use client'

import { useState, useEffect } from 'react'
import { Check, ChevronsUpDown, AlertCircle, AlertTriangle, Wrench, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'
import { logger } from '@/lib/utils/logger'
import { Button } from '@/components/ui/button'
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
} from '@/components/ui/command'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'
import { createClient } from '@/lib/supabase/client'
import { useConversationStore } from '@/lib/stores/conversation'
import { useToast } from '@/hooks/use-toast'
import { Badge } from '@/components/ui/badge'

interface Model {
  model_id: string
  display_name: string
  provider_name: string
  model_type: string
  context_window?: number
  is_aggregator: boolean
  capabilities?: any
  tier_required: string
  // For compatibility with old code
  id?: string
  provider?: string
  model?: string
  is_active?: boolean
  health_status?: 'healthy' | 'degraded' | 'unavailable' | 'maintenance'
  health_message?: string
}

export function ModelSelector() {
  const [open, setOpen] = useState(false)
  const [models, setModels] = useState<Model[]>([])
  const [userTier, setUserTier] = useState<'free' | 'pro' | 'max'>('free')
  const [loading, setLoading] = useState(true)
  
  const supabase = createClient()
  const { toast } = useToast()
  const { currentConversation, setCurrentConversation } = useConversationStore()

  useEffect(() => {
    loadModelsAndUserTier()
  }, [])

  const loadModelsAndUserTier = async () => {
    try {
      // Get user tier
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: tierData } = await supabase
        .from('user_tiers')
        .select('tier')
        .eq('user_id', user.id)
        .single()

      if (tierData) {
        setUserTier(tierData.tier)
      }

      // Get all available models (direct + aggregator)
      const { data: availableModels, error: modelsError } = await supabase
        .rpc('get_all_available_models')

      if (!modelsError && availableModels) {
        // Transform to match the expected interface
        const transformedModels = availableModels.map((m: any) => ({
          ...m,
          // Add compatibility fields
          id: m.model_id,
          provider: m.provider_name,
          model: m.model_id,
          is_active: true,
          // Convert tier_required to typed union
          tier_required: m.tier_required as 'free' | 'pro' | 'max'
        }))

        setModels(transformedModels)
      }
    } catch (error) {
      logger.error('Error loading models', { error })
      toast({
        title: 'Error',
        description: 'Failed to load models',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const isModelAvailable = (model: Model) => {
    if (model.is_aggregator) return true // Aggregator models always available if provider is configured
    const tierOrder = { free: 0, pro: 1, max: 2 }
    const modelTier = model.tier_required as 'free' | 'pro' | 'max'
    return tierOrder[userTier] >= tierOrder[modelTier]
  }

  const handleModelChange = async (modelId: string) => {
    const model = models.find(m => m.model_id === modelId)
    if (!model || !currentConversation) return

    if (!isModelAvailable(model)) {
      toast({
        title: 'Upgrade Required',
        description: `${model.display_name} requires ${model.tier_required} tier`,
        variant: 'destructive',
      })
      return
    }

    // Warn about unhealthy models
    if (model.health_status === 'unavailable') {
      toast({
        title: 'Model Unavailable',
        description: model.health_message || 'This model is temporarily unavailable',
        variant: 'destructive',
      })
      return
    } else if (model.health_status === 'degraded') {
      toast({
        title: 'Model May Be Slow',
        description: model.health_message || 'This model is experiencing issues and may be slow or unreliable',
      })
    } else if (model.health_status === 'maintenance') {
      toast({
        title: 'Model Under Maintenance',
        description: model.health_message || 'This model is currently under maintenance',
      })
    }

    try {
      const { error } = await supabase
        .from('conversations')
        .update({
          model: model.model_id,
          provider: model.provider_name,
        })
        .eq('id', currentConversation.id)

      if (error) throw error

      setCurrentConversation({
        ...currentConversation,
        model: model.model_id,
        provider: model.provider_name,
      })

      setOpen(false)
    } catch (error) {
      logger.error('Error updating model', { error })
      toast({
        title: 'Error',
        description: 'Failed to update model',
        variant: 'destructive',
      })
    }
  }

  const currentModel = models.find(
    m => m.model_id === currentConversation?.model
  )

  // Group models by provider and type
  const groupedModels = models.reduce((acc, model) => {
    const key = model.is_aggregator ? `aggregator_${model.provider_name}` : model.provider_name
    if (!acc[key]) {
      acc[key] = []
    }
    acc[key].push(model)
    return acc
  }, {} as Record<string, Model[]>)

  // Sort groups: direct providers first, then aggregators
  const sortedGroups = Object.entries(groupedModels).sort(([a], [b]) => {
    const aIsAggregator = a.startsWith('aggregator_')
    const bIsAggregator = b.startsWith('aggregator_')
    
    if (aIsAggregator && !bIsAggregator) return 1
    if (!aIsAggregator && bIsAggregator) return -1
    return a.localeCompare(b)
  })

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          className="w-[350px] justify-between"
          disabled={loading}
        >
          <div className="flex items-center gap-2 truncate">
            {currentModel ? (
              <>
                {currentModel.is_aggregator && (
                  <Sparkles className="h-4 w-4 text-violet-500" />
                )}
                <span className="truncate">{currentModel.display_name}</span>
              </>
            ) : (
              "Select model..."
            )}
          </div>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[400px] p-0">
        <Command>
          <CommandInput placeholder="Search models..." />
          <CommandEmpty>No model found.</CommandEmpty>
          {sortedGroups.map(([key, models]) => {
            const isAggregator = key.startsWith('aggregator_')
            const displayName = isAggregator 
              ? key.replace('aggregator_', '')
              : key.toUpperCase()
            
            return (
              <CommandGroup 
                key={key} 
                heading={
                  <div className="flex items-center gap-2">
                    {isAggregator && (
                      <Badge variant="secondary" className="text-xs">
                        Aggregator
                      </Badge>
                    )}
                    <span>{displayName}</span>
                  </div>
                }
              >
                {models.map((model) => (
                  <CommandItem
                    key={model.model_id}
                    value={model.model_id}
                    onSelect={handleModelChange}
                    disabled={!isModelAvailable(model)}
                  >
                    <Check
                      className={cn(
                        "mr-2 h-4 w-4",
                        currentModel?.model_id === model.model_id ? "opacity-100" : "opacity-0"
                      )}
                    />
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <span>{model.display_name}</span>
                          {model.health_status && model.health_status !== 'healthy' && (
                            <span title={model.health_message}>
                              {model.health_status === 'degraded' && (
                                <AlertTriangle className="h-3 w-3 text-yellow-500" />
                              )}
                              {model.health_status === 'unavailable' && (
                                <AlertCircle className="h-3 w-3 text-red-500" />
                              )}
                              {model.health_status === 'maintenance' && (
                                <Wrench className="h-3 w-3 text-blue-500" />
                              )}
                            </span>
                          )}
                        </div>
                        {!isModelAvailable(model) && (
                          <span className="text-xs text-muted-foreground">
                            {model.tier_required}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        {model.context_window && (
                          <span className="text-xs text-muted-foreground">
                            {model.context_window.toLocaleString()} tokens
                          </span>
                        )}
                        {model.capabilities?.vision && (
                          <Badge variant="outline" className="text-xs">
                            👁️ Vision
                          </Badge>
                        )}
                        {model.capabilities?.functions && (
                          <Badge variant="outline" className="text-xs">
                            🔧 Functions
                          </Badge>
                        )}
                        {model.capabilities?.streaming && (
                          <Badge variant="outline" className="text-xs">
                            📡 Stream
                          </Badge>
                        )}
                      </div>
                      {model.health_message && model.health_status !== 'healthy' && (
                        <p className="text-xs text-muted-foreground mt-1">
                          {model.health_message}
                        </p>
                      )}
                    </div>
                  </CommandItem>
                ))}
              </CommandGroup>
            )
          })}
        </Command>
      </PopoverContent>
    </Popover>
  )
}