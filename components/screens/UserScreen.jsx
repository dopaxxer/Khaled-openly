'use client'
import dynamic from 'next/dynamic'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Identity } from '../Identity'
import { PostCard } from '../PostCard'
import { NotFound } from './NotFound'

// Taste panels sit below the identity header and are only rendered once the
// profile answers, so they do not belong in the chunk the profile boots with.
const PublicMusicProfile = dynamic(() => import('../PublicMusicProfile').then(m => m.PublicMusicProfile))
const PublicInterestProfile = dynamic(() => import('../InterestDiscovery').then(m => m.PublicInterestProfile))

export function UserScreen({ code }) {
  const router = useRouter()
  const [user, setUser] = useState(undefined)
  const [posts, setPosts] = useState([])
  const [music, setMusic] = useState(null)
  const [interests, setInterests] = useState(null)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const [u, p, m, i] = await Promise.all([
          fetch(`/api/users/${encodeURIComponent(code)}`, { cache: 'no-store' }),
          fetch(`/api/posts?author=${encodeURIComponent(code)}`, { cache: 'no-store' }),
          fetch(`/api/v1/users/${encodeURIComponent(code)}/music`, { cache: 'no-store' }),
          fetch(`/api/v1/users/${encodeURIComponent(code)}/interests`, { cache: 'no-store' })
        ])
        if (cancelled) return
        if (u.status === 404) { setUser(null); return }
        if (!u.ok) { setError('تعذر فتح الملف'); setUser(null); return }
        setUser((await u.json()).user)
        if (p.ok) setPosts((await p.json()).items || [])
        setMusic(m.ok ? (await m.json()).profile : null)
        setInterests(i.ok ? (await i.json()).profile : null)
      } catch {
        if (!cancelled) { setError('تعذر فتح الملف'); setUser(null) }
      }
    })()
    return () => { cancelled = true }
  }, [code])

  async function startMessage() {
    if (busy) return
    setBusy('message')
    setError('')
    try {
      const response = await fetch('/api/v1/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ publicCode: user.publicCode })
      })
      if (response.status === 401) {
        location.href = '/login'
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر بدء المحادثة')
      router.push(`/messages/${data.conversation.conversationId}`)
    } catch (messageError) {
      setError(messageError.message || 'تعذر بدء المحادثة')
    } finally {
      setBusy('')
    }
  }

  async function relation(kind, enabled) {
    if (busy) return
    setBusy(kind)
    setError('')
    try {
      const r = await fetch(`/api/users/${code}/relation`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ kind, enabled })
      })
      if (r.status === 401) {
        location.href = '/login'
        return
      }
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || 'تعذر تحديث العلاقة')
      setUser(u => ({ ...u, [kind === 'follow' ? 'viewerIsFollowing' : kind === 'mute' ? 'viewerHasMuted' : 'viewerHasBlocked']: enabled }))
    } catch (e) {
      setError(e.message || 'تعذر تحديث العلاقة')
    } finally {
      setBusy('')
    }
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (!user) return <NotFound />

  return <>
    <section className="profile-hero">
      <Identity code={user.publicCode} color={user.identityColor} large />
      {user.status && <p className="profile-status">{user.status}</p>}
      {user.bio && <p className="profile-bio" data-user-content="">{user.bio}</p>}
      <p className="profile-meta">انضم في {new Intl.DateTimeFormat('ar', { dateStyle: 'medium' }).format(new Date(user.createdAt))}</p>
      {!user.isSelf && <div className="row wrap mt20">
        <button className="primary-button" disabled={busy === 'follow'} onClick={() => relation('follow', !user.viewerIsFollowing)}>{user.viewerIsFollowing ? 'إلغاء المتابعة' : 'متابعة'}</button>
        <button className="secondary-button" disabled={!!busy || user.viewerHasBlocked || user.viewerHasMuted} onClick={startMessage}>{busy === 'message' ? 'جارِ فتح المحادثة…' : 'رسالة خاصة'}</button>
        <button className="secondary-button" disabled={busy === 'mute'} onClick={() => relation('mute', !user.viewerHasMuted)}>{user.viewerHasMuted ? 'إلغاء الكتم' : 'كتم'}</button>
        <button className="danger-button" disabled={busy === 'block'} onClick={() => relation('block', !user.viewerHasBlocked)}>{user.viewerHasBlocked ? 'إلغاء الحظر' : 'حظر'}</button>
      </div>}
      {error && <p className="status-message error mt16">{error}</p>}
    </section>
    <PublicInterestProfile profile={interests} />
    <PublicMusicProfile music={music} />
    <div className="section-title">الكتابات</div>
    {posts.length
      ? posts.map(p => <PostCard key={p.id} post={p} viewerCode={user.isSelf ? user.publicCode : null} />)
      : <div className="empty-state"><p>لا توجد منشورات.</p></div>}
  </>
}
