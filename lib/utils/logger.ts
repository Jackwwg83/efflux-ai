/**
 * Production-safe logging utility
 * In production, these should be sent to a monitoring service like Sentry
 */

const isDevelopment = process.env.NODE_ENV === 'development'

interface LogContext {
  userId?: string
  conversationId?: string
  error?: unknown
  [key: string]: any
}

class Logger {
  private log(level: 'info' | 'warn' | 'error', message: string, context?: LogContext) {
    // Process the error to ensure it's serializable
    const processedContext = context ? { ...context } : {}
    if (processedContext.error) {
      // Convert unknown error to a serializable format
      if (processedContext.error instanceof Error) {
        processedContext.error = {
          message: processedContext.error.message,
          name: processedContext.error.name,
          stack: processedContext.error.stack,
        }
      } else if (typeof processedContext.error === 'string') {
        processedContext.error = { message: processedContext.error }
      } else {
        processedContext.error = { message: String(processedContext.error) }
      }
    }

    if (isDevelopment) {
      const logFn = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log
      logFn(`[${level.toUpperCase()}] ${message}`, processedContext)
    } else {
      // In production, send to monitoring service
      // Example: Sentry, LogRocket, DataDog, etc.
      // For now, we'll just silence the logs
      
      // TODO: Integrate with monitoring service
      // Example implementation:
      // if (level === 'error' && context?.error instanceof Error) {
      //   Sentry.captureException(context.error, {
      //     extra: context,
      //     tags: { level }
      //   })
      // }
    }
  }

  info(message: string, context?: LogContext) {
    this.log('info', message, context)
  }

  warn(message: string, context?: LogContext) {
    this.log('warn', message, context)
  }

  error(message: string, context?: LogContext) {
    this.log('error', message, context)
  }
}

export const logger = new Logger()