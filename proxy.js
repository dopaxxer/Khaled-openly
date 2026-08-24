import { createServerClient } from '@supabase/ssr'
import { NextResponse } from 'next/server'

// Must match lib/supabase.js. If these point at different projects, refreshed
// auth cookies cannot be consumed by the API route handlers.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://rjucldqvuyeahjqrlene.supabase.co'
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_jnnQqwOVGdK2g1Y7LfjnHg_APSaqz5r'

function contentSecurityPolicy(nonce) {
  const isDev = process.env.NODE_ENV === 'development'
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ''}`,
    "script-src-attr 'none'",
    `style-src-elem 'self' 'nonce-${nonce}'`,
    "style-src-attr 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    "connect-src 'self'",
    "frame-src 'none'",
    "manifest-src 'self'",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    ...(isDev ? [] : ['upgrade-insecure-requests'])
  ].join('; ')
}

function secure(response, request, csp) {
  response.headers.set('Content-Security-Policy', csp)
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
  response.headers.set('X-Content-Type-Options', 'nosniff')
  response.headers.set('X-Frame-Options', 'DENY')
  response.headers.set('Cross-Origin-Opener-Policy', 'same-origin')
  response.headers.set('Cross-Origin-Resource-Policy', 'same-origin')
  response.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=()')
  if (request.nextUrl.pathname.startsWith('/api/')) {
    response.headers.set('Cache-Control', 'private, no-store, max-age=0')
    response.headers.set('Pragma', 'no-cache')
  }
  if (process.env.NODE_ENV === 'production' && request.nextUrl.protocol === 'https:') {
    response.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
  }
  return response
}

export async function proxy(request) {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64')
  const csp = contentSecurityPolicy(nonce)
  const requestHeaders = new Headers(request.headers)
  requestHeaders.set('x-nonce', nonce)
  requestHeaders.set('Content-Security-Policy', csp)

  const fetchSite = request.headers.get('sec-fetch-site')
  if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method) && fetchSite === 'cross-site') {
    return secure(NextResponse.json({ error: 'طلب عبر موقع خارجي مرفوض' }, { status: 403 }), request, csp)
  }

  const nextResponse = () => NextResponse.next({ request: { headers: requestHeaders } })
  let response = nextResponse()

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value)
        response = nextResponse()
        for (const { name, value, options } of cookiesToSet) response.cookies.set(name, value, options)
      }
    }
  })

  // Validate and refresh immediately after client creation. getClaims verifies
  // the JWT signature instead of trusting cookie contents.
  await supabase.auth.getClaims()

  return secure(response, request, csp)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|manifest.webmanifest).*)']
}
