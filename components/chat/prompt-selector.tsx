'use client'

import { useState, useEffect } from 'react'
import { Check, ChevronDown, Plus, Settings } from 'lucide-react'
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
import { Database } from '@/types/database'

type PromptTemplate = Database['public']['Tables']['prompt_templates']['Row']
type UserPromptConfig = Database['public']['Tables']['user_prompt_configs']['Row']

interface PromptSelectorProps {
  onOpenSettings?: () => void
}

interface UserPromptConfigWithTemplate extends UserPromptConfig {
  prompt_templates?: PromptTemplate
}

export function PromptSelector({ onOpenSettings }: PromptSelectorProps) {
  const supabase = createClient()
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [templates, setTemplates] = useState<PromptTemplate[]>([])
  const [currentConfig, setCurrentConfig] = useState<UserPromptConfigWithTemplate | null>(null)
  const [loading, setLoading] = useState(true)
  
  const { currentConversation } = useConversationStore()

  useEffect(() => {
    if (currentConversation) {
      loadTemplates()
      loadCurrentConfig()
    }
  }, [currentConversation])

  const loadTemplates = async () => {
    try {
      const { data, error } = await supabase
        .from('prompt_templates')
        .select('*')
        .eq('is_active', true)
        .order('role', { ascending: true })
        .order('name', { ascending: true })

      if (error) throw error
      setTemplates(data || [])
    } catch (error) {
      console.error('Error loading templates:', error)
    }
  }

  const loadCurrentConfig = async () => {
    if (!currentConversation) return

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) return

      const { data, error } = await supabase
        .from('user_prompt_configs')
        .select('*, prompt_templates(*)')
        .eq('conversation_id', currentConversation.id)
        .eq('user_id', user.user.id)
        .single()

      if (error && error.code !== 'PGRST116') throw error
      setCurrentConfig(data)
    } catch (error) {
      console.error('Error loading config:', error)
    } finally {
      setLoading(false)
    }
  }

  const selectTemplate = async (template: PromptTemplate | null) => {
    if (!currentConversation) return

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) return

      if (template) {
        // Upsert user config
        const { error } = await supabase
          .from('user_prompt_configs')
          .upsert({
            user_id: user.user.id,
            conversation_id: currentConversation.id,
            template_id: template.id,
            variables: template.variables
          }, {
            onConflict: 'user_id,conversation_id'
          })

        if (error) throw error
      } else {
        // Delete config to use default
        const { error } = await supabase
          .from('user_prompt_configs')
          .delete()
          .eq('conversation_id', currentConversation.id)
          .eq('user_id', user.user.id)

        if (error && error.code !== 'PGRST116') throw error
      }

      await loadCurrentConfig()
      setOpen(false)
      
      toast({
        title: 'Success',
        description: template 
          ? `Switched to "${template.name}" prompt`
          : 'Switched to default prompt',
      })
    } catch (error) {
      console.error('Error selecting template:', error)
      toast({
        title: 'Error',
        description: 'Failed to update prompt template',
        variant: 'destructive',
      })
    }
  }

  const currentTemplate = currentConfig?.prompt_templates
  const groupedTemplates = templates.reduce((acc, template) => {
    const role = template.role || 'custom'
    if (!acc[role]) acc[role] = []
    acc[role].push(template)
    return acc
  }, {} as Record<string, PromptTemplate[]>)

  const roleLabels: Record<string, string> = {
    default: 'General',
    programming: 'Programming',
    writing: 'Writing',
    analysis: 'Analysis',
    creative: 'Creative',
    educational: 'Educational',
    custom: 'Custom',
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          className="w-[200px] justify-between"
          size="sm"
        >
          <span className="truncate">
            {currentTemplate ? currentTemplate.name : "Default Assistant"}
          </span>
          <ChevronDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[300px] p-0">
        <Command>
          <CommandInput placeholder="Search prompts..." />
          <CommandEmpty>No prompt found.</CommandEmpty>
          
          {/* Default option */}
          <CommandGroup heading="System Default">
            <CommandItem
              onSelect={() => selectTemplate(null)}
            >
              <Check
                className={cn(
                  "mr-2 h-4 w-4",
                  !currentTemplate ? "opacity-100" : "opacity-0"
                )}
              />
              Default Assistant
              <span className="ml-auto text-xs text-muted-foreground">
                Auto-detect
              </span>
            </CommandItem>
          </CommandGroup>

          {/* Template groups */}
          {Object.entries(groupedTemplates).map(([role, templates]) => (
            <CommandGroup key={role} heading={roleLabels[role] || role}>
              {templates.map((template) => (
                <CommandItem
                  key={template.id}
                  onSelect={() => selectTemplate(template)}
                >
                  <Check
                    className={cn(
                      "mr-2 h-4 w-4",
                      currentTemplate?.id === template.id ? "opacity-100" : "opacity-0"
                    )}
                  />
                  <div className="flex flex-col">
                    <span>{template.name}</span>
                    {template.description && (
                      <span className="text-xs text-muted-foreground">
                        {template.description}
                      </span>
                    )}
                  </div>
                </CommandItem>
              ))}
            </CommandGroup>
          ))}
          
          {/* Settings option */}
          {onOpenSettings && (
            <CommandGroup>
              <CommandItem
                onSelect={() => {
                  setOpen(false)
                  onOpenSettings()
                }}
              >
                <Settings className="mr-2 h-4 w-4" />
                Manage Prompts
              </CommandItem>
            </CommandGroup>
          )}
        </Command>
      </PopoverContent>
    </Popover>
  )
}