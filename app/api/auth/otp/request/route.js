import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { AUTH_RESEND_COOLDOWN_SECONDS, describeAuthError, diagnosticPayload, isValidE164, maskAuthTarget, normalizeE164 } from '@/lib/authFlow'
import { isValidEmail, normalizeEmail, readJson } from '@/lib/validation'
import { getPublicOrigin } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, {
  status,
  headers: { 'Cache-Control': 'private, no-store, max-age=0' }
})

export async function POST(request) {
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)

  const method = parsed.data.method === 'phone' ? 'phone' : 'email'
  const supabase = await createSupabaseServerClient()

  if (method === 'email') {
    const email = normalizeEmail(parsed.data.email)
    if (!isValidEmail(email)) return json({ error: 'أدخل بريدًا إلكترونيًا صحيحًا' }, 400)

    const emailMode = process.env.AUTH_EMAIL_MODE === 'link' ? 'link' : 'otp'
    const emailRedirectTo = new URL('/api/auth/callback?next=/onboarding/interests', getPublicOrigin(request)).toString()
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: true, emailRedirectTo }
    })
    if (error) {
      const safe = describeAuthError(error, 'request')
      console.error('[auth/otp/request] email', safe.code)
      return json(diagnosticPayload(error, { error: safe.message }), safe.status)
    }

    return json({
      ok: true,
      method,
      target: maskAuthTarget(method, email),
      delivery: emailMode,
      cooldownSeconds: AUTH_RESEND_COOLDOWN_SECONDS
    })
  }

  const phone = normalizeE164(parsed.data.phone)
  if (!isValidE164(phone)) {
    return json({ error: 'أدخل رقم الهاتف بصيغة دولية صحيحة مثل +491234567890' }, 400)
  }

  const { error } = await supabase.auth.signInWithOtp({ phone })
  if (error) {
    const safe = describeAuthError(error, 'request')
    console.error('[auth/otp/request] phone', safe.code)
    return json(diagnosticPayload(error, { error: safe.message }), safe.status)
  }

  return json({
    ok: true,
    method,
    target: maskAuthTarget(method, phone),
    cooldownSeconds: AUTH_RESEND_COOLDOWN_SECONDS
  })
}
