'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { MessageSquare, Settings, CreditCard, LogOut, Shield } from 'lucide-react'
import { cn } from '@/lib/utils'
import { logger } from '@/lib/utils/logger'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { useState, useEffect } from 'react'

const navigation = [
  { name: 'Chat', href: '/chat', icon: MessageSquare },
  { name: 'Billing', href: '/billing', icon: CreditCard },
  { name: 'Settings', href: '/settings', icon: Settings },
]

export function Sidebar() {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    checkAdminStatus()
  }, [])

  const checkAdminStatus = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: adminUser } = await supabase
        .from('admin_users')
        .select('user_id')
        .eq('user_id', user.id)
        .single()

      setIsAdmin(!!adminUser)
    } catch (error) {
      logger.error('Error checking admin status', { error })
    }
  }

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  return (
    <div className="flex h-full w-64 flex-col bg-muted/50 border-r">
      <div className="flex h-16 items-center border-b px-6">
        <h1 className="text-xl font-bold">Efflux AI</h1>
      </div>
      
      <nav className="flex-1 space-y-1 p-4">
        {navigation.map((item) => {
          const isActive = pathname.startsWith(item.href)
          return (
            <Link
              key={item.name}
              href={item.href}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <item.icon className="h-4 w-4" />
              {item.name}
            </Link>
          )
        })}
        
        {isAdmin && (
          <>
            <div className="my-2 border-t" />
            <Link
              href="/admin"
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                pathname.startsWith('/admin')
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <Shield className="h-4 w-4" />
              Admin Panel
            </Link>
          </>
        )}
      </nav>
      
      <div className="border-t p-4">
        <Button
          variant="ghost"
          className="w-full justify-start"
          onClick={handleSignOut}
        >
          <LogOut className="mr-2 h-4 w-4" />
          Sign out
        </Button>
      </div>
    </div>
  )
}