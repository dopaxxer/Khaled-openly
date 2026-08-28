'use client'
import { RotateCcw } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { PostCard } from './PostCard'
import { fetchViewer } from '@/lib/viewer'

function FeedSkeleton() {
  return <div className="feed-skeleton" aria-label="جارِ تحميل المنشورات">
    {[0, 1, 2].map(item => <article className="post-skeleton" key={item}>
      <div className="skeleton-line skeleton-meta" />
      <div className="skeleton-line skeleton-body" />
      <div className="skeleton-line skeleton-body short" />
      <div className="skeleton-line skeleton-actions" />
    </article>)}
  </div>
}

export function Timeline({
  endpoint = '/api/posts',
  empty = 'لا توجد منشورات بعد. كن أول من يكتب.',
  // Bumped by the caller after publishing, so a new post appears without a
  // navigation. Any changing value works; the timeline only watches it.
  refreshToken = 0
}) {
  const [posts, setPosts] = useState([])
  const [engagement, setEngagement] = useState({})
  // Cards hold off on their own engagement lookup while the batch below is in
  // flight, so a page of thirty posts costs one request instead of thirty-one.
  const [engagementPending, setEngagementPending] = useState(true)
  const [cursor, setCursor] = useState(null)
  const [loading, setLoading] = useState(true)
  const [moreLoading, setMoreLoading] = useState(false)
  const [error, setError] = useState('')
  const [viewerCode, setViewerCode] = useState(null)
  const loadGeneration = useRef(0)
  const sentinelRef = useRef(null)

  const load = useCallback(async function load(next = null, signal = undefined) {
    const generation = ++loadGeneration.current
    next ? setMoreLoading(true) : setLoading(true)
    setError('')
    try {
      const sep = endpoint.includes('?') ? '&' : '?'
      const url = next ? `${endpoint}${sep}cursor=${encodeURIComponent(next)}` : endpoint
      const res = await fetch(url, { cache: 'no-store', signal })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'تعذر تحميل المنشورات')
      if (generation !== loadGeneration.current) return
      const incoming = data.items || []
      setPosts(old => {
        if (!next) return incoming
        const known = new Set(old.map(post => post.id))
        return [...old, ...incoming.filter(post => !known.has(post.id))]
      })
      setCursor(data.nextCursor || null)
      if (incoming.length) {
        setEngagementPending(true)
        const er = await fetch(`/api/engagement?ids=${encodeURIComponent(incoming.map(p => p.id).join(','))}`, { cache: 'no-store', signal })
        if (generation !== loadGeneration.current) return
        if (er.ok) {
          const ed = await er.json()
          setEngagement(old => ({ ...old, ...Object.fromEntries((ed.items || []).map(x => [x.postId, x])) }))
        }
        setEngagementPending(false)
      } else {
        setEngagementPending(false)
      }
    } catch (e) {
      if (e?.name === 'AbortError') return
      if (generation !== loadGeneration.current) return
      setEngagementPending(false)
      setError(e.message || 'تعذر تحميل المنشورات')
    } finally {
      if (generation === loadGeneration.current) {
        setLoading(false)
        setMoreLoading(false)
      }
    }
  }, [endpoint])

  useEffect(() => {
    const controller = new AbortController()
    load(null, controller.signal)
    return () => controller.abort()
  }, [load, refreshToken])

  useEffect(() => {
    let cancelled = false
    fetchViewer()
      .then(user => { if (!cancelled) setViewerCode(user?.publicCode || null) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    if (!cursor || loading || moreLoading) return
    const node = sentinelRef.current
    if (!node) return
    const observer = new IntersectionObserver(entries => {
      if (entries[0]?.isIntersecting) load(cursor)
    }, { rootMargin: '640px 0px' })
    observer.observe(node)
    return () => observer.disconnect()
  }, [load, cursor, loading, moreLoading])

  if (loading) return <FeedSkeleton />
  if (error && !posts.length) return <div className="empty-state"><div><p>{error}</p><button className="secondary-button mt16" onClick={() => load()}><RotateCcw size={16} aria-hidden="true"/>المحاولة مجددًا</button></div></div>
  if (!posts.length) return <div className="empty-state"><div><p>{empty}</p></div></div>

  return <div aria-live="polite">
    {/* `load` is stable, so a card only re-renders when its own props move. */}
    {posts.map(post => <PostCard
      key={post.id}
      post={post}
      initialEngagement={engagement[post.id] || null}
      engagementPending={engagementPending}
      viewerCode={viewerCode}
      onChanged={load}
    />)}
    <div className="feed-footer">
      {cursor
        ? <>
            <div ref={sentinelRef} className="feed-sentinel" aria-hidden="true" />
            <button className="secondary-button" disabled={moreLoading} onClick={() => load(cursor)}>{moreLoading ? 'جارِ التحميل…' : 'عرض المزيد'}</button>
          </>
        : <span className="tiny subtle">هذه كل المنشورات المتاحة.</span>}
      {error && <p className="tiny danger-text">{error}</p>}
    </div>
  </div>
}
