'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/hooks/use-toast'
import { 
  Plus, 
  Settings, 
  Trash2, 
  RefreshCw, 
  Key,
  CheckCircle,
  XCircle,
  Loader2,
  ExternalLink
} from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { AddProviderModal } from './add-provider-modal'
import { ModelSyncService } from '@/lib/services/model-sync'

interface APIProvider {
  id: string
  name: string
  display_name: string
  provider_type: 'aggregator' | 'direct'
  base_url: string
  api_standard: string
  features: any
  documentation_url?: string
  is_active: boolean
}

interface UserAPIProvider {
  id: string
  user_id: string
  provider_id: string
  endpoint_override?: string
  settings?: any
  monthly_budget?: number
  is_active: boolean
  created_at: string
  updated_at: string
  provider?: APIProvider
  model_count?: number
  last_sync?: string
}

export function ProviderList() {
  const [providers, setProviders] = useState<APIProvider[]>([])
  const [userProviders, setUserProviders] = useState<UserAPIProvider[]>([])
  const [loading, setLoading] = useState(true)
  const [syncing, setSyncing] = useState<string | null>(null)
  const [deleteId, setDeleteId] = useState<string | null>(null)
  const [showAddModal, setShowAddModal] = useState(false)
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    try {
      // Load available providers
      const { data: providersData, error: providersError } = await supabase
        .from('api_providers')
        .select('*')
        .eq('is_active', true)
        .eq('provider_type', 'aggregator')
        .order('display_name')

      if (providersError) throw providersError
      setProviders(providersData || [])

      // Load user's providers
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: userProvidersData, error: userProvidersError } = await supabase
        .from('user_api_providers')
        .select(`
          *,
          provider:api_providers(*)
        `)
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })

      if (userProvidersError) throw userProvidersError

      // Get model counts for each provider
      const providersWithCounts = await Promise.all(
        (userProvidersData || []).map(async (up) => {
          const { count } = await supabase
            .from('aggregator_models')
            .select('*', { count: 'exact', head: true })
            .eq('provider_id', up.provider_id)
            .eq('is_available', true)

          return {
            ...up,
            model_count: count || 0
          }
        })
      )

      setUserProviders(providersWithCounts)
    } catch (error) {
      console.error('Error loading providers:', error)
      toast({
        title: 'Error',
        description: 'Failed to load providers',
        variant: 'destructive'
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSync = async (userProviderId: string) => {
    setSyncing(userProviderId)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      toast({
        title: 'Syncing models',
        description: 'This may take a few moments...'
      })
      
      const syncService = new ModelSyncService()
      const result = await syncService.syncProviderModels(userProviderId, user.id)
      
      if (result.success) {
        toast({
          title: 'Sync complete',
          description: `Successfully synced ${result.modelCount || 0} models`
        })
      } else {
        throw new Error(result.error || 'Sync failed')
      }
      
      await loadData()
    } catch (error) {
      console.error('Error syncing models:', error)
      toast({
        title: 'Sync failed',
        description: error instanceof Error ? error.message : 'Failed to sync models',
        variant: 'destructive'
      })
    } finally {
      setSyncing(null)
    }
  }

  const handleDelete = async (userProviderId: string) => {
    try {
      const { error } = await supabase
        .from('user_api_providers')
        .delete()
        .eq('id', userProviderId)

      if (error) throw error

      toast({
        title: 'Provider removed',
        description: 'The API provider has been removed'
      })

      await loadData()
    } catch (error) {
      console.error('Error deleting provider:', error)
      toast({
        title: 'Error',
        description: 'Failed to remove provider',
        variant: 'destructive'
      })
    } finally {
      setDeleteId(null)
    }
  }

  const availableProviders = providers.filter(
    p => !userProviders.some(up => up.provider_id === p.id)
  )

  if (loading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-8">
          <Loader2 className="h-6 w-6 animate-spin" />
        </CardContent>
      </Card>
    )
  }

  return (
    <>
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>API Providers</CardTitle>
              <CardDescription>
                Connect to API aggregators to access hundreds of AI models
              </CardDescription>
            </div>
            <Button 
              onClick={() => setShowAddModal(true)}
              disabled={availableProviders.length === 0}
            >
              <Plus className="h-4 w-4 mr-2" />
              Add Provider
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {userProviders.length === 0 ? (
            <div className="text-center py-8">
              <Key className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
              <p className="text-muted-foreground mb-4">
                No API providers connected yet
              </p>
              <Button onClick={() => setShowAddModal(true)}>
                <Plus className="h-4 w-4 mr-2" />
                Add Your First Provider
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              {userProviders.map((userProvider) => (
                <div
                  key={userProvider.id}
                  className="flex items-center justify-between p-4 border rounded-lg"
                >
                  <div className="flex items-center space-x-4">
                    <div className="h-10 w-10 rounded-lg bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center">
                      <Key className="h-5 w-5 text-white" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium">
                          {userProvider.provider?.display_name}
                        </h3>
                        {userProvider.is_active ? (
                          <Badge variant="outline" className="text-green-600">
                            <CheckCircle className="h-3 w-3 mr-1" />
                            Active
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-red-600">
                            <XCircle className="h-3 w-3 mr-1" />
                            Inactive
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">
                        {userProvider.model_count || 0} models available
                        {userProvider.last_sync && (
                          <span> • Last synced {new Date(userProvider.last_sync).toLocaleDateString()}</span>
                        )}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {userProvider.provider?.documentation_url && (
                      <Button
                        variant="ghost"
                        size="icon"
                        asChild
                      >
                        <a 
                          href={userProvider.provider.documentation_url}
                          target="_blank"
                          rel="noopener noreferrer"
                        >
                          <ExternalLink className="h-4 w-4" />
                        </a>
                      </Button>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleSync(userProvider.id)}
                      disabled={syncing === userProvider.id}
                    >
                      {syncing === userProvider.id ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <RefreshCw className="h-4 w-4" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => setDeleteId(userProvider.id)}
                    >
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <AddProviderModal
        open={showAddModal}
        onOpenChange={setShowAddModal}
        providers={availableProviders}
        onSuccess={() => {
          setShowAddModal(false)
          loadData()
        }}
      />

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove API Provider</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to remove this API provider? This will remove access to all models from this provider.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => deleteId && handleDelete(deleteId)}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}