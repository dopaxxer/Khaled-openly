'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { Timeline } from '../Timeline'

const relativeTime = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })

export function NotificationsScreen() {
  const [items, setItems] = useState(undefined)

  async function load() {
    const r = await fetch('/api/notifications', { cache: 'no-store' })
    if (r.status === 401) { setItems(null); return }
    const d = await r.json()
    setItems(d.items || [])
    if ((d.items || []).some(x => !x.readAt)) {
      await fetch('/api/notifications', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: (d.items || []).filter(x => !x.readAt).map(x => x.id) })
      })
    }
  }

  useEffect(() => { load() }, [])

  if (items === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (items === null) return <div className="empty-state"><Link href="/login" className="primary-button">تسجيل الدخول</Link></div>

  return <section className="v2-notifications">
    <header className="v2-notifications-head">
      <h1>Notifications</h1>
      <p>Only things that need your attention</p>
    </header>
    {items.length
      ? items.map(n => <Link
          href={n.commentId ? `/post/${n.postId}#comment-${n.commentId}` : `/post/${n.postId}`}
          className={`notification v2-notification${n.readAt ? '' : ' unread'}`}
          key={n.id}
        >
          <span className="v2-notification-dot" style={{ backgroundColor: n.actorColor }} aria-hidden="true" />
          <div className="notification-main">
            <p><strong>{n.actorCode}</strong>{' '}
              {n.kind === 'like' ? 'liked your post' : n.kind === 'mention' ? 'mentioned you' : 'replied to your post'}
            </p>
            <time>{relativeTime.format(-Math.max(1, Math.round((Date.now()-new Date(n.createdAt).getTime())/60000)), 'minute')}</time>
          </div>
        </Link>)
      : <div className="empty-state"><p>لا توجد إشعارات.</p></div>}
    <p className="v2-notifications-note">No badges for noise. Only meaningful activity appears here.</p>
  </section>
}

export function BookmarksScreen() {
  return <section className="v2-bookmarks">
    <header className="v2-bookmarks-head">
      <h1>Bookmarks</h1>
      <p>Private. Only you can see what you save.</p>
    </header>
    <Timeline endpoint="/api/bookmarks" empty="لا توجد منشورات محفوظة." />
  </section>
}
