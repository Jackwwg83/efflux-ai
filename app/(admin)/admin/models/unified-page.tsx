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
import { cn } from '@/lib/utils'
import { 
  Search, 
  Save,
  Plus,
  Edit2,
  DollarSign,
  Tag,
  RefreshCw,
  AlertCircle,
  CheckCircle,
  Sparkles,
  Gauge,
  Globe
} from 'lucide-react'
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

interface UnifiedModel {
  model_id: string
  display_name: string
  custom_name?: string
  model_type: string
  capabilities: any
  context_window: number
  max_output_tokens?: number
  input_price: number
  output_price: number
  tier_required: string
  tags: string[]
  is_active: boolean
  is_featured: boolean
  health_status: string
  available_sources: number
  sources?: {
    provider_name: string
    provider_type: 'direct' | 'aggregator'
    is_available: boolean
    priority: number
  }[]
}

const MODEL_TAGS = [
  { value: 'recommended', label: '推荐', color: 'bg-blue-500' },
  { value: 'popular', label: '热门', color: 'bg-orange-500' },
  { value: 'new', label: '新增', color: 'bg-green-500' },
  { value: 'vision', label: '视觉', color: 'bg-purple-500' },
  { value: 'fast', label: '快速', color: 'bg-yellow-500' },
  { value: 'powerful', label: '强大', color: 'bg-red-500' }
]

const MODEL_TYPES = [
  { value: 'all', label: '全部类型' },
  { value: 'chat', label: '对话模型' },
  { value: 'completion', label: '补全模型' },
  { value: 'image', label: '图像模型' },
  { value: 'audio', label: '音频模型' },
  { value: 'embedding', label: '嵌入模型' }
]

export default function UnifiedModelsPage() {
  const [models, setModels] = useState<UnifiedModel[]>([])
  const [loading, setLoading] = useState(true)
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedType, setSelectedType] = useState('all')
  const [selectedTag, setSelectedTag] = useState('all')
  const [editingModel, setEditingModel] = useState<UnifiedModel | null>(null)
  const [syncing, setSyncing] = useState(false)
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadModels()
  }, [])

  const loadModels = async () => {
    setLoading(true)
    try {
      // This would call the new unified function
      const { data, error } = await supabase
        .rpc('get_all_models_with_sources')

      if (error) throw error

      setModels(data || [])
    } catch (error) {
      console.error('Error loading models:', error)
      toast({
        title: 'Error',
        description: 'Failed to load models',
        variant: 'destructive'
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSaveModel = async () => {
    if (!editingModel) return

    try {
      const { error } = await supabase
        .from('models')
        .update({
          custom_name: editingModel.custom_name,
          input_price: editingModel.input_price,
          output_price: editingModel.output_price,
          tier_required: editingModel.tier_required,
          tags: editingModel.tags,
          is_active: editingModel.is_active,
          is_featured: editingModel.is_featured
        })
        .eq('model_id', editingModel.model_id)

      if (error) throw error

      toast({
        title: 'Success',
        description: 'Model configuration updated'
      })

      setEditingModel(null)
      loadModels()
    } catch (error) {
      console.error('Error saving model:', error)
      toast({
        title: 'Error',
        description: 'Failed to save model configuration',
        variant: 'destructive'
      })
    }
  }

  const handleSyncModels = async () => {
    setSyncing(true)
    try {
      // Call sync endpoint to refresh all model sources
      const response = await fetch('/api/admin/sync-models', {
        method: 'POST'
      })

      if (!response.ok) throw new Error('Sync failed')

      toast({
        title: 'Sync Complete',
        description: 'All model sources have been synchronized'
      })

      loadModels()
    } catch (error) {
      console.error('Error syncing models:', error)
      toast({
        title: 'Sync Failed',
        description: 'Failed to sync model sources',
        variant: 'destructive'
      })
    } finally {
      setSyncing(false)
    }
  }

  const filteredModels = models.filter(model => {
    const matchesSearch = model.display_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         model.model_id.toLowerCase().includes(searchTerm.toLowerCase())
    const matchesType = selectedType === 'all' || model.model_type === selectedType
    const matchesTag = selectedTag === 'all' || model.tags.includes(selectedTag)
    return matchesSearch && matchesType && matchesTag
  })

  // Group models by availability and featured status
  const featuredModels = filteredModels.filter(m => m.is_featured)
  const activeModels = filteredModels.filter(m => m.is_active && !m.is_featured)
  const inactiveModels = filteredModels.filter(m => !m.is_active)

  const modelStats = {
    total: models.length,
    active: models.filter(m => m.is_active).length,
    multiSource: models.filter(m => m.available_sources > 1).length,
    featured: models.filter(m => m.is_featured).length
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Stats Overview */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Models</CardTitle>
            <Globe className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{modelStats.total}</div>
            <p className="text-xs text-muted-foreground">
              From all providers
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Models</CardTitle>
            <CheckCircle className="h-4 w-4 text-green-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{modelStats.active}</div>
            <p className="text-xs text-muted-foreground">
              Available to users
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Multi-Source</CardTitle>
            <Gauge className="h-4 w-4 text-blue-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{modelStats.multiSource}</div>
            <p className="text-xs text-muted-foreground">
              Multiple providers
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Featured</CardTitle>
            <Sparkles className="h-4 w-4 text-purple-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{modelStats.featured}</div>
            <p className="text-xs text-muted-foreground">
              Recommended models
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Model Management */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Unified Model Management</CardTitle>
              <CardDescription>
                Manage all AI models from direct providers and aggregators in one place
              </CardDescription>
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                onClick={handleSyncModels}
                disabled={syncing}
              >
                <RefreshCw className={cn("mr-2 h-4 w-4", syncing && "animate-spin")} />
                {syncing ? 'Syncing...' : 'Sync All Sources'}
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {/* Filters */}
          <div className="mb-4 flex flex-wrap gap-4">
            <div className="flex-1 min-w-[200px]">
              <div className="relative">
                <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search models..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-8"
                />
              </div>
            </div>
            <Tabs value={selectedType} onValueChange={setSelectedType}>
              <TabsList>
                {MODEL_TYPES.map(type => (
                  <TabsTrigger key={type.value} value={type.value}>
                    {type.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
            <Tabs value={selectedTag} onValueChange={setSelectedTag}>
              <TabsList>
                <TabsTrigger value="all">All Tags</TabsTrigger>
                {MODEL_TAGS.map(tag => (
                  <TabsTrigger key={tag.value} value={tag.value}>
                    {tag.label}
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
                  <TableHead>Type</TableHead>
                  <TableHead>Sources</TableHead>
                  <TableHead>Pricing</TableHead>
                  <TableHead>Context</TableHead>
                  <TableHead>Tags</TableHead>
                  <TableHead>Tier</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {/* Featured Models */}
                {featuredModels.length > 0 && (
                  <>
                    <TableRow>
                      <TableCell colSpan={9} className="bg-purple-50 font-medium">
                        <div className="flex items-center gap-2">
                          <Sparkles className="h-4 w-4 text-purple-500" />
                          Featured Models
                        </div>
                      </TableCell>
                    </TableRow>
                    {featuredModels.map(model => (
                      <ModelRow key={model.model_id} model={model} onEdit={setEditingModel} />
                    ))}
                  </>
                )}

                {/* Active Models */}
                {activeModels.length > 0 && (
                  <>
                    <TableRow>
                      <TableCell colSpan={9} className="bg-green-50 font-medium">
                        Active Models
                      </TableCell>
                    </TableRow>
                    {activeModels.map(model => (
                      <ModelRow key={model.model_id} model={model} onEdit={setEditingModel} />
                    ))}
                  </>
                )}

                {/* Inactive Models */}
                {inactiveModels.length > 0 && (
                  <>
                    <TableRow>
                      <TableCell colSpan={9} className="bg-gray-50 font-medium">
                        Inactive Models
                      </TableCell>
                    </TableRow>
                    {inactiveModels.map(model => (
                      <ModelRow key={model.model_id} model={model} onEdit={setEditingModel} />
                    ))}
                  </>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Edit Model Dialog */}
      <Dialog open={!!editingModel} onOpenChange={() => setEditingModel(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Configure Model</DialogTitle>
            <DialogDescription>
              Customize model settings for your platform
            </DialogDescription>
          </DialogHeader>
          
          {editingModel && (
            <div className="grid gap-4 py-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Model ID</Label>
                  <Input value={editingModel.model_id} disabled />
                </div>
                
                <div className="space-y-2">
                  <Label>Custom Display Name</Label>
                  <Input
                    value={editingModel.custom_name || ''}
                    onChange={(e) => setEditingModel({...editingModel, custom_name: e.target.value})}
                    placeholder={editingModel.display_name}
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

              <div className="space-y-2">
                <Label>Tags</Label>
                <div className="flex flex-wrap gap-2">
                  {MODEL_TAGS.map(tag => (
                    <Badge
                      key={tag.value}
                      variant={editingModel.tags.includes(tag.value) ? "default" : "outline"}
                      className="cursor-pointer"
                      onClick={() => {
                        const newTags = editingModel.tags.includes(tag.value)
                          ? editingModel.tags.filter(t => t !== tag.value)
                          : [...editingModel.tags, tag.value]
                        setEditingModel({...editingModel, tags: newTags})
                      }}
                    >
                      {tag.label}
                    </Badge>
                  ))}
                </div>
              </div>

              <div className="space-y-4">
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
                
                <div className="flex items-center justify-between">
                  <div>
                    <Label>Featured</Label>
                    <p className="text-sm text-muted-foreground">Highlight as recommended model</p>
                  </div>
                  <Switch
                    checked={editingModel.is_featured}
                    onCheckedChange={(checked) => setEditingModel({...editingModel, is_featured: checked})}
                  />
                </div>
              </div>

              {/* Show available sources */}
              <div className="border-t pt-4">
                <Label>Available Sources</Label>
                <div className="mt-2 space-y-2">
                  {editingModel.sources?.map(source => (
                    <div key={source.provider_name} className="flex items-center justify-between p-2 bg-gray-50 rounded">
                      <div className="flex items-center gap-2">
                        <Badge variant={source.provider_type === 'direct' ? "default" : "secondary"}>
                          {source.provider_type}
                        </Badge>
                        <span>{source.provider_name}</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-muted-foreground">Priority: {source.priority}</span>
                        {source.is_available ? (
                          <CheckCircle className="h-4 w-4 text-green-500" />
                        ) : (
                          <AlertCircle className="h-4 w-4 text-red-500" />
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setEditingModel(null)}>
              Cancel
            </Button>
            <Button onClick={handleSaveModel}>
              <Save className="mr-2 h-4 w-4" />
              Save Configuration
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// Helper component for model rows
function ModelRow({ model, onEdit }: { model: UnifiedModel, onEdit: (model: UnifiedModel) => void }) {
  return (
    <TableRow>
      <TableCell>
        <div>
          <p className="font-medium">
            {model.custom_name || model.display_name}
            {model.is_featured && <Sparkles className="inline ml-2 h-4 w-4 text-purple-500" />}
          </p>
          <p className="text-sm text-muted-foreground">{model.model_id}</p>
        </div>
      </TableCell>
      <TableCell>
        <Badge variant="outline">{model.model_type}</Badge>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <span className="text-sm">{model.available_sources} sources</span>
          {model.available_sources > 1 && (
            <Gauge className="h-4 w-4 text-blue-500" title="Multiple providers available" />
          )}
        </div>
      </TableCell>
      <TableCell>
        <div className="text-sm">
          <div className="flex items-center gap-1">
            <span className="text-muted-foreground">In:</span>
            ${model.input_price}/M
          </div>
          <div className="flex items-center gap-1">
            <span className="text-muted-foreground">Out:</span>
            ${model.output_price}/M
          </div>
        </div>
      </TableCell>
      <TableCell>
        <div className="text-sm">
          <p>{(model.context_window / 1000).toFixed(0)}K context</p>
          {model.max_output_tokens && (
            <p className="text-xs text-muted-foreground">
              {model.max_output_tokens.toLocaleString()} max out
            </p>
          )}
        </div>
      </TableCell>
      <TableCell>
        <div className="flex flex-wrap gap-1">
          {model.tags.map(tag => {
            const tagConfig = MODEL_TAGS.find(t => t.value === tag)
            return tagConfig ? (
              <Badge key={tag} className={cn("text-xs", tagConfig.color, "text-white")}>
                {tagConfig.label}
              </Badge>
            ) : null
          })}
        </div>
      </TableCell>
      <TableCell>
        <Badge variant="outline">{model.tier_required}</Badge>
      </TableCell>
      <TableCell>
        <Switch checked={model.is_active} disabled />
      </TableCell>
      <TableCell className="text-right">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => onEdit(model)}
        >
          <Edit2 className="h-4 w-4" />
        </Button>
      </TableCell>
    </TableRow>
  )
}