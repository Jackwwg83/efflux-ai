'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Activity } from 'lucide-react'

export default function MonitoringPage() {
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Real-time Monitoring</CardTitle>
          <CardDescription>Monitor system health and performance in real-time</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col items-center justify-center py-20 text-center">
            <Activity className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-semibold">Monitoring Coming Soon</h3>
            <p className="text-sm text-muted-foreground mt-2">
              This feature is under development. You'll be able to monitor API latency, success rates, and system health here.
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}