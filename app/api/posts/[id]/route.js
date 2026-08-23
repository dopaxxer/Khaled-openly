import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, { status })

async function currentUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

async function getOnePost(supabase, id) {
  const { data: post } = await supabase
    .from('posts')
    .select('id,author_id,body,created_at,deleted_at')
    .eq('id', id)
    .is('deleted_at', null)
    .maybeSingle()
  if (!post) return null

  const [{ data: author }, { count }] = await Promise.all([
    supabase.from('profiles').select('public_code,identity_color').eq('id', post.author_id).maybeSingle(),
    supabase.from('comments').select('*', { count: 'exact', head: true }).eq('post_id', id).is('deleted_at', null)
  ])

  return {
    id: post.id,
    body: post.body,
    createdAt: post.created_at,
    authorCode: author?.public_code,
    authorColor: author?.identity_color,
    commentCount: count || 0
  }
}

export async function GET(_request, { params }) {
  const { id } = await params
  const supabase = await createSupabaseServerClient()
  const post = await getOnePost(supabase, id)
  if (!post) return json({ error: 'المنشور غير موجود' }, 404)

  const { data: rows, error } = await supabase
    .from('comments')
    .select('id,author_id,body,created_at,parent_comment_id')
    .eq('post_id', id)
    .is('deleted_at', null)
    .order('created_at', { ascending: true })

  if (error) return json({ post, comments: [] })

  const authorIds = [...new Set((rows || []).map(x => x.author_id))]
  const { data: profiles } = authorIds.length
    ? await supabase.from('profiles').select('id,public_code,identity_color').in('id', authorIds)
    : { data: [] }
  const byId = Object.fromEntries((profiles || []).map(p => [p.id, p]))
  const comments = (rows || []).map(c => ({
    id: c.id,
    body: c.body,
    createdAt: c.created_at,
    parentCommentId: c.parent_comment_id,
    authorCode: byId[c.author_id]?.public_code,
    authorColor: byId[c.author_id]?.identity_color
  }))

  return json({ post, comments })
}

export async function PATCH(request, { params }) {
  const { id } = await params
  const supabase = await createSupabaseServerClient()
  const user = await currentUser(supabase)
  if (!user) return json({ error: 'غير مسجل' }, 401)

  const body = await request.json().catch(() => ({}))
  const text = String(body.body || '').trim()
  if (!text || text.length > 3000) return json({ error: 'النص يجب أن يكون بين 1 و3000 حرف' }, 400)

  const { data, error } = await supabase
    .from('posts')
    .update({ body: text })
    .eq('id', id)
    .eq('author_id', user.id)
    .is('deleted_at', null)
    .select('id')
    .maybeSingle()

  if (error) return json({ error: 'تعذر تعديل المنشور' }, 400)
  if (!data) return json({ error: 'المنشور غير موجود' }, 404)
  return json({ ok: true })
}

export async function DELETE(_request, { params }) {
  const { id } = await params
  const supabase = await createSupabaseServerClient()
  const user = await currentUser(supabase)
  if (!user) return json({ error: 'غير مسجل' }, 401)

  const { data, error } = await supabase
    .from('posts')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', id)
    .eq('author_id', user.id)
    .is('deleted_at', null)
    .select('id')
    .maybeSingle()

  if (error) return json({ error: 'تعذر حذف المنشور' }, 400)
  if (!data) return json({ error: 'المنشور غير موجود' }, 404)
  return json({ ok: true })
}
