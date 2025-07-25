import { NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function checkAdminAuth(request: NextRequest) {
  const supabase = createClient()
  
  // Get user from auth
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    return { authorized: false, error: 'Unauthorized', status: 401 }
  }
  
  // Check if user is admin
  const { data: adminUser, error: adminError } = await supabase
    .from('admin_users')
    .select('user_id')
    .eq('user_id', user.id)
    .single()
  
  if (adminError || !adminUser) {
    return { authorized: false, error: 'Admin access required', status: 403 }
  }
  
  return { authorized: true, user }
}