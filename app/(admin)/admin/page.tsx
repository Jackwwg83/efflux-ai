'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { 
  Users, 
  Key, 
  Activity, 
  DollarSign,
  TrendingUp,
  AlertCircle,
  CheckCircle,
  Clock,
  BarChart3,
  Zap
} from 'lucide-react'

interface Stats {
  totalUsers: number
  activeUsers: number
  totalApiKeys: number
  activeApiKeys: number
  totalRequests: number
  totalTokens: number
  totalCost: number
  errorRate: number
}

interface ProviderHealth {
  provider: string
  status: 'healthy' | 'degraded' | 'down'
  activeKeys: number
  totalKeys: number
  errorRate: number
  lastError?: string
}

export default function AdminDashboard() {
  const [stats, setStats] = useState<Stats>({
    totalUsers: 0,
    activeUsers: 0,
    totalApiKeys: 0,
    activeApiKeys: 0,
    totalRequests: 0,
    totalTokens: 0,
    totalCost: 0,
    errorRate: 0
  })
  const [providerHealth, setProviderHealth] = useState<ProviderHealth[]>([])
  const [recentActivity, setRecentActivity] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [timeRange, setTimeRange] = useState('today')
  const supabase = createClient()

  useEffect(() => {
    loadDashboardData()
    // Set up real-time subscription
    const subscription = supabase
      .channel('dashboard-updates')
      .on('postgres_changes', { 
        event: '*', 
        schema: 'public', 
        table: 'usage_logs' 
      }, () => {
        loadDashboardData()
      })
      .subscribe()

    return () => {
      subscription.unsubscribe()
    }
  }, [timeRange])

  const loadDashboardData = async () => {
    setLoading(true)
    try {
      // Calculate date range
      const now = new Date()
      let startDate = new Date()
      
      switch (timeRange) {
        case 'today':
          startDate.setHours(0, 0, 0, 0)
          break
        case 'week':
          startDate.setDate(now.getDate() - 7)
          break
        case 'month':
          startDate.setMonth(now.getMonth() - 1)
          break
      }

      // Load all data in parallel
      const [
        usersData,
        apiKeysData,
        usageData,
        recentLogsData,
        providerStatsData
      ] = await Promise.all([
        // Total and active users
        supabase.from('users_view').select('id, created_at'),
        
        // API Keys stats
        supabase.from('api_key_pool').select('*'),
        
        // Usage statistics
        supabase.from('usage_logs')
          .select('total_tokens, estimated_cost, status')
          .gte('created_at', startDate.toISOString()),
        
        // Recent activity - join with users_view
        supabase.from('usage_logs')
          .select(`
            *,
            users:users_view!user_id(email)
          `)
          .order('created_at', { ascending: false })
          .limit(10),
        
        // Provider health
        supabase.rpc('get_provider_health_stats')
      ])

      // Process users data
      const totalUsers = usersData.data?.length || 0
      const activeUsers = usersData.data?.filter(u => {
        const userDate = new Date(u.created_at)
        return userDate >= startDate
      }).length || 0

      // Process API keys data
      const apiKeys = apiKeysData.data || []
      const totalApiKeys = apiKeys.length
      const activeApiKeys = apiKeys.filter(k => k.is_active && k.consecutive_errors < 5).length

      // Process usage data
      const usage = usageData.data || []
      const totalRequests = usage.length
      const totalTokens = usage.reduce((sum, u) => sum + (u.total_tokens || 0), 0)
      const totalCost = usage.reduce((sum, u) => sum + (u.estimated_cost || 0), 0)
      const errors = usage.filter(u => u.status === 'error').length
      const errorRate = totalRequests > 0 ? (errors / totalRequests) * 100 : 0

      // Process provider health
      const providers = ['openai', 'anthropic', 'google', 'bedrock']
      const providerHealthData = providers.map(provider => {
        const providerKeys = apiKeys.filter(k => k.provider === provider)
        const activeProviderKeys = providerKeys.filter(k => k.is_active && k.consecutive_errors < 5)
        const totalProviderRequests = providerKeys.reduce((sum, k) => sum + k.total_requests, 0)
        const totalProviderErrors = providerKeys.reduce((sum, k) => sum + k.error_count, 0)
        const providerErrorRate = totalProviderRequests > 0 ? (totalProviderErrors / totalProviderRequests) * 100 : 0
        
        let status: 'healthy' | 'degraded' | 'down' = 'healthy'
        if (activeProviderKeys.length === 0) status = 'down'
        else if (providerErrorRate > 10) status = 'degraded'

        return {
          provider,
          status,
          activeKeys: activeProviderKeys.length,
          totalKeys: providerKeys.length,
          errorRate: providerErrorRate,
          lastError: providerKeys.find(k => k.last_error)?.last_error
        }
      })

      setStats({
        totalUsers,
        activeUsers,
        totalApiKeys,
        activeApiKeys,
        totalRequests,
        totalTokens,
        totalCost,
        errorRate
      })
      setProviderHealth(providerHealthData)
      setRecentActivity(recentLogsData.data || [])
    } catch (error) {
      console.error('Error loading dashboard data:', error)
    } finally {
      setLoading(false)
    }
  }

  const formatNumber = (num: number) => {
    if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`
    if (num >= 1000) return `${(num / 1000).toFixed(1)}K`
    return num.toString()
  }

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="h-5 w-5 text-green-500" />
      case 'degraded':
        return <AlertCircle className="h-5 w-5 text-yellow-500" />
      case 'down':
        return <AlertCircle className="h-5 w-5 text-red-500" />
      default:
        return null
    }
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
      {/* Time Range Selector */}
      <div className="flex justify-between items-center">
        <h2 className="text-3xl font-bold tracking-tight">Dashboard Overview</h2>
        <Tabs value={timeRange} onValueChange={setTimeRange}>
          <TabsList>
            <TabsTrigger value="today">Today</TabsTrigger>
            <TabsTrigger value="week">This Week</TabsTrigger>
            <TabsTrigger value="month">This Month</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {/* Stats Grid */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Users</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatNumber(stats.totalUsers)}</div>
            <p className="text-xs text-muted-foreground">
              {stats.activeUsers} active {timeRange}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">API Requests</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatNumber(stats.totalRequests)}</div>
            <p className="text-xs text-muted-foreground">
              {stats.errorRate.toFixed(1)}% error rate
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Tokens Used</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatNumber(stats.totalTokens)}</div>
            <p className="text-xs text-muted-foreground">
              Across all models
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Cost</CardTitle>
            <DollarSign className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${stats.totalCost.toFixed(2)}</div>
            <p className="text-xs text-muted-foreground">
              {timeRange} spend
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Provider Health Status */}
      <Card>
        <CardHeader>
          <CardTitle>Provider Health Status</CardTitle>
          <CardDescription>Real-time status of AI provider integrations</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {providerHealth.map((provider) => (
              <div key={provider.provider} className="flex items-center justify-between p-4 border rounded-lg">
                <div className="flex items-center space-x-4">
                  {getStatusIcon(provider.status)}
                  <div>
                    <h4 className="text-sm font-semibold capitalize">{provider.provider}</h4>
                    <p className="text-sm text-muted-foreground">
                      {provider.activeKeys} / {provider.totalKeys} keys active
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-sm font-medium">{provider.errorRate.toFixed(1)}% errors</p>
                  {provider.lastError && (
                    <p className="text-xs text-red-500 truncate max-w-[200px]">{provider.lastError}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Recent Activity */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Activity</CardTitle>
          <CardDescription>Latest API calls and their status</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {recentActivity.map((activity) => (
              <div key={activity.id} className="flex items-center justify-between py-2 border-b last:border-0">
                <div className="flex items-center space-x-4">
                  <Clock className="h-4 w-4 text-muted-foreground" />
                  <div>
                    <p className="text-sm font-medium">{activity.model}</p>
                    <p className="text-xs text-muted-foreground">
                      {activity.users?.email || 'Unknown user'} • {new Date(activity.created_at).toLocaleString()}
                    </p>
                  </div>
                </div>
                <div className="flex items-center space-x-2">
                  <span className={`text-xs px-2 py-1 rounded-full ${
                    activity.status === 'success' 
                      ? 'bg-green-100 text-green-700' 
                      : 'bg-red-100 text-red-700'
                  }`}>
                    {activity.status}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {activity.total_tokens} tokens
                  </span>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}