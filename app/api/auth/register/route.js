import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { getPublicOrigin } from '@/lib/publicOrigin'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, { status })

export async function POST(request) {
  const body = await request.json().catch(() => ({}))
  const email = String(body.email || '').trim()
  const password = String(body.password || '')

  if (!email || password.length < 8 || password.length > 128) {
    return json({ error: 'تحقق من البريد وكلمة المرور' }, 400)
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
    return json({ error: messages[error.code] || 'تعذر إنشاء الحساب. حاول مرة أخرى.' }, 400)
  }

  return json({ ok: true, requiresEmailConfirmation: !data.session })
}
