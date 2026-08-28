'use client'
import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'
import { CommentThread } from '../CommentThread'
import { MentionField } from '../MentionField'
import { PostCard } from '../PostCard'
import { COMMENT_MAX_LENGTH } from '@/lib/validation'
import { NotFound } from './NotFound'
import { fetchViewer } from '@/lib/viewer'

export function PostScreen({ id }) {
  const [post, setPost] = useState(undefined)
  const [comments, setComments] = useState([])
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState(false)
  const [viewerCode, setViewerCode] = useState(null)
  const [commentError, setCommentError] = useState('')
  const [loadError, setLoadError] = useState('')
  const postRef = useRef(null)

  async function load() {
    try {
      const r = await fetch(`/api/posts/${id}`, { cache: 'no-store' })
      if (r.status === 404) {
        postRef.current = null
        setPost(null)
        setLoadError('')
        return
      }
      if (!r.ok) {
        if (postRef.current) {
          setCommentError('تعذر تحديث المنشور. حاول مجددًا.')
          return
        }
        setLoadError('تعذر فتح المنشور.')
        setPost(null)
        return
      }
      const d = await r.json()
      postRef.current = d.post
      setPost(d.post)
      setComments(d.comments || [])
      setCommentError('')
      setLoadError('')
    } catch {
      if (postRef.current) {
        setCommentError('تعذر تحديث المنشور. حاول مجددًا.')
        return
      }
      setLoadError('تعذر فتح المنشور.')
      setPost(null)
    }
  }

  useEffect(() => { load() }, [id])
  useEffect(() => {
    let cancelled = false
    fetchViewer()
      .then(user => { if (!cancelled) setViewerCode(user?.publicCode || null) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [])

  async function comment(e) {
    e.preventDefault()
    if (!body.trim()) return
    setBusy(true); setCommentError('')
    try {
      const r = await fetch(`/api/posts/${id}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body })
      })
      if (r.status === 401) { location.href = '/login'; return }
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || 'تعذر إضافة التعليق')
      setBody('')
      await load()
    } catch (e) {
      setCommentError(e.message || 'تعذر إضافة التعليق')
    } finally { setBusy(false) }
  }

  if (post === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (!post) return loadError
    ? <div className="empty-state"><div><p>{loadError}</p><button className="secondary-button mt16" onClick={load}>المحاولة مجددًا</button></div></div>
    : <NotFound />

  return <section className="v2-post-detail">
    <header className="v2-post-detail-head">
      <Link href="/" className="v2-back-link">‹ العودة</Link>
      <h1>المنشور</h1>
    </header>
    <PostCard post={post} viewerCode={viewerCode} onChanged={load} />
    <form className="comment-form v2-comment-form" onSubmit={comment}>
      <MentionField maxLength={COMMENT_MAX_LENGTH} value={body} onChange={setBody} placeholder="أضف ردًا…" aria-label="نص التعليق" />
      <div className="row between">
        <span className="tiny subtle" dir="ltr">{body.length} / {COMMENT_MAX_LENGTH}</span>
        <button className="primary-button" disabled={busy || !body.trim()}>{busy ? 'جارِ الإرسال…' : 'رد'}</button>
      </div>
      {commentError && <p className="status-message error">{commentError}</p>}
    </form>
    <div className="v2-replies-title">الردود</div>
    <CommentThread comments={comments} postId={id} viewerCode={viewerCode} onChanged={load} />
  </section>
}
