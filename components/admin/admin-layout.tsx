'use client'

import { useEffect, useState } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  LayoutDashboard,
  Key,
  Users,
  Settings,
  BarChart,
  LogOut,
  Menu,
  X,
  ChevronRight,
  Shield,
  FileText,
  Activity
} from 'lucide-react'

interface NavItem {
  title: string
  href: string
  icon: React.ElementType
  description?: string
}

const navItems: NavItem[] = [
  {
    title: 'Dashboard',
    href: '/admin',
    icon: LayoutDashboard,
    description: 'System overview and statistics'
  },
  {
    title: 'API Keys',
    href: '/admin/api-keys',
    icon: Key,
    description: 'Manage provider API keys'
  },
  {
    title: 'Users',
    href: '/admin/users',
    icon: Users,
    description: 'User management and tiers'
  },
  {
    title: 'Models',
    href: '/admin/models',
    icon: Settings,
    description: 'Configure AI models and pricing'
  },
  {
    title: 'Analytics',
    href: '/admin/analytics',
    icon: BarChart,
    description: 'Usage statistics and reports'
  },
  {
    title: 'Logs',
    href: '/admin/logs',
    icon: FileText,
    description: 'System and audit logs'
  },
  {
    title: 'Monitoring',
    href: '/admin/monitoring',
    icon: Activity,
    description: 'Real-time system monitoring'
  }
]

export function AdminLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const pathname = usePathname()
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    checkUser()
  }, [])

  const checkUser = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      
      if (!user) {
        router.push('/login')
        return
      }

      // Check if user is admin
      const { data: adminData } = await supabase
        .from('admins')
        .select('id')
        .eq('user_id', user.id)
        .single()

      if (!adminData) {
        router.push('/')
        return
      }

      setUser(user)
    } catch (error) {
      console.error('Error checking user:', error)
      router.push('/login')
    } finally {
      setLoading(false)
    }
  }

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
      </div>
    )
  }

  if (!user) {
    return null
  }

  // Get current page title
  const currentPage = navItems.find(item => item.href === pathname)
  const pageTitle = currentPage?.title || 'Admin'

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Mobile sidebar backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black bg-opacity-50 z-40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={cn(
          "fixed top-0 left-0 z-50 h-full w-64 bg-white border-r border-gray-200 transform transition-transform duration-200 ease-in-out lg:translate-x-0",
          sidebarOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className="flex items-center justify-between p-4 border-b">
            <div className="flex items-center space-x-2">
              <Shield className="h-8 w-8 text-blue-600" />
              <span className="text-xl font-bold">Admin Panel</span>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="lg:hidden"
              onClick={() => setSidebarOpen(false)}
            >
              <X className="h-5 w-5" />
            </Button>
          </div>

          {/* Navigation */}
          <nav className="flex-1 p-4 space-y-1 overflow-y-auto">
            {navItems.map((item) => {
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center space-x-3 px-3 py-2 rounded-lg transition-colors",
                    isActive
                      ? "bg-blue-50 text-blue-600"
                      : "text-gray-700 hover:bg-gray-100"
                  )}
                  onClick={() => setSidebarOpen(false)}
                >
                  <item.icon className="h-5 w-5" />
                  <div className="flex-1">
                    <p className="text-sm font-medium">{item.title}</p>
                    {item.description && (
                      <p className="text-xs text-gray-500">{item.description}</p>
                    )}
                  </div>
                  {isActive && <ChevronRight className="h-4 w-4" />}
                </Link>
              )
            })}
          </nav>

          {/* User info */}
          <div className="p-4 border-t">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <div className="h-8 w-8 rounded-full bg-gray-300 flex items-center justify-center">
                  <span className="text-sm font-medium">
                    {user.email?.[0].toUpperCase()}
                  </span>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">
                    {user.email}
                  </p>
                  <p className="text-xs text-gray-500">Administrator</p>
                </div>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={handleLogout}
                title="Logout"
              >
                <LogOut className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <div className="lg:pl-64">
        {/* Top bar */}
        <header className="sticky top-0 z-30 bg-white border-b border-gray-200">
          <div className="flex items-center justify-between px-4 py-3">
            <div className="flex items-center space-x-4">
              <Button
                variant="ghost"
                size="icon"
                className="lg:hidden"
                onClick={() => setSidebarOpen(true)}
              >
                <Menu className="h-5 w-5" />
              </Button>
              <h1 className="text-xl font-semibold text-gray-900">
                {pageTitle}
              </h1>
            </div>
            
            {/* Breadcrumb */}
            <nav className="hidden md:flex items-center space-x-2 text-sm">
              <Link href="/admin" className="text-gray-500 hover:text-gray-700">
                Admin
              </Link>
              {pathname !== '/admin' && (
                <>
                  <ChevronRight className="h-4 w-4 text-gray-400" />
                  <span className="text-gray-900">{pageTitle}</span>
                </>
              )}
            </nav>
          </div>
        </header>

        {/* Page content */}
        <main className="p-6">
          {children}
        </main>
      </div>
    </div>
  )
}