import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

export async function GET() {
  const supabase = await createSupabaseServerClient()
  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) {
    return NextResponse.json({ user: null }, {
      headers: { 'Cache-Control': 'private, no-store, max-age=0' }
    })
  }

  const { data: profile } = await supabase
    .from('profiles')
    .select('id,public_code,identity_color,created_at,status,bio')
    .eq('id', user.id)
    .maybeSingle()

  return NextResponse.json({
    user: profile ? {
      publicCode: profile.public_code,
      identityColor: profile.identity_color,
      createdAt: profile.created_at,
      status: profile.status,
      bio: profile.bio
    } : null
  }, { headers: { 'Cache-Control': 'private, no-store, max-age=0' } })
}
