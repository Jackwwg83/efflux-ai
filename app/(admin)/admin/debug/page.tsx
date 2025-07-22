'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { logger } from '@/lib/utils/logger'
import type { User } from '@supabase/supabase-js'

interface DebugInfo {
  error?: string
  [key: string]: unknown
}

export default function DebugPage() {
  const [debugInfo, setDebugInfo] = useState<DebugInfo | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const supabase = createClient()

  useEffect(() => {
    const checkAuth = async () => {
      // Get current user
      const { data: { user } } = await supabase.auth.getUser()
      setUser(user)

      // Call debug function
      const { data, error } = await supabase.rpc('debug_current_user')
      
      if (error) {
        logger.error('Debug error', { error })
        setDebugInfo({ error: error.message })
      } else {
        setDebugInfo(data)
      }

      // Test admin check directly
      const { data: adminCheck, error: adminError } = await supabase
        .from('admin_users')
        .select('*')
        .eq('user_id', user?.id)
        .single()

      logger.info('Admin check result', { adminCheck, adminError })
    }

    checkAuth()
  }, [])

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold mb-4">Debug Information</h1>
      
      <div className="space-y-4">
        <div className="p-4 bg-gray-100 rounded">
          <h2 className="font-semibold">Current User:</h2>
          <pre>{JSON.stringify(user, null, 2)}</pre>
        </div>

        <div className="p-4 bg-gray-100 rounded">
          <h2 className="font-semibold">Debug Info:</h2>
          <pre>{JSON.stringify(debugInfo, null, 2)}</pre>
        </div>
      </div>
    </div>
  )
}