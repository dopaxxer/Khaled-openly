import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { createSupabaseServerClient, mapPost, mentionsBySource, withMentions } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { PASSWORD_RECOVERY_COOKIE } from '@/lib/publicOrigin'
import {
  COMMENT_MAX_LENGTH,
  isStrongPassword,
  isMailDeliveryFailure,
  isUuid,
  isValidEmail,
  normalizeEmail,
  parseCursor,
  PASSWORD_MAX_LENGTH,
  PASSWORD_MIN_LENGTH,
  POST_MAX_LENGTH,
  readJson,
  REPORT_MAX_LENGTH
} from '@/lib/validation'

export const dynamic = 'force-dynamic'

const json = (body, status = 200) => NextResponse.json(body, {
  status,
  headers: {
    'Cache-Control': 'private, no-store, max-age=0',
    'X-Content-Type-Options': 'nosniff'
  }
})
const code = value => String(value || '').trim().toUpperCase()

// Every 500 records why before it answers: a route that fails silently can only
// be discovered by someone complaining.
const serverError = (event, error, message) => {
  logError(event, error)
  return json({ error: message }, 500)
}
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
  if (error) throw error
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
    .select('id,author_id,body,created_at,deleted_at,track_id')
    .eq('id', id)
    .is('deleted_at', null)
    .maybeSingle()
  if (!post) return null
  const [authorResult, commentResult, trackResult] = await Promise.all([
    supabase
      .from('profiles')
      .select('public_code,identity_color')
      .eq('id', post.author_id)
      .maybeSingle(),
    supabase
      .from('comments')
      .select('*', { count: 'exact', head: true })
      .eq('post_id', id)
      .is('deleted_at', null),
    post.track_id
      ? supabase
          .from('music_tracks')
          .select('id,title,artist_name,artwork_url,preview_url,external_url')
          .eq('id', post.track_id)
          .maybeSingle()
      : Promise.resolve({ data: null })
  ])
  const author = authorResult.data
  const track = trackResult.data
  return {
    id: post.id,
    body: post.body,
    createdAt: post.created_at,
    authorCode: author?.public_code,
    authorColor: author?.identity_color,
    commentCount: commentResult.count || 0,
    track: track ? {
      id: track.id,
      title: track.title,
      artist: track.artist_name,
      artworkUrl: track.artwork_url,
      previewUrl: track.preview_url,
      externalUrl: track.external_url
    } : null
  }
}

export async function GET(request, { params }) {
  const { path, supabase } = await ctx(params)
  const url = new URL(request.url)

  if (path.join('/') === 'auth/me') {
    const user = await currentUser(supabase)
    if (!user) return json({ user: null })
    const profile = await getProfile(supabase, user.id)
    return json({ user: userPayload(profile) })
  }

  if (path.join('/') === 'auth/password-mode') {
    const cookieStore = await cookies()
    return json({ recovery: cookieStore.get(PASSWORD_RECOVERY_COOKIE)?.value === '1' })
  }

  if (path[0] === 'posts' && path.length === 1) {
    const author = url.searchParams.get('author')
    if (author) {
      const { data, error } = await supabase.rpc('get_user_posts', { p_public_code: code(author), p_limit: 100 })
      if (error) return serverError('posts.byAuthor', error, 'تعذر تحميل المنشورات')
      return json({ items: await withMentions(supabase, (data || []).map(mapPost), 'post'), nextCursor: null })
    }
    const cursor = parseCursor(url.searchParams.get('cursor'))
    if (!cursor) return json({ error: 'مؤشر الصفحة غير صالح' }, 400)
    const { data, error } = await supabase.rpc('get_timeline', {
      p_cursor_created_at: cursor.createdAt,
      p_cursor_id: cursor.id,
      p_limit: 30
    })
    if (error) return serverError('timeline.load', error, 'تعذر تحميل المنشورات')
    const items = await withMentions(supabase, (data || []).map(mapPost), 'post')
    const last = items.at(-1)
    return json({ items, nextCursor: items.length === 30 && last ? `${last.createdAt}|${last.id}` : null })
  }

  if (path[0] === 'posts' && path[1] && path.length === 2) {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const post = await getOnePost(supabase, path[1])
    if (!post) return json({ error: 'المنشور غير موجود' }, 404)
    const { data: rows, error } = await supabase
      .from('comments')
      .select('id,author_id,body,created_at,parent_comment_id')
      .eq('post_id', path[1])
      .is('deleted_at', null)
      .order('created_at', { ascending: true })
    if (error) return serverError('comments.load', error, 'تعذر تحميل التعليقات')
    const authorIds = [...new Set((rows || []).map(x => x.author_id))]
    const { data: profiles, error: profileError } = authorIds.length
      ? await supabase.from('profiles').select('id,public_code,identity_color').in('id', authorIds)
      : { data: [], error: null }
    if (profileError) return serverError('comments.authors', profileError, 'تعذر تحميل أصحاب التعليقات')
    const byId = Object.fromEntries((profiles || []).map(p => [p.id, p]))
    const [commentMentions, postMentions] = await Promise.all([
      mentionsBySource(supabase, 'comment', (rows || []).map(c => c.id)),
      mentionsBySource(supabase, 'post', [post.id])
    ])
    const comments = (rows || []).map(c => ({
      id: c.id,
      body: c.body,
      createdAt: c.created_at,
      parentCommentId: c.parent_comment_id,
      authorCode: byId[c.author_id]?.public_code,
      authorColor: byId[c.author_id]?.identity_color,
      mentions: commentMentions[c.id] || []
    }))
    return json({ post: { ...post, mentions: postMentions[post.id] || [] }, comments })
  }

  if (path[0] === 'search' && path.length === 1) {
    const q = String(url.searchParams.get('q') || '').trim().slice(0, 120)
    if (!q) return json({ posts: [], users: [] })
    const [{ data: posts, error: postsError }, { data: users, error: usersError }] = await Promise.all([
      supabase.rpc('search_posts', { p_query: q, p_limit: 30 }),
      supabase.from('profiles').select('public_code,identity_color').ilike('public_code', `%${code(q)}%`).limit(10)
    ])
    if (postsError || usersError) return serverError('search', postsError || usersError, 'تعذر إكمال البحث')
    return json({
      posts: await withMentions(supabase, (posts || []).map(mapPost), 'post'),
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
    if (!ids.length) return json({ items: [] })
    if (ids.some(id => !isUuid(id))) return json({ error: 'معرّف منشور غير صالح' }, 400)
    try {
      return json({ items: await engagementFor(supabase, ids) })
    } catch (thrown) {
      return serverError('engagement', thrown, 'تعذر تحميل التفاعل')
    }
  }

  if (path.join('/') === 'notifications/count') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data, error } = await supabase.rpc('get_unread_notification_count')
    if (error) return serverError('notifications.count', error, 'تعذر تحميل الإشعارات')
    return json({ unreadCount: Number(data || 0) })
  }

  if (path.join('/') === 'notifications') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const [{ data, error }, unread] = await Promise.all([
      supabase.rpc('get_notifications', { p_limit: 50 }),
      supabase.rpc('get_unread_notification_count')
    ])
    if (error) return serverError('notifications.list', error, 'تعذر تحميل الإشعارات')
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
    if (error) return serverError('bookmarks.load', error, 'تعذر تحميل المحفوظات')
    return json({ items: await withMentions(supabase, (data || []).map(mapPost), 'post'), nextCursor: null })
  }

  if (path.join('/') === 'privacy') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const { data, error } = await supabase.rpc('get_privacy_relations')
    if (error) return serverError('privacy.load', error, 'تعذر تحميل الخصوصية')
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
    if (error) return serverError('admin.reports', error, 'تعذر تحميل البلاغات')
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
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)
  const body = parsed.data

  if (path.join('/') === 'auth/login') {
    const email = normalizeEmail(body.email)
    const password = String(body.password || '')
    if (!isValidEmail(email) || !password || password.length > PASSWORD_MAX_LENGTH) return json({ error: 'أدخل البريد وكلمة المرور' }, 400)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) {
      // Supabase answers invalid_credentials for both a wrong password and an
      // address that was never registered, on purpose: telling them apart would
      // let anyone test which emails have accounts. Keep that, but say what the
      // person can actually do next instead of a bare rejection — the old
      // wording read as "your account is gone".
      const messages = {
        email_not_confirmed: 'أكد بريدك الإلكتروني أولًا. ابحث عن رسالة التحقق أو اطلب كودًا جديدًا.',
        over_request_rate_limit: 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.',
        user_banned: 'هذا الحساب موقوف. تواصل معنا إن كنت تظن أن هذا خطأ.'
      }
      if (!messages[error.code]) console.error('[auth/login]', error.code, error.message)
      return json({
        error: messages[error.code]
          || 'البريد أو كلمة المرور غير صحيحة. إن نسيت كلمة المرور فأعد تعيينها، وإن لم يكن لديك حساب فأنشئ هويتك.'
      }, 400)
    }
    return json({ ok: true })
  }

  if (path.join('/') === 'auth/update-password') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'رابط إعادة التعيين منتهي أو غير صالح' }, 401)
    const password = String(body.password || '')
    if (!isStrongPassword(password)) {
      return json({ error: `كلمة المرور يجب أن تكون بين ${PASSWORD_MIN_LENGTH} و${PASSWORD_MAX_LENGTH} حرفًا وتضم حرفًا ورقمًا` }, 400)
    }

    const cookieStore = await cookies()
    const isRecovery = cookieStore.get(PASSWORD_RECOVERY_COOKIE)?.value === '1'
    if (!isRecovery) {
      const currentPassword = String(body.currentPassword || '')
      if (!currentPassword || currentPassword.length > PASSWORD_MAX_LENGTH || !user.email) {
        return json({ error: 'أدخل كلمة المرور الحالية أولًا' }, 400)
      }
      const { error: verificationError } = await supabase.auth.signInWithPassword({
        email: user.email,
        password: currentPassword
      })
      if (verificationError) return json({ error: 'كلمة المرور الحالية غير صحيحة' }, 403)
    }

    const { error } = await supabase.auth.updateUser({ password })
    if (error) return json({ error: 'تعذر تحديث كلمة المرور' }, 400)
    const response = json({ ok: true })
    response.cookies.set(PASSWORD_RECOVERY_COOKIE, '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/api/auth',
      maxAge: 0
    })
    return response
  }

  if (path.join('/') === 'auth/verify') {
    const email = normalizeEmail(body.email)
    const token = String(body.token || '').trim()
    if (!isValidEmail(email) || !/^\d{6}$/.test(token)) return json({ error: 'أدخل كودًا صحيحًا من 6 أرقام' }, 400)
    const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' })
    if (error) return json({ error: error.code === 'otp_expired' ? 'انتهت صلاحية الكود. اطلب كودًا جديدًا.' : 'الكود غير صحيح' }, 400)
    return json({ ok: true })
  }

  if (path.join('/') === 'auth/resend-code') {
    const email = normalizeEmail(body.email)
    if (!isValidEmail(email)) return json({ error: 'البريد غير صالح' }, 400)
    const { error } = await supabase.auth.resend({ type: 'signup', email })
    if (error && error.code === 'over_email_send_rate_limit') return json({ error: 'محاولات كثيرة. حاول بعد قليل.' }, 429)
    if (error) {
      console.error('[resend-code]', error.code, error.message)
      // Reporting success after the send failed is what leaves someone waiting
      // for a code that was never sent. A delivery failure is the server's
      // fault, so say so rather than letting them retry a broken path.
      if (isMailDeliveryFailure(error.code)) {
        return json({ error: 'تعذر إرسال الكود الآن. حاول بعد قليل أو تواصل معنا.' }, 502)
      }
    }
    // Any other failure stays quiet: whether an address is registered is not
    // something this endpoint may reveal.
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
      .update({ public_code: publicCode, identity_color: identityColor, status, bio })
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
    if (!text || text.length > POST_MAX_LENGTH) return json({ error: `النص يجب أن يكون بين 1 و${POST_MAX_LENGTH} حرف` }, 400)
    const trackId = body.trackId == null ? null : String(body.trackId).trim()
    if (trackId !== null && !isUuid(trackId)) return json({ error: 'معرّف الأغنية غير صالح' }, 400)
    // create_post inserts the row and resolves its mentions in one
    // transaction, so a post can never be published without them.
    const { data, error } = await supabase.rpc('create_post', {
      p_body: text,
      p_track_id: trackId
    })
    if (error || !data) return json({ error: 'تعذر النشر' }, 400)
    return json({ id: data }, 201)
  }

  if (path[0] === 'posts' && path[1] && path[2] === 'comments') {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const text = String(body.body || '').trim()
    if (!text || text.length > COMMENT_MAX_LENGTH) return json({ error: `التعليق يجب أن يكون بين 1 و${COMMENT_MAX_LENGTH} حرف` }, 400)
    const parentCommentId = body.parentCommentId || null
    if (parentCommentId && !isUuid(parentCommentId)) return json({ error: 'معرّف التعليق الأصلي غير صالح' }, 400)
    const { data, error } = await supabase.rpc('create_comment', {
      p_post_id: path[1],
      p_parent_comment_id: parentCommentId,
      p_body: text
    })
    if (error || !data) return json({ error: 'تعذر إضافة التعليق' }, 400)
    return json({ id: data }, 201)
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
    if (enabled) {
      const { error } = await supabase.from(table).insert({ [left]: user.id, [right]: target.id })
      if (error && error.code !== '23505') return json({ error: 'تعذر تحديث العلاقة' }, 400)
    } else {
      const { error } = await supabase.from(table).delete().eq(left, user.id).eq(right, target.id)
      if (error) return json({ error: 'تعذر تحديث العلاقة' }, 400)
    }
    if (kind === 'block' && enabled) {
      await Promise.all([
        supabase.from('follows').delete().eq('follower_id', user.id).eq('followed_id', target.id),
        supabase.from('follows').delete().eq('follower_id', target.id).eq('followed_id', user.id)
      ])
    }
    return json({ ok: true })
  }

  if (path[0] === 'posts' && path[1] && path[2] === 'like') {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const enabled = !!body.enabled
    const { data, error } = await supabase.rpc('set_post_like', { p_post_id: path[1], p_liked: enabled })
    // The RPC returns the resulting state. A successful unlike therefore returns
    // false; treating only true as success made every unlike look like a failure
    // even though the row had already been removed.
    if (error || data !== enabled) return json({ error: 'تعذر حفظ الإعجاب' }, 400)
    return json({ ok: true })
  }

  if (path[0] === 'posts' && path[1] && path[2] === 'bookmark') {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const enabled = !!body.enabled
    const { data, error } = await supabase.rpc('set_post_bookmark', { p_post_id: path[1], p_bookmarked: enabled })
    // As with likes, false is the valid success value when removing a bookmark.
    if (error || data !== enabled) return json({ error: 'تعذر حفظ المنشور' }, 400)
    return json({ ok: true })
  }

  if (path.join('/') === 'reports') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const targetType = body.targetType
    if ((targetType !== 'post' && targetType !== 'comment') || !isUuid(body.targetId) || !reasons.has(body.reason)) return json({ error: 'بلاغ غير صالح' }, 400)
    const description = body.description ? String(body.description).trim().slice(0, REPORT_MAX_LENGTH) : null
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
  const parsed = await readJson(request)
  if (parsed.error) return json({ error: parsed.error }, parsed.status)
  const body = parsed.data

  if (path.join('/') === 'notifications') {
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const ids = Array.isArray(body.ids) ? body.ids.slice(0, 100) : []
    if (!ids.length) return json({ ok: true })
    if (ids.some(id => !isUuid(id))) return json({ error: 'معرّف إشعار غير صالح' }, 400)
    const { error } = await supabase.rpc('mark_notifications_read', { p_ids: ids })
    if (error) return json({ error: 'تعذر تحديث الإشعارات' }, 400)
    return json({ ok: true })
  }

  if (path[0] === 'admin' && path[1] === 'reports' && path[2]) {
    if (!isUuid(path[2])) return json({ error: 'معرّف البلاغ غير صالح' }, 400)
    const { data: admin } = await supabase.rpc('is_admin')
    if (!admin) return json({ error: 'غير مصرح' }, 403)
    const allowed = new Set(['delete-content', 'suspend-author', 'ban-author', 'resolve', 'dismiss'])
    if (!allowed.has(body.action)) return json({ error: 'إجراء غير صالح' }, 400)
    const { data, error } = await supabase.rpc('moderate_report', { p_report_id: path[2], p_action: body.action })
    if (error) return json({ error: 'تعذر تنفيذ الإجراء' }, 400)
    return json({ ok: !!data })
  }

  if (path[0] === 'posts' && path[1] && path.length === 2) {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const user = await currentUser(supabase)
    if (!user) return json({ error: 'غير مسجل' }, 401)
    const text = String(body.body || '').trim()
    if (!text || text.length > POST_MAX_LENGTH) return json({ error: `النص يجب أن يكون بين 1 و${POST_MAX_LENGTH} حرف` }, 400)
    const trackId = body.trackId == null ? null : String(body.trackId).trim()
    if (trackId !== null && !isUuid(trackId)) return json({ error: 'معرّف الأغنية غير صالح' }, 400)
    // update_own_post rewrites the body and re-resolves mentions together, so
    // an edit that adds or drops a mention stays consistent.
    const { data, error } = await supabase.rpc('update_own_post', {
      p_post_id: path[1],
      p_body: text,
      p_track_id: trackId
    })
    if (error) return json({ error: 'تعذر تعديل المنشور' }, 400)
    if (data !== true) return json({ error: 'المنشور غير موجود' }, 404)
    return json({ ok: true })
  }

  return json({ error: 'المسار غير موجود' }, 404)
}

export async function DELETE(request, { params }) {
  const { path, supabase } = await ctx(params)
  const user = await currentUser(supabase)
  if (!user) return json({ error: 'غير مسجل' }, 401)

  if (path[0] === 'posts' && path[1] && path.length === 2) {
    if (!isUuid(path[1])) return json({ error: 'معرّف المنشور غير صالح' }, 400)
    const { data, error } = await supabase.rpc('delete_own_post', { p_post_id: path[1] })
    if (error) return json({ error: 'تعذر حذف المنشور' }, 400)
    if (data !== true) return json({ error: 'المنشور غير موجود' }, 404)
    return json({ ok: true })
  }

  if (path[0] === 'comments' && path[1] && path.length === 2) {
    if (!isUuid(path[1])) return json({ error: 'معرّف التعليق غير صالح' }, 400)
    const { data, error } = await supabase.rpc('delete_own_comment', { p_comment_id: path[1] })
    if (error) return json({ error: 'تعذر حذف التعليق' }, 400)
    if (data !== true) return json({ error: 'التعليق غير موجود' }, 404)
    return json({ ok: true })
  }

  return json({ error: 'المسار غير موجود' }, 404)
}
