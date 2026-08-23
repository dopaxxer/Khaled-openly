import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, { status })
const normalizeCode = value => String(value || '').trim().toUpperCase()
const codePattern = /^[A-HJ-NP-Z2-9]{4,8}$/
const colorPattern = /^#[0-9A-F]{6}$/

export async function POST(request) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return json({ error: 'غير مسجل' }, 401)

  const body = await request.json().catch(() => ({}))
  const publicCode = normalizeCode(body.publicCode)
  const identityColor = String(body.identityColor || '').trim().toUpperCase()
  const status = String(body.status || '').trim().slice(0, 60) || null
  const bio = String(body.bio || '').trim().slice(0, 240) || null

  if (!codePattern.test(publicCode)) return json({ error: 'الكود يجب أن يكون من 4 إلى 8 أحرف أو أرقام واضحة' }, 400)
  if (!colorPattern.test(identityColor)) return json({ error: 'لون الهوية غير صالح' }, 400)

  const { error } = await supabase
    .from('profiles')
    .update({
      public_code: publicCode,
      identity_color: identityColor,
      status,
      bio,
      updated_at: new Date().toISOString()
    })
    .eq('id', user.id)

  if (error?.code === '23505') return json({ error: 'هذا الكود مستخدم بالفعل. اختر كودًا آخر.' }, 409)
  if (error) return json({ error: 'تعذر حفظ الهوية' }, 400)

  const { data: profile } = await supabase
    .from('profiles')
    .select('public_code,identity_color,created_at,status,bio')
    .eq('id', user.id)
    .single()

  return json({
    user: {
      publicCode: profile.public_code,
      identityColor: profile.identity_color,
      createdAt: profile.created_at,
      status: profile.status,
      bio: profile.bio
    }
  })
}
