import { createServerClient } from '@supabase/ssr'
import { NextResponse } from 'next/server'

const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://jaipfjwxddpefwfqsnrj.supabase.co'
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_E-A5Oh81tq0YRwuM0NuoXg_eAsMSsvv'

// Supabase access tokens are short-lived. Without a refresh on the way through,
// a returning visitor with a valid refresh token still renders as signed out
// until something happens to touch the session. getUser() performs that
// refresh, and the rewritten cookies are carried back on the response.
export async function proxy(request) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value)
        response = NextResponse.next({ request })
        for (const { name, value, options } of cookiesToSet) response.cookies.set(name, value, options)
      }
    }
  })

  await supabase.auth.getUser()

  return response
}

export const config = {
  // Everything except Next's own assets and the icons, which never read a session.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|manifest.webmanifest).*)']
}
