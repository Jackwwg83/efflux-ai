'use client'

import { useEffect, useState } from 'react'
import { User } from '@supabase/supabase-js'
import { createClient } from '@/lib/supabase/client'
import { Database } from '@/types/database'
import { Zap } from 'lucide-react'
import { Progress } from '@/components/ui/progress'

type UserTier = Database['public']['Tables']['user_tiers']['Row']

interface HeaderProps {
  user: User
}

export function Header({ user }: HeaderProps) {
  const [userTier, setUserTier] = useState<UserTier | null>(null)
  const supabase = createClient()

  useEffect(() => {
    loadUserTier()
    
    // Subscribe to changes
    const subscription = supabase
      .channel('user_tier_changes')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'user_tiers',
        filter: `user_id=eq.${user.id}`,
      }, () => {
        loadUserTier()
      })
      .subscribe()

    return () => {
      subscription.unsubscribe()
    }
  }, [user.id])

  const loadUserTier = async () => {
    const { data } = await supabase
      .from('user_tiers')
      .select('*')
      .eq('user_id', user.id)
      .single()

    setUserTier(data)
  }

  const creditsPercentage = userTier
    ? (userTier.credits_balance / userTier.credits_limit) * 100
    : 0

  return (
    <header className="flex h-16 items-center justify-between border-b px-6">
      <div className="flex items-center gap-4">
        <h2 className="text-lg font-semibold">
          Welcome, {user.email?.split('@')[0]}
        </h2>
        {userTier && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <span className="font-medium uppercase">{userTier.tier}</span>
            <span>•</span>
            <span>Resets {new Date(userTier.reset_at).toLocaleDateString()}</span>
          </div>
        )}
      </div>
      
      {userTier && (
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Zap className="h-4 w-4 text-yellow-500" />
            <div className="w-32">
              <div className="flex justify-between text-xs text-muted-foreground mb-1">
                <span>{Math.round(userTier.credits_balance).toLocaleString()}</span>
                <span>{Math.round(userTier.credits_limit).toLocaleString()}</span>
              </div>
              <Progress value={creditsPercentage} className="h-2" />
            </div>
          </div>
        </div>
      )}
    </header>
  )
}