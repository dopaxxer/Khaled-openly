'use client'
import { ArrowLeft, Send } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState } from 'react'

export function Composer({ firstPost = false }) {
  const router = useRouter()
  const [body, setBody] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

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
        autoFocus
        value={body}
        onChange={e => setBody(e.target.value)}
        maxLength={3000}
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
        التخطي الآن <ArrowLeft size={15} aria-hidden="true"/>
      </button>}
    </div>
  </section>
}
