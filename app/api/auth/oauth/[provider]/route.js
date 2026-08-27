import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { describeAuthError } from '@/lib/authFlow'
import { getPublicOrigin, safeInternalPath } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

export async function GET(request, { params }) {
  const { provider } = await params
  if (!['google', 'apple'].includes(provider)) {
    return NextResponse.json({ error: 'مزود تسجيل الدخول غير مدعوم' }, { status: 404 })
  }

  const url = new URL(request.url)
  const next = safeInternalPath(url.searchParams.get('next'), '/')
  const origin = getPublicOrigin(request)
  const supabase = await createSupabaseServerClient()

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: `${origin}/api/auth/callback?next=${encodeURIComponent(next)}`,
      skipBrowserRedirect: true
    }
  })

  if (error || !data?.url) {
    const safe = describeAuthError(error || { code: 'oauth_start_failed' }, 'request')
    console.error('[auth/oauth/start]', provider, safe.code)
    return NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(safe.code)}`, origin))
  }

  return NextResponse.redirect(data.url)
}
