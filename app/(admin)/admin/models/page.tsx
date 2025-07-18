'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/hooks/use-toast'
import { 
  Settings, 
  Save,
  Plus,
  Edit2,
  Trash2,
  DollarSign,
  Zap,
  Shield,
  X
} from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from '@/components/ui/tabs'

interface ModelConfig {
  id: string
  provider: string
  model: string
  display_name: string
  provider_model_id: string | null
  input_price: number
  output_price: number
  max_tokens: number
  context_window: number
  tier_required: 'free' | 'pro' | 'max'
  is_active: boolean
  supports_streaming: boolean
  supports_functions: boolean
  default_temperature: number
  created_at: string
  updated_at: string
}

const PROVIDERS = [
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic' },
  { value: 'google', label: 'Google' },
  { value: 'bedrock', label: 'AWS Bedrock' }
]

const TIER_OPTIONS = [
  { value: 'free', label: 'Free', color: 'bg-gray-500' },
  { value: 'pro', label: 'Pro', color: 'bg-blue-500' },
  { value: 'max', label: 'Max', color: 'bg-purple-500' }
]

export default function ModelsPage() {
  const [models, setModels] = useState<ModelConfig[]>([])
  const [loading, setLoading] = useState(true)
  const [editingModel, setEditingModel] = useState<ModelConfig | null>(null)
  const [isAddingModel, setIsAddingModel] = useState(false)
  const [saving, setSaving] = useState(false)
  const [selectedProvider, setSelectedProvider] = useState<string>('all')
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadModels()
  }, [])

  const loadModels = async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('model_configs')
        .select('*')
        .order('provider', { ascending: true })
        .order('display_name', { ascending: true })

      if (error) throw error
      setModels(data || [])
    } catch (error) {
      console.error('Error loading models:', error)
      toast({
        title: 'Error',
        description: 'Failed to load model configurations',
        variant: 'destructive'
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSaveModel = async () => {
    if (!editingModel) return

    setSaving(true)
    try {
      const modelData = {
        provider: editingModel.provider,
        model: editingModel.model,
        display_name: editingModel.display_name,
        provider_model_id: editingModel.provider_model_id,
        input_price: editingModel.input_price,
        output_price: editingModel.output_price,
        max_tokens: editingModel.max_tokens,
        context_window: editingModel.context_window,
        tier_required: editingModel.tier_required,
        is_active: editingModel.is_active,
        supports_streaming: editingModel.supports_streaming,
        supports_functions: editingModel.supports_functions,
        default_temperature: editingModel.default_temperature
      }

      if (editingModel.id) {
        // Update existing model
        const { error } = await supabase
          .from('model_configs')
          .update(modelData)
          .eq('id', editingModel.id)

        if (error) throw error
      } else {
        // Insert new model
        const { error } = await supabase
          .from('model_configs')
          .insert(modelData)

        if (error) throw error
      }

      toast({
        title: 'Success',
        description: editingModel.id ? 'Model updated successfully' : 'Model added successfully'
      })

      setEditingModel(null)
      setIsAddingModel(false)
      loadModels()
    } catch (error) {
      console.error('Error saving model:', error)
      toast({
        title: 'Error',
        description: 'Failed to save model configuration',
        variant: 'destructive'
      })
    } finally {
      setSaving(false)
    }
  }

  const handleDeleteModel = async (id: string) => {
    if (!confirm('Are you sure you want to delete this model?')) return

    try {
      const { error } = await supabase
        .from('model_configs')
        .delete()
        .eq('id', id)

      if (error) throw error

      toast({
        title: 'Success',
        description: 'Model deleted successfully'
      })

      loadModels()
    } catch (error) {
      console.error('Error deleting model:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete model',
        variant: 'destructive'
      })
    }
  }

  const toggleModelActive = async (model: ModelConfig) => {
    try {
      const { error } = await supabase
        .from('model_configs')
        .update({ is_active: !model.is_active })
        .eq('id', model.id)

      if (error) throw error

      toast({
        title: 'Success',
        description: `Model ${!model.is_active ? 'activated' : 'deactivated'} successfully`
      })

      loadModels()
    } catch (error) {
      console.error('Error toggling model:', error)
      toast({
        title: 'Error',
        description: 'Failed to update model status',
        variant: 'destructive'
      })
    }
  }

  const filteredModels = selectedProvider === 'all' 
    ? models 
    : models.filter(m => m.provider === selectedProvider)

  const providerStats = PROVIDERS.map(provider => {
    const providerModels = models.filter(m => m.provider === provider.value)
    return {
      ...provider,
      total: providerModels.length,
      active: providerModels.filter(m => m.is_active).length
    }
  })

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Provider Stats */}
      <div className="grid gap-4 md:grid-cols-4">
        {providerStats.map(stat => (
          <Card key={stat.value}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">{stat.label}</CardTitle>
              <Settings className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stat.active}/{stat.total}</div>
              <p className="text-xs text-muted-foreground">Active models</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Models Management */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Model Configurations</CardTitle>
              <CardDescription>Configure AI models, pricing, and access tiers</CardDescription>
            </div>
            <Button onClick={() => {
              setEditingModel({
                id: '',
                provider: 'openai',
                model: '',
                display_name: '',
                provider_model_id: null,
                input_price: 0,
                output_price: 0,
                max_tokens: 4096,
                context_window: 128000,
                tier_required: 'free',
                is_active: true,
                supports_streaming: true,
                supports_functions: false,
                default_temperature: 0.7,
                created_at: '',
                updated_at: ''
              })
              setIsAddingModel(true)
            }}>
              <Plus className="mr-2 h-4 w-4" />
              Add Model
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {/* Provider Filter */}
          <div className="mb-4">
            <Tabs value={selectedProvider} onValueChange={setSelectedProvider}>
              <TabsList>
                <TabsTrigger value="all">All Providers</TabsTrigger>
                {PROVIDERS.map(provider => (
                  <TabsTrigger key={provider.value} value={provider.value}>
                    {provider.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>

          {/* Models Table */}
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Model</TableHead>
                  <TableHead>Provider</TableHead>
                  <TableHead>Pricing</TableHead>
                  <TableHead>Limits</TableHead>
                  <TableHead>Tier</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredModels.map((model) => {
                  const tierConfig = TIER_OPTIONS.find(t => t.value === model.tier_required)
                  
                  return (
                    <TableRow key={model.id}>
                      <TableCell>
                        <div>
                          <p className="font-medium">{model.display_name}</p>
                          <p className="text-sm text-muted-foreground">{model.model}</p>
                          {model.provider_model_id && (
                            <p className="text-xs text-muted-foreground">
                              Provider ID: {model.provider_model_id}
                            </p>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">{model.provider}</Badge>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          <div className="flex items-center gap-1">
                            <span className="text-muted-foreground">Input:</span>
                            ${model.input_price}/M
                          </div>
                          <div className="flex items-center gap-1">
                            <span className="text-muted-foreground">Output:</span>
                            ${model.output_price}/M
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          <p>{model.max_tokens.toLocaleString()} tokens</p>
                          <p className="text-xs text-muted-foreground">
                            {(model.context_window / 1000).toFixed(0)}K context
                          </p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge className={tierConfig?.color}>
                          {tierConfig?.label}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Switch
                          checked={model.is_active}
                          onCheckedChange={() => toggleModelActive(model)}
                        />
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-2">
                          <Button
                            variant="ghost"
                            size="icon"
                            onClick={() => setEditingModel(model)}
                          >
                            <Edit2 className="h-4 w-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            onClick={() => handleDeleteModel(model.id)}
                          >
                            <Trash2 className="h-4 w-4 text-red-500" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Edit/Add Model Dialog */}
      <Dialog open={!!editingModel} onOpenChange={() => {
        setEditingModel(null)
        setIsAddingModel(false)
      }}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>
              {isAddingModel ? 'Add New Model' : 'Edit Model Configuration'}
            </DialogTitle>
            <DialogDescription>
              Configure model settings and pricing
            </DialogDescription>
          </DialogHeader>
          
          {editingModel && (
            <div className="grid gap-4 py-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Provider</Label>
                  <Select
                    value={editingModel.provider}
                    onValueChange={(value) => setEditingModel({...editingModel, provider: value})}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {PROVIDERS.map(provider => (
                        <SelectItem key={provider.value} value={provider.value}>
                          {provider.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                
                <div className="space-y-2">
                  <Label>Model ID</Label>
                  <Input
                    value={editingModel.model}
                    onChange={(e) => setEditingModel({...editingModel, model: e.target.value})}
                    placeholder="gpt-4-turbo"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Display Name</Label>
                  <Input
                    value={editingModel.display_name}
                    onChange={(e) => setEditingModel({...editingModel, display_name: e.target.value})}
                    placeholder="GPT-4 Turbo"
                  />
                </div>
                
                <div className="space-y-2">
                  <Label>Provider Model ID</Label>
                  <Input
                    value={editingModel.provider_model_id || ''}
                    onChange={(e) => setEditingModel({...editingModel, provider_model_id: e.target.value || null})}
                    placeholder="Leave empty if same as Model ID"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Input Price (per 1M tokens)</Label>
                  <Input
                    type="number"
                    step="0.01"
                    value={editingModel.input_price}
                    onChange={(e) => setEditingModel({...editingModel, input_price: parseFloat(e.target.value) || 0})}
                  />
                </div>
                
                <div className="space-y-2">
                  <Label>Output Price (per 1M tokens)</Label>
                  <Input
                    type="number"
                    step="0.01"
                    value={editingModel.output_price}
                    onChange={(e) => setEditingModel({...editingModel, output_price: parseFloat(e.target.value) || 0})}
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Max Tokens</Label>
                  <Input
                    type="number"
                    value={editingModel.max_tokens}
                    onChange={(e) => setEditingModel({...editingModel, max_tokens: parseInt(e.target.value) || 0})}
                  />
                </div>
                
                <div className="space-y-2">
                  <Label>Context Window</Label>
                  <Input
                    type="number"
                    value={editingModel.context_window}
                    onChange={(e) => setEditingModel({...editingModel, context_window: parseInt(e.target.value) || 0})}
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Required Tier</Label>
                  <Select
                    value={editingModel.tier_required}
                    onValueChange={(value: 'free' | 'pro' | 'max') => setEditingModel({...editingModel, tier_required: value})}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {TIER_OPTIONS.map(tier => (
                        <SelectItem key={tier.value} value={tier.value}>
                          {tier.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                
                <div className="space-y-2">
                  <Label>Default Temperature</Label>
                  <Input
                    type="number"
                    step="0.1"
                    min="0"
                    max="2"
                    value={editingModel.default_temperature}
                    onChange={(e) => setEditingModel({...editingModel, default_temperature: parseFloat(e.target.value) || 0.7})}
                  />
                </div>
              </div>

              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <Label>Supports Streaming</Label>
                    <p className="text-sm text-muted-foreground">Enable streaming responses</p>
                  </div>
                  <Switch
                    checked={editingModel.supports_streaming}
                    onCheckedChange={(checked) => setEditingModel({...editingModel, supports_streaming: checked})}
                  />
                </div>
                
                <div className="flex items-center justify-between">
                  <div>
                    <Label>Supports Functions</Label>
                    <p className="text-sm text-muted-foreground">Enable function calling</p>
                  </div>
                  <Switch
                    checked={editingModel.supports_functions}
                    onCheckedChange={(checked) => setEditingModel({...editingModel, supports_functions: checked})}
                  />
                </div>
                
                <div className="flex items-center justify-between">
                  <div>
                    <Label>Active</Label>
                    <p className="text-sm text-muted-foreground">Make model available to users</p>
                  </div>
                  <Switch
                    checked={editingModel.is_active}
                    onCheckedChange={(checked) => setEditingModel({...editingModel, is_active: checked})}
                  />
                </div>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => {
              setEditingModel(null)
              setIsAddingModel(false)
            }}>
              Cancel
            </Button>
            <Button onClick={handleSaveModel} disabled={saving}>
              <Save className="mr-2 h-4 w-4" />
              {saving ? 'Saving...' : 'Save Model'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}