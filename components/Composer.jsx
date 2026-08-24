'use client'
import { ArrowLeft, Bold, Italic, List, Send } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'
import { Avatar } from './Avatar'
import { toggleListPrefix, toggleWrap } from '@/lib/textFormatting'
import { POST_MAX_LENGTH } from '@/lib/validation'

const MAX_LENGTH = POST_MAX_LENGTH

export function Composer({ firstPost = false }) {
  const router = useRouter()
  const [body, setBody] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [viewer, setViewer] = useState(null)
  const textareaRef = useRef(null)

  useEffect(() => {
    fetch('/api/auth/me', { cache: 'no-store' })
      .then(r => r.ok ? r.json() : { user: null })
      .then(d => setViewer(d.user || null))
      .catch(() => {})
  }, [])

  // Starts small and grows with the text instead of opening as one large box —
  // the CSS max-height caps it so a long post scrolls internally rather than
  // pushing the publish button off screen.
  function grow(el) {
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }

  function format(kind) {
    const el = textareaRef.current
    if (!el) return
    const result = kind === 'list'
      ? toggleListPrefix(body, el.selectionStart, el.selectionEnd)
      : toggleWrap(body, el.selectionStart, el.selectionEnd, kind === 'bold' ? '**' : '*')
    setBody(result.value)
    // The value only updates on the next render; the selection restore has
    // to wait for that, and growing again keeps the box matching the new text.
    requestAnimationFrame(() => {
      el.focus()
      el.setSelectionRange(result.start, result.end)
      grow(el)
    })
  }

  async function publish() {
    if (!body.trim() || busy) return
    setBusy(true)
    setError('')
    try {
      const res = await fetch('/api/posts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body })
      })
      const data = await res.json()
      if (res.status === 401) {
        router.push('/login')
        return
      }
      if (!res.ok) throw new Error(data.error || 'تعذر النشر')
      router.push('/')
      router.refresh()
    } catch (e) {
      setError(e.message || 'تعذر النشر')
    } finally {
      setBusy(false)
    }
  }

  return <section>
    <header className="page-header">
      <h1 className="page-title">{firstPost ? 'منشورك الأول' : 'منشور جديد'}</h1>
      <p className="page-description">سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.</p>
    </header>
    <div className="composer panel">
      <div className="composer-toolbar" role="toolbar" aria-label="تنسيق النص">
        <button type="button" className="toolbar-button" aria-label="عريض" title="عريض" onClick={() => format('bold')}><Bold size={16}/></button>
        <button type="button" className="toolbar-button" aria-label="مائل" title="مائل" onClick={() => format('italic')}><Italic size={16}/></button>
        <button type="button" className="toolbar-button" aria-label="قائمة نقطية" title="قائمة نقطية" onClick={() => format('list')}><List size={16}/></button>
      </div>
      <div className="composer-row">
        {viewer && <Avatar code={viewer.publicCode} color={viewer.identityColor} size={40}/>}
        <textarea
          ref={textareaRef}
          autoFocus
          value={body}
          onChange={e => { setBody(e.target.value); grow(e.target) }}
          maxLength={MAX_LENGTH}
          rows={3}
          placeholder="ماذا تريد أن تقول؟"
          aria-label="نص المنشور"
        />
      </div>
      <div className="composer-foot">
        <span className={`tiny ${body.length > MAX_LENGTH - 40 ? 'danger-text' : 'subtle'}`} dir="ltr">{body.length} / {MAX_LENGTH}</span>
        <button className="primary-button" onClick={publish} disabled={busy || !body.trim()}>
          <Send size={16} aria-hidden="true"/>
          {busy ? 'جارِ النشر…' : 'نشر'}
        </button>
      </div>
      {error && <p className="status-message error composer-message">{error}</p>}
      {firstPost && <button className="action-button muted composer-skip" onClick={() => router.push('/')}>
        التخطي الآن <ArrowLeft size={16} aria-hidden="true"/>
      </button>}
    </div>
  </section>
}
