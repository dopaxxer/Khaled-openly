'use client'
import { ArrowLeft, Send } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useRef, useState } from 'react'

export function Composer({ firstPost = false }) {
  const router = useRouter()
  const [body, setBody] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const textareaRef = useRef(null)

  // Starts small and grows with the text instead of opening as one large box —
  // the CSS max-height caps it so a long post scrolls internally rather than
  // pushing the publish button off screen.
  function grow(el) {
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
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
      <textarea
        ref={textareaRef}
        autoFocus
        value={body}
        onChange={e => { setBody(e.target.value); grow(e.target) }}
        maxLength={3000}
        rows={3}
        placeholder="ماذا تريد أن تقول؟"
        aria-label="نص المنشور"
      />
      <div className="composer-foot">
        <span className={`tiny ${body.length > 2800 ? 'danger-text' : 'subtle'}`} dir="ltr">{body.length} / 3000</span>
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
