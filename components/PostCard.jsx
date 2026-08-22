'use client'
import Link from 'next/link'
import { Bookmark, Flag, Heart, MessageCircle } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Identity } from './Identity'

export function PostCard({ post, initialEngagement = null }) {
  const router = useRouter()
  const [eng, setEng] = useState(initialEngagement || { likeCount: post.likeCount || 0, viewerHasLiked: false, viewerHasBookmarked: false })
  const [busy, setBusy] = useState('')

  useEffect(() => {
    if (initialEngagement) return
    fetch(`/api/engagement?ids=${encodeURIComponent(post.id)}`, { cache: 'no-store' })
      .then(r => r.ok ? r.json() : null)
      .then(data => data?.items?.[0] && setEng(data.items[0]))
      .catch(() => {})
  }, [post.id, initialEngagement])

  async function toggle(action, enabled) {
    if (busy) return
    setBusy(action)
    const previous = eng
    const optimistic = action === 'like'
      ? { ...eng, viewerHasLiked: enabled, likeCount: Math.max(0, eng.likeCount + (enabled ? 1 : -1)) }
      : { ...eng, viewerHasBookmarked: enabled }
    setEng(optimistic)
    try {
      const res = await fetch(`/api/engagement/${post.id}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action, enabled }) })
      if (res.status === 401) { setEng(previous); router.push('/login'); return }
      if (!res.ok) throw new Error()
      const data = await res.json()
      if (data.engagement) setEng(data.engagement)
    } catch { setEng(previous) } finally { setBusy('') }
  }

  const time = new Intl.DateTimeFormat('ar', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(post.createdAt))
  return <article className="post-card">
    <div className="post-top"><Identity code={post.authorCode} color={post.authorColor}/><time className="tiny subtle" dateTime={post.createdAt}>{time}</time></div>
    <Link href={`/post/${post.id}`}><p className="post-body">{post.body}</p></Link>
    <div className="post-actions">
      <Link href={`/post/${post.id}`} className="action-button"><MessageCircle size={16} strokeWidth={1.7}/><span>{post.commentCount ? `${post.commentCount} تعليق` : 'تعليق'}</span></Link>
      <button className={`action-button like${eng.viewerHasLiked ? ' active' : ''}`} onClick={() => toggle('like', !eng.viewerHasLiked)} disabled={busy === 'like'} aria-pressed={eng.viewerHasLiked}><Heart size={16} strokeWidth={1.7} fill={eng.viewerHasLiked ? 'currentColor' : 'none'}/><span>{eng.likeCount || 'إعجاب'}</span></button>
      <button className={`action-button bookmark${eng.viewerHasBookmarked ? ' active' : ''}`} onClick={() => toggle('bookmark', !eng.viewerHasBookmarked)} disabled={busy === 'bookmark'} aria-pressed={eng.viewerHasBookmarked}><Bookmark size={16} strokeWidth={1.7} fill={eng.viewerHasBookmarked ? 'currentColor' : 'none'}/><span>{eng.viewerHasBookmarked ? 'محفوظ' : 'حفظ'}</span></button>
      <Link href={`/report/post/${post.id}`} className="action-button"><Flag size={16} strokeWidth={1.7}/><span>إبلاغ</span></Link>
    </div>
  </article>
}
