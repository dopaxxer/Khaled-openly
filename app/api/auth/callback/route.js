import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin, PASSWORD_RECOVERY_COOKIE, safeInternalPath } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

function redirectTo(path, request) {
  return NextResponse.redirect(new URL(path, getPublicOrigin(request)))
}

export async function GET(request) {
  const url = new URL(request.url)
  const authCode = url.searchParams.get('code')
  const next = safeInternalPath(url.searchParams.get('next'))

  if (!authCode) {
    return redirectTo('/login?error=auth_callback_failed', request)
  }

  const supabase = await createSupabaseServerClient()
  const { error } = await supabase.auth.exchangeCodeForSession(authCode)

  if (error) {
    return redirectTo('/login?error=auth_callback_failed', request)
  }

  const response = redirectTo(next, request)
  if (next.split('?')[0] === '/auth/update-password') {
    response.cookies.set(PASSWORD_RECOVERY_COOKIE, '1', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/api/auth',
      maxAge: 10 * 60
    })
  }
  return response
}
