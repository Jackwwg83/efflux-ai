import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { DashboardWrapper } from '@/components/layout/dashboard-wrapper'
import { Header } from '@/components/layout/header'
import { Providers } from '@/components/providers'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  return (
    <Providers>
      <DashboardWrapper>
        <Header user={user} />
        <main className="flex-1 overflow-hidden">
          {children}
        </main>
      </DashboardWrapper>
    </Providers>
  )
}