'use client'
import Link from 'next/link'
import { Search } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { PostCard } from '../PostCard'

export function SearchScreen() {
  const [q, setQ] = useState('')
  const [posts, setPosts] = useState([])
  const [users, setUsers] = useState([])
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState('')
  const [filter, setFilter] = useState('all')
  const requestRef = useRef(null)

  useEffect(() => () => requestRef.current?.abort(), [])

  function changeQuery(value) {
    requestRef.current?.abort()
    setQ(value)
    setPosts([])
    setUsers([])
    setDone(false)
    setBusy(false)
    setError('')
  }

  async function run(e) {
    e?.preventDefault()
    if (!q.trim()) return
    requestRef.current?.abort()
    const controller = new AbortController()
    requestRef.current = controller
    setBusy(true)
    setError('')
    try {
      const r = await fetch(`/api/search?q=${encodeURIComponent(q.trim())}`, { cache: 'no-store', signal: controller.signal })
      const d = await r.json()
      if (controller.signal.aborted) return
      if (!r.ok) throw new Error(d.error || 'تعذر إكمال البحث')
      setPosts(d.posts || [])
      setUsers(d.users || [])
      setDone(true)
    } catch (e) {
      if (controller.signal.aborted) return
      setError(e.message || 'تعذر إكمال البحث')
    } finally {
      if (!controller.signal.aborted) setBusy(false)
    }
  }

  return <section className="v2-search">
    <header className="v2-search-head">
      <h1>بحث</h1>
      <p>ابحث عن هوية أو منشور…</p>
    </header>

    <form className="v2-search-box" onSubmit={run}>
      <Search size={17} aria-hidden="true" />
      <input
        value={q}
        onChange={e => changeQuery(e.target.value)}
        enterKeyHint="search"
        maxLength={120}
        placeholder="ابحث عن هوية أو منشور…"
        aria-label="بحث"
      />
      <div className="v2-search-actions">
        {q && <button type="button" className="v2-search-clear" aria-label="مسح البحث" onClick={() => changeQuery('')}>×</button>}
        <button type="submit" className="v2-search-submit" disabled={busy || !q.trim()}>بحث</button>
      </div>
    </form>

    <div className="v2-search-tabs" role="group" aria-label="تصفية نتائج البحث">
      {[['all', 'الكل'], ['users', 'أشخاص'], ['posts', 'منشورات']].map(([value, label]) =>
        <button key={value} type="button" className={filter === value ? 'active' : ''} aria-pressed={filter === value} onClick={() => setFilter(value)}>{label}</button>
      )}
    </div>

    {error && <p className="status-message error v2-search-status">{error}</p>}
    {busy && <div className="screen-pad"><div className="skeleton" /></div>}

    {!busy && filter !== 'posts' && users.length > 0 && <section>
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

    {!busy && filter !== 'users' && posts.length > 0 && <section>
      <div className="v2-search-section-title">منشورات</div>
      {posts.map(p => <PostCard key={p.id} post={p} />)}
    </section>}

    {!busy && !done && <section className="v2-search-recents">
      <div className="v2-search-section-title">جرّب البحث</div>
      <button type="button" onClick={() => changeQuery('K7M2')}>K7M2</button>
      <button type="button" onClick={() => changeQuery('music')}>music</button>
      <button type="button" onClick={() => changeQuery('film')}>film</button>
    </section>}

    {!busy && done && !(filter !== 'posts' && users.length) && !(filter !== 'users' && posts.length) && <div className="empty-state"><p>لا توجد نتائج.</p></div>}
  </section>
}
