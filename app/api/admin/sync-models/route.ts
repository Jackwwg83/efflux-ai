import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: NextRequest) {
  try {
    const supabase = createClient()
    
    // Verify admin
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    
    // Check if user is admin
    const { data: adminUser } = await supabase
      .from('admin_users')
      .select('id')
      .eq('user_id', user.id)
      .single()
    
    if (!adminUser) {
      return NextResponse.json({ error: 'Admin access required' }, { status: 403 })
    }
    
    // Sync direct provider models
    const directProviders = ['openai', 'anthropic', 'google', 'aws', 'azure']
    let syncedModels = 0
    let errors: string[] = []
    
    for (const provider of directProviders) {
      try {
        // This would typically call provider APIs to get latest models
        // For now, we'll just update timestamps
        const { error } = await supabase
          .from('model_sources')
          .update({ last_checked: new Date().toISOString() })
          .eq('provider_name', provider)
          .eq('provider_type', 'direct')
        
        if (error) throw error
        syncedModels++
      } catch (error) {
        errors.push(`Failed to sync ${provider}: ${error instanceof Error ? error.message : String(error)}`)
      }
    }
    
    // Sync aggregator models
    const { data: aggregators } = await supabase
      .from('api_providers')
      .select('name')
      .eq('provider_type', 'aggregator')
    
    for (const aggregator of aggregators || []) {
      try {
        // This would typically call aggregator APIs to get latest models
        // For now, we'll just update timestamps
        const { error } = await supabase
          .from('model_sources')
          .update({ last_checked: new Date().toISOString() })
          .eq('provider_name', aggregator.name)
          .eq('provider_type', 'aggregator')
        
        if (error) throw error
        syncedModels++
      } catch (error) {
        errors.push(`Failed to sync ${aggregator.name}: ${error instanceof Error ? error.message : String(error)}`)
      }
    }
    
    // Update model health status based on source availability
    const { error: healthError } = await supabase.rpc('update_model_health_status')
    if (healthError) {
      errors.push(`Failed to update health status: ${healthError.message}`)
    }
    
    return NextResponse.json({
      success: true,
      syncedProviders: syncedModels,
      errors: errors.length > 0 ? errors : undefined
    })
    
  } catch (error) {
    console.error('Sync models error:', error)
    return NextResponse.json(
      { error: 'Failed to sync models' },
      { status: 500 }
    )
  }
}