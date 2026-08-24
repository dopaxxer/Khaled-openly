import { createServerClient } from '@supabase/ssr'
import { NextResponse } from 'next/server'

// Must match lib/supabase.js. If these point at different projects, refreshed
// auth cookies cannot be consumed by the API route handlers.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://rjucldqvuyeahjqrlene.supabase.co'
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_jnnQqwOVGdK2g1Y7LfjnHg_APSaqz5r'

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

  // Validate/refresh the token on every matched request so the proxy and route
  // handlers observe the same authenticated session.
  await supabase.auth.getUser()

  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|manifest.webmanifest).*)']
}
