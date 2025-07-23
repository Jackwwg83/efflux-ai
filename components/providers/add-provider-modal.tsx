'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useToast } from '@/hooks/use-toast'
import { VaultClient } from '@/lib/crypto/vault'
import { ModelSyncService } from '@/lib/services/model-sync'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Loader2, Eye, EyeOff, AlertCircle } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'

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

interface AddProviderModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  providers: APIProvider[]
  onSuccess: () => void
}

export function AddProviderModal({
  open,
  onOpenChange,
  providers,
  onSuccess
}: AddProviderModalProps) {
  const [selectedProviderId, setSelectedProviderId] = useState('')
  const [apiKey, setApiKey] = useState('')
  const [showApiKey, setShowApiKey] = useState(false)
  const [endpointOverride, setEndpointOverride] = useState('')
  const [monthlyBudget, setMonthlyBudget] = useState('')
  const [loading, setLoading] = useState(false)
  const [validating, setValidating] = useState(false)
  
  const supabase = createClient()
  const { toast } = useToast()

  const selectedProvider = providers.find(p => p.id === selectedProviderId)

  const handleValidate = async () => {
    if (!selectedProvider || !apiKey) return

    setValidating(true)
    try {
      // For now, we'll just do a basic validation
      // In the future, this will use the provider factory to validate
      const endpoint = endpointOverride || selectedProvider.base_url
      const response = await fetch(`${endpoint}/models`, {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        }
      })

      if (response.ok) {
        toast({
          title: 'API Key Valid',
          description: 'Successfully connected to the provider'
        })
        return true
      } else {
        toast({
          title: 'Invalid API Key',
          description: 'Failed to authenticate with the provider',
          variant: 'destructive'
        })
        return false
      }
    } catch (error) {
      console.error('Validation error:', error)
      toast({
        title: 'Connection Failed',
        description: 'Could not connect to the provider',
        variant: 'destructive'
      })
      return false
    } finally {
      setValidating(false)
    }
  }

  const handleSubmit = async () => {
    if (!selectedProvider || !apiKey) return

    // Validate first
    const isValid = await handleValidate()
    if (!isValid) return

    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      // Initialize vault client
      const vault = new VaultClient(user.id)
      await vault.initialize()

      // Encrypt the API key
      const encryptedKey = await vault.encryptData(apiKey)
      
      // Generate hash for duplicate detection
      const encoder = new TextEncoder()
      const data = encoder.encode(apiKey)
      const hashBuffer = await crypto.subtle.digest('SHA-256', data)
      const hashArray = Array.from(new Uint8Array(hashBuffer))
      const keyHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

      // Save to database
      const { data: newProvider, error } = await supabase
        .from('user_api_providers')
        .insert({
          user_id: user.id,
          provider_id: selectedProviderId,
          api_key_encrypted: encryptedKey,
          api_key_hash: keyHash,
          endpoint_override: endpointOverride || null,
          monthly_budget: monthlyBudget ? parseFloat(monthlyBudget) : null,
          settings: {},
          is_active: true
        })
        .select()
        .single()

      if (error) {
        if (error.code === '23505') { // Unique constraint violation
          throw new Error('You already have this provider configured')
        }
        throw error
      }

      toast({
        title: 'Provider Added',
        description: 'Successfully added API provider. Syncing models...'
      })

      // Trigger model sync
      try {
        const syncService = new ModelSyncService()
        const syncResult = await syncService.syncProviderModels(newProvider.id, user.id)
        
        if (syncResult.success) {
          toast({
            title: 'Models Synced',
            description: `Successfully synced ${syncResult.modelCount || 0} models`
          })
        }
      } catch (syncError) {
        console.error('Model sync error:', syncError)
        toast({
          title: 'Sync Warning',
          description: 'Provider added but model sync failed. You can retry from the settings page.',
          variant: 'default'
        })
      }

      onSuccess()
      
      // Reset form
      setSelectedProviderId('')
      setApiKey('')
      setEndpointOverride('')
      setMonthlyBudget('')
    } catch (error: any) {
      console.error('Error adding provider:', error)
      toast({
        title: 'Error',
        description: error.message || 'Failed to add provider',
        variant: 'destructive'
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Add API Provider</DialogTitle>
          <DialogDescription>
            Connect to an API aggregator to access hundreds of AI models
          </DialogDescription>
        </DialogHeader>
        
        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="provider">Provider</Label>
            <Select
              value={selectedProviderId}
              onValueChange={setSelectedProviderId}
            >
              <SelectTrigger>
                <SelectValue placeholder="Select a provider" />
              </SelectTrigger>
              <SelectContent>
                {providers.map((provider) => (
                  <SelectItem key={provider.id} value={provider.id}>
                    {provider.display_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {selectedProvider && (
            <>
              <div className="space-y-2">
                <Label htmlFor="apiKey">API Key</Label>
                <div className="relative">
                  <Input
                    id="apiKey"
                    type={showApiKey ? 'text' : 'password'}
                    value={apiKey}
                    onChange={(e) => setApiKey(e.target.value)}
                    placeholder="Enter your API key"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="absolute right-0 top-0 h-full px-3"
                    onClick={() => setShowApiKey(!showApiKey)}
                  >
                    {showApiKey ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </Button>
                </div>
                {selectedProvider.documentation_url && (
                  <p className="text-sm text-muted-foreground">
                    Get your API key from{' '}
                    <a
                      href={selectedProvider.documentation_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-primary hover:underline"
                    >
                      {selectedProvider.display_name} documentation
                    </a>
                  </p>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor="endpoint">
                  Custom Endpoint (Optional)
                </Label>
                <Input
                  id="endpoint"
                  type="url"
                  value={endpointOverride}
                  onChange={(e) => setEndpointOverride(e.target.value)}
                  placeholder={selectedProvider.base_url}
                />
                <p className="text-sm text-muted-foreground">
                  Leave empty to use the default endpoint
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="budget">
                  Monthly Budget (Optional)
                </Label>
                <Input
                  id="budget"
                  type="number"
                  min="0"
                  step="0.01"
                  value={monthlyBudget}
                  onChange={(e) => setMonthlyBudget(e.target.value)}
                  placeholder="100.00"
                />
                <p className="text-sm text-muted-foreground">
                  Set a monthly spending limit in USD
                </p>
              </div>

              {selectedProvider.features?.requires_referer && (
                <Alert>
                  <AlertCircle className="h-4 w-4" />
                  <AlertDescription>
                    This provider requires additional headers for security.
                    These will be automatically configured.
                  </AlertDescription>
                </Alert>
              )}
            </>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={loading || validating}
          >
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={!selectedProviderId || !apiKey || loading || validating}
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Adding...
              </>
            ) : validating ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Validating...
              </>
            ) : (
              'Add Provider'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}