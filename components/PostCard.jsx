'use client'
import Link from 'next/link'
import { Bold, Bookmark, Flag, Heart, Italic, List, MessageCircle, Pencil, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'
import { Avatar } from './Avatar'
import { MentionField } from './MentionField'
import { TrackAttachment } from './TrackAttachment'
import { renderRichText } from '@/lib/richText'
import { toggleListPrefix, toggleWrap } from '@/lib/textFormatting'
import { POST_MAX_LENGTH } from '@/lib/validation'

export function PostCard({ post, initialEngagement = null, viewerCode = null, onChanged = null }) {
  const router = useRouter()
  const [eng, setEng] = useState(initialEngagement || { likeCount: post.likeCount || 0, viewerHasLiked: false, viewerHasBookmarked: false })
  const [busy, setBusy] = useState('')
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(post.body)
  const [displayBody, setDisplayBody] = useState(post.body)
  const [gone, setGone] = useState(false)
  const [ownerError, setOwnerError] = useState('')
  const editRef = useRef(null)

  function formatDraft(kind) {
    const el = editRef.current
    if (!el) return
    const result = kind === 'list'
      ? toggleListPrefix(draft, el.selectionStart, el.selectionEnd)
      : toggleWrap(draft, el.selectionStart, el.selectionEnd, kind === 'bold' ? '**' : '*')
    setDraft(result.value)
    requestAnimationFrame(() => { el.focus(); el.setSelectionRange(result.start, result.end) })
  }
  // Public codes are unique, so matching the viewer's own code is enough to
  // decide what to *offer*. The server re-derives ownership from the session
  // before it writes anything.
  const isOwner = !!viewerCode && post.authorCode === viewerCode

  useEffect(() => {
    if (initialEngagement) return
    fetch(`/api/engagement?ids=${encodeURIComponent(post.id)}`, { cache: 'no-store' })
      .then(r => r.ok ? r.json() : null)
      .then(data => data?.items?.[0] && setEng(data.items[0]))
      .catch(() => {})
  }, [post.id, initialEngagement])

  useEffect(() => {
    setDisplayBody(post.body)
    setDraft(post.body)
  }, [post.body])

  async function toggle(action, enabled) {
    if (busy) return
    setBusy(action)
    setOwnerError('')
    const previous = eng
    const optimistic = action === 'like'
      ? { ...eng, viewerHasLiked: enabled, likeCount: Math.max(0, eng.likeCount + (enabled ? 1 : -1)) }
      : { ...eng, viewerHasBookmarked: enabled }
    setEng(optimistic)
    try {
      const res = await fetch(`/api/posts/${post.id}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled }) })
      if (res.status === 401) { setEng(previous); router.push('/login'); return }
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر حفظ التفاعل')
    } catch (error) {
      setEng(previous)
      setOwnerError(error.message || 'تعذر حفظ التفاعل')
    } finally { setBusy('') }
  }

  async function saveEdit() {
    const text = draft.trim()
    if (!text || busy) return
    setBusy('edit')
    setOwnerError('')
    try {
      const res = await fetch(`/api/posts/${post.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body: text, trackId: post.track?.id || null })
      })
      if (res.status === 401) { router.push('/login'); return }
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر التعديل')
      setDisplayBody(text)
      setDraft(text)
      setEditing(false)
      onChanged?.()
    } catch (e) { setOwnerError(e.message) } finally { setBusy('') }
  }

  async function remove() {
    if (busy || !confirm('حذف هذا المنشور؟ لا يمكن التراجع.')) return
    setBusy('delete')
    setOwnerError('')
    try {
      const res = await fetch(`/api/posts/${post.id}`, { method: 'DELETE' })
      if (res.status === 401) { router.push('/login'); return }
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر الحذف')
      setGone(true)
      onChanged?.()
    } catch (e) { setOwnerError(e.message); setBusy('') }
  }

  if (gone) return null

  const time = new Intl.DateTimeFormat('ar', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(post.createdAt))
  return <article className="post-card">
    <Link href={`/u/${post.authorCode}`} className="post-avatar-link" aria-label={`صفحة ${post.authorCode}`}><Avatar code={post.authorCode} color={post.authorColor} size={40}/></Link>

    <div className="post-main">
      <div className="post-top">
        <Link href={`/u/${post.authorCode}`} className="post-author">{post.authorCode}</Link>
        <span className="dot-sep" aria-hidden="true">·</span>
        <time className="tiny subtle" dateTime={post.createdAt}>{time}</time>
      </div>

      {editing
        ? <div className="owner-edit composer panel">
            <div className="composer-toolbar" role="toolbar" aria-label="تنسيق النص">
              <button type="button" className="toolbar-button" aria-label="عريض" title="عريض" onClick={() => formatDraft('bold')}><Bold size={16}/></button>
              <button type="button" className="toolbar-button" aria-label="مائل" title="مائل" onClick={() => formatDraft('italic')}><Italic size={16}/></button>
              <button type="button" className="toolbar-button" aria-label="قائمة نقطية" title="قائمة نقطية" onClick={() => formatDraft('list')}><List size={16}/></button>
            </div>
            <MentionField textareaRef={editRef} className="" value={draft} onChange={setDraft} maxLength={POST_MAX_LENGTH} rows={5} aria-label="تعديل المنشور"/>
            <span className="tiny subtle" dir="ltr">{draft.length} / {POST_MAX_LENGTH}</span>
            <div className="row wrap owner-edit-actions">
              <button className="primary-button" onClick={saveEdit} disabled={busy === 'edit' || !draft.trim()}>{busy === 'edit' ? 'جارِ الحفظ…' : 'حفظ'}</button>
              <button className="secondary-button" onClick={() => { setDraft(displayBody); setEditing(false); setOwnerError('') }}>إلغاء</button>
            </div>
          </div>
        : <div className="post-body-wrap">
            {/* A mention inside the body is a real link, so the body cannot be
                wrapped in one. The overlay keeps "tap anywhere to open the
                post" working without nesting anchors. */}
            <Link href={`/post/${post.id}`} className="post-open-overlay" aria-label="فتح المنشور والتعليقات" />
            <div className="post-body">{renderRichText(displayBody, { mentions: post.mentions })}</div>
          </div>}

      {post.track && <TrackAttachment track={post.track}/>}

      {ownerError && <p className="status-message error mt12">{ownerError}</p>}

      <div className="post-actions">
        <Link href={`/post/${post.id}`} className="action-button"><MessageCircle size={16} strokeWidth={1.7}/><span>{post.commentCount ? `${post.commentCount} تعليق` : 'تعليق'}</span></Link>
        <button className={`action-button like${eng.viewerHasLiked ? ' active' : ''}`} onClick={() => toggle('like', !eng.viewerHasLiked)} disabled={busy === 'like'} aria-pressed={eng.viewerHasLiked}><Heart size={16} strokeWidth={1.7} fill={eng.viewerHasLiked ? 'currentColor' : 'none'}/><span>{eng.likeCount || 'إعجاب'}</span></button>
        <button className={`action-button bookmark${eng.viewerHasBookmarked ? ' active' : ''}`} onClick={() => toggle('bookmark', !eng.viewerHasBookmarked)} disabled={busy === 'bookmark'} aria-pressed={eng.viewerHasBookmarked}><Bookmark size={16} strokeWidth={1.7} fill={eng.viewerHasBookmarked ? 'currentColor' : 'none'}/><span>{eng.viewerHasBookmarked ? 'محفوظ' : 'حفظ'}</span></button>
        {isOwner
          ? <>
              <button className="action-button" onClick={() => setEditing(true)} disabled={editing}><Pencil size={16} strokeWidth={1.7}/><span>تعديل</span></button>
              <button className="action-button danger-action" onClick={remove} disabled={busy === 'delete'}><Trash2 size={16} strokeWidth={1.7}/><span>{busy === 'delete' ? 'جارِ الحذف…' : 'حذف'}</span></button>
            </>
          : <Link href={`/report/post/${post.id}`} className="action-button"><Flag size={16} strokeWidth={1.7}/><span>إبلاغ</span></Link>}
      </div>
    </div>
  </article>
}
