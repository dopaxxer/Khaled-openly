import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

export async function GET() {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  const response = (body, status = 200) => NextResponse.json(body, {
    status,
    headers: { 'Cache-Control': 'private, no-store, max-age=0' }
  })
  if (!user) return response({ error: 'غير مسجل' }, 401)

  // Followers are intentionally private under RLS. Use the audited public RPC
  // wrapper so we return only the count without exposing follower identities.
  const { data, error } = await supabase.rpc('get_private_follower_count')
  if (error) return response({ error: 'تعذر تحميل العدد' }, 500)
  return response({ count: Number(data || 0) })
}
