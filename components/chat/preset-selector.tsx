'use client'

import React, { useState, useEffect } from 'react'
import { Bot, Check, ChevronDown, Sparkles } from 'lucide-react'
import * as Icons from 'lucide-react'
import { cn } from '@/lib/utils'
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

interface Preset {
  id: string
  category_id: string | null
  name: string
  slug: string
  description: string | null
  icon: string | null
  color: string | null
  system_prompt: string
  model_preference: string | null
  temperature: number | null
  max_tokens: number | null
  is_default: boolean
  usage_count: number
}

interface PresetCategory {
  id: string
  name: string
  slug: string
  description: string | null
  icon: string | null
  color: string | null
  presets?: Preset[]
}

export function PresetSelector() {
  const supabase = createClient()
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [categories, setCategories] = useState<PresetCategory[]>([])
  const [presets, setPresets] = useState<Preset[]>([])
  const [selectedPreset, setSelectedPreset] = useState<Preset | null>(null)
  const [loading, setLoading] = useState(true)
  
  const { currentConversation } = useConversationStore()

  useEffect(() => {
    loadPresetsAndCategories()
    if (currentConversation) {
      loadCurrentSelection()
    }
  }, [currentConversation])

  const loadPresetsAndCategories = async () => {
    try {
      // Load categories
      const { data: categoriesData, error: categoriesError } = await supabase
        .from('preset_categories')
        .select('*')
        .order('sort_order', { ascending: true })

      if (categoriesError) throw categoriesError

      // Load presets
      const { data: presetsData, error: presetsError } = await supabase
        .from('presets')
        .select('*')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })

      if (presetsError) throw presetsError

      // Group presets by category
      const categoriesWithPresets = categoriesData?.map(category => ({
        ...category,
        presets: presetsData?.filter(preset => preset.category_id === category.id) || []
      })) || []

      // Add uncategorized presets
      const uncategorizedPresets = presetsData?.filter(preset => !preset.category_id) || []
      if (uncategorizedPresets.length > 0) {
        categoriesWithPresets.push({
          id: 'uncategorized',
          name: 'Other',
          slug: 'other',
          description: null,
          icon: 'MoreHorizontal',
          color: '#6b7280',
          presets: uncategorizedPresets
        })
      }

      setCategories(categoriesWithPresets)
      setPresets(presetsData || [])

      // Set default preset if no selection
      if (!selectedPreset) {
        const defaultPreset = presetsData?.find(p => p.is_default)
        if (defaultPreset) {
          setSelectedPreset(defaultPreset)
        }
      }
    } catch (error) {
      console.error('Error loading presets:', error)
    } finally {
      setLoading(false)
    }
  }

  const loadCurrentSelection = async () => {
    if (!currentConversation) return

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) return

      // Get the user's preset selection
      const { data: selection, error: selectionError } = await supabase
        .from('user_preset_selections')
        .select('preset_id')
        .eq('conversation_id', currentConversation.id)
        .eq('user_id', user.user.id)
        .single()

      if (!selectionError && selection?.preset_id) {
        // Get the preset details
        const { data: preset, error: presetError } = await supabase
          .from('presets')
          .select('*')
          .eq('id', selection.preset_id)
          .single()

        if (!presetError && preset) {
          setSelectedPreset(preset as Preset)
        }
      }
    } catch (error) {
      // No selection yet, use default
      console.log('No preset selection found, using default')
    }
  }

  const selectPreset = async (preset: Preset) => {
    if (!currentConversation) {
      toast({
        title: 'No conversation',
        description: 'Please start a conversation first',
        variant: 'destructive',
      })
      return
    }

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) return

      // Upsert user selection
      const { error } = await supabase
        .from('user_preset_selections')
        .upsert({
          user_id: user.user.id,
          conversation_id: currentConversation.id,
          preset_id: preset.id,
          selected_at: new Date().toISOString()
        }, {
          onConflict: 'user_id,conversation_id'
        })

      if (error) throw error

      setSelectedPreset(preset)
      setOpen(false)
      
      toast({
        title: 'Preset changed',
        description: `Switched to "${preset.name}"`,
      })
    } catch (error) {
      console.error('Error selecting preset:', error)
      toast({
        title: 'Error',
        description: 'Failed to change preset',
        variant: 'destructive',
      })
    }
  }

  const getIcon = (iconName: string | null) => {
    if (!iconName) return Bot
    const Icon = Icons[iconName as keyof typeof Icons]
    // Type guard to ensure it's a valid component
    if (typeof Icon === 'function') {
      return Icon as React.ComponentType<any>
    }
    return Bot
  }

  const renderPresetItem = (preset: Preset) => {
    const Icon = getIcon(preset.icon)
    const isSelected = selectedPreset?.id === preset.id

    return (
      <CommandItem
        key={preset.id}
        onSelect={() => selectPreset(preset)}
        className="flex items-start gap-3 px-2 py-3 cursor-pointer"
      >
        <div 
          className="mt-0.5 p-2 rounded-lg"
          style={{ backgroundColor: preset.color ? `${preset.color}20` : '#6366f120' }}
        >
          <Icon 
            className="h-4 w-4" 
            style={{ color: preset.color || '#6366f1' }}
          />
        </div>
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <span className="font-medium">{preset.name}</span>
            {preset.is_default && (
              <Badge variant="secondary" className="text-xs">Default</Badge>
            )}
            {isSelected && <Check className="h-4 w-4 ml-auto" />}
          </div>
          {preset.description && (
            <p className="text-sm text-muted-foreground mt-1">
              {preset.description}
            </p>
          )}
          {preset.model_preference && (
            <p className="text-xs text-muted-foreground mt-1">
              Optimized for: {preset.model_preference}
            </p>
          )}
        </div>
      </CommandItem>
    )
  }

  if (loading) {
    return (
      <Button variant="outline" size="sm" disabled>
        <Bot className="h-4 w-4 mr-2" />
        Loading...
      </Button>
    )
  }

  const SelectedIcon = getIcon(selectedPreset?.icon || null)

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          className="justify-between min-w-[200px]"
          size="sm"
        >
          <div className="flex items-center gap-2">
            {selectedPreset ? (
              <>
                <div 
                  className="p-1 rounded"
                  style={{ backgroundColor: selectedPreset.color ? `${selectedPreset.color}20` : '#6366f120' }}
                >
                  <SelectedIcon 
                    className="h-3 w-3" 
                    style={{ color: selectedPreset.color || '#6366f1' }}
                  />
                </div>
                <span className="truncate">{selectedPreset.name}</span>
              </>
            ) : (
              <>
                <Sparkles className="h-4 w-4" />
                <span>Choose a preset</span>
              </>
            )}
          </div>
          <ChevronDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[400px] p-0" align="start">
        <Command>
          <CommandInput placeholder="Search presets..." />
          <CommandEmpty>No preset found.</CommandEmpty>
          
          {categories.map((category, index) => (
            <div key={category.id}>
              {index > 0 && <CommandSeparator />}
              <CommandGroup heading={
                <div className="flex items-center gap-2">
                  {category.icon && (
                    <div 
                      className="p-1 rounded"
                      style={{ backgroundColor: category.color ? `${category.color}20` : '#6b728020' }}
                    >
                      {React.createElement(getIcon(category.icon), {
                        className: "h-3 w-3",
                        style: { color: category.color || '#6b7280' }
                      })}
                    </div>
                  )}
                  <span>{category.name}</span>
                </div>
              }>
                {category.presets?.map(preset => renderPresetItem(preset))}
              </CommandGroup>
            </div>
          ))}
        </Command>
      </PopoverContent>
    </Popover>
  )
}