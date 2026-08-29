'use client'
import Link from 'next/link'
import { Search } from 'lucide-react'
import { useState } from 'react'
import { PostCard } from '../PostCard'

export function SearchScreen() {
  const [q, setQ] = useState('')
  const [posts, setPosts] = useState([])
  const [users, setUsers] = useState([])
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState('')

  async function run(e) {
    e?.preventDefault()
    if (!q.trim()) return
    setBusy(true)
    setError('')
    try {
      const r = await fetch(`/api/search?q=${encodeURIComponent(q.trim())}`, { cache: 'no-store' })
      const d = await r.json()
      if (!r.ok) throw new Error(d.error || 'تعذر إكمال البحث')
      setPosts(d.posts || [])
      setUsers(d.users || [])
      setDone(true)
    } catch (e) {
      setError(e.message || 'تعذر إكمال البحث')
    } finally {
      setBusy(false)
    }
  }

  return <section className="v2-search">
    <header className="v2-search-head">
      <h1>بحث</h1>
      <p>أشخاص، منشورات، وسياق ثقافي</p>
    </header>

    <form className="v2-search-box" onSubmit={run}>
      <Search size={17} aria-hidden="true" />
      <input
        value={q}
        onChange={e => setQ(e.target.value)}
        maxLength={120}
        placeholder="ابحث عن هوية أو منشور…"
        aria-label="بحث"
      />
      {q && <button type="button" className="v2-search-clear" onClick={() => { setQ(''); setPosts([]); setUsers([]); setDone(false) }}>×</button>}
    </form>

    <div className="v2-search-tabs" aria-hidden="true">
      <span className="active">أشخاص</span>
      <span>منشورات</span>
      <span>موسيقى</span>
      <span>كتب</span>
      <span>أفلام</span>
    </div>

    {error && <p className="status-message error v2-search-status">{error}</p>}
    {busy && <div className="screen-pad"><div className="skeleton" /></div>}

    {!busy && users.length > 0 && <section>
      <div className="v2-search-section-title">أشخاص</div>
      {users.map(u => <Link className="v2-search-person" key={u.publicCode} href={`/u/${u.publicCode}`}>
        <span className="v2-search-person-dot" style={{ backgroundColor: u.identityColor }} aria-hidden="true" />
        <span className="v2-search-person-copy">
          <strong>{u.publicCode}</strong>
          <span>افتح الملف</span>
        </span>
        <span className="v2-search-arrow">›</span>
      </Link>)}
    </section>}

    {!busy && posts.length > 0 && <section>
      <div className="v2-search-section-title">منشورات</div>
      {posts.map(p => <PostCard key={p.id} post={p} />)}
    </section>}

    {!busy && !done && <section className="v2-search-recents">
      <div className="v2-search-section-title">جرّب البحث</div>
      <button type="button" onClick={() => setQ('K7M2')}>K7M2</button>
      <button type="button" onClick={() => setQ('music')}>music</button>
      <button type="button" onClick={() => setQ('film')}>film</button>
    </section>}

    {!busy && done && !users.length && !posts.length && <div className="empty-state"><p>لا توجد نتائج.</p></div>}
  </section>
}
