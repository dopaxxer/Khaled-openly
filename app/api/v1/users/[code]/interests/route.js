import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { PUBLIC_CODE_PATTERN } from '@/lib/mentions'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

export async function GET(_request, { params }) {
  const { code: rawCode } = await params
  const code = String(rawCode || '').trim().toUpperCase()
  if (!PUBLIC_CODE_PATTERN.test(code)) {
    return NextResponse.json({ error: 'الكود غير صالح', code: 'invalid_code' }, { status: 400, headers: HEADERS })
  }

  const supabase = await createSupabaseServerClient()
  const { data, error } = await supabase.rpc('get_public_interest_profile', { p_public_code: code })
  if (error) {
    return NextResponse.json({ error: 'تعذر تحميل الاهتمامات', code: 'profile_failed' }, { status: 500, headers: HEADERS })
  }
  return NextResponse.json({ profile: data || null }, { status: 200, headers: HEADERS })
}
