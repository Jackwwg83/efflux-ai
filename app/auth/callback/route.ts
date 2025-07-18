import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'

export async function GET(request: Request) {
  const requestUrl = new URL(request.url)
  const code = requestUrl.searchParams.get('code')
  const cookieStore = cookies()
  
  // Debug: Log all query params
  console.log('Auth callback URL:', request.url)
  console.log('All query params:', Object.fromEntries(requestUrl.searchParams))

  if (code) {
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get(name: string) {
            return cookieStore.get(name)?.value
          },
          set(name: string, value: string, options: CookieOptions) {
            cookieStore.set({ name, value, ...options })
          },
          remove(name: string, options: CookieOptions) {
            cookieStore.set({ name, value: '', ...options })
          },
        },
      }
    )

    const { error } = await supabase.auth.exchangeCodeForSession(code)
    
    if (error) {
      // Redirect to error page
      return NextResponse.redirect(new URL('/login?error=auth_error', requestUrl.origin))
    }
  }

  // Get the redirect URL from cookie or query params
  const redirectCookie = cookieStore.get('auth-redirect')
  let redirectTo = '/chat'
  
  if (redirectCookie) {
    redirectTo = decodeURIComponent(redirectCookie.value)
    // Clear the cookie after use
    cookieStore.delete('auth-redirect')
  } else if (requestUrl.searchParams.get('redirectTo')) {
    // Fallback to query param for email login
    redirectTo = requestUrl.searchParams.get('redirectTo') || '/chat'
  }
  
  console.log('Redirecting to:', redirectTo)
  
  // URL to redirect to after sign in process completes
  return NextResponse.redirect(new URL(redirectTo, requestUrl.origin))
}