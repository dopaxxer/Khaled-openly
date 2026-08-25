import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin } from '@/lib/publicOrigin'
import { isMailDeliveryFailure, isStrongPassword, isValidEmail, normalizeEmail, PASSWORD_MAX_LENGTH, PASSWORD_MIN_LENGTH, readJson } from '@/lib/validation'

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
  const password = String(body.password || '')

  if (!isValidEmail(email)) {
    return json({ error: 'أدخل بريدًا إلكترونيًا صحيحًا' }, 400)
  }
  if (!isStrongPassword(password)) {
    return json({ error: `كلمة المرور يجب أن تكون بين ${PASSWORD_MIN_LENGTH} و${PASSWORD_MAX_LENGTH} حرفًا وتضم حرفًا ورقمًا` }, 400)
  }

  const supabase = await createSupabaseServerClient()
  const origin = getPublicOrigin(request)
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${origin}/api/auth/callback?next=/first-post`
    }
  })

  if (error) {
    const messages = {
      user_already_exists: 'هذا البريد مسجَّل بالفعل. سجّل الدخول بدلًا من ذلك.',
      weak_password: 'كلمة المرور ضعيفة جدًا. اختر كلمة مرور أقوى.',
      email_address_invalid: 'البريد الإلكتروني غير صالح.',
      over_email_send_rate_limit: 'محاولات كثيرة. حاول بعد قليل.'
    }
    // A mail sender that is down is the server's problem, and it is the one
    // failure that leaves someone staring at a verification screen for a code
    // that was never sent. Name it, and record the code so it can be traced.
    if (isMailDeliveryFailure(error.code)) {
      console.error('[auth/register] mail delivery failed:', error.code, error.message)
      return json({ error: 'تعذر إرسال كود التحقق الآن. المشكلة عندنا — حاول بعد قليل.' }, 502)
    }
    if (!messages[error.code]) console.error('[auth/register]', error.code, error.message)
    return json({ error: messages[error.code] || 'تعذر إنشاء الحساب. حاول مرة أخرى.' }, 400)
  }

  return json({ ok: true, requiresEmailConfirmation: !data.session, email })
}
