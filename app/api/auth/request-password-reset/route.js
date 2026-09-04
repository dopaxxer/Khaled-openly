import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin } from '@/lib/publicOrigin'
import { isValidEmail, normalizeEmail, readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, {
  status,
  headers: { 'Cache-Control': 'private, no-store, max-age=0' }
})

export async function POST(request) {
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)
  const body = parsed.data
  const email = normalizeEmail(body.email)

  if (!isValidEmail(email)) {
    return json({ error: 'أدخل بريدًا إلكترونيًا صحيحًا' }, 400)
  }

  const supabase = await createSupabaseServerClient()
  const origin = getPublicOrigin(request)
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    // The nested query has to be encoded: unencoded, `?recovery=1` parsed as a
    // parameter of the callback itself, so `next` arrived as a bare
    // `/auth/update-password` and the flag was dropped on the way through.
    redirectTo: `${origin}/api/auth/callback?next=${encodeURIComponent('/auth/update-password?recovery=1')}`
  })

  if (error?.code === 'over_email_send_rate_limit') {
    return json({ error: 'محاولات كثيرة. حاول بعد قليل.' }, 429)
  }

  if (error) console.error('[password-reset]', error.code, error.message)

  // Keep the response non-enumerating: don't reveal whether an account exists.
  return json({ ok: true })
}
