'use client'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { Timeline } from '../Timeline'
import { formatRelativeTime } from '@/lib/relativeTime'

function notificationAction(kind) {
  if (kind === 'like') return 'أعجب بمنشورك'
  if (kind === 'mention') return 'أشار إليك'
  return 'رد على منشورك'
}

export function NotificationsScreen() {
  const [items, setItems] = useState(undefined)
  const [error, setError] = useState('')
  const [language, setLanguage] = useState('ar')

  async function load(signal) {
    setItems(undefined)
    setError('')
    try {
      const response = await fetch('/api/notifications', { cache: 'no-store', signal })
      if (response.status === 401) {
        setItems(null)
        return
      }
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الإشعارات')
      if (signal?.aborted) return

      const nextItems = Array.isArray(data.items) ? data.items : []
      setItems(nextItems)
      const unreadIds = nextItems.filter(item => !item.readAt).map(item => item.id)
      if (unreadIds.length) {
        const marked = await fetch('/api/notifications', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ids: unreadIds }),
          signal
        }).catch(() => null)
        if (marked?.ok && !signal?.aborted) {
          window.dispatchEvent(new Event('openly:notifications-changed'))
        }
      }
    } catch (loadError) {
      if (loadError?.name === 'AbortError' || signal?.aborted) return
      setItems([])
      setError(loadError.message || 'تعذر تحميل الإشعارات')
    }
  }

  useEffect(() => {
    try {
      setLanguage(localStorage.getItem('openly.language') === 'en' ? 'en' : 'ar')
    } catch {}
    const controller = new AbortController()
    load(controller.signal)
    return () => controller.abort()
  }, [])

  if (items === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (items === null) return <div className="empty-state"><Link href="/login" className="primary-button">تسجيل الدخول</Link></div>

  return <section className="v2-notifications">
    <header className="v2-notifications-head">
      <h1>الإشعارات</h1>
      <p>ما يحتاج إلى انتباهك فقط.</p>
    </header>
    {error
      ? <div className="empty-state"><div>
          <p>{error}</p>
          <button type="button" className="secondary-button mt16" onClick={() => load()}>المحاولة مجددًا</button>
        </div></div>
      : items.length
      ? items.map(n => <Link
          href={n.commentId ? `/post/${n.postId}#comment-${n.commentId}` : `/post/${n.postId}`}
          className={`notification v2-notification${n.readAt ? '' : ' unread'}`}
          key={n.id}
        >
          <span className="v2-notification-dot" style={{ backgroundColor: n.actorColor }} aria-hidden="true" />
          <div className="notification-main">
            <p><strong>{n.actorCode}</strong>{' '}
              {notificationAction(n.kind)}
            </p>
            <time dateTime={n.createdAt}>{formatRelativeTime(n.createdAt, language)}</time>
          </div>
        </Link>)
      : <div className="empty-state"><p>لا توجد إشعارات.</p></div>}
    <p className="v2-notifications-note">لا شارات للضوضاء؛ يظهر هنا النشاط المهم فقط.</p>
  </section>
}

export function BookmarksScreen() {
  return <section className="v2-bookmarks">
    <header className="v2-bookmarks-head">
      <h1>المحفوظات</h1>
      <p>خاصة بك؛ أنت وحدك ترى ما تحفظه.</p>
    </header>
    <Timeline endpoint="/api/bookmarks" empty="لا توجد منشورات محفوظة." />
  </section>
}
