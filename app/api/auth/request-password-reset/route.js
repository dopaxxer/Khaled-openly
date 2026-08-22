import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, { status })

export async function POST(request) {
  const body = await request.json().catch(() => ({}))
  const email = String(body.email || '').trim()

  if (!email || email.length > 320 || !email.includes('@')) {
    return json({ error: 'أدخل بريدًا إلكترونيًا صحيحًا' }, 400)
  }

  const supabase = await createSupabaseServerClient()
  const origin = getPublicOrigin(request)
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${origin}/api/auth/callback?next=/auth/update-password`
  })

  if (error?.code === 'over_email_send_rate_limit') {
    return json({ error: 'محاولات كثيرة. حاول بعد قليل.' }, 429)
  }

  if (error) console.error('[password-reset]', error.code, error.message)

  // Keep the response non-enumerating: don't reveal whether an account exists.
  return json({ ok: true })
}
