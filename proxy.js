import { createServerClient } from '@supabase/ssr'
import { NextResponse } from 'next/server'

// Shares lib/supabaseEnv.js with the route handlers: one source for the
// project means refreshed auth cookies are always consumable by the API, and
// an unset variable stops the deployment instead of silently pointing it at a
// project this account does not own.
import { supabaseKey, supabaseUrl } from '@/lib/supabaseEnv'

function contentSecurityPolicy(nonce) {
  const isDev = process.env.NODE_ENV === 'development'
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ''}`,
    "script-src-attr 'none'",
    `style-src-elem 'self' 'nonce-${nonce}'`,
    "style-src-attr 'unsafe-inline'",
    "img-src 'self' blob: data: https://*.mzstatic.com",
    "media-src 'self' https://*.mzstatic.com",
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

  // A deployment that cannot name its own database still must not authenticate
  // anyone, and it does not: supabaseUrl() throws, no client is built, and no
  // session is refreshed. But throwing out of the proxy answered every single
  // route with a blank Internal Server Error -- including /api/health, which
  // exists to report this exact misconfiguration and could never be reached to
  // do it. So the failure is recorded and the request continues: the routes
  // fail on their own terms, and the one endpoint that can explain why answers.
  try {
    const supabase = createServerClient(supabaseUrl(), supabaseKey(), {
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
  } catch (error) {
    console.error('[openly]', JSON.stringify({
      level: 'error',
      event: 'proxy.session_refresh_skipped',
      message: String(error?.message || error).slice(0, 300)
    }))
  }

  return secure(response, request, csp)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|manifest.webmanifest).*)']
}
