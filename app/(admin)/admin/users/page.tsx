'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/hooks/use-toast'
import { 
  Search, 
  UserCheck, 
  UserX, 
  Shield, 
  TrendingUp,
  Calendar,
  Zap,
  DollarSign,
  MoreVertical,
  ChevronLeft,
  ChevronRight
} from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

interface User {
  id: string
  email: string
  created_at: string
  user_tier?: {
    tier: 'free' | 'pro' | 'max'
    updated_at: string
  }
  user_quotas?: {
    tokens_used_today: number
    tokens_used_month: number
    requests_today: number
    requests_month: number
    cost_today: number
    cost_month: number
    last_reset_daily: string
    last_reset_monthly: string
  }
  usage_logs?: Array<{
    total_tokens: number
    estimated_cost: number
    created_at: string
  }>
}

const TIER_LIMITS = {
  free: { daily: 5000, monthly: 150000, label: 'Free', color: 'bg-gray-500' },
  pro: { daily: 50000, monthly: 1500000, label: 'Pro', color: 'bg-blue-500' },
  max: { daily: 500000, monthly: 15000000, label: 'Max', color: 'bg-purple-500' }
}

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [filterTier, setFilterTier] = useState<string>('all')
  const [selectedUser, setSelectedUser] = useState<User | null>(null)
  const [changingTier, setChangingTier] = useState(false)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const itemsPerPage = 10
  
  const supabase = createClient()
  const { toast } = useToast()

  useEffect(() => {
    loadUsers()
  }, [page, filterTier])

  const loadUsers = async () => {
    setLoading(true)
    try {
      let query = supabase
        .from('users')
        .select(`
          *,
          user_tiers!left(tier, updated_at),
          user_quotas!left(*)
        `, { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((page - 1) * itemsPerPage, page * itemsPerPage - 1)

      // Apply search filter
      if (searchQuery) {
        query = query.ilike('email', `%${searchQuery}%`)
      }

      // Apply tier filter
      if (filterTier !== 'all') {
        query = query.eq('user_tiers.tier', filterTier)
      }

      const { data, error, count } = await query

      if (error) throw error

      // Calculate total usage for each user
      const usersWithStats = await Promise.all((data || []).map(async (user) => {
        const { data: usageLogs } = await supabase
          .from('usage_logs')
          .select('total_tokens, estimated_cost, created_at')
          .eq('user_id', user.id)
          .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())

        return {
          ...user,
          user_tier: user.user_tiers,
          user_quotas: user.user_quotas,
          usage_logs: usageLogs || []
        }
      }))

      setUsers(usersWithStats)
      setTotalPages(Math.ceil((count || 0) / itemsPerPage))
    } catch (error) {
      console.error('Error loading users:', error)
      toast({
        title: 'Error',
        description: 'Failed to load users',
        variant: 'destructive'
      })
    } finally {
      setLoading(false)
    }
  }

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    setPage(1)
    loadUsers()
  }

  const changeTier = async (userId: string, newTier: 'free' | 'pro' | 'max') => {
    setChangingTier(true)
    try {
      // Check if user_tiers record exists
      const { data: existing } = await supabase
        .from('user_tiers')
        .select('id')
        .eq('user_id', userId)
        .single()

      if (existing) {
        // Update existing record
        const { error } = await supabase
          .from('user_tiers')
          .update({ tier: newTier, updated_at: new Date().toISOString() })
          .eq('user_id', userId)
        
        if (error) throw error
      } else {
        // Insert new record
        const { error } = await supabase
          .from('user_tiers')
          .insert({ user_id: userId, tier: newTier })
        
        if (error) throw error
      }

      toast({
        title: 'Success',
        description: `User tier updated to ${TIER_LIMITS[newTier].label}`
      })

      setSelectedUser(null)
      loadUsers()
    } catch (error) {
      console.error('Error changing tier:', error)
      toast({
        title: 'Error',
        description: 'Failed to update user tier',
        variant: 'destructive'
      })
    } finally {
      setChangingTier(false)
    }
  }

  const resetUserQuota = async (userId: string) => {
    try {
      const { error } = await supabase
        .from('user_quotas')
        .update({
          tokens_used_today: 0,
          requests_today: 0,
          cost_today: 0,
          last_reset_daily: new Date().toISOString()
        })
        .eq('user_id', userId)

      if (error) throw error

      toast({
        title: 'Success',
        description: 'User quota reset successfully'
      })

      loadUsers()
    } catch (error) {
      console.error('Error resetting quota:', error)
      toast({
        title: 'Error',
        description: 'Failed to reset quota',
        variant: 'destructive'
      })
    }
  }

  const filteredUsers = users

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Users</CardTitle>
            <UserCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{users.length}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Free Tier</CardTitle>
            <Shield className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter(u => (u.user_tier?.tier || 'free') === 'free').length}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Pro Tier</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter(u => u.user_tier?.tier === 'pro').length}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Max Tier</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter(u => u.user_tier?.tier === 'max').length}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardHeader>
          <CardTitle>User Management</CardTitle>
          <CardDescription>Manage user accounts, tiers, and quotas</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex gap-4 mb-6">
            <form onSubmit={handleSearch} className="flex-1">
              <div className="relative">
                <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search by email..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-8"
                />
              </div>
            </form>
            <Select value={filterTier} onValueChange={setFilterTier}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Filter by tier" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Tiers</SelectItem>
                <SelectItem value="free">Free</SelectItem>
                <SelectItem value="pro">Pro</SelectItem>
                <SelectItem value="max">Max</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Users Table */}
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>User</TableHead>
                  <TableHead>Tier</TableHead>
                  <TableHead>Usage Today</TableHead>
                  <TableHead>Usage This Month</TableHead>
                  <TableHead>Joined</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredUsers.map((user) => {
                  const tier = user.user_tier?.tier || 'free'
                  const tierConfig = TIER_LIMITS[tier]
                  const quotas = user.user_quotas
                  const usagePercent = quotas 
                    ? (quotas.tokens_used_today / tierConfig.daily) * 100
                    : 0

                  return (
                    <TableRow key={user.id}>
                      <TableCell>
                        <div>
                          <p className="font-medium">{user.email}</p>
                          <p className="text-sm text-muted-foreground">{user.id.slice(0, 8)}...</p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge className={tierConfig.color}>
                          {tierConfig.label}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <div>
                          <p className="text-sm">
                            {quotas?.tokens_used_today.toLocaleString() || 0} tokens
                          </p>
                          <div className="w-24 h-1 bg-gray-200 rounded-full mt-1">
                            <div 
                              className="h-1 bg-blue-500 rounded-full"
                              style={{ width: `${Math.min(usagePercent, 100)}%` }}
                            />
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div>
                          <p className="text-sm">
                            {quotas?.tokens_used_month.toLocaleString() || 0} tokens
                          </p>
                          <p className="text-xs text-muted-foreground">
                            ${quotas?.cost_month.toFixed(2) || '0.00'}
                          </p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          <p>{new Date(user.created_at).toLocaleDateString()}</p>
                          <p className="text-xs text-muted-foreground">
                            {new Date(user.created_at).toLocaleTimeString()}
                          </p>
                        </div>
                      </TableCell>
                      <TableCell className="text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon">
                              <MoreVertical className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuLabel>Actions</DropdownMenuLabel>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem onClick={() => setSelectedUser(user)}>
                              Change Tier
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => resetUserQuota(user.id)}>
                              Reset Daily Quota
                            </DropdownMenuItem>
                            <DropdownMenuItem className="text-red-600">
                              Suspend User
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>

          {/* Pagination */}
          <div className="flex items-center justify-between mt-4">
            <p className="text-sm text-muted-foreground">
              Page {page} of {totalPages}
            </p>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage(page - 1)}
                disabled={page === 1}
              >
                <ChevronLeft className="h-4 w-4" />
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage(page + 1)}
                disabled={page === totalPages}
              >
                Next
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Change Tier Dialog */}
      <Dialog open={!!selectedUser} onOpenChange={() => setSelectedUser(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Change User Tier</DialogTitle>
            <DialogDescription>
              Update tier for {selectedUser?.email}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 my-4">
            {(['free', 'pro', 'max'] as const).map((tier) => {
              const config = TIER_LIMITS[tier]
              const isCurrentTier = (selectedUser?.user_tier?.tier || 'free') === tier
              
              return (
                <div
                  key={tier}
                  className={`p-4 border rounded-lg cursor-pointer transition-colors ${
                    isCurrentTier ? 'border-blue-500 bg-blue-50' : 'hover:bg-gray-50'
                  }`}
                  onClick={() => !isCurrentTier && changeTier(selectedUser!.id, tier)}
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <h4 className="font-semibold">{config.label}</h4>
                      <p className="text-sm text-muted-foreground">
                        {config.daily.toLocaleString()} tokens/day • {config.monthly.toLocaleString()} tokens/month
                      </p>
                    </div>
                    {isCurrentTier && (
                      <Badge variant="default">Current</Badge>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSelectedUser(null)}>
              Cancel
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}