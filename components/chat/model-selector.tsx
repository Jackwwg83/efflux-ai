'use client'

import { useState, useEffect } from 'react'
import { Check, ChevronsUpDown, AlertCircle, AlertTriangle, Wrench, Sparkles, Zap, Brain, Eye } from 'lucide-react'
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
  health_status?: 'healthy' | 'degraded' | 'unavailable' | 'maintenance'
  health_message?: string
  is_featured?: boolean
  tags?: string[]
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

      // Get all available models from unified system
      const { data: availableModels, error: modelsError } = await supabase
        .rpc('get_all_available_models')

      if (!modelsError && availableModels) {
        setModels(availableModels)
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

  // Group models by tags for better organization
  const featuredModels = models.filter(m => m.is_featured)
  const fastModels = models.filter(m => m.tags?.includes('fast'))
  const powerfulModels = models.filter(m => m.tags?.includes('powerful'))
  const visionModels = models.filter(m => m.capabilities?.vision === true)
  const otherModels = models.filter(m => 
    !m.is_featured && 
    !m.tags?.includes('fast') && 
    !m.tags?.includes('powerful') &&
    m.capabilities?.vision !== true
  )

  const getModelIcon = (model: Model) => {
    if (model.tags?.includes('fast')) return <Zap className="h-4 w-4 text-yellow-500" />
    if (model.tags?.includes('powerful')) return <Brain className="h-4 w-4 text-purple-500" />
    if (model.capabilities?.vision) return <Eye className="h-4 w-4 text-blue-500" />
    if (model.is_aggregator) return <Sparkles className="h-4 w-4 text-violet-500" />
    return null
  }

  const getHealthIcon = (status?: string) => {
    switch (status) {
      case 'degraded':
        return <AlertTriangle className="h-3 w-3 text-yellow-500" />
      case 'unavailable':
        return <AlertCircle className="h-3 w-3 text-red-500" />
      case 'maintenance':
        return <Wrench className="h-3 w-3 text-blue-500" />
      default:
        return null
    }
  }

  const ModelGroup = ({ title, models, icon }: { title: string, models: Model[], icon?: React.ReactNode }) => {
    if (models.length === 0) return null

    return (
      <CommandGroup 
        heading={
          <div className="flex items-center gap-2">
            {icon}
            <span>{title}</span>
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
                  {getModelIcon(model)}
                  <span>{model.display_name}</span>
                  {getHealthIcon(model.health_status)}
                </div>
                {!isModelAvailable(model) && (
                  <Badge variant="outline" className="text-xs">
                    {model.tier_required}
                  </Badge>
                )}
              </div>
              <div className="flex items-center gap-2 mt-1">
                {model.context_window && (
                  <span className="text-xs text-muted-foreground">
                    {(model.context_window / 1000).toFixed(0)}K context
                  </span>
                )}
                {model.tags?.includes('new') && (
                  <Badge variant="secondary" className="text-xs">
                    New
                  </Badge>
                )}
                {model.tags?.includes('recommended') && (
                  <Badge variant="default" className="text-xs">
                    Recommended
                  </Badge>
                )}
                {model.is_aggregator && (
                  <Badge variant="outline" className="text-xs">
                    via {model.provider_name}
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
  }

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
                {getModelIcon(currentModel)}
                <span className="truncate">{currentModel.display_name}</span>
              </>
            ) : (
              "Select model..."
            )}
          </div>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[450px] p-0">
        <Command>
          <CommandInput placeholder="Search models..." />
          <CommandEmpty>No model found.</CommandEmpty>
          
          <ModelGroup 
            title="Featured Models" 
            models={featuredModels}
            icon={<Sparkles className="h-4 w-4 text-violet-500" />}
          />
          
          <ModelGroup 
            title="Fast Models" 
            models={fastModels}
            icon={<Zap className="h-4 w-4 text-yellow-500" />}
          />
          
          <ModelGroup 
            title="Powerful Models" 
            models={powerfulModels}
            icon={<Brain className="h-4 w-4 text-purple-500" />}
          />
          
          <ModelGroup 
            title="Vision Models" 
            models={visionModels}
            icon={<Eye className="h-4 w-4 text-blue-500" />}
          />
          
          <ModelGroup 
            title="Other Models" 
            models={otherModels}
          />
        </Command>
      </PopoverContent>
    </Popover>
  )
}