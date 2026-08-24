import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

export async function GET() {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'غير مسجل' }, { status: 401 })

  // Followers are intentionally private under RLS. Use the audited public RPC
  // wrapper so we return only the count without exposing follower identities.
  const { data, error } = await supabase.rpc('get_private_follower_count')
  if (error) return NextResponse.json({ error: 'تعذر تحميل العدد' }, { status: 500 })
  return NextResponse.json({ count: Number(data || 0) })
}
