'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { useToast } from '@/hooks/use-toast'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { Slider } from '@/components/ui/slider'
import { 
  Trash2, Plus, Save, Copy, ChevronUp, ChevronDown, 
  Bot, Settings, Sparkles, Palette, Hash
} from 'lucide-react'
import * as Icons from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'

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
  is_active: boolean
  is_default: boolean
  sort_order: number
  usage_count: number
  created_at: string
  updated_at: string
}

interface PresetCategory {
  id: string
  name: string
  slug: string
  description: string | null
  icon: string | null
  color: string | null
  sort_order: number
}

export default function PresetsManagementPage() {
  const supabase = createClient()
  const { toast } = useToast()
  const [categories, setCategories] = useState<PresetCategory[]>([])
  const [presets, setPresets] = useState<Preset[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedPreset, setSelectedPreset] = useState<Preset | null>(null)
  const [selectedCategory, setSelectedCategory] = useState<PresetCategory | null>(null)
  const [activeTab, setActiveTab] = useState('presets')
  const [isCreating, setIsCreating] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    checkAdminStatus()
  }, [])

  const checkAdminStatus = async () => {
    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) {
        window.location.href = '/login'
        return
      }

      const { data, error } = await supabase
        .from('admin_users')
        .select('user_id')
        .eq('user_id', user.user.id)
        .single()

      if (error || !data) {
        toast({
          title: 'Access Denied',
          description: 'You need admin privileges to access this page',
          variant: 'destructive',
        })
        window.location.href = '/settings'
        return
      }

      setIsAdmin(true)
      loadData()
    } catch (error) {
      console.error('Error checking admin status:', error)
    }
  }

  const loadData = async () => {
    try {
      // Load categories
      const { data: categoriesData, error: categoriesError } = await supabase
        .from('preset_categories')
        .select('*')
        .order('sort_order', { ascending: true })

      if (categoriesError) throw categoriesError
      setCategories(categoriesData || [])

      // Load presets
      const { data: presetsData, error: presetsError } = await supabase
        .from('presets')
        .select('*')
        .order('category_id', { ascending: true })
        .order('sort_order', { ascending: true })

      if (presetsError) throw presetsError
      setPresets(presetsData || [])
    } catch (error) {
      console.error('Error loading data:', error)
      toast({
        title: 'Error',
        description: 'Failed to load presets data',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSavePreset = async () => {
    if (!selectedPreset) return

    try {
      const { error } = await supabase
        .from('presets')
        .update({
          name: selectedPreset.name,
          slug: selectedPreset.slug,
          description: selectedPreset.description,
          category_id: selectedPreset.category_id,
          icon: selectedPreset.icon,
          color: selectedPreset.color,
          system_prompt: selectedPreset.system_prompt,
          model_preference: selectedPreset.model_preference,
          temperature: selectedPreset.temperature,
          max_tokens: selectedPreset.max_tokens,
          is_active: selectedPreset.is_active,
          is_default: selectedPreset.is_default,
          sort_order: selectedPreset.sort_order,
          updated_at: new Date().toISOString(),
        })
        .eq('id', selectedPreset.id)

      if (error) throw error

      await loadData()
      toast({
        title: 'Success',
        description: 'Preset updated successfully',
      })
    } catch (error) {
      console.error('Error saving preset:', error)
      toast({
        title: 'Error',
        description: 'Failed to save preset',
        variant: 'destructive',
      })
    }
  }

  const handleCreatePreset = async () => {
    if (!selectedPreset) return

    try {
      const { data: user } = await supabase.auth.getUser()
      if (!user.user) throw new Error('Not authenticated')

      const { error } = await supabase
        .from('presets')
        .insert({
          name: selectedPreset.name,
          slug: selectedPreset.slug,
          description: selectedPreset.description,
          category_id: selectedPreset.category_id,
          icon: selectedPreset.icon,
          color: selectedPreset.color,
          system_prompt: selectedPreset.system_prompt,
          model_preference: selectedPreset.model_preference,
          temperature: selectedPreset.temperature,
          max_tokens: selectedPreset.max_tokens,
          is_active: selectedPreset.is_active,
          is_default: selectedPreset.is_default,
          sort_order: selectedPreset.sort_order,
          created_by: user.user.id,
        })

      if (error) throw error

      await loadData()
      setSelectedPreset(null)
      setIsCreating(false)
      toast({
        title: 'Success',
        description: 'Preset created successfully',
      })
    } catch (error) {
      console.error('Error creating preset:', error)
      toast({
        title: 'Error',
        description: 'Failed to create preset',
        variant: 'destructive',
      })
    }
  }

  const handleDeletePreset = async (id: string) => {
    if (!confirm('Are you sure you want to delete this preset?')) return

    try {
      const { error } = await supabase
        .from('presets')
        .delete()
        .eq('id', id)

      if (error) throw error

      await loadData()
      if (selectedPreset?.id === id) {
        setSelectedPreset(null)
      }
      toast({
        title: 'Success',
        description: 'Preset deleted successfully',
      })
    } catch (error) {
      console.error('Error deleting preset:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete preset',
        variant: 'destructive',
      })
    }
  }

  const handleDuplicatePreset = (preset: Preset) => {
    setSelectedPreset({
      ...preset,
      id: crypto.randomUUID(),
      name: `${preset.name} (Copy)`,
      slug: `${preset.slug}-copy`,
      is_default: false,
      usage_count: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    setIsCreating(true)
  }

  const handleMovePreset = async (preset: Preset, direction: 'up' | 'down') => {
    const categoryPresets = presets.filter(p => p.category_id === preset.category_id)
    const currentIndex = categoryPresets.findIndex(p => p.id === preset.id)
    
    if (
      (direction === 'up' && currentIndex === 0) ||
      (direction === 'down' && currentIndex === categoryPresets.length - 1)
    ) {
      return
    }

    const swapIndex = direction === 'up' ? currentIndex - 1 : currentIndex + 1
    const swapPreset = categoryPresets[swapIndex]

    try {
      // Swap sort orders
      await supabase
        .from('presets')
        .update({ sort_order: swapPreset.sort_order })
        .eq('id', preset.id)

      await supabase
        .from('presets')
        .update({ sort_order: preset.sort_order })
        .eq('id', swapPreset.id)

      await loadData()
    } catch (error) {
      console.error('Error reordering presets:', error)
      toast({
        title: 'Error',
        description: 'Failed to reorder presets',
        variant: 'destructive',
      })
    }
  }

  const createNewPreset = () => {
    setSelectedPreset({
      id: crypto.randomUUID(),
      category_id: categories[0]?.id || null,
      name: 'New Preset',
      slug: 'new-preset',
      description: '',
      icon: 'Bot',
      color: '#6366f1',
      system_prompt: 'You are a helpful AI assistant.',
      model_preference: null,
      temperature: 0.7,
      max_tokens: null,
      is_active: true,
      is_default: false,
      sort_order: presets.length,
      usage_count: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    setIsCreating(true)
  }

  const getIcon = (iconName: string | null) => {
    if (!iconName) return Bot
    const Icon = Icons[iconName as keyof typeof Icons]
    return Icon || Bot
  }

  const iconOptions = [
    'Bot', 'Brain', 'Sparkles', 'Zap', 'MessageSquare', 'Code2', 'Terminal',
    'PenTool', 'Lightbulb', 'GraduationCap', 'BookOpen', 'Search', 'Mail',
    'FileText', 'Bug', 'Rocket', 'Heart', 'Star', 'Shield', 'Target'
  ]

  const colorOptions = [
    '#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', 
    '#3b82f6', '#06b6d4', '#84cc16', '#f97316', '#ef4444'
  ]

  if (loading || !isAdmin) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    )
  }

  return (
    <div className="container mx-auto py-6 max-w-7xl">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">Preset Management</h1>
        <p className="text-muted-foreground">
          Configure AI presets for different use cases
        </p>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="mb-6">
          <TabsTrigger value="presets">Presets</TabsTrigger>
          <TabsTrigger value="categories">Categories</TabsTrigger>
          <TabsTrigger value="analytics">Analytics</TabsTrigger>
        </TabsList>

        <TabsContent value="presets">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {/* Preset List */}
            <div className="md:col-span-1">
              <Card>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <CardTitle>Presets</CardTitle>
                    <Button size="sm" onClick={createNewPreset}>
                      <Plus className="h-4 w-4 mr-1" />
                      New
                    </Button>
                  </div>
                </CardHeader>
                <CardContent className="p-0">
                  <div className="max-h-[700px] overflow-y-auto">
                    {categories.map(category => {
                      const categoryPresets = presets.filter(p => p.category_id === category.id)
                      if (categoryPresets.length === 0) return null

                      return (
                        <div key={category.id} className="border-b last:border-0">
                          <div className="px-4 py-2 bg-muted/50">
                            <div className="flex items-center gap-2 text-sm font-medium">
                              {React.createElement(getIcon(category.icon), {
                                className: "h-4 w-4",
                                style: { color: category.color || '#6b7280' }
                              })}
                              {category.name}
                            </div>
                          </div>
                          {categoryPresets.map((preset, index) => (
                            <div
                              key={preset.id}
                              className={`px-4 py-3 cursor-pointer hover:bg-muted/50 border-b last:border-0 ${
                                selectedPreset?.id === preset.id ? 'bg-muted' : ''
                              }`}
                              onClick={() => {
                                setSelectedPreset(preset)
                                setIsCreating(false)
                              }}
                            >
                              <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                  {React.createElement(getIcon(preset.icon), {
                                    className: "h-4 w-4",
                                    style: { color: preset.color || '#6366f1' }
                                  })}
                                  <span className="font-medium">{preset.name}</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  <Button
                                    size="icon"
                                    variant="ghost"
                                    className="h-6 w-6"
                                    onClick={(e) => {
                                      e.stopPropagation()
                                      handleMovePreset(preset, 'up')
                                    }}
                                    disabled={index === 0}
                                  >
                                    <ChevronUp className="h-3 w-3" />
                                  </Button>
                                  <Button
                                    size="icon"
                                    variant="ghost"
                                    className="h-6 w-6"
                                    onClick={(e) => {
                                      e.stopPropagation()
                                      handleMovePreset(preset, 'down')
                                    }}
                                    disabled={index === categoryPresets.length - 1}
                                  >
                                    <ChevronDown className="h-3 w-3" />
                                  </Button>
                                </div>
                              </div>
                              <div className="flex items-center gap-2 mt-1">
                                {preset.is_default && (
                                  <Badge variant="secondary" className="text-xs">Default</Badge>
                                )}
                                {!preset.is_active && (
                                  <Badge variant="outline" className="text-xs">Inactive</Badge>
                                )}
                                <span className="text-xs text-muted-foreground">
                                  Used {preset.usage_count} times
                                </span>
                              </div>
                            </div>
                          ))}
                        </div>
                      )
                    })}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Preset Editor */}
            <div className="md:col-span-2">
              {selectedPreset ? (
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <CardTitle>
                        {isCreating ? 'Create Preset' : 'Edit Preset'}
                      </CardTitle>
                      <div className="flex items-center gap-2">
                        {!isCreating && (
                          <>
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => handleDuplicatePreset(selectedPreset)}
                            >
                              <Copy className="h-4 w-4 mr-1" />
                              Duplicate
                            </Button>
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => handleDeletePreset(selectedPreset.id)}
                            >
                              <Trash2 className="h-4 w-4 mr-1" />
                              Delete
                            </Button>
                          </>
                        )}
                        <Button
                          size="sm"
                          onClick={isCreating ? handleCreatePreset : handleSavePreset}
                        >
                          <Save className="h-4 w-4 mr-1" />
                          {isCreating ? 'Create' : 'Save'}
                        </Button>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-6">
                    {/* Basic Info */}
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <Label htmlFor="name">Name</Label>
                        <Input
                          id="name"
                          value={selectedPreset.name}
                          onChange={(e) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              name: e.target.value,
                              slug: e.target.value.toLowerCase().replace(/\s+/g, '-'),
                            })
                          }
                        />
                      </div>
                      <div>
                        <Label htmlFor="category">Category</Label>
                        <Select
                          value={selectedPreset.category_id || ''}
                          onValueChange={(value) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              category_id: value || null,
                            })
                          }
                        >
                          <SelectTrigger id="category">
                            <SelectValue placeholder="Select category" />
                          </SelectTrigger>
                          <SelectContent>
                            {categories.map((category) => (
                              <SelectItem key={category.id} value={category.id}>
                                {category.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>

                    <div>
                      <Label htmlFor="description">Description</Label>
                      <Input
                        id="description"
                        value={selectedPreset.description || ''}
                        onChange={(e) =>
                          setSelectedPreset({
                            ...selectedPreset,
                            description: e.target.value,
                          })
                        }
                        placeholder="Brief description of this preset"
                      />
                    </div>

                    {/* Visual Settings */}
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <Label>Icon</Label>
                        <Dialog>
                          <DialogTrigger asChild>
                            <Button variant="outline" className="w-full justify-start">
                              {React.createElement(getIcon(selectedPreset.icon), {
                                className: "h-4 w-4 mr-2",
                                style: { color: selectedPreset.color || '#6366f1' }
                              })}
                              {selectedPreset.icon || 'Choose icon'}
                            </Button>
                          </DialogTrigger>
                          <DialogContent>
                            <DialogHeader>
                              <DialogTitle>Choose Icon</DialogTitle>
                              <DialogDescription>
                                Select an icon for this preset
                              </DialogDescription>
                            </DialogHeader>
                            <div className="grid grid-cols-5 gap-2 mt-4">
                              {iconOptions.map((iconName) => {
                                const Icon = getIcon(iconName)
                                return (
                                  <Button
                                    key={iconName}
                                    variant={selectedPreset.icon === iconName ? 'default' : 'outline'}
                                    size="icon"
                                    onClick={() =>
                                      setSelectedPreset({
                                        ...selectedPreset,
                                        icon: iconName,
                                      })
                                    }
                                  >
                                    <Icon className="h-4 w-4" />
                                  </Button>
                                )
                              })}
                            </div>
                          </DialogContent>
                        </Dialog>
                      </div>
                      <div>
                        <Label>Color</Label>
                        <Dialog>
                          <DialogTrigger asChild>
                            <Button variant="outline" className="w-full justify-start">
                              <div
                                className="h-4 w-4 rounded mr-2"
                                style={{ backgroundColor: selectedPreset.color || '#6366f1' }}
                              />
                              {selectedPreset.color || 'Choose color'}
                            </Button>
                          </DialogTrigger>
                          <DialogContent>
                            <DialogHeader>
                              <DialogTitle>Choose Color</DialogTitle>
                              <DialogDescription>
                                Select a color for this preset
                              </DialogDescription>
                            </DialogHeader>
                            <div className="grid grid-cols-5 gap-2 mt-4">
                              {colorOptions.map((color) => (
                                <Button
                                  key={color}
                                  variant={selectedPreset.color === color ? 'default' : 'outline'}
                                  size="icon"
                                  onClick={() =>
                                    setSelectedPreset({
                                      ...selectedPreset,
                                      color,
                                    })
                                  }
                                >
                                  <div
                                    className="h-6 w-6 rounded"
                                    style={{ backgroundColor: color }}
                                  />
                                </Button>
                              ))}
                            </div>
                          </DialogContent>
                        </Dialog>
                      </div>
                    </div>

                    {/* System Prompt */}
                    <div>
                      <Label htmlFor="system_prompt">System Prompt</Label>
                      <Textarea
                        id="system_prompt"
                        value={selectedPreset.system_prompt}
                        onChange={(e) =>
                          setSelectedPreset({
                            ...selectedPreset,
                            system_prompt: e.target.value,
                          })
                        }
                        rows={10}
                        className="font-mono text-sm"
                        placeholder="Enter the system prompt..."
                      />
                    </div>

                    {/* AI Settings */}
                    <div className="space-y-4">
                      <h3 className="text-lg font-semibold">AI Settings</h3>
                      
                      <div>
                        <Label htmlFor="model_preference">Model Preference</Label>
                        <Input
                          id="model_preference"
                          value={selectedPreset.model_preference || ''}
                          onChange={(e) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              model_preference: e.target.value || null,
                            })
                          }
                          placeholder="e.g., gpt-4, claude-3-opus, or leave empty for any"
                        />
                      </div>

                      <div>
                        <Label htmlFor="temperature">
                          Temperature: {selectedPreset.temperature?.toFixed(2) || '0.70'}
                        </Label>
                        <Slider
                          id="temperature"
                          min={0}
                          max={2}
                          step={0.1}
                          value={[selectedPreset.temperature || 0.7]}
                          onValueChange={([value]) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              temperature: value,
                            })
                          }
                          className="mt-2"
                        />
                      </div>

                      <div>
                        <Label htmlFor="max_tokens">Max Tokens (optional)</Label>
                        <Input
                          id="max_tokens"
                          type="number"
                          value={selectedPreset.max_tokens || ''}
                          onChange={(e) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              max_tokens: e.target.value ? parseInt(e.target.value) : null,
                            })
                          }
                          placeholder="Leave empty for model default"
                        />
                      </div>
                    </div>

                    {/* Status */}
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-2">
                        <Switch
                          id="is_active"
                          checked={selectedPreset.is_active}
                          onCheckedChange={(checked) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              is_active: checked,
                            })
                          }
                        />
                        <Label htmlFor="is_active">Active</Label>
                      </div>
                      <div className="flex items-center space-x-2">
                        <Switch
                          id="is_default"
                          checked={selectedPreset.is_default}
                          onCheckedChange={(checked) =>
                            setSelectedPreset({
                              ...selectedPreset,
                              is_default: checked,
                            })
                          }
                        />
                        <Label htmlFor="is_default">Default Preset</Label>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ) : (
                <Card>
                  <CardContent className="flex items-center justify-center h-[600px] text-muted-foreground">
                    Select a preset to edit or create a new one
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        </TabsContent>

        <TabsContent value="categories">
          <Card>
            <CardHeader>
              <CardTitle>Category Management</CardTitle>
              <CardDescription>
                Organize presets into categories
              </CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-muted-foreground">
                Category management coming soon...
              </p>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="analytics">
          <Card>
            <CardHeader>
              <CardTitle>Usage Analytics</CardTitle>
              <CardDescription>
                See which presets are most popular
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {presets
                  .sort((a, b) => b.usage_count - a.usage_count)
                  .slice(0, 10)
                  .map((preset) => (
                    <div key={preset.id} className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        {React.createElement(getIcon(preset.icon), {
                          className: "h-4 w-4",
                          style: { color: preset.color || '#6366f1' }
                        })}
                        <span>{preset.name}</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-muted-foreground">
                          {preset.usage_count} uses
                        </span>
                        <Progress
                          value={(preset.usage_count / Math.max(...presets.map(p => p.usage_count), 1)) * 100}
                          className="w-[100px]"
                        />
                      </div>
                    </div>
                  ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}