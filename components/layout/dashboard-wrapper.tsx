'use client'

import { ErrorBoundary } from '@/components/ui/error-boundary'
import { ConversationSidebar } from '@/components/layout/conversation-sidebar'
import { AlertCircle } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { useRouter } from 'next/navigation'

interface DashboardWrapperProps {
  children: React.ReactNode
}

export function DashboardWrapper({ children }: DashboardWrapperProps) {
  const router = useRouter()

  return (
    <div className="flex h-screen bg-background">
      <ErrorBoundary
        fallback={
          <div className="flex items-center justify-center w-full h-full p-4">
            <Alert variant="destructive" className="max-w-md">
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Application Error</AlertTitle>
              <AlertDescription className="mt-2 space-y-2">
                <p>
                  We encountered an unexpected error. Please try refreshing the page.
                </p>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => router.refresh()}
                  className="mt-4"
                >
                  Refresh Page
                </Button>
              </AlertDescription>
            </Alert>
          </div>
        }
      >
        <ConversationSidebar />
        <div className="flex-1 flex flex-col">
          {children}
        </div>
      </ErrorBoundary>
    </div>
  )
}