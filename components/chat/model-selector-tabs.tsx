'use client'

import { useState, useEffect, useMemo } from 'react'
import { Check, ChevronsUpDown, Star, Zap, Brain, Eye, Sparkles, Search } from 'lucide-react'
import { cn } from '@/lib/utils'
import { logger } from '@/lib/utils/logger'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
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
  input_price?: number
  output_price?: number
}

// Quick access models - most commonly used
const QUICK_ACCESS_MODELS = [
  { id: 'gpt-4o-mini', name: 'GPT-4o Mini', desc: 'Fast & affordable • Free tier' },
  { id: 'claude-3-5-sonnet-20241022', name: 'Claude 3.5 Sonnet', desc: 'Best for complex tasks • Pro tier' },
  { id: 'gemini-2.0-flash-exp', name: 'Gemini 2.0 Flash', desc: 'Google\'s fastest • Free tier' },
  { id: 'deepseek-r1', name: 'DeepSeek R1', desc: 'Reasoning specialist • Free tier' },
]

export function ModelSelectorTabs() {
  const [open, setOpen] = useState(false)
  const [models, setModels] = useState<Model[]>([])
  const [userTier, setUserTier] = useState<'free' | 'pro' | 'max'>('free')
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [favorites, setFavorites] = useState<string[]>([])
  const [activeTab, setActiveTab] = useState('quick')
  
  const supabase = createClient()
  const { toast } = useToast()
  const { currentConversation, setCurrentConversation } = useConversationStore()

  useEffect(() => {
    loadModelsAndUserTier()
    loadUserPreferences()
  }, [])

  const loadUserPreferences = () => {
    const storedFavorites = localStorage.getItem('modelFavorites')
    if (storedFavorites) {
      setFavorites(JSON.parse(storedFavorites))
    }
  }

  const loadModelsAndUserTier = async () => {
    try {
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

  const toggleFavorite = (modelId: string) => {
    const newFavorites = favorites.includes(modelId)
      ? favorites.filter(id => id !== modelId)
      : [...favorites, modelId]
    
    setFavorites(newFavorites)
    localStorage.setItem('modelFavorites', JSON.stringify(newFavorites))
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

      // Add to recent models
      const recentModels = JSON.parse(localStorage.getItem('recentModels') || '[]')
      const newRecent = [modelId, ...recentModels.filter((id: string) => id !== modelId)].slice(0, 5)
      localStorage.setItem('recentModels', JSON.stringify(newRecent))

      setOpen(false)
      toast({
        title: 'Model changed',
        description: `Now using ${model.display_name}`,
      })
    } catch (error) {
      logger.error('Error updating model', { error })
      toast({
        title: 'Error',
        description: 'Failed to update model',
        variant: 'destructive',
      })
    }
  }

  const currentModel = models.find(m => m.model_id === currentConversation?.model)

  // Filter and organize models
  const filteredModels = useMemo(() => {
    if (!search) return models
    const searchLower = search.toLowerCase()
    return models.filter(model => 
      model.display_name.toLowerCase().includes(searchLower) ||
      model.model_id.toLowerCase().includes(searchLower) ||
      model.provider_name.toLowerCase().includes(searchLower)
    )
  }, [models, search])

  const quickAccessModels = QUICK_ACCESS_MODELS.map(qm => {
    const model = models.find(m => m.model_id === qm.id)
    return model ? { ...model, quickDesc: qm.desc } : null
  }).filter(Boolean) as (Model & { quickDesc: string })[]

  const favoriteModels = models.filter(m => favorites.includes(m.model_id))
  
  const modelsByProvider = useMemo(() => {
    const grouped: Record<string, Model[]> = {}
    filteredModels.forEach(model => {
      const provider = model.provider_name || 'Other'
      if (!grouped[provider]) grouped[provider] = []
      grouped[provider].push(model)
    })
    return grouped
  }, [filteredModels])

  const getModelIcon = (model: Model) => {
    if (model.tags?.includes('fast')) return <Zap className="h-4 w-4 text-yellow-500" />
    if (model.tags?.includes('powerful')) return <Brain className="h-4 w-4 text-purple-500" />
    if (model.capabilities?.vision) return <Eye className="h-4 w-4 text-blue-500" />
    if (model.is_aggregator) return <Sparkles className="h-4 w-4 text-violet-500" />
    return null
  }

  const ModelCard = ({ model, description }: { model: Model & { quickDesc?: string }, description?: string }) => (
    <div
      onClick={() => handleModelChange(model.model_id)}
      className={cn(
        "p-4 rounded-lg border cursor-pointer transition-all hover:border-primary hover:bg-muted/50",
        currentModel?.model_id === model.model_id && "border-primary bg-muted",
        !isModelAvailable(model) && "opacity-50 cursor-not-allowed"
      )}
    >
      <div className="flex items-start justify-between mb-2">
        <div className="flex items-center gap-2">
          {getModelIcon(model)}
          <h4 className="font-medium">{model.display_name}</h4>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={(e) => {
            e.stopPropagation()
            toggleFavorite(model.model_id)
          }}
        >
          <Star 
            className={cn(
              "h-4 w-4",
              favorites.includes(model.model_id) 
                ? "fill-yellow-500 text-yellow-500" 
                : "text-muted-foreground"
            )}
          />
        </Button>
      </div>
      
      <p className="text-sm text-muted-foreground mb-2">
        {description || model.quickDesc || `${model.context_window ? `${(model.context_window / 1000).toFixed(0)}K context` : ''}`}
      </p>
      
      <div className="flex items-center gap-2">
        <Badge variant={isModelAvailable(model) ? "secondary" : "outline"} className="text-xs">
          {model.tier_required.charAt(0).toUpperCase() + model.tier_required.slice(1)}
        </Badge>
        {currentModel?.model_id === model.model_id && (
          <Badge variant="default" className="text-xs">
            Current
          </Badge>
        )}
        {model.tags?.includes('new') && (
          <Badge variant="secondary" className="text-xs">
            New
          </Badge>
        )}
      </div>
    </div>
  )

  const ModelList = ({ models }: { models: Model[] }) => (
    <div className="space-y-2">
      {models.map(model => (
        <div
          key={model.model_id}
          onClick={() => handleModelChange(model.model_id)}
          className={cn(
            "flex items-center justify-between p-3 rounded-lg cursor-pointer transition-all hover:bg-muted",
            currentModel?.model_id === model.model_id && "bg-muted",
            !isModelAvailable(model) && "opacity-50 cursor-not-allowed"
          )}
        >
          <div className="flex items-center gap-3">
            <Check
              className={cn(
                "h-4 w-4",
                currentModel?.model_id === model.model_id ? "opacity-100" : "opacity-0"
              )}
            />
            {getModelIcon(model)}
            <div>
              <div className="font-medium">{model.display_name}</div>
              <div className="text-xs text-muted-foreground">
                {model.context_window && `${(model.context_window / 1000).toFixed(0)}K`}
                {model.tier_required && ` • ${model.tier_required === 'free' ? 'Free' : model.tier_required === 'pro' ? 'Pro' : 'Max'} tier`}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge 
              variant={isModelAvailable(model) ? "secondary" : "outline"} 
              className="text-xs"
              title={`Requires ${model.tier_required} tier`}
            >
              {model.tier_required === 'free' ? 'Free' : model.tier_required === 'pro' ? 'Pro' : 'Max'}
            </Badge>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={(e) => {
                e.stopPropagation()
                toggleFavorite(model.model_id)
              }}
            >
              <Star 
                className={cn(
                  "h-4 w-4",
                  favorites.includes(model.model_id) 
                    ? "fill-yellow-500 text-yellow-500" 
                    : "text-muted-foreground"
                )}
              />
            </Button>
          </div>
        </div>
      ))}
    </div>
  )

  return (
    <>
      <Button
        variant="outline"
        onClick={() => setOpen(true)}
        className="w-full sm:w-[300px] justify-between"
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

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-4xl max-h-[80vh]">
          <DialogHeader>
            <DialogTitle>Select AI Model</DialogTitle>
          </DialogHeader>
          
          <div className="relative mb-4">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Search models..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-10"
            />
          </div>

          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1">
            <TabsList className="grid w-full grid-cols-4">
              <TabsTrigger value="quick">Quick Access</TabsTrigger>
              <TabsTrigger value="favorites" className="flex items-center gap-1">
                <Star className="h-3 w-3" />
                Favorites
              </TabsTrigger>
              <TabsTrigger value="provider">By Provider</TabsTrigger>
              <TabsTrigger value="all">All Models</TabsTrigger>
            </TabsList>
            
            <div className="h-[450px] mt-4 overflow-y-auto">
              <TabsContent value="quick" className="mt-0">
                <div className="grid grid-cols-2 gap-4">
                  {quickAccessModels.map(model => (
                    <ModelCard key={model.model_id} model={model} />
                  ))}
                </div>
              </TabsContent>
              
              <TabsContent value="favorites" className="mt-0">
                {favoriteModels.length > 0 ? (
                  <ModelList models={favoriteModels} />
                ) : (
                  <div className="text-center py-8 text-muted-foreground">
                    No favorite models yet. Click the star icon to add favorites.
                  </div>
                )}
              </TabsContent>
              
              <TabsContent value="provider" className="mt-0">
                <div className="space-y-6">
                  {Object.entries(modelsByProvider).map(([provider, models]) => (
                    <div key={provider}>
                      <h3 className="font-medium mb-3 text-sm text-muted-foreground">
                        {provider} ({models.length})
                      </h3>
                      <ModelList models={models} />
                    </div>
                  ))}
                </div>
              </TabsContent>
              
              <TabsContent value="all" className="mt-0">
                <ModelList models={filteredModels} />
              </TabsContent>
            </div>
          </Tabs>
        </DialogContent>
      </Dialog>
    </>
  )
}