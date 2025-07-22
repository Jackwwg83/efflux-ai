'use client'

import { ErrorBoundary } from '@/components/ui/error-boundary'
import { AlertCircle, RefreshCw } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { useRouter } from 'next/navigation'

interface ChatErrorBoundaryProps {
  children: React.ReactNode
  conversationId?: string
}

export function ChatErrorBoundary({ children, conversationId }: ChatErrorBoundaryProps) {
  const router = useRouter()

  const handleReset = () => {
    // Refresh the page to reset the chat state
    router.refresh()
  }

  return (
    <ErrorBoundary
      resetKeys={conversationId ? [conversationId] : []}
      fallback={
        <div className="flex items-center justify-center h-full p-4">
          <Alert variant="destructive" className="max-w-md">
            <AlertCircle className="h-4 w-4" />
            <AlertTitle>Chat Error</AlertTitle>
            <AlertDescription className="mt-2 space-y-2">
              <p>
                We encountered an error while loading the chat. This might be due to a 
                network issue or a temporary problem with our services.
              </p>
              <div className="flex gap-2 mt-4">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleReset}
                  className="flex items-center gap-2"
                >
                  <RefreshCw className="h-3 w-3" />
                  Reload Chat
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => router.push('/chat')}
                >
                  Start New Chat
                </Button>
              </div>
            </AlertDescription>
          </Alert>
        </div>
      }
    >
      {children}
    </ErrorBoundary>
  )
}