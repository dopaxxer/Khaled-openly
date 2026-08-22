import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

function safeNext(value, fallback = '/') {
  const next = String(value || '')
  return next.startsWith('/') && !next.startsWith('//') ? next : fallback
}

function redirectTo(path, request) {
  return NextResponse.redirect(new URL(path, getPublicOrigin(request)))
}

export async function GET(request) {
  const url = new URL(request.url)
  const authCode = url.searchParams.get('code')
  const next = safeNext(url.searchParams.get('next'))

  if (!authCode) {
    return redirectTo('/login?error=auth_callback_failed', request)
  }

  const supabase = await createSupabaseServerClient()
  const { error } = await supabase.auth.exchangeCodeForSession(authCode)

  if (error) {
    return redirectTo('/login?error=auth_callback_failed', request)
  }

  return redirectTo(next, request)
}
