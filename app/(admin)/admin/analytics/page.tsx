'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { 
  BarChart3, 
  TrendingUp, 
  Users, 
  DollarSign,
  Activity,
  Download,
  Calendar,
  Filter
} from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  Legend
} from 'recharts'

interface AnalyticsData {
  usageByDay: Array<{
    date: string
    requests: number
    tokens: number
    cost: number
  }>
  usageByModel: Array<{
    model: string
    provider: string
    requests: number
    tokens: number
    cost: number
  }>
  usageByUser: Array<{
    email: string
    tier: string
    requests: number
    tokens: number
    cost: number
  }>
  providerDistribution: Array<{
    provider: string
    percentage: number
  }>
  errorRates: Array<{
    date: string
    success: number
    error: number
    errorRate: number
  }>
}

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884D8']

export default function AnalyticsPage() {
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData>({
    usageByDay: [],
    usageByModel: [],
    usageByUser: [],
    providerDistribution: [],
    errorRates: []
  })
  const [loading, setLoading] = useState(true)
  const [timeRange, setTimeRange] = useState('7d')
  const [provider, setProvider] = useState('all')
  
  const supabase = createClient()

  useEffect(() => {
    loadAnalytics()
  }, [timeRange, provider])

  const loadAnalytics = async () => {
    setLoading(true)
    try {
      // Calculate date range
      const endDate = new Date()
      const startDate = new Date()
      
      switch (timeRange) {
        case '24h':
          startDate.setHours(endDate.getHours() - 24)
          break
        case '7d':
          startDate.setDate(endDate.getDate() - 7)
          break
        case '30d':
          startDate.setDate(endDate.getDate() - 30)
          break
        case '90d':
          startDate.setDate(endDate.getDate() - 90)
          break
      }

      // Load usage logs
      let query = supabase
        .from('usage_logs')
        .select('*, users!inner(email, user_tiers!inner(tier))')
        .gte('created_at', startDate.toISOString())
        .lte('created_at', endDate.toISOString())

      if (provider !== 'all') {
        query = query.eq('provider', provider)
      }

      const { data: logs, error } = await query

      if (error) throw error

      // Process data for charts
      const processedData = processAnalyticsData(logs || [], timeRange)
      setAnalyticsData(processedData)
    } catch (error) {
      console.error('Error loading analytics:', error)
    } finally {
      setLoading(false)
    }
  }

  const processAnalyticsData = (logs: any[], timeRange: string): AnalyticsData => {
    // Usage by day
    const usageByDayMap = new Map()
    const usageByModelMap = new Map()
    const usageByUserMap = new Map()
    const providerCounts = new Map()
    const errorByDayMap = new Map()

    logs.forEach(log => {
      const date = new Date(log.created_at).toLocaleDateString()
      
      // Usage by day
      if (!usageByDayMap.has(date)) {
        usageByDayMap.set(date, { requests: 0, tokens: 0, cost: 0 })
      }
      const dayData = usageByDayMap.get(date)
      dayData.requests += 1
      dayData.tokens += log.total_tokens || 0
      dayData.cost += log.estimated_cost || 0

      // Usage by model
      const modelKey = `${log.provider}-${log.model}`
      if (!usageByModelMap.has(modelKey)) {
        usageByModelMap.set(modelKey, { 
          model: log.model, 
          provider: log.provider,
          requests: 0, 
          tokens: 0, 
          cost: 0 
        })
      }
      const modelData = usageByModelMap.get(modelKey)
      modelData.requests += 1
      modelData.tokens += log.total_tokens || 0
      modelData.cost += log.estimated_cost || 0

      // Usage by user
      const userEmail = log.users?.email || 'Unknown'
      const userTier = log.users?.user_tiers?.tier || 'free'
      if (!usageByUserMap.has(userEmail)) {
        usageByUserMap.set(userEmail, { 
          email: userEmail,
          tier: userTier,
          requests: 0, 
          tokens: 0, 
          cost: 0 
        })
      }
      const userData = usageByUserMap.get(userEmail)
      userData.requests += 1
      userData.tokens += log.total_tokens || 0
      userData.cost += log.estimated_cost || 0

      // Provider distribution
      providerCounts.set(log.provider, (providerCounts.get(log.provider) || 0) + 1)

      // Error rates by day
      if (!errorByDayMap.has(date)) {
        errorByDayMap.set(date, { success: 0, error: 0 })
      }
      const errorData = errorByDayMap.get(date)
      if (log.status === 'success') {
        errorData.success += 1
      } else {
        errorData.error += 1
      }
    })

    // Convert maps to arrays
    const usageByDay = Array.from(usageByDayMap.entries())
      .map(([date, data]) => ({ date, ...data }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())

    const usageByModel = Array.from(usageByModelMap.values())
      .sort((a, b) => b.requests - a.requests)
      .slice(0, 10)

    const usageByUser = Array.from(usageByUserMap.values())
      .sort((a, b) => b.requests - a.requests)
      .slice(0, 10)

    const totalProviderRequests = Array.from(providerCounts.values()).reduce((a, b) => a + b, 0)
    const providerDistribution = Array.from(providerCounts.entries())
      .map(([provider, count]) => ({
        provider,
        percentage: Math.round((count / totalProviderRequests) * 100)
      }))

    const errorRates = Array.from(errorByDayMap.entries())
      .map(([date, data]) => ({
        date,
        ...data,
        errorRate: data.success + data.error > 0 
          ? Math.round((data.error / (data.success + data.error)) * 100)
          : 0
      }))
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())

    return {
      usageByDay,
      usageByModel,
      usageByUser,
      providerDistribution,
      errorRates
    }
  }

  const exportData = () => {
    const csvData = analyticsData.usageByDay.map(row => ({
      Date: row.date,
      Requests: row.requests,
      Tokens: row.tokens,
      Cost: row.cost.toFixed(2)
    }))

    const csvContent = [
      Object.keys(csvData[0]).join(','),
      ...csvData.map(row => Object.values(row).join(','))
    ].join('\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = window.URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `analytics-${timeRange}-${new Date().toISOString().split('T')[0]}.csv`
    a.click()
    window.URL.revokeObjectURL(url)
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
      {/* Filters */}
      <div className="flex justify-between items-center">
        <div className="flex gap-4">
          <Select value={timeRange} onValueChange={setTimeRange}>
            <SelectTrigger className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="24h">Last 24 hours</SelectItem>
              <SelectItem value="7d">Last 7 days</SelectItem>
              <SelectItem value="30d">Last 30 days</SelectItem>
              <SelectItem value="90d">Last 90 days</SelectItem>
            </SelectContent>
          </Select>

          <Select value={provider} onValueChange={setProvider}>
            <SelectTrigger className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Providers</SelectItem>
              <SelectItem value="openai">OpenAI</SelectItem>
              <SelectItem value="anthropic">Anthropic</SelectItem>
              <SelectItem value="google">Google</SelectItem>
              <SelectItem value="bedrock">AWS Bedrock</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <Button onClick={exportData} variant="outline">
          <Download className="mr-2 h-4 w-4" />
          Export CSV
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Requests</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {analyticsData.usageByDay.reduce((sum, day) => sum + day.requests, 0).toLocaleString()}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Tokens</CardTitle>
            <BarChart3 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {(analyticsData.usageByDay.reduce((sum, day) => sum + day.tokens, 0) / 1000000).toFixed(1)}M
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Cost</CardTitle>
            <DollarSign className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              ${analyticsData.usageByDay.reduce((sum, day) => sum + day.cost, 0).toFixed(2)}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Avg Error Rate</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {analyticsData.errorRates.length > 0
                ? (analyticsData.errorRates.reduce((sum, day) => sum + day.errorRate, 0) / analyticsData.errorRates.length).toFixed(1)
                : 0}%
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Charts */}
      <Tabs defaultValue="usage" className="space-y-4">
        <TabsList>
          <TabsTrigger value="usage">Usage Trends</TabsTrigger>
          <TabsTrigger value="models">Model Performance</TabsTrigger>
          <TabsTrigger value="users">Top Users</TabsTrigger>
          <TabsTrigger value="errors">Error Analysis</TabsTrigger>
        </TabsList>

        <TabsContent value="usage" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Usage Over Time</CardTitle>
              <CardDescription>Daily requests, tokens, and costs</CardDescription>
            </CardHeader>
            <CardContent className="h-[400px]">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={analyticsData.usageByDay}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis yAxisId="left" />
                  <YAxis yAxisId="right" orientation="right" />
                  <Tooltip />
                  <Legend />
                  <Line 
                    yAxisId="left"
                    type="monotone" 
                    dataKey="requests" 
                    stroke="#8884d8" 
                    name="Requests"
                  />
                  <Line 
                    yAxisId="left"
                    type="monotone" 
                    dataKey="tokens" 
                    stroke="#82ca9d" 
                    name="Tokens"
                  />
                  <Line 
                    yAxisId="right"
                    type="monotone" 
                    dataKey="cost" 
                    stroke="#ffc658" 
                    name="Cost ($)"
                  />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>

          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>Provider Distribution</CardTitle>
                <CardDescription>Request distribution by provider</CardDescription>
              </CardHeader>
              <CardContent className="h-[300px]">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={analyticsData.providerDistribution}
                      cx="50%"
                      cy="50%"
                      labelLine={false}
                      label={({provider, percentage}) => `${provider}: ${percentage}%`}
                      outerRadius={80}
                      fill="#8884d8"
                      dataKey="percentage"
                    >
                      {analyticsData.providerDistribution.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Request Volume by Hour</CardTitle>
                <CardDescription>Peak usage patterns</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="text-center text-muted-foreground py-20">
                  Hourly breakdown coming soon
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="models" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Model Usage Statistics</CardTitle>
              <CardDescription>Top 10 most used models</CardDescription>
            </CardHeader>
            <CardContent className="h-[400px]">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={analyticsData.usageByModel}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="model" angle={-45} textAnchor="end" height={100} />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="requests" fill="#8884d8" name="Requests" />
                  <Bar dataKey="cost" fill="#82ca9d" name="Cost ($)" />
                </BarChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="users" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Top Users by Usage</CardTitle>
              <CardDescription>Most active users in the selected period</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {analyticsData.usageByUser.map((user, index) => (
                  <div key={user.email} className="flex items-center justify-between p-4 border rounded-lg">
                    <div className="flex items-center gap-4">
                      <div className="text-2xl font-bold text-muted-foreground">
                        #{index + 1}
                      </div>
                      <div>
                        <p className="font-medium">{user.email}</p>
                        <p className="text-sm text-muted-foreground">
                          Tier: {user.tier}
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-medium">{user.requests.toLocaleString()} requests</p>
                      <p className="text-sm text-muted-foreground">
                        {(user.tokens / 1000).toFixed(1)}K tokens • ${user.cost.toFixed(2)}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="errors" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Error Rate Trend</CardTitle>
              <CardDescription>Success vs error rates over time</CardDescription>
            </CardHeader>
            <CardContent className="h-[400px]">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={analyticsData.errorRates}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="date" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line 
                    type="monotone" 
                    dataKey="errorRate" 
                    stroke="#ff0000" 
                    name="Error Rate (%)"
                  />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}