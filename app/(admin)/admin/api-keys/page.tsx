'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useToast } from '@/hooks/use-toast'
import { Eye, EyeOff, Trash2, Plus, AlertCircle, CheckCircle2, Activity, Sparkles, RefreshCw, Loader2 } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from '@/components/ui/tabs'
import { ModelSyncService } from '@/lib/services/model-sync-admin'

interface ApiKeyPool {
  id: string
  provider: string
  api_key: string
  name: string
  is_active: boolean
  rate_limit_remaining: number
  last_used_at: string | null
  error_count: number
  consecutive_errors: number
  total_requests: number
  total_tokens_used: number
  created_at: string
  provider_type: 'direct' | 'aggregator'
  provider_config?: any
}

interface ApiProvider {
  id: string
  name: string
  display_name: string
  provider_type: 'aggregator' | 'direct'
  base_url: string
  api_standard: string
  features: any
  documentation_url?: string
}

const DIRECT_PROVIDERS = [
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic' },
  { value: 'google', label: 'Google' },
  { value: 'bedrock', label: 'AWS Bedrock' },
]

export default function ApiKeysPage() {
  const [apiKeys, setApiKeys] = useState<ApiKeyPool[]>([])
  const [aggregatorProviders, setAggregatorProviders] = useState<ApiProvider[]>([])
  const [loading, setLoading] = useState(true)
  const [showKeys, setShowKeys] = useState<Record<string, boolean>>({})
  const [newKey, setNewKey] = useState({ 
    provider: '', 
    api_key: '', 
    name: '',
    provider_type: 'direct' as 'direct' | 'aggregator'
  })
  const [saving, setSaving] = useState(false)
  const [syncing, setSyncing] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState('direct')
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadData()
    // Set up real-time subscription
    const subscription = supabase
      .channel('api_key_updates')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'api_key_pool'
      }, () => {
        loadData()
      })
      .subscribe()

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  const loadData = async () => {
    try {
      // Load API keys
      const { data, error } = await supabase
        .from('api_key_pool')
        .select('*')
        .order('provider', { ascending: true })
        .order('created_at', { ascending: false })

      if (error) throw error
      setApiKeys(data || [])

      // Load aggregator providers
      const { data: providers, error: providersError } = await supabase
        .from('api_providers')
        .select('*')
        .eq('provider_type', 'aggregator')
        .order('display_name')

      if (providersError) throw providersError
      setAggregatorProviders(providers || [])
    } catch (error) {
      console.error('Error loading data:', error)
      toast({
        title: 'Error',
        description: 'Failed to load API keys',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const addApiKey = async () => {
    if (!newKey.provider || !newKey.api_key || !newKey.name) {
      toast({
        title: 'Error',
        description: 'Please fill in all fields',
        variant: 'destructive',
      })
      return
    }

    setSaving(true)
    try {
      const keyData: any = {
        provider: newKey.provider,
        api_key: newKey.api_key,
        name: newKey.name,
        provider_type: newKey.provider_type,
        is_active: true,
        rate_limit_remaining: 1000,
        error_count: 0,
        consecutive_errors: 0,
        total_requests: 0,
        total_tokens_used: 0
      }

      // If it's an aggregator, add provider config
      if (newKey.provider_type === 'aggregator') {
        const provider = aggregatorProviders.find(p => p.name === newKey.provider)
        if (provider) {
          keyData.provider_config = {
            base_url: provider.base_url,
            features: provider.features
          }
        }
      }

      const { data, error } = await supabase
        .from('api_key_pool')
        .insert(keyData)
        .select()
        .single()

      if (error) throw error

      toast({
        title: 'Success',
        description: 'API key added successfully',
      })

      // If it's an aggregator, sync models
      if (newKey.provider_type === 'aggregator' && data) {
        toast({
          title: 'Syncing models',
          description: 'Fetching available models from the aggregator...',
        })
        
        const syncService = new ModelSyncService()
        const result = await syncService.syncAggregatorModels(data.id, data.provider)
        
        if (result.success) {
          toast({
            title: 'Models synced',
            description: `Successfully synced ${result.modelCount || 0} models`,
          })
        }
      }

      setNewKey({ provider: '', api_key: '', name: '', provider_type: 'direct' })
      loadData()
    } catch (error: any) {
      console.error('Error adding API key:', error)
      toast({
        title: 'Error',
        description: error.message || 'Failed to add API key',
        variant: 'destructive',
      })
    } finally {
      setSaving(false)
    }
  }

  const toggleApiKey = async (id: string, isActive: boolean) => {
    try {
      const { error } = await supabase
        .from('api_key_pool')
        .update({ is_active: !isActive })
        .eq('id', id)

      if (error) throw error

      toast({
        title: 'Success',
        description: `API key ${!isActive ? 'activated' : 'deactivated'}`,
      })
    } catch (error) {
      console.error('Error toggling API key:', error)
      toast({
        title: 'Error',
        description: 'Failed to toggle API key',
        variant: 'destructive',
      })
    }
  }

  const deleteApiKey = async (id: string) => {
    try {
      const { error } = await supabase
        .from('api_key_pool')
        .delete()
        .eq('id', id)

      if (error) throw error

      toast({
        title: 'Success',
        description: 'API key deleted',
      })
    } catch (error) {
      console.error('Error deleting API key:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete API key',
        variant: 'destructive',
      })
    }
  }

  const syncAggregatorModels = async (keyId: string, provider: string) => {
    setSyncing(keyId)
    try {
      const syncService = new ModelSyncService()
      const result = await syncService.syncAggregatorModels(keyId, provider)
      
      if (result.success) {
        toast({
          title: 'Models synced',
          description: `Successfully synced ${result.modelCount || 0} models`,
        })
      } else {
        throw new Error(result.error || 'Sync failed')
      }
      
      loadData()
    } catch (error) {
      console.error('Error syncing models:', error)
      toast({
        title: 'Sync failed',
        description: error instanceof Error ? error.message : 'Failed to sync models',
        variant: 'destructive',
      })
    } finally {
      setSyncing(null)
    }
  }

  const getHealthIcon = (key: ApiKeyPool) => {
    if (key.consecutive_errors >= 5) {
      return <AlertCircle className="h-4 w-4 text-red-500" />
    } else if (key.consecutive_errors > 0) {
      return <AlertCircle className="h-4 w-4 text-yellow-500" />
    } else if (key.is_active) {
      return <CheckCircle2 className="h-4 w-4 text-green-500" />
    }
    return <AlertCircle className="h-4 w-4 text-gray-400" />
  }

  const getUsagePercentage = (key: ApiKeyPool) => {
    if (!key.rate_limit_remaining) return 0
    return Math.max(0, Math.min(100, (1 - key.rate_limit_remaining / 1000) * 100))
  }

  const directKeys = apiKeys.filter(k => k.provider_type !== 'aggregator')
  const aggregatorKeys = apiKeys.filter(k => k.provider_type === 'aggregator')

  // Get all providers (direct + aggregator)
  const allProviders = newKey.provider_type === 'direct' 
    ? DIRECT_PROVIDERS
    : aggregatorProviders.map(p => ({ value: p.name, label: p.display_name }))

  return (
    <Card>
      <CardHeader>
        <CardTitle>API Key Management</CardTitle>
        <CardDescription>
          Manage API keys for direct providers and aggregators
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Tabs value={activeTab} onValueChange={setActiveTab}>
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="direct">Direct Providers</TabsTrigger>
            <TabsTrigger value="aggregator">
              <Sparkles className="h-4 w-4 mr-2" />
              Aggregators
            </TabsTrigger>
          </TabsList>

          <TabsContent value="direct" className="space-y-4">
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              <div>
                <Label htmlFor="provider">Provider</Label>
                <Select 
                  value={newKey.provider} 
                  onValueChange={(value) => setNewKey({ ...newKey, provider: value, provider_type: 'direct' })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select provider" />
                  </SelectTrigger>
                  <SelectContent>
                    {DIRECT_PROVIDERS.map((provider) => (
                      <SelectItem key={provider.value} value={provider.value}>
                        {provider.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="name">Name</Label>
                <Input
                  id="name"
                  value={newKey.name}
                  onChange={(e) => setNewKey({ ...newKey, name: e.target.value })}
                  placeholder="Production Key"
                />
              </div>
              <div>
                <Label htmlFor="api_key">API Key</Label>
                <div className="flex gap-2">
                  <Input
                    id="api_key"
                    type={showKeys['new'] ? 'text' : 'password'}
                    value={newKey.api_key}
                    onChange={(e) => setNewKey({ ...newKey, api_key: e.target.value })}
                    placeholder="sk-..."
                  />
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => setShowKeys({ ...showKeys, new: !showKeys.new })}
                  >
                    {showKeys['new'] ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </Button>
                  <Button onClick={addApiKey} disabled={saving}>
                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                  </Button>
                </div>
              </div>
            </div>

            <div className="space-y-4">
              {directKeys.map((key) => (
                <div
                  key={key.id}
                  className="p-4 border rounded-lg space-y-3"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      {getHealthIcon(key)}
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-medium">{key.name}</h3>
                          <Badge variant={key.is_active ? 'default' : 'secondary'}>
                            {key.provider.toUpperCase()}
                          </Badge>
                        </div>
                        <p className="text-sm text-muted-foreground">
                          Added {new Date(key.created_at).toLocaleDateString()}
                          {key.last_used_at && ` • Last used ${new Date(key.last_used_at).toLocaleString()}`}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setShowKeys({ ...showKeys, [key.id]: !showKeys[key.id] })}
                      >
                        {showKeys[key.id] ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => toggleApiKey(key.id, key.is_active)}
                      >
                        <Activity className="h-4 w-4" />
                      </Button>
                      <AlertDialog>
                        <AlertDialogTrigger asChild>
                          <Button variant="ghost" size="sm">
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </AlertDialogTrigger>
                        <AlertDialogContent>
                          <AlertDialogHeader>
                            <AlertDialogTitle>Delete API Key</AlertDialogTitle>
                            <AlertDialogDescription>
                              Are you sure you want to delete this API key? This action cannot be undone.
                            </AlertDialogDescription>
                          </AlertDialogHeader>
                          <AlertDialogFooter>
                            <AlertDialogCancel>Cancel</AlertDialogCancel>
                            <AlertDialogAction onClick={() => deleteApiKey(key.id)}>
                              Delete
                            </AlertDialogAction>
                          </AlertDialogFooter>
                        </AlertDialogContent>
                      </AlertDialog>
                    </div>
                  </div>

                  {showKeys[key.id] && (
                    <div className="p-3 bg-muted rounded-md font-mono text-sm">
                      {key.api_key}
                    </div>
                  )}

                  <div className="grid grid-cols-3 gap-4 text-sm">
                    <div>
                      <p className="text-muted-foreground">Requests</p>
                      <p className="font-medium">{key.total_requests.toLocaleString()}</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Tokens Used</p>
                      <p className="font-medium">{key.total_tokens_used.toLocaleString()}</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Errors</p>
                      <p className="font-medium">{key.error_count}</p>
                    </div>
                  </div>

                  {key.rate_limit_remaining > 0 && (
                    <div className="space-y-1">
                      <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">Rate Limit Usage</span>
                        <span>{getUsagePercentage(key).toFixed(0)}%</span>
                      </div>
                      <Progress value={getUsagePercentage(key)} />
                    </div>
                  )}
                </div>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="aggregator" className="space-y-4">
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              <div>
                <Label htmlFor="aggregator-provider">Aggregator</Label>
                <Select 
                  value={newKey.provider} 
                  onValueChange={(value) => setNewKey({ ...newKey, provider: value, provider_type: 'aggregator' })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select aggregator" />
                  </SelectTrigger>
                  <SelectContent>
                    {aggregatorProviders.map((provider) => (
                      <SelectItem key={provider.name} value={provider.name}>
                        {provider.display_name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label htmlFor="aggregator-name">Name</Label>
                <Input
                  id="aggregator-name"
                  value={newKey.name}
                  onChange={(e) => setNewKey({ ...newKey, name: e.target.value })}
                  placeholder="Main Aggregator Key"
                />
              </div>
              <div>
                <Label htmlFor="aggregator-api-key">API Key</Label>
                <div className="flex gap-2">
                  <Input
                    id="aggregator-api-key"
                    type={showKeys['new-aggregator'] ? 'text' : 'password'}
                    value={newKey.api_key}
                    onChange={(e) => setNewKey({ ...newKey, api_key: e.target.value })}
                    placeholder="Bearer..."
                  />
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => setShowKeys({ ...showKeys, 'new-aggregator': !showKeys['new-aggregator'] })}
                  >
                    {showKeys['new-aggregator'] ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </Button>
                  <Button onClick={addApiKey} disabled={saving}>
                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                  </Button>
                </div>
              </div>
            </div>

            <div className="space-y-4">
              {aggregatorKeys.map((key) => {
                const provider = aggregatorProviders.find(p => p.name === key.provider)
                return (
                  <div
                    key={key.id}
                    className="p-4 border rounded-lg space-y-3"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        {getHealthIcon(key)}
                        <div>
                          <div className="flex items-center gap-2">
                            <h3 className="font-medium">{key.name}</h3>
                            <Badge variant="secondary">
                              <Sparkles className="h-3 w-3 mr-1" />
                              {provider?.display_name || key.provider}
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Added {new Date(key.created_at).toLocaleDateString()}
                            {key.last_used_at && ` • Last used ${new Date(key.last_used_at).toLocaleString()}`}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => syncAggregatorModels(key.id, key.provider)}
                          disabled={syncing === key.id}
                        >
                          {syncing === key.id ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <RefreshCw className="h-4 w-4" />
                          )}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setShowKeys({ ...showKeys, [key.id]: !showKeys[key.id] })}
                        >
                          {showKeys[key.id] ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => toggleApiKey(key.id, key.is_active)}
                        >
                          <Activity className="h-4 w-4" />
                        </Button>
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button variant="ghost" size="sm">
                              <Trash2 className="h-4 w-4 text-destructive" />
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Delete API Key</AlertDialogTitle>
                              <AlertDialogDescription>
                                Are you sure you want to delete this API key? This will also remove all synced models.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction onClick={() => deleteApiKey(key.id)}>
                                Delete
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      </div>
                    </div>

                    {showKeys[key.id] && (
                      <div className="p-3 bg-muted rounded-md font-mono text-sm">
                        {key.api_key}
                      </div>
                    )}

                    <div className="grid grid-cols-3 gap-4 text-sm">
                      <div>
                        <p className="text-muted-foreground">Models</p>
                        <p className="font-medium">{key.provider_config?.model_count || 0}</p>
                      </div>
                      <div>
                        <p className="text-muted-foreground">Requests</p>
                        <p className="font-medium">{key.total_requests.toLocaleString()}</p>
                      </div>
                      <div>
                        <p className="text-muted-foreground">Tokens Used</p>
                        <p className="font-medium">{key.total_tokens_used.toLocaleString()}</p>
                      </div>
                    </div>

                    {provider?.documentation_url && (
                      <div className="pt-2">
                        <a 
                          href={provider.documentation_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-sm text-primary hover:underline"
                        >
                          View Documentation →
                        </a>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}