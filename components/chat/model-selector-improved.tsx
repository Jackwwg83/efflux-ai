'use client'

import { useState, useEffect, useMemo } from 'react'
import { Check, ChevronsUpDown, Star, Clock, Zap, Brain, Eye, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'
import { logger } from '@/lib/utils/logger'
import { Button } from '@/components/ui/button'
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandSeparator,
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
import { ScrollArea } from '@/components/ui/scroll-area'

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

// Model aliases for better search
const MODEL_ALIASES: Record<string, string[]> = {
  'gpt-4o': ['gpt4o', 'gpt-4-o', 'gpt4-o'],
  'gpt-4o-mini': ['gpt4o-mini', 'gpt-4-o-mini'],
  'claude-3-5-sonnet-20241022': ['claude', 'claude-3.5', 'claude-sonnet', 'sonnet'],
  'claude-3-5-haiku-20241022': ['haiku', 'claude-haiku'],
  'gemini-2.0-flash-exp': ['gemini', 'gemini-2', 'gemini-flash', 'flash'],
  'deepseek-r1': ['deepseek', 'r1'],
}

// Default recommended models
const RECOMMENDED_MODEL_IDS = [
  'gpt-4o-mini',
  'claude-3-5-sonnet-20241022',
  'gemini-2.0-flash-exp',
  'deepseek-r1',
]

export function ModelSelectorImproved() {
  const [open, setOpen] = useState(false)
  const [models, setModels] = useState<Model[]>([])
  const [userTier, setUserTier] = useState<'free' | 'pro' | 'max'>('free')
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [favorites, setFavorites] = useState<string[]>([])
  const [recentModels, setRecentModels] = useState<string[]>([])
  
  const supabase = createClient()
  const { toast } = useToast()
  const { currentConversation, setCurrentConversation } = useConversationStore()

  useEffect(() => {
    loadModelsAndUserTier()
    loadUserPreferences()
  }, [])

  const loadUserPreferences = () => {
    // Load from localStorage
    const storedFavorites = localStorage.getItem('modelFavorites')
    const storedRecent = localStorage.getItem('recentModels')
    
    if (storedFavorites) {
      setFavorites(JSON.parse(storedFavorites))
    }
    if (storedRecent) {
      setRecentModels(JSON.parse(storedRecent))
    }
  }

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

  const toggleFavorite = (modelId: string, e: React.MouseEvent) => {
    e.stopPropagation()
    const newFavorites = favorites.includes(modelId)
      ? favorites.filter(id => id !== modelId)
      : [...favorites, modelId]
    
    setFavorites(newFavorites)
    localStorage.setItem('modelFavorites', JSON.stringify(newFavorites))
  }

  const addToRecent = (modelId: string) => {
    const newRecent = [modelId, ...recentModels.filter(id => id !== modelId)].slice(0, 5)
    setRecentModels(newRecent)
    localStorage.setItem('recentModels', JSON.stringify(newRecent))
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

      addToRecent(model.model_id)
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

  // Filter models based on search
  const filteredModels = useMemo(() => {
    if (!search) return models

    const searchLower = search.toLowerCase()
    return models.filter(model => {
      // Check display name
      if (model.display_name.toLowerCase().includes(searchLower)) return true
      
      // Check model ID
      if (model.model_id.toLowerCase().includes(searchLower)) return true
      
      // Check aliases
      for (const [modelId, aliases] of Object.entries(MODEL_ALIASES)) {
        if (model.model_id === modelId && aliases.some(alias => alias.includes(searchLower))) {
          return true
        }
      }
      
      return false
    })
  }, [models, search])

  // Organize models
  const favoriteModels = filteredModels.filter(m => favorites.includes(m.model_id))
  const recentlyUsedModels = filteredModels.filter(m => 
    recentModels.includes(m.model_id) && !favorites.includes(m.model_id)
  )
  const recommendedModels = filteredModels.filter(m => 
    RECOMMENDED_MODEL_IDS.includes(m.model_id) && 
    !favorites.includes(m.model_id) && 
    !recentModels.includes(m.model_id)
  )
  const otherModels = filteredModels.filter(m => 
    !favorites.includes(m.model_id) && 
    !recentModels.includes(m.model_id) &&
    !RECOMMENDED_MODEL_IDS.includes(m.model_id)
  )

  const getModelIcon = (model: Model) => {
    if (model.tags?.includes('fast')) return <Zap className="h-4 w-4 text-yellow-500" />
    if (model.tags?.includes('powerful')) return <Brain className="h-4 w-4 text-purple-500" />
    if (model.capabilities?.vision) return <Eye className="h-4 w-4 text-blue-500" />
    if (model.is_aggregator) return <Sparkles className="h-4 w-4 text-violet-500" />
    return null
  }

  const ModelItem = ({ model }: { model: Model }) => (
    <CommandItem
      key={model.model_id}
      value={model.model_id}
      onSelect={handleModelChange}
      disabled={!isModelAvailable(model)}
      className="flex items-center justify-between py-3"
    >
      <div className="flex items-center gap-2 flex-1">
        <Check
          className={cn(
            "h-4 w-4",
            currentModel?.model_id === model.model_id ? "opacity-100" : "opacity-0"
          )}
        />
        {getModelIcon(model)}
        <div className="flex-1">
          <div className="font-medium">{model.display_name}</div>
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            {model.context_window && (
              <span>{(model.context_window / 1000).toFixed(0)}K context</span>
            )}
            {model.provider_name && (
              <span>• {model.provider_name}</span>
            )}
          </div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        {!isModelAvailable(model) && (
          <Badge variant="outline" className="text-xs">
            {model.tier_required}
          </Badge>
        )}
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={(e) => toggleFavorite(model.model_id, e)}
        >
          <Star 
            className={cn(
              "h-3 w-3",
              favorites.includes(model.model_id) 
                ? "fill-yellow-500 text-yellow-500" 
                : "text-muted-foreground"
            )}
          />
        </Button>
      </div>
    </CommandItem>
  )

  const ModelGroup = ({ title, models, icon }: { title: string, models: Model[], icon?: React.ReactNode }) => {
    if (models.length === 0) return null

    return (
      <>
        <CommandGroup>
          <div className="flex items-center gap-2 px-2 py-1.5 text-xs font-medium text-muted-foreground">
            {icon}
            <span>{title}</span>
          </div>
          {models.map(model => (
            <ModelItem key={model.model_id} model={model} />
          ))}
        </CommandGroup>
        <CommandSeparator />
      </>
    )
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          className="w-[300px] justify-between"
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
      <PopoverContent className="w-[400px] p-0" align="start">
        <Command shouldFilter={false}>
          <CommandInput 
            placeholder="Search models..." 
            value={search}
            onValueChange={setSearch}
          />
          <CommandEmpty>No model found.</CommandEmpty>
          
          <ScrollArea className="h-[400px]">
            <ModelGroup 
              title="Favorites" 
              models={favoriteModels}
              icon={<Star className="h-4 w-4 text-yellow-500" />}
            />
            
            <ModelGroup 
              title="Recent" 
              models={recentlyUsedModels}
              icon={<Clock className="h-4 w-4 text-muted-foreground" />}
            />
            
            <ModelGroup 
              title="Recommended" 
              models={recommendedModels}
              icon={<Sparkles className="h-4 w-4 text-violet-500" />}
            />
            
            <ModelGroup 
              title="All Models" 
              models={otherModels}
            />
          </ScrollArea>
        </Command>
      </PopoverContent>
    </Popover>
  )
}