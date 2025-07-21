'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Database } from '@/types/database'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { useToast } from '@/hooks/use-toast'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Trash2, Plus, Save, Copy } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

type PromptTemplate = Database['public']['Tables']['prompt_templates']['Row']

export default function PromptsSettingsPage() {
  const supabase = createClient()
  const { toast } = useToast()
  const [templates, setTemplates] = useState<PromptTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedTemplate, setSelectedTemplate] = useState<PromptTemplate | null>(null)
  const [isCreating, setIsCreating] = useState(false)

  useEffect(() => {
    loadTemplates()
  }, [])

  const loadTemplates = async () => {
    try {
      const { data, error } = await supabase
        .from('prompt_templates')
        .select('*')
        .order('role', { ascending: true })
        .order('name', { ascending: true })

      if (error) throw error
      setTemplates(data || [])
    } catch (error) {
      console.error('Error loading templates:', error)
      toast({
        title: 'Error',
        description: 'Failed to load prompt templates',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSave = async () => {
    if (!selectedTemplate) return

    try {
      const { error } = await supabase
        .from('prompt_templates')
        .update({
          name: selectedTemplate.name,
          description: selectedTemplate.description,
          role: selectedTemplate.role,
          model_type: selectedTemplate.model_type,
          template: selectedTemplate.template,
          is_active: selectedTemplate.is_active,
          updated_at: new Date().toISOString(),
        })
        .eq('id', selectedTemplate.id)

      if (error) throw error

      await loadTemplates()
      toast({
        title: 'Success',
        description: 'Prompt template updated successfully',
      })
    } catch (error) {
      console.error('Error saving template:', error)
      toast({
        title: 'Error',
        description: 'Failed to save prompt template',
        variant: 'destructive',
      })
    }
  }

  const handleCreate = async () => {
    if (!selectedTemplate) return

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) throw new Error('Not authenticated')

      const { error } = await supabase
        .from('prompt_templates')
        .insert({
          name: selectedTemplate.name,
          description: selectedTemplate.description,
          role: selectedTemplate.role as any,
          model_type: selectedTemplate.model_type as any,
          template: selectedTemplate.template,
          is_active: selectedTemplate.is_active,
          created_by: user.user.id,
          variables: {},
        })

      if (error) throw error

      await loadTemplates()
      setSelectedTemplate(null)
      setIsCreating(false)
      toast({
        title: 'Success',
        description: 'Prompt template created successfully',
      })
    } catch (error) {
      console.error('Error creating template:', error)
      toast({
        title: 'Error',
        description: 'Failed to create prompt template',
        variant: 'destructive',
      })
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this template?')) return

    try {
      const { error } = await supabase
        .from('prompt_templates')
        .delete()
        .eq('id', id)

      if (error) throw error

      await loadTemplates()
      if (selectedTemplate?.id === id) {
        setSelectedTemplate(null)
      }
      toast({
        title: 'Success',
        description: 'Prompt template deleted successfully',
      })
    } catch (error) {
      console.error('Error deleting template:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete prompt template',
        variant: 'destructive',
      })
    }
  }

  const handleDuplicate = (template: PromptTemplate) => {
    setSelectedTemplate({
      ...template,
      id: crypto.randomUUID(),
      name: `${template.name} (Copy)`,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    setIsCreating(true)
  }

  const createNewTemplate = () => {
    setSelectedTemplate({
      id: crypto.randomUUID(),
      name: 'New Template',
      description: '',
      role: 'custom',
      model_type: 'general',
      template: 'You are a helpful AI assistant.',
      variables: {},
      is_active: true,
      created_by: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    setIsCreating(true)
  }

  const roleOptions = [
    { value: 'default', label: 'Default' },
    { value: 'programming', label: 'Programming' },
    { value: 'writing', label: 'Writing' },
    { value: 'analysis', label: 'Analysis' },
    { value: 'creative', label: 'Creative' },
    { value: 'educational', label: 'Educational' },
    { value: 'custom', label: 'Custom' },
  ]

  const modelTypeOptions = [
    { value: 'general', label: 'All Models' },
    { value: 'claude', label: 'Claude' },
    { value: 'gpt', label: 'GPT' },
    { value: 'gemini', label: 'Gemini' },
  ]

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    )
  }

  return (
    <div className="container mx-auto py-6 max-w-7xl">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">Prompt Templates</h1>
        <p className="text-muted-foreground">
          Manage system prompts for different AI models and use cases
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Template List */}
        <div className="md:col-span-1">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle>Templates</CardTitle>
                <Button size="sm" onClick={createNewTemplate}>
                  <Plus className="h-4 w-4 mr-1" />
                  New
                </Button>
              </div>
            </CardHeader>
            <CardContent className="p-0">
              <div className="max-h-[600px] overflow-y-auto">
                {templates.map((template) => (
                  <div
                    key={template.id}
                    className={`p-4 border-b cursor-pointer hover:bg-muted/50 ${
                      selectedTemplate?.id === template.id ? 'bg-muted' : ''
                    }`}
                    onClick={() => {
                      setSelectedTemplate(template)
                      setIsCreating(false)
                    }}
                  >
                    <div className="flex items-center justify-between mb-1">
                      <h4 className="font-medium">{template.name}</h4>
                      {!template.is_active && (
                        <Badge variant="secondary">Inactive</Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Badge variant="outline">{template.role}</Badge>
                      {template.model_type && template.model_type !== 'general' && (
                        <Badge variant="outline">{template.model_type}</Badge>
                      )}
                    </div>
                    {template.description && (
                      <p className="text-sm text-muted-foreground mt-1">
                        {template.description}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Template Editor */}
        <div className="md:col-span-2">
          {selectedTemplate ? (
            <Card>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle>
                    {isCreating ? 'Create Template' : 'Edit Template'}
                  </CardTitle>
                  <div className="flex items-center gap-2">
                    {!isCreating && (
                      <>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleDuplicate(selectedTemplate)}
                        >
                          <Copy className="h-4 w-4 mr-1" />
                          Duplicate
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleDelete(selectedTemplate.id)}
                        >
                          <Trash2 className="h-4 w-4 mr-1" />
                          Delete
                        </Button>
                      </>
                    )}
                    <Button
                      size="sm"
                      onClick={isCreating ? handleCreate : handleSave}
                    >
                      <Save className="h-4 w-4 mr-1" />
                      {isCreating ? 'Create' : 'Save'}
                    </Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label htmlFor="name">Name</Label>
                    <Input
                      id="name"
                      value={selectedTemplate.name}
                      onChange={(e) =>
                        setSelectedTemplate({
                          ...selectedTemplate,
                          name: e.target.value,
                        })
                      }
                    />
                  </div>
                  <div>
                    <Label htmlFor="role">Role</Label>
                    <Select
                      value={selectedTemplate.role}
                      onValueChange={(value) =>
                        setSelectedTemplate({
                          ...selectedTemplate,
                          role: value as any,
                        })
                      }
                    >
                      <SelectTrigger id="role">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {roleOptions.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label htmlFor="model_type">Model Type</Label>
                    <Select
                      value={selectedTemplate.model_type || 'general'}
                      onValueChange={(value) =>
                        setSelectedTemplate({
                          ...selectedTemplate,
                          model_type: value as any,
                        })
                      }
                    >
                      <SelectTrigger id="model_type">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {modelTypeOptions.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Switch
                      id="is_active"
                      checked={selectedTemplate.is_active}
                      onCheckedChange={(checked) =>
                        setSelectedTemplate({
                          ...selectedTemplate,
                          is_active: checked,
                        })
                      }
                    />
                    <Label htmlFor="is_active">Active</Label>
                  </div>
                </div>

                <div>
                  <Label htmlFor="description">Description</Label>
                  <Input
                    id="description"
                    value={selectedTemplate.description || ''}
                    onChange={(e) =>
                      setSelectedTemplate({
                        ...selectedTemplate,
                        description: e.target.value,
                      })
                    }
                    placeholder="Brief description of this template"
                  />
                </div>

                <div>
                  <Label htmlFor="template">Template</Label>
                  <Textarea
                    id="template"
                    value={selectedTemplate.template}
                    onChange={(e) =>
                      setSelectedTemplate({
                        ...selectedTemplate,
                        template: e.target.value,
                      })
                    }
                    rows={15}
                    className="font-mono text-sm"
                    placeholder="Enter your prompt template here..."
                  />
                  <p className="text-sm text-muted-foreground mt-2">
                    Supported variables: {'{{MODEL_NAME}}'}, {'{{CURRENT_DATE}}'}, {'{{USER_TIER}}'}, {'{{USER_LANGUAGE}}'}
                  </p>
                </div>
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardContent className="flex items-center justify-center h-[600px] text-muted-foreground">
                Select a template to edit or create a new one
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  )
}