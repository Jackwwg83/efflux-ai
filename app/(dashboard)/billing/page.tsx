'use client'

import { useState, useEffect } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import { createClient } from '@/lib/supabase/client'
import { Database } from '@/types/database'
import { Check, Zap } from 'lucide-react'

type UserTier = Database['public']['Tables']['user_tiers']['Row']
type UsageLog = Database['public']['Tables']['usage_logs']['Row']

const TIER_FEATURES = {
  free: {
    name: 'Free',
    price: '$0',
    credits: 5000,
    features: [
      '5,000 tokens per day',
      'Access to basic models',
      'Standard support',
      '5 requests per minute',
    ],
  },
  pro: {
    name: 'Pro',
    price: '$10',
    credits: 500000,
    features: [
      '500,000 tokens per day',
      'Access to advanced models',
      'Priority support',
      '30 requests per minute',
      'GPT-4 and Claude Sonnet',
    ],
  },
  max: {
    name: 'Max',
    price: '$50',
    credits: 5000000,
    features: [
      '5,000,000 tokens per day',
      'Access to all models',
      'Premium support',
      '100 requests per minute',
      'Gemini 2.5 Pro and GPT-4.1',
      'AWS Bedrock models',
    ],
  },
}

export default function BillingPage() {
  const [userTier, setUserTier] = useState<UserTier | null>(null)
  const [usageLogs, setUsageLogs] = useState<UsageLog[]>([])
  const [loading, setLoading] = useState(true)
  const supabase = createClient()

  useEffect(() => {
    loadBillingInfo()
  }, [])

  const loadBillingInfo = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      // Load user tier
      const { data: tierData } = await supabase
        .from('user_tiers')
        .select('*')
        .eq('user_id', user.id)
        .single()

      setUserTier(tierData)

      // Load recent usage
      const { data: logsData } = await supabase
        .from('usage_logs')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(10)

      setUsageLogs(logsData || [])
    } catch (error) {
      console.error('Error loading billing info:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleUpgrade = (tier: 'pro' | 'max') => {
    // TODO: Implement Stripe integration
    console.log('Upgrade to', tier)
  }

  if (loading) {
    return <div className="flex items-center justify-center h-full">Loading...</div>
  }

  const creditsPercentage = userTier
    ? (userTier.credits_balance / userTier.credits_limit) * 100
    : 0

  const totalCost = usageLogs.reduce((sum, log) => sum + Number(log.cost), 0)

  return (
    <div className="container max-w-6xl py-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold">Billing & Usage</h1>
        <p className="text-muted-foreground">
          Manage your subscription and monitor usage
        </p>
      </div>

      {/* Current Plan */}
      <Card className="mb-8">
        <CardHeader>
          <CardTitle>Current Plan</CardTitle>
          <CardDescription>Your subscription details</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-2xl font-bold">
                {TIER_FEATURES[userTier?.tier || 'free'].name}
              </h3>
              <p className="text-muted-foreground">
                {TIER_FEATURES[userTier?.tier || 'free'].price}/month
              </p>
            </div>
            <Badge variant="outline" className="text-lg px-4 py-2">
              {userTier?.tier.toUpperCase()}
            </Badge>
          </div>

          <div className="space-y-4">
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span>Credits Used</span>
                <span>
                  {Math.round(userTier?.credits_balance || 0).toLocaleString()} / 
                  {Math.round(userTier?.credits_limit || 0).toLocaleString()}
                </span>
              </div>
              <Progress value={creditsPercentage} className="h-3" />
            </div>

            <div className="text-sm text-muted-foreground">
              Resets on {new Date(userTier?.reset_at || '').toLocaleDateString()}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Pricing Plans */}
      <div className="grid md:grid-cols-3 gap-6 mb-8">
        {Object.entries(TIER_FEATURES).map(([tier, features]) => (
          <Card key={tier} className={userTier?.tier === tier ? 'border-primary' : ''}>
            <CardHeader>
              <CardTitle>{features.name}</CardTitle>
              <CardDescription>
                <span className="text-2xl font-bold">{features.price}</span>
                /month
              </CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="space-y-2 mb-6">
                {features.features.map((feature, index) => (
                  <li key={index} className="flex items-start gap-2">
                    <Check className="h-4 w-4 text-green-500 mt-0.5" />
                    <span className="text-sm">{feature}</span>
                  </li>
                ))}
              </ul>
              
              {userTier?.tier === tier ? (
                <Button disabled className="w-full">
                  Current Plan
                </Button>
              ) : (
                <Button
                  className="w-full"
                  onClick={() => handleUpgrade(tier as 'pro' | 'max')}
                  disabled={tier === 'free'}
                >
                  {tier === 'free' ? 'Downgrade' : 'Upgrade'}
                </Button>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Recent Usage */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Usage</CardTitle>
          <CardDescription>Your API usage in the last 24 hours</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {usageLogs.length > 0 ? (
              <>
                <div className="text-sm text-muted-foreground">
                  Total cost: ${totalCost.toFixed(6)}
                </div>
                <div className="space-y-2">
                  {usageLogs.map((log) => (
                    <div key={log.id} className="flex items-center justify-between text-sm">
                      <div className="flex items-center gap-2">
                        <Zap className="h-3 w-3" />
                        <span>{log.model}</span>
                        <span className="text-muted-foreground">
                          {log.total_tokens} tokens
                        </span>
                      </div>
                      <span>${Number(log.cost).toFixed(6)}</span>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <p className="text-sm text-muted-foreground">No usage yet</p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}