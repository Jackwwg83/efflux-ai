import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import { 
  Bot, 
  Key, 
  Users, 
  Settings, 
  ChevronLeft,
  Shield
} from 'lucide-react'

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = createClient()
  
  // Check if user is authenticated
  const { data: { user } } = await supabase.auth.getUser()
  
  if (!user) {
    redirect('/login')
  }
  
  // Check if user is admin
  const { data: adminUser } = await supabase
    .from('admin_users')
    .select('user_id')
    .eq('user_id', user.id)
    .single()
  
  if (!adminUser) {
    redirect('/chat')
  }
  
  const adminLinks = [
    {
      href: '/admin',
      label: 'Dashboard',
      icon: Shield,
    },
    {
      href: '/admin/presets',
      label: 'AI Presets',
      icon: Bot,
    },
    {
      href: '/admin/users',
      label: 'Users',
      icon: Users,
    },
    {
      href: '/admin/api-keys',
      label: 'API Keys',
      icon: Key,
    },
  ]
  
  return (
    <div className="flex h-full">
      {/* Admin Sidebar */}
      <div className="w-64 border-r bg-muted/10">
        <div className="p-4">
          <Link 
            href="/chat" 
            className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground mb-4"
          >
            <ChevronLeft className="h-4 w-4" />
            Back to Chat
          </Link>
          
          <h2 className="text-lg font-semibold mb-4">Admin Panel</h2>
          
          <nav className="space-y-1">
            {adminLinks.map((link) => {
              const Icon = link.icon
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className="flex items-center gap-3 px-3 py-2 rounded-lg text-sm hover:bg-muted/50 transition-colors"
                >
                  <Icon className="h-4 w-4" />
                  {link.label}
                </Link>
              )
            })}
          </nav>
        </div>
      </div>
      
      {/* Main Content */}
      <div className="flex-1 overflow-auto">
        {children}
      </div>
    </div>
  )
}