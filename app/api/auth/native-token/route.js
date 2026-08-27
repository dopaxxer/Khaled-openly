import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { describeAuthError, diagnosticPayload } from '@/lib/authFlow'
import { readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, {
  status,
  headers: { 'Cache-Control': 'private, no-store, max-age=0' }
})

export async function POST(request) {
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)

  const provider = String(parsed.data.provider || '')
  if (!['google', 'apple'].includes(provider)) return json({ error: 'مزود تسجيل الدخول غير مدعوم' }, 400)

  const token = String(parsed.data.idToken || '')
  const nonce = parsed.data.nonce == null ? undefined : String(parsed.data.nonce)
  const accessToken = parsed.data.accessToken == null ? undefined : String(parsed.data.accessToken)

  if (!token || token.length > 12000 || (nonce && nonce.length > 512) || (accessToken && accessToken.length > 12000)) {
    return json({ error: 'بيانات تسجيل الدخول غير صالحة' }, 400)
  }

  const supabase = await createSupabaseServerClient()
  const credentials = { provider, token }
  if (nonce) credentials.nonce = nonce
  if (accessToken) credentials.access_token = accessToken

  const { data, error } = await supabase.auth.signInWithIdToken(credentials)
  if (error) {
    const safe = describeAuthError(error, 'verify')
    console.error('[auth/native-token]', provider, safe.code)
    return json(diagnosticPayload(error, { error: safe.message }), safe.status)
  }
  if (!data?.session || !data?.user) return json({ error: 'تعذر إنشاء جلسة تسجيل الدخول' }, 500)

  return json({ ok: true })
}
