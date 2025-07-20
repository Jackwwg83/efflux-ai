'use client'

import { useState, useRef, KeyboardEvent } from 'react'
import { Send, StopCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'

interface MessageInputProps {
  onSendMessage: (message: string) => void
  isLoading: boolean
  onStopStreaming?: () => void
  disabled?: boolean
  onInputChange?: (value: string) => void
}

export function MessageInput({
  onSendMessage,
  isLoading,
  onStopStreaming,
  disabled = false,
  onInputChange,
}: MessageInputProps) {
  const [message, setMessage] = useState('')
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  const handleSubmit = () => {
    if (message.trim() && !isLoading && !disabled) {
      onSendMessage(message.trim())
      setMessage('')
      textareaRef.current?.focus()
    }
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  return (
    <div className="border-t p-4">
      <div className="max-w-3xl mx-auto">
        <div className="flex gap-2">
          <Textarea
            ref={textareaRef}
            value={message}
            onChange={(e) => {
              setMessage(e.target.value)
              onInputChange?.(e.target.value)
            }}
            onKeyDown={handleKeyDown}
            placeholder="Type your message..."
            className="resize-none"
            rows={1}
            disabled={isLoading || disabled}
          />
          
          {isLoading && onStopStreaming ? (
            <Button
              onClick={onStopStreaming}
              size="icon"
              variant="destructive"
            >
              <StopCircle className="h-4 w-4" />
            </Button>
          ) : (
            <Button
              onClick={handleSubmit}
              size="icon"
              disabled={!message.trim() || isLoading || disabled}
            >
              <Send className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    </div>
  )
}