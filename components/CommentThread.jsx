'use client'
import Link from 'next/link'
import { CornerDownLeft, Flag, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'
import { Identity } from './Identity'
import { renderRichText } from '@/lib/richText'

// Replies nest, but only so far. Past a few levels the indent eats the column
// on a phone and the thread stops being readable, so deeper replies keep
// rendering — they just stop stepping further in.
const MAX_DEPTH = 4

function buildTree(comments) {
  const nodes = new Map()
  for (const c of comments) nodes.set(c.id, { ...c, children: [] })
  const roots = []
  for (const c of comments) {
    const node = nodes.get(c.id)
    const parent = c.parentCommentId ? nodes.get(c.parentCommentId) : null
    // A reply whose parent is missing (deleted, or filtered out by a block)
    // is promoted to the top rather than dropped — losing it would silently
    // hide a live reply from the thread.
    if (parent) parent.children.push(node)
    else roots.push(node)
  }
  return roots
}

function Comment({ node, depth, postId, viewerCode, onChanged }) {
  const router = useRouter()
  const [replying, setReplying] = useState(false)
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const isOwner = !!viewerCode && node.authorCode === viewerCode

  async function submitReply(e) {
    e.preventDefault()
    const text = body.trim()
    if (!text || busy) return
    setBusy('reply')
    setError('')
    try {
      const res = await fetch(`/api/posts/${postId}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body: text, parentCommentId: node.id })
      })
      if (res.status === 401) { router.push('/login'); return }
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر إضافة الرد')
      setBody('')
      setReplying(false)
      await onChanged()
    } catch (err) { setError(err.message) } finally { setBusy('') }
  }

  async function remove() {
    if (busy || !confirm('حذف هذا التعليق؟ لا يمكن التراجع.')) return
    setBusy('delete')
    setError('')
    try {
      const res = await fetch(`/api/comments/${node.id}`, { method: 'DELETE' })
      if (res.status === 401) { router.push('/login'); return }
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر الحذف')
      await onChanged()
    } catch (err) { setError(err.message); setBusy('') }
  }

  const time = new Intl.DateTimeFormat('ar', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(node.createdAt))

  return <div className={depth > 0 ? 'comment-branch' : undefined}>
    <article className="comment">
      <div className="row between">
        <Identity code={node.authorCode} color={node.authorColor}/>
        <time className="tiny subtle" dateTime={node.createdAt}>{time}</time>
      </div>
      <div className="comment-body">{renderRichText(node.body)}</div>

      <div className="comment-actions">
        <button className="action-button" onClick={() => setReplying(v => !v)}>
          <CornerDownLeft size={16} strokeWidth={1.7}/><span>رد</span>
        </button>
        {isOwner
          ? <button className="action-button danger-action" onClick={remove} disabled={busy === 'delete'}>
              <Trash2 size={16} strokeWidth={1.7}/><span>{busy === 'delete' ? 'جارِ الحذف…' : 'حذف'}</span>
            </button>
          : <Link href={`/report/comment/${node.id}`} className="action-button">
              <Flag size={16} strokeWidth={1.7}/><span>إبلاغ</span>
            </Link>}
      </div>

      {error && <p className="status-message error mt12">{error}</p>}

      {replying && <form className="reply-form" onSubmit={submitReply}>
        <textarea className="form-control" value={body} onChange={e => setBody(e.target.value)} maxLength={2000} rows={3} autoFocus placeholder="اكتب ردك…" aria-label="نص الرد"/>
        <div className="row between mt12">
          <span className="tiny subtle" dir="ltr">{body.length} / 2000</span>
          <div className="row">
            <button className="primary-button" disabled={busy === 'reply' || !body.trim()}>{busy === 'reply' ? 'جارِ الإرسال…' : 'إرسال'}</button>
            <button className="secondary-button" type="button" onClick={() => { setReplying(false); setBody('') }}>إلغاء</button>
          </div>
        </div>
      </form>}
    </article>

    {node.children.map(child => (
      <Comment
        key={child.id}
        node={child}
        depth={Math.min(depth + 1, MAX_DEPTH)}
        postId={postId}
        viewerCode={viewerCode}
        onChanged={onChanged}
      />
    ))}
  </div>
}

export function CommentThread({ comments, postId, viewerCode, onChanged }) {
  const roots = useMemo(() => buildTree(comments), [comments])
  if (!roots.length) return <div className="empty-state"><div><p>لا توجد تعليقات بعد.</p></div></div>
  return <div>
    {roots.map(node => (
      <Comment key={node.id} node={node} depth={0} postId={postId} viewerCode={viewerCode} onChanged={onChanged}/>
    ))}
  </div>
}
