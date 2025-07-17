'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useToast } from '@/hooks/use-toast'
import { Eye, EyeOff, Trash2, Plus, AlertCircle, CheckCircle2, Activity } from 'lucide-react'
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
}

const PROVIDERS = [
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic' },
  { value: 'google', label: 'Google' },
  { value: 'bedrock', label: 'AWS Bedrock' },
]

export default function ApiKeysPage() {
  const [apiKeys, setApiKeys] = useState<ApiKeyPool[]>([])
  const [loading, setLoading] = useState(true)
  const [showKeys, setShowKeys] = useState<Record<string, boolean>>({})
  const [newKey, setNewKey] = useState({ provider: '', api_key: '', name: '' })
  const [saving, setSaving] = useState(false)
  const [activeTab, setActiveTab] = useState('active')
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadApiKeys()
    // Set up real-time subscription
    const subscription = supabase
      .channel('api_key_updates')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'api_key_pool'
      }, () => {
        loadApiKeys()
      })
      .subscribe()

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  const loadApiKeys = async () => {
    try {
      const { data, error } = await supabase
        .from('api_key_pool')
        .select('*')
        .order('provider', { ascending: true })
        .order('created_at', { ascending: false })

      if (error) throw error
      setApiKeys(data || [])
    } catch (error) {
      console.error('Error loading API keys:', error)
      toast({
        title: 'Error',
        description: 'Failed to load API keys',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const handleAddKey = async () => {
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
      const { data: { user } } = await supabase.auth.getUser()
      
      const { error } = await supabase
        .from('api_key_pool')
        .insert({
          provider: newKey.provider,
          api_key: newKey.api_key,
          name: newKey.name,
          created_by: user?.id,
        })

      if (error) throw error

      toast({
        title: 'Success',
        description: 'API key added successfully',
      })
      
      setNewKey({ provider: '', api_key: '', name: '' })
      loadApiKeys()
    } catch (error) {
      console.error('Error adding API key:', error)
      toast({
        title: 'Error',
        description: 'Failed to add API key',
        variant: 'destructive',
      })
    } finally {
      setSaving(false)
    }
  }

  const handleToggleActive = async (id: string, isActive: boolean) => {
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
      
      loadApiKeys()
    } catch (error) {
      console.error('Error toggling API key:', error)
      toast({
        title: 'Error',
        description: 'Failed to update API key',
        variant: 'destructive',
      })
    }
  }

  const handleDelete = async (id: string) => {
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
      
      loadApiKeys()
    } catch (error) {
      console.error('Error deleting API key:', error)
      toast({
        title: 'Error',
        description: 'Failed to delete API key',
        variant: 'destructive',
      })
    }
  }

  const handleResetErrors = async (id: string) => {
    try {
      const { error } = await supabase
        .from('api_key_pool')
        .update({ 
          consecutive_errors: 0,
          error_count: 0 
        })
        .eq('id', id)

      if (error) throw error

      toast({
        title: 'Success',
        description: 'Error count reset',
      })
      
      loadApiKeys()
    } catch (error) {
      console.error('Error resetting errors:', error)
      toast({
        title: 'Error',
        description: 'Failed to reset error count',
        variant: 'destructive',
      })
    }
  }

  const toggleShowKey = (id: string) => {
    setShowKeys(prev => ({ ...prev, [id]: !prev[id] }))
  }

  const maskApiKey = (key: string) => {
    if (key.length <= 8) return '••••••••'
    return `${key.slice(0, 4)}••••••••${key.slice(-4)}`
  }

  const getKeyStatus = (key: ApiKeyPool) => {
    if (!key.is_active) return { label: 'Inactive', variant: 'secondary' as const }
    if (key.consecutive_errors >= 5) return { label: 'Error', variant: 'destructive' as const }
    if (key.rate_limit_remaining < 100) return { label: 'Rate Limited', variant: 'warning' as const }
    return { label: 'Active', variant: 'success' as const }
  }

  const formatLastUsed = (date: string | null) => {
    if (!date) return 'Never'
    const diff = Date.now() - new Date(date).getTime()
    const minutes = Math.floor(diff / 60000)
    if (minutes < 1) return 'Just now'
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours}h ago`
    return `${Math.floor(hours / 24)}d ago`
  }

  const filteredKeys = apiKeys.filter(key => {
    if (activeTab === 'active') return key.is_active && key.consecutive_errors < 5
    if (activeTab === 'inactive') return !key.is_active
    if (activeTab === 'error') return key.consecutive_errors >= 5
    return true
  })

  const providerStats = PROVIDERS.map(provider => {
    const keys = apiKeys.filter(k => k.provider === provider.value)
    const activeKeys = keys.filter(k => k.is_active && k.consecutive_errors < 5)
    const totalRequests = keys.reduce((sum, k) => sum + k.total_requests, 0)
    const totalTokens = keys.reduce((sum, k) => sum + k.total_tokens_used, 0)
    
    return {
      ...provider,
      total: keys.length,
      active: activeKeys.length,
      requests: totalRequests,
      tokens: totalTokens
    }
  })

  if (loading) {
    return <div>Loading...</div>
  }

  return (
    <div className="space-y-6">
      {/* Provider Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {providerStats.map(stat => (
          <Card key={stat.value}>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">{stat.label}</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stat.active}/{stat.total}</div>
              <p className="text-xs text-muted-foreground">
                {stat.requests.toLocaleString()} requests
              </p>
              <Progress 
                value={(stat.active / Math.max(stat.total, 1)) * 100} 
                className="mt-2 h-1"
              />
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Main Content */}
      <Card>
        <CardHeader>
          <CardTitle>API Keys Pool Management</CardTitle>
          <CardDescription>
            Manage API keys for AI providers with load balancing and automatic failover.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {/* Add new key form */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 p-4 border rounded-lg">
              <div>
                <Label>Provider</Label>
                <Select
                  value={newKey.provider}
                  onValueChange={(value) => setNewKey({ ...newKey, provider: value })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select provider" />
                  </SelectTrigger>
                  <SelectContent>
                    {PROVIDERS.map((provider) => (
                      <SelectItem key={provider.value} value={provider.value}>
                        {provider.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              
              <div>
                <Label>Name</Label>
                <Input
                  placeholder="Production Key 1"
                  value={newKey.name}
                  onChange={(e) => setNewKey({ ...newKey, name: e.target.value })}
                />
              </div>
              
              <div>
                <Label>API Key</Label>
                <Input
                  type="password"
                  placeholder="sk-..."
                  value={newKey.api_key}
                  onChange={(e) => setNewKey({ ...newKey, api_key: e.target.value })}
                />
              </div>
              
              <div className="flex items-end">
                <Button onClick={handleAddKey} disabled={saving} className="w-full">
                  <Plus className="mr-2 h-4 w-4" />
                  Add Key
                </Button>
              </div>
            </div>

            {/* Tabs */}
            <Tabs value={activeTab} onValueChange={setActiveTab}>
              <TabsList>
                <TabsTrigger value="active">
                  Active ({apiKeys.filter(k => k.is_active && k.consecutive_errors < 5).length})
                </TabsTrigger>
                <TabsTrigger value="inactive">
                  Inactive ({apiKeys.filter(k => !k.is_active).length})
                </TabsTrigger>
                <TabsTrigger value="error">
                  Error ({apiKeys.filter(k => k.consecutive_errors >= 5).length})
                </TabsTrigger>
                <TabsTrigger value="all">All ({apiKeys.length})</TabsTrigger>
              </TabsList>

              <TabsContent value={activeTab} className="space-y-2 mt-4">
                {filteredKeys.map((key) => {
                  const status = getKeyStatus(key)
                  
                  return (
                    <div
                      key={key.id}
                      className="p-4 border rounded-lg space-y-3"
                    >
                      <div className="flex items-start justify-between">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <p className="font-medium">{key.name}</p>
                            <Badge variant={status.variant}>{status.label}</Badge>
                            <Badge variant="outline" className="capitalize">
                              {key.provider}
                            </Badge>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <code className="text-sm text-muted-foreground">
                              {showKeys[key.id] ? key.api_key : maskApiKey(key.api_key)}
                            </code>
                            <button
                              onClick={() => toggleShowKey(key.id)}
                              className="text-muted-foreground hover:text-foreground"
                            >
                              {showKeys[key.id] ? (
                                <EyeOff className="h-4 w-4" />
                              ) : (
                                <Eye className="h-4 w-4" />
                              )}
                            </button>
                          </div>
                        </div>
                        
                        <div className="flex items-center gap-2">
                          {key.consecutive_errors > 0 && (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleResetErrors(key.id)}
                            >
                              Reset Errors
                            </Button>
                          )}
                          
                          <Button
                            variant={key.is_active ? 'default' : 'outline'}
                            size="sm"
                            onClick={() => handleToggleActive(key.id, key.is_active)}
                          >
                            {key.is_active ? 'Active' : 'Inactive'}
                          </Button>
                          
                          <AlertDialog>
                            <AlertDialogTrigger asChild>
                              <Button variant="destructive" size="sm">
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </AlertDialogTrigger>
                            <AlertDialogContent>
                              <AlertDialogHeader>
                                <AlertDialogTitle>Delete API Key</AlertDialogTitle>
                                <AlertDialogDescription>
                                  Are you sure you want to delete "{key.name}"? This action cannot be undone.
                                </AlertDialogDescription>
                              </AlertDialogHeader>
                              <AlertDialogFooter>
                                <AlertDialogCancel>Cancel</AlertDialogCancel>
                                <AlertDialogAction onClick={() => handleDelete(key.id)}>
                                  Delete
                                </AlertDialogAction>
                              </AlertDialogFooter>
                            </AlertDialogContent>
                          </AlertDialog>
                        </div>
                      </div>
                      
                      {/* Stats */}
                      <div className="grid grid-cols-2 md:grid-cols-5 gap-4 text-sm">
                        <div>
                          <p className="text-muted-foreground">Last Used</p>
                          <p className="font-medium">{formatLastUsed(key.last_used_at)}</p>
                        </div>
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
                          <p className="font-medium flex items-center gap-1">
                            {key.consecutive_errors > 0 && (
                              <AlertCircle className="h-3 w-3 text-destructive" />
                            )}
                            {key.consecutive_errors}/{key.error_count}
                          </p>
                        </div>
                        <div>
                          <p className="text-muted-foreground">Rate Limit</p>
                          <p className="font-medium">
                            {key.rate_limit_remaining > 1000 ? 
                              <span className="flex items-center gap-1">
                                <CheckCircle2 className="h-3 w-3 text-green-500" />
                                OK
                              </span> : 
                              `${key.rate_limit_remaining} left`
                            }
                          </p>
                        </div>
                      </div>
                    </div>
                  )
                })}
                
                {filteredKeys.length === 0 && (
                  <div className="text-center py-8 text-muted-foreground">
                    No API keys in this category
                  </div>
                )}
              </TabsContent>
            </Tabs>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}