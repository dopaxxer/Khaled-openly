import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { describeAuthError, diagnosticPayload, isValidE164, normalizeE164 } from '@/lib/authFlow'
import { isValidEmail, normalizeEmail, readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, {
  status,
  headers: { 'Cache-Control': 'private, no-store, max-age=0' }
})

export async function POST(request) {
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)

  const method = parsed.data.method === 'phone' ? 'phone' : 'email'
  const token = String(parsed.data.token || '').trim()
  if (!/^\d{6}$/.test(token)) return json({ error: 'أدخل كودًا صحيحًا من 6 أرقام' }, 400)

  const supabase = await createSupabaseServerClient()
  let result

  if (method === 'email') {
    const email = normalizeEmail(parsed.data.email)
    if (!isValidEmail(email)) return json({ error: 'البريد الإلكتروني غير صالح' }, 400)
    result = await supabase.auth.verifyOtp({ email, token, type: 'email' })
  } else {
    const phone = normalizeE164(parsed.data.phone)
    if (!isValidE164(phone)) return json({ error: 'رقم الهاتف غير صالح' }, 400)
    result = await supabase.auth.verifyOtp({ phone, token, type: 'sms' })
  }

  if (result.error) {
    const safe = describeAuthError(result.error, 'verify')
    console.error('[auth/otp/verify]', method, safe.code)
    return json(diagnosticPayload(result.error, { error: safe.message }), safe.status)
  }
  if (!result.data?.session || !result.data?.user) {
    return json({ error: 'تم قبول الكود لكن تعذر إنشاء جلسة. أعد المحاولة.' }, 500)
  }

  const createdAt = Date.parse(result.data.user.created_at || '')
  const lastSignInAt = Date.parse(result.data.user.last_sign_in_at || '')
  const isNewUser = Number.isFinite(createdAt)
    && Number.isFinite(lastSignInAt)
    && Math.abs(lastSignInAt - createdAt) <= 10 * 60 * 1000

  return json({ ok: true, next: isNewUser ? '/onboarding/interests' : '/' })
}
