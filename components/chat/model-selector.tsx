'use client'

import { useState, useEffect } from 'react'
import { Check, ChevronsUpDown } from 'lucide-react'
import { cn } from '@/lib/utils'
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

interface Model {
  id: string
  provider: string
  model: string
  display_name: string
  tier_required: 'free' | 'pro' | 'max'
  is_active: boolean
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

      // Get available models
      const { data: modelsData, error } = await supabase
        .from('model_configs')
        .select('*')
        .eq('is_active', true)
        .order('provider', { ascending: true })
        .order('display_name', { ascending: true })

      if (error) throw error

      setModels(modelsData || [])
    } catch (error) {
      console.error('Error loading models:', error)
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
    return tierOrder[userTier] >= tierOrder[model.tier_required]
  }

  const handleModelChange = async (modelId: string) => {
    const model = models.find(m => m.id === modelId)
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
          model: model.model,
          provider: model.provider,
        })
        .eq('id', currentConversation.id)

      if (error) throw error

      setCurrentConversation({
        ...currentConversation,
        model: model.model,
        provider: model.provider,
      })

      setOpen(false)
    } catch (error) {
      console.error('Error updating model:', error)
      toast({
        title: 'Error',
        description: 'Failed to update model',
        variant: 'destructive',
      })
    }
  }

  const currentModel = models.find(
    m => m.model === currentConversation?.model
  )

  const groupedModels = models.reduce((acc, model) => {
    if (!acc[model.provider]) {
      acc[model.provider] = []
    }
    acc[model.provider].push(model)
    return acc
  }, {} as Record<string, Model[]>)

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
          {currentModel ? currentModel.display_name : "Select model..."}
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[300px] p-0">
        <Command>
          <CommandInput placeholder="Search models..." />
          <CommandEmpty>No model found.</CommandEmpty>
          {Object.entries(groupedModels).map(([provider, models]) => (
            <CommandGroup key={provider} heading={provider.toUpperCase()}>
              {models.map((model) => (
                <CommandItem
                  key={model.id}
                  value={model.id}
                  onSelect={handleModelChange}
                  disabled={!isModelAvailable(model)}
                >
                  <Check
                    className={cn(
                      "mr-2 h-4 w-4",
                      currentModel?.id === model.id ? "opacity-100" : "opacity-0"
                    )}
                  />
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <span>{model.display_name}</span>
                      {!isModelAvailable(model) && (
                        <span className="text-xs text-muted-foreground">
                          {model.tier_required}
                        </span>
                      )}
                    </div>
                  </div>
                </CommandItem>
              ))}
            </CommandGroup>
          ))}
        </Command>
      </PopoverContent>
    </Popover>
  )
}