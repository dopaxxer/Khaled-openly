import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

export async function POST() {
  const supabase = await createSupabaseServerClient()
  const { error } = await supabase.auth.signOut()
  if (error) {
    console.error('[auth/logout]', error.code || 'unknown')
    return NextResponse.json({ error: 'تعذر تسجيل الخروج' }, { status: 400 })
  }
  return NextResponse.json({ ok: true }, {
    headers: { 'Cache-Control': 'private, no-store, max-age=0' }
  })
}
