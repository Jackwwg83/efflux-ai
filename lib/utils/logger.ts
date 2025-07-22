/**
 * Production-safe logging utility
 * In production, these should be sent to a monitoring service like Sentry
 */

const isDevelopment = process.env.NODE_ENV === 'development'

interface LogContext {
  userId?: string
  conversationId?: string
  error?: Error
  [key: string]: any
}

class Logger {
  private log(level: 'info' | 'warn' | 'error', message: string, context?: LogContext) {
    if (isDevelopment) {
      const logFn = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log
      logFn(`[${level.toUpperCase()}] ${message}`, context)
    } else {
      // In production, send to monitoring service
      // Example: Sentry, LogRocket, DataDog, etc.
      // For now, we'll just silence the logs
      
      // TODO: Integrate with monitoring service
      // Example implementation:
      // if (level === 'error' && context?.error) {
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