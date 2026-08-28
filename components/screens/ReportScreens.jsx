'use client'
import { Flag, ShieldCheck } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'

export function ReportScreen({ targetType, id }) {
  const router = useRouter()
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError('')
    const f = new FormData(e.currentTarget)
    const r = await fetch('/api/reports', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ targetType, targetId: id, reason: f.get('reason'), description: f.get('description') || null })
    })
    if (r.status === 401) {
      router.push('/login')
      return
    }
    if (r.ok) router.back()
    else setError('تعذر إرسال البلاغ.')
    setBusy(false)
  }

  return <>
    <header className="page-header">
      <div className="page-title-row"><Flag size={20} /><h1 className="page-title">{targetType === 'comment' ? 'إبلاغ عن تعليق' : 'إبلاغ عن منشور'}</h1></div>
      <p className="page-description">البلاغات خاصة ويطّلع عليها فريق الإشراف فقط.</p>
    </header>
    <form className="screen-pad stack" onSubmit={submit}>
      <label className="label">
        السبب
        <select name="reason" className="form-control" defaultValue="spam">
          <option value="spam">محتوى مزعج أو مكرر</option>
          <option value="harassment">مضايقة</option>
          <option value="hate">خطاب كراهية</option>
          <option value="threat">تهديد</option>
          <option value="sexual">محتوى جنسي</option>
          <option value="illegal">محتوى غير قانوني</option>
          <option value="other">سبب آخر</option>
        </select>
      </label>
      <label className="label">تفاصيل إضافية<textarea name="description" maxLength={1000} className="form-control" style={{ minHeight: 128 }} placeholder="اختياري" /></label>
      {error && <p className="status-message error">{error}</p>}
      <div className="row"><button className="primary-button" disabled={busy}>{busy ? 'جارِ الإرسال…' : 'إرسال البلاغ'}</button><button className="secondary-button" type="button" onClick={() => router.back()}>إلغاء</button></div>
    </form>
  </>
}

export function AdminReportsScreen() {
  const [items, setItems] = useState(undefined)
  const [error, setError] = useState('')

  async function load() {
    const r = await fetch('/api/admin/reports', { cache: 'no-store' })
    if (!r.ok) {
      setError(r.status === 403 ? 'غير مصرح لك.' : 'تعذر تحميل البلاغات.')
      setItems([])
      return
    }
    setItems((await r.json()).items || [])
  }

  useEffect(() => { load() }, [])

  async function act(id, action) {
    const r = await fetch(`/api/admin/reports/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action })
    })
    if (r.ok) await load()
  }

  if (items === undefined) return <div className="screen-pad"><div className="skeleton" /></div>

  return <>
    <header className="page-header"><div className="page-title-row"><ShieldCheck size={20} /><h1 className="page-title">البلاغات</h1></div></header>
    {error && <div className="screen-pad"><p className="status-message error">{error}</p></div>}
    {items.map(x => <article className="admin-card" key={x.id}>
      <div className="small muted">{x.targetType} · {x.reason} · {x.status}</div>
      <div className="mono tiny mt8">{x.targetId}</div>
      {x.description && <p>{x.description}</p>}
      <div className="row wrap mt16">
        {[
          ['delete-content', 'حذف المحتوى'],
          ['suspend-author', 'تعليق الحساب'],
          ['ban-author', 'حظر الحساب'],
          ['resolve', 'حل'],
          ['dismiss', 'رفض البلاغ']
        ].map(([a, l]) => <button key={a} className="secondary-button" onClick={() => act(x.id, a)}>{l}</button>)}
      </div>
    </article>)}
    {!error && !items.length && <div className="empty-state"><p>لا توجد بلاغات.</p></div>}
  </>
}
