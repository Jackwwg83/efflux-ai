'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

export default function ApiKeysManagementPage() {
  return (
    <div className="container mx-auto py-6 max-w-7xl">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">API Key Management</h1>
        <p className="text-muted-foreground">
          Manage AI provider API keys
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>API Keys</CardTitle>
          <CardDescription>
            Configure API keys for different AI providers
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">
            API key management functionality coming soon...
          </p>
        </CardContent>
      </Card>
    </div>
  )
}