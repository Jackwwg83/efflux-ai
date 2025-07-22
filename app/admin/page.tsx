import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Bot, Users, Key, Activity } from 'lucide-react'
import Link from 'next/link'

export default async function AdminDashboard() {
  const supabase = createClient()
  
  // Get statistics
  const { count: userCount } = await supabase
    .from('profiles')
    .select('*', { count: 'exact', head: true })
    
  const { count: presetCount } = await supabase
    .from('presets')
    .select('*', { count: 'exact', head: true })
    
  const { count: apiKeyCount } = await supabase
    .from('api_keys')
    .select('*', { count: 'exact', head: true })
    .eq('is_active', true)
  
  const stats = [
    {
      title: 'Total Users',
      value: userCount || 0,
      icon: Users,
      href: '/admin/users',
      description: 'Registered users',
    },
    {
      title: 'AI Presets',
      value: presetCount || 0,
      icon: Bot,
      href: '/admin/presets',
      description: 'Active presets',
    },
    {
      title: 'API Keys',
      value: apiKeyCount || 0,
      icon: Key,
      href: '/admin/api-keys',
      description: 'Active API keys',
    },
  ]
  
  return (
    <div className="p-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold">Admin Dashboard</h1>
        <p className="text-muted-foreground">
          Manage your Efflux AI instance
        </p>
      </div>
      
      <div className="grid gap-6 md:grid-cols-3 mb-8">
        {stats.map((stat) => {
          const Icon = stat.icon
          return (
            <Link key={stat.href} href={stat.href}>
              <Card className="hover:bg-muted/50 transition-colors cursor-pointer">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">
                    {stat.title}
                  </CardTitle>
                  <Icon className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{stat.value}</div>
                  <p className="text-xs text-muted-foreground">
                    {stat.description}
                  </p>
                </CardContent>
              </Card>
            </Link>
          )
        })}
      </div>
      
      <Card>
        <CardHeader>
          <CardTitle>Quick Actions</CardTitle>
          <CardDescription>
            Common administrative tasks
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Link 
            href="/admin/presets" 
            className="flex items-center gap-3 p-4 rounded-lg border hover:bg-muted/50 transition-colors"
          >
            <Bot className="h-5 w-5" />
            <div>
              <p className="font-medium">Manage AI Presets</p>
              <p className="text-sm text-muted-foreground">
                Configure AI behavior presets for different use cases
              </p>
            </div>
          </Link>
          
          <Link 
            href="/admin/api-keys" 
            className="flex items-center gap-3 p-4 rounded-lg border hover:bg-muted/50 transition-colors"
          >
            <Key className="h-5 w-5" />
            <div>
              <p className="font-medium">Manage API Keys</p>
              <p className="text-sm text-muted-foreground">
                Add and manage AI provider API keys
              </p>
            </div>
          </Link>
          
          <Link 
            href="/admin/users" 
            className="flex items-center gap-3 p-4 rounded-lg border hover:bg-muted/50 transition-colors"
          >
            <Users className="h-5 w-5" />
            <div>
              <p className="font-medium">User Management</p>
              <p className="text-sm text-muted-foreground">
                View and manage user accounts
              </p>
            </div>
          </Link>
        </CardContent>
      </Card>
    </div>
  )
}