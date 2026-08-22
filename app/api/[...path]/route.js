import { NextResponse } from 'next/server'
import { createSupabaseServerClient, mapPost } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, { status })
const code = value => String(value || '').trim().toUpperCase()
const reasons = new Set(['spam', 'harassment', 'hate', 'threat', 'sexual', 'illegal', 'other'])
const publicCodePattern = /^[A-HJ-NP-Z2-9]{4,8}$/
const identityColorPattern = /^#[0-9A-F]{6}$/

async function ctx(params) {
  const { path = [] } = await params
  const supabase = await createSupabaseServerClient()
  return { path, supabase }
}

async function currentUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

async function getProfile(supabase, userId) {
  if (!userId) return null
  const { data } = await supabase
    .from('profiles')
    .select('id,public_code,identity_color,created_at,status,bio')
    .eq('id', userId)
    .maybeSingle()
  return data || null
}

function userPayload(profile) {
  if (!profile) return null
  return {
    publicCode: profile.public_code,
    identityColor: profile.identity_color,
    createdAt: profile.created_at,
    status: profile.status,
    bio: profile.bio
  }
}

async function engagementFor(supabase, ids) {
  if (!ids.length) return []
  const { data, error } = await supabase.rpc('get_post_engagement', { p_post_ids: ids })
  if (error) return []
  return (data || []).map(x => ({
    postId: x.post_id,
    likeCount: Number(x.like_count || 0),
    viewerHasLiked: !!x.viewer_has_liked,
    viewerHasBookmarked: !!x.viewer_has_bookmarked
  }))
}

async function getOnePost(supabase, id) {
  const { data: post } = await supabase
    .from('posts')
    .select('id,author_id,body,created_at,deleted_at')
    .eq('id', id)
    .is('deleted_at', null)
    .maybeSingle()
  if (!post) return null
  const { data: author } = await supabase
    .from('profiles')
    .select('public_code,identity_color')
    .eq('id', post.author_id)
    .maybeSingle()
  const { count } = await supabase
    .from('comments')
    .select('*', { count: 'exact', head: true })
    .eq('post_id', id)
    .is('deleted_at', null)
  return {
    id: post.id,
    body: post.body,
    createdAt: post.created_at,
    authorCode: author?.public_code,
    authorColor: author?.identity_color,
    commentCount: count || 0
  }
}

function safeNext(value, fallback = '/') {
  const next = String(value || '')
  return next.startsWith('/') && !next.startsWith('//') ? next : fallback
}

export async function GET(request, { params }) {
  const { path, supabase } = await ctx(params)
  const url = new URL(request.url)

  if (path.join('/') === 'auth/callback') {
    const authCode = url.searchParams.get('code')
    const next = safeNext(url.searchParams.get('next'))
    if (!authCode) return NextResponse.redirect(new URL('/login?error=auth_callback_failed', request.url))
    const { error } = await supabase.auth.exchangeCodeForSession(authCode)
    if (error) return NextResponse.redirect(new URL('/login?error=auth_callback_failed', request.url))
    return NextResponse.redirect(new URL(next, request.url))
  }

  if (path.join('/') === 'auth/me') {
    const user = await currentUser(supabase)
    if (!user) return json({ user: null })
    const profile = await getProfile(supabase, user.id)
    return json({ user: userPayload(profile) })
  }

  if (path[0] === 'posts' && path.length === 1) {
    const author = url.searchParams.get('author')
    if (author) {
      const { data, error } = await supabase.rpc('get_user_posts', { p_public_code: code(author), p_limit: 100 })
      if (error) return json({ error: 'تعذر تحميل المنشورات' }, 500)
      return json({ items: (data || []).map(mapPost), nextCursor: null })
    }
    const cursor = url.searchParams.get('cursor')
    let created = null
    let id = null
    if (cursor) {
      const split = cursor.split('|')
      if (split.length === 2) [created, id] = split
    }
    const { data, error } = await supabase.rpc('get_timeline', {
      p_cursor_created_at: created,
      p_cursor_id: id,
      p_limit: 30
    })
    if (error) return json({ error: 'تعذر تحميل المنشورات' }, 500)
    const items = (data || []).map(mapPost)
    const last = items.at(-1)
    return json({ items, nextCursor: items.length === 30 && last ? `${last.createdAt}|${last.id}` : null })
  }

  if (path[0] === 'posts' && path[1] && path.length === 2) {
    const post = await getOnePost(supabase, path[1])
    if (!post) return json({ error: 'المنشور غير موجود' }, 404)
    const { data: rows, error } = await supabase
      .from('comments')
      .select('id,author_id,body,created_at,parent_comment_id')
      .eq('post_id', path[1])
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

  if (path[0] === 'search' && path.length === 1) {
    const q = String(url.searchParams.get('q') || '').trim().slice(0, 120)
    if (!q) return json({ posts: [], users: [] })
    const [{ data: posts }, { data: users }] = await Promise.all([
      supabase.rpc('search_posts', { p_query: q, p_limit: 30 }),
      supabase.from('profiles').select('public_code,identity_color').ilike('public_code', `%${code(q)}%`).limit(10)
    ])
    return json({
      posts: (posts || []).map(mapPost),
      users: (users || []).map(u => ({ publicCode: u.public_code, identityColor: u.identity_color }))
    })
  }

  if (path[0] === 'users' && path[1] && path.length === 2) {
    const targetCode = code(path[1])
    const { data: profile } = await supabase
      .from('profiles')
      .select('id,public_code,identity_color,created_at,status,bio')
      .eq('public_code', targetCode)
      .maybeSingle()
    if (!profile) return json({ error: 'المستخدم غير موجود' }, 404)
    const user = await currentUser(supabase)
    let viewerIsFollowing = false
    let viewerHasMuted = false
    let viewerHasBlocked = false
    if (user && user.id !== profile.id) {
      const [f, m, b] = await Promise.all([
        supabase.from('follows').select('follower_id').eq('follower_id', user.id).eq('followed_id', profile.id).maybeSingle(),
        supabase.from('mutes').select('muter_id').eq('muter_id', user.id).eq('muted_id', profile.id).maybeSingle(),
        supabase.from('blocks').select('blocker_id').eq('blocker_id', user.id).eq('blocked_id', profile.id).maybeSingle()
      ])
      viewerIsFollowing = !!f.data
      viewerHasMuted = !!m.data
      viewerHasBlocked = !!b.data
    }
    return json({
      user: {
        ...userPayload(profile),
        viewerIsFollowing,
        viewerHasMuted,
        viewerHasBlocked,
        isSelf: !!user && user.id === profile.id
      }
    })
  }

  if (path.join('/') === 'me/followers-count') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { count } = await supabase.from('follows').select('*', { count: 'exact', head: true }).eq('followed_id', user.id)
    return json({ count: count || 0 })
  }

  if (path.join('/') === 'me/following') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data: follows } = await supabase
      .from('follows')
      .select('followed_id,created_at')
      .eq('follower_id', user.id)
      .order('created_at', { ascending: false })
    const ids = (follows || []).map(x => x.followed_id)
    const { data: profiles } = ids.length
      ? await supabase.from('profiles').select('id,public_code,identity_color').in('id', ids)
      : { data: [] }
    const byId = Object.fromEntries((profiles || []).map(p => [p.id, p]))
    return json({ items: ids.map(id => byId[id]).filter(Boolean).map(p => ({ publicCode: p.public_code, identityColor: p.identity_color })) })
  }

  if (path[0] === 'engagement' && path.length === 1) {
    const ids = String(url.searchParams.get('ids') || '').split(',').map(x => x.trim()).filter(Boolean).slice(0, 50)
    return json({ items: await engagementFor(supabase, ids) })
  }

  if (path.join('/') === 'notifications') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const [{ data, error }, unread] = await Promise.all([
      supabase.rpc('get_notifications', { p_limit: 50 }),
      supabase.rpc('get_unread_notification_count')
    ])
    if (error) return json({ error: 'تعذر تحميل الإشعارات' }, 500)
    const items = (data || []).map(n => ({
      id: n.id,
      kind: n.kind,
      postId: n.post_id,
      commentId: n.comment_id,
      actorCode: n.actor_code,
      actorColor: n.actor_color,
      readAt: n.read_at,
      createdAt: n.created_at
    }))
    return json({ items, unreadCount: Number(unread.data || 0) })
  }

  if (path.join('/') === 'bookmarks') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data, error } = await supabase.rpc('get_bookmarked_posts', { p_limit: 50 })
    if (error) return json({ error: 'تعذر تحميل المحفوظات' }, 500)
    return json({ items: (data || []).map(mapPost), nextCursor: null })
  }

  if (path.join('/') === 'privacy') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data, error } = await supabase.rpc('get_privacy_relations')
    if (error) return json({ error: 'تعذر تحميل الخصوصية' }, 500)
    return json({
      items: (data || []).map(x => ({
        kind: x.kind,
        publicCode: x.public_code,
        identityColor: x.identity_color,
        createdAt: x.created_at
      }))
    })
  }

  if (path.join('/') === 'admin/reports') {
    const { data: admin } = await supabase.rpc('is_admin')
    if (!admin) return json({ error: 'غير مصرح' }, 403)
    const { data, error } = await supabase
      .from('reports')
      .select('id,target_type,target_id,reason,description,status,created_at')
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) return json({ error: 'تعذر تحميل البلاغات' }, 500)
    return json({
      items: (data || []).map(r => ({
        id: r.id,
        targetType: r.target_type,
        targetId: r.target_id,
        reason: r.reason,
        description: r.description,
        status: r.status,
        createdAt: r.created_at
      }))
    })
  }

  return json({ error: 'المسار غير موجود' }, 404)
}

export async function POST(request, { params }) {
  const { path, supabase } = await ctx(params)
  const body = await request.json().catch(() => ({}))

  if (path.join('/') === 'auth/login') {
    const { email, password } = body
    if (!email || !password) return json({ error: 'أدخل البريد وكلمة المرور' }, 400)
    const { error } = await supabase.auth.signInWithPassword({ email: String(email), password: String(password) })
    if (error) return json({ error: error.code === 'email_not_confirmed' ? 'أكد بريدك الإلكتروني أولًا' : 'بيانات الدخول غير صحيحة' }, 400)
    return json({ ok: true })
  }

  if (path.join('/') === 'auth/register') {
    const email = String(body.email || '').trim()
    const password = String(body.password || '')
    if (!email || password.length < 8 || password.length > 128) return json({ error: 'تحقق من البريد وكلمة المرور' }, 400)
    const origin = new URL(request.url).origin
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: `${origin}/api/auth/callback?next=/first-post` }
    })
    if (error) return json({ error: error.message || 'تعذر إنشاء الحساب' }, 400)
    return json({ ok: true, requiresEmailConfirmation: !data.session })
  }

  if (path.join('/') === 'auth/request-password-reset') {
    const email = String(body.email || '').trim()
    if (!email || email.length > 320 || !email.includes('@')) return json({ error: 'أدخل بريدًا إلكترونيًا صحيحًا' }, 400)
    const origin = new URL(request.url).origin
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${origin}/api/auth/callback?next=/auth/update-password`
    })
    if (error && error.code === 'over_email_send_rate_limit') return json({ error: 'محاولات كثيرة. حاول بعد قليل.' }, 429)
    if (error) console.error('[password-reset]', error.code, error.message)
    return json({ ok: true })
  }

  if (path.join('/') === 'auth/update-password') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'رابط إعادة التعيين منتهي أو غير صالح' }, 401)
    const password = String(body.password || '')
    if (password.length < 8 || password.length > 128) return json({ error: 'كلمة المرور يجب أن تكون بين 8 و128 حرفًا' }, 400)
    const { error } = await supabase.auth.updateUser({ password })
    if (error) return json({ error: 'تعذر تحديث كلمة المرور' }, 400)
    return json({ ok: true })
  }

  if (path.join('/') === 'auth/logout') {
    await supabase.auth.signOut()
    return json({ ok: true })
  }

  if (path.join('/') === 'profile') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const publicCode = code(body.publicCode)
    const identityColor = String(body.identityColor || '').trim().toUpperCase()
    const status = String(body.status || '').trim().slice(0, 60) || null
    const bio = String(body.bio || '').trim().slice(0, 240) || null
    if (!publicCodePattern.test(publicCode)) return json({ error: 'الكود يجب أن يكون من 4 إلى 8 أحرف أو أرقام واضحة' }, 400)
    if (!identityColorPattern.test(identityColor)) return json({ error: 'لون الهوية غير صالح' }, 400)
    const { error } = await supabase
      .from('profiles')
      .update({ public_code: publicCode, identity_color: identityColor, status, bio, updated_at: new Date().toISOString() })
      .eq('id', user.id)
    if (error?.code === '23505') return json({ error: 'هذا الكود مستخدم بالفعل. اختر كودًا آخر.' }, 409)
    if (error) return json({ error: 'تعذر حفظ الهوية' }, 400)
    const profile = await getProfile(supabase, user.id)
    return json({ ok: true, user: userPayload(profile) })
  }

  if (path[0] === 'posts' && path.length === 1) {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const text = String(body.body || '').trim()
    if (!text || text.length > 3000) return json({ error: 'النص يجب أن يكون بين 1 و3000 حرف' }, 400)
    const { data, error } = await supabase.from('posts').insert({ author_id: user.id, body: text }).select('id').single()
    if (error) return json({ error: 'تعذر النشر' }, 400)
    return json({ id: data.id }, 201)
  }

  if (path[0] === 'posts' && path[1] && path[2] === 'comments') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const text = String(body.body || '').trim()
    if (!text || text.length > 2000) return json({ error: 'التعليق غير صالح' }, 400)
    const { data, error } = await supabase
      .from('comments')
      .insert({ post_id: path[1], author_id: user.id, body: text, parent_comment_id: body.parentCommentId || null })
      .select('id')
      .single()
    if (error) return json({ error: 'تعذر إضافة التعليق' }, 400)
    return json({ id: data.id }, 201)
  }

  if (path[0] === 'users' && path[1] && path[2] === 'relation') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data: target } = await supabase.from('profiles').select('id').eq('public_code', code(path[1])).maybeSingle()
    if (!target || target.id === user.id) return json({ error: 'العلاقة غير صالحة' }, 400)
    const kind = body.kind
    const enabled = !!body.enabled
    const config = kind === 'follow'
      ? ['follows', 'follower_id', 'followed_id']
      : kind === 'mute'
        ? ['mutes', 'muter_id', 'muted_id']
        : kind === 'block'
          ? ['blocks', 'blocker_id', 'blocked_id']
          : null
    if (!config) return json({ error: 'نوع غير صالح' }, 400)
    const [table, left, right] = config
    const result = enabled
      ? await supabase.from(table).upsert({ [left]: user.id, [right]: target.id })
      : await supabase.from(table).delete().eq(left, user.id).eq(right, target.id)
    if (result.error) return json({ error: 'تعذر تحديث العلاقة' }, 400)
    if (kind === 'block' && enabled) {
      await Promise.all([
        supabase.from('follows').delete().eq('follower_id', user.id).eq('followed_id', target.id),
        supabase.from('follows').delete().eq('follower_id', target.id).eq('followed_id', user.id)
      ])
    }
    return json({ ok: true })
  }

  if (path[0] === 'engagement' && path[1]) {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const action = body.action
    const enabled = !!body.enabled
    const fn = action === 'like' ? 'set_post_like' : action === 'bookmark' ? 'set_post_bookmark' : null
    const key = action === 'like' ? 'p_liked' : 'p_bookmarked'
    if (!fn) return json({ error: 'إجراء غير صالح' }, 400)
    const { error } = await supabase.rpc(fn, { p_post_id: path[1], [key]: enabled })
    if (error) return json({ error: 'تعذر تحديث التفاعل' }, 400)
    const [engagement] = await engagementFor(supabase, [path[1]])
    return json({ ok: true, engagement })
  }

  if (path.join('/') === 'reports') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const targetType = body.targetType
    if ((targetType !== 'post' && targetType !== 'comment') || !body.targetId || !reasons.has(body.reason)) return json({ error: 'بلاغ غير صالح' }, 400)
    const description = body.description ? String(body.description).slice(0, 1000) : null
    const { error } = await supabase.from('reports').insert({
      reporter_id: user.id,
      target_type: targetType,
      target_id: body.targetId,
      reason: body.reason,
      description
    })
    if (error) return json({ error: 'تعذر إرسال البلاغ' }, 400)
    return json({ ok: true }, 201)
  }

  return json({ error: 'المسار غير موجود' }, 404)
}

export async function PATCH(request, { params }) {
  const { path, supabase } = await ctx(params)
  const body = await request.json().catch(() => ({}))

  if (path.join('/') === 'notifications') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const ids = Array.isArray(body.ids) ? body.ids : null
    const { data, error } = await supabase.rpc('mark_notifications_read', { p_ids: ids })
    if (error) return json({ error: 'تعذر تحديث الإشعارات' }, 400)
    return json({ ok: true, count: Number(data || 0) })
  }

  if (path[0] === 'admin' && path[1] === 'reports' && path[2]) {
    const { data: admin } = await supabase.rpc('is_admin')
    if (!admin) return json({ error: 'غير مصرح' }, 403)
    const allowed = new Set(['delete-content', 'suspend-author', 'ban-author', 'resolve', 'dismiss'])
    if (!allowed.has(body.action)) return json({ error: 'إجراء غير صالح' }, 400)
    const { data, error } = await supabase.rpc('moderate_report', { p_report_id: path[2], p_action: body.action })
    if (error) return json({ error: 'تعذر تنفيذ الإجراء' }, 400)
    return json({ ok: !!data })
  }

  if (path[0] === 'posts' && path[1] && path.length === 2) {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const text = String(body.body || '').trim()
    if (!text || text.length > 3000) return json({ error: 'النص يجب أن يكون بين 1 و3000 حرف' }, 400)
    // Ownership is re-derived from the session and applied as a filter, so a
    // forged id simply matches no row rather than editing someone else's post.
    const { data, error } = await supabase.from('posts').update({ body: text }).eq('id', path[1]).eq('author_id', user.id).is('deleted_at', null).select('id').maybeSingle()
    if (error) return json({ error: 'تعذر تعديل المنشور' }, 400)
    if (!data) return json({ error: 'المنشور غير موجود' }, 404)
    return json({ ok: true })
  }

  return json({ error: 'المسار غير موجود' }, 404)
}

export async function DELETE(request, { params }) {
  const { path, supabase } = await ctx(params)
  const user = await currentUser(supabase)
  if (!user) return json({ error: 'غير مسجل' }, 401)
  const now = new Date().toISOString()

  // Soft delete, matching how the feed and threads already filter: the row
  // stays so replies and moderation history keep resolving.
  if (path[0] === 'posts' && path[1] && path.length === 2) {
    const { data, error } = await supabase.from('posts').update({ deleted_at: now }).eq('id', path[1]).eq('author_id', user.id).is('deleted_at', null).select('id').maybeSingle()
    if (error) return json({ error: 'تعذر حذف المنشور' }, 400)
    if (!data) return json({ error: 'المنشور غير موجود' }, 404)
    return json({ ok: true })
  }

  if (path[0] === 'comments' && path[1] && path.length === 2) {
    const { data, error } = await supabase.from('comments').update({ deleted_at: now }).eq('id', path[1]).eq('author_id', user.id).is('deleted_at', null).select('id').maybeSingle()
    if (error) return json({ error: 'تعذر حذف التعليق' }, 400)
    if (!data) return json({ error: 'التعليق غير موجود' }, 404)
    return json({ ok: true })
  }

  return json({ error: 'المسار غير موجود' }, 404)
}
