'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ArrowUpLeft, Bell, Bookmark, CircleUserRound, Compass, House, LogIn, MessageCircle, Music2, PenLine, Search, Settings2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { fetchViewer } from '@/lib/viewer'

const nav = [
  { href: '/', label: 'الرئيسية', icon: House },
  { href: '/search', label: 'بحث', icon: Search },
  { href: '/discover', label: 'اكتشف', icon: Compass },
  { href: '/bookmarks', label: 'المحفوظات', icon: Bookmark },
  { href: '/me', label: 'حسابي', icon: CircleUserRound }
]

const mobileNav = [
  { href: '/', label: 'الرئيسية', icon: House },
  { href: '/search', label: 'بحث', icon: Search },
  { href: '/write', label: 'اكتب', icon: PenLine },
  { href: '/discover', label: 'اكتشف', icon: Compass },
  { href: '/me', label: 'أنت', icon: CircleUserRound }
]

function Brand() {
  return <Link href="/" className="brand" aria-label="openly — الرئيسية" dir="ltr">
    <img className="brand-mark" src="/openly-logo.jpg" width="32" height="32" alt="" />
    <span>openly</span>
  </Link>
}

export function AppShell({ children }) {
  const pathname = usePathname()
  const [user, setUser] = useState(undefined)
  const [unread, setUnread] = useState(0)
  const [unreadMessages, setUnreadMessages] = useState(0)

  useEffect(() => {
    let controller = new AbortController()

    async function sync({ revalidateSession }) {
      controller.abort()
      controller = new AbortController()
      const signal = controller.signal
      try {
        // The shell is the first thing on the page to ask who is looking, so
        // it takes the fresh answer and leaves it where the composer, the
        // timeline and the screens can reuse it instead of each asking again.
        const viewer = await fetchViewer({ force: revalidateSession })
        if (signal.aborted) return
        setUser(viewer)
        if (!viewer) {
          setUnread(0)
          setUnreadMessages(0)
          return
        }
        const [notifications, messages] = await Promise.all([
          fetch('/api/notifications/count', { cache: 'no-store', signal }).catch(() => null),
          fetch('/api/v1/messages/unread', { cache: 'no-store', signal }).catch(() => null)
        ])
        if (notifications?.ok) setUnread((await notifications.json()).unreadCount || 0)
        if (messages?.ok) setUnreadMessages((await messages.json()).unreadCount || 0)
      } catch (error) {
        if (error?.name !== 'AbortError') setUser(null)
      }
    }

    // A sign-in or sign-out changes who the session belongs to; a read receipt
    // only changes a badge, and re-verifying the session for it was a round
    // trip nobody asked for.
    const syncAuthState = () => sync({ revalidateSession: true })
    const syncBadges = () => sync({ revalidateSession: false })

    // Three requests a minute, forever, in every open tab. A backgrounded tab
    // has nobody to show a badge to, so it waits and catches up the moment it
    // is looked at again.
    function poll() {
      if (document.visibilityState === 'visible') syncAuthState()
    }

    function onVisible() {
      if (document.visibilityState === 'visible') syncAuthState()
    }

    // Nothing is staler than a session the page has just been served with, and
    // the child screens have already asked by the time the shell's effect runs
    // -- so the first pass joins their request instead of opening a second.
    syncBadges()
    const timer = window.setInterval(poll, 60_000)
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('openly:auth-changed', syncAuthState)
    window.addEventListener('openly:messages-changed', syncBadges)
    window.addEventListener('openly:notifications-changed', syncBadges)
    return () => {
      controller.abort()
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('openly:auth-changed', syncAuthState)
      window.removeEventListener('openly:messages-changed', syncBadges)
      window.removeEventListener('openly:notifications-changed', syncBadges)
    }
  }, [])

  useEffect(() => {
    // The header collapses on scroll, so this listener runs on every frame of
    // every flick. It reads the scroll position inside a rAF and writes the
    // class only when the state actually flips -- a scroll handler that
    // touches the DOM on each event is what makes a feed feel sticky.
    const root = document.documentElement
    let last = window.scrollY
    let compact = false
    let queued = false

    function measure() {
      queued = false
      const y = window.scrollY
      const next = y > last + 8 && y > 52 ? true
        : y < last - 8 || y < 20 ? false
          : compact
      last = y
      if (next === compact) return
      compact = next
      root.classList.toggle('openly-compact', compact)
    }

    function onScroll() {
      if (queued) return
      queued = true
      requestAnimationFrame(measure)
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      window.removeEventListener('scroll', onScroll)
      root.classList.remove('openly-compact')
    }
  }, [pathname])

  const active = href => href === '/' ? pathname === '/' : pathname.startsWith(href)
  const mobileIndex = mobileNav.findIndex(({ href }) => active(href))

  return <div className={`app-shell${pathname === '/' ? ' is-home' : ''}`}>
    <a href="#main-content" className="skip-content">انتقل إلى المحتوى</a>
    <aside className="desktop-sidebar">
      <Brand />
      <nav className="side-nav" aria-label="التنقل الرئيسي">
        {nav.map(({ href, label, icon: Icon }) => {
          const isActive = active(href)
          return <Link key={href} href={href} className={`nav-link${isActive ? ' active' : ''}`} aria-current={isActive ? 'page' : undefined}>
            <Icon size={20} strokeWidth={1.75} aria-hidden="true"/>
            <span>{label}</span>
          </Link>
        })}
        {user && <Link href="/messages" className={`nav-link${active('/messages') ? ' active' : ''}`} aria-current={active('/messages') ? 'page' : undefined}>
          <MessageCircle size={20} strokeWidth={1.75} aria-hidden="true"/>
          <span>الرسائل</span>
          {unreadMessages > 0 && <span className="nav-badge">{unreadMessages > 99 ? '99+' : unreadMessages}</span>}
        </Link>}
        {user && <Link href="/notifications" className={`nav-link${active('/notifications') ? ' active' : ''}`} aria-current={active('/notifications') ? 'page' : undefined}>
          <Bell size={20} strokeWidth={1.75} aria-hidden="true"/>
          <span>الإشعارات</span>
          {unread > 0 && <span className="nav-badge">{unread > 99 ? '99+' : unread}</span>}
        </Link>}
      </nav>
      <Link href="/write" className="sidebar-write"><PenLine size={19} aria-hidden="true"/><span>اكتب شيئًا</span></Link>
      <div className="sidebar-foot">
        <Link href="/settings" className="nav-link"><Settings2 size={19} aria-hidden="true"/><span>الإعدادات</span></Link>
        {user
          ? <Link href={`/u/${user.publicCode}`} className="identity-chip" dir="ltr"><span className="identity-dot" style={{ backgroundColor: user.identityColor }}/><span>{user.publicCode}</span></Link>
          : user === null
            ? <Link href="/login" className="nav-link"><LogIn size={20} aria-hidden="true"/><span>تسجيل الدخول</span></Link>
            : <span className="sidebar-user-skeleton" aria-label="جارِ تحميل الحساب"/>}
        <p>كلمات عامة، بلا خوارزمية.</p>
      </div>
    </aside>

    <div className="mobile-header">
      <div className="mobile-brand-stack">
        <Brand />
        {pathname === '/' && <span className="mobile-brand-context">مساحة عامة · الأحدث أولًا</span>}
      </div>
      <div className="mobile-header-actions">
        <Link href="/search" className="icon-button" aria-label="بحث"><Search size={21} aria-hidden="true"/></Link>
        {user && <Link href="/messages" className="icon-button" aria-label="الرسائل">
          <MessageCircle size={20} aria-hidden="true"/>
          {unreadMessages > 0 && <span className="icon-badge">{unreadMessages > 9 ? '9+' : unreadMessages}</span>}
        </Link>}
        {user && <Link href="/notifications" className="icon-button" aria-label="الإشعارات">
          <Bell size={20} aria-hidden="true"/>
          {unread > 0 && <span className="icon-badge">{unread > 9 ? '9+' : unread}</span>}
        </Link>}
        {user
          ? <Link href={`/u/${user.publicCode}`} className="identity-chip compact" dir="ltr"><span className="identity-dot" style={{ backgroundColor: user.identityColor }}/><span>{user.publicCode}</span></Link>
          : <Link href="/login" className="icon-button" aria-label="تسجيل الدخول"><LogIn size={20} aria-hidden="true"/></Link>}
      </div>
    </div>

    <main id="main-content" tabIndex={-1} className="content-column"><div key={pathname} className="route-stage">{children}</div></main>

    {pathname === '/' && <aside className="home-aside" aria-label="اكتشف المزيد">
      <div className="discovery-card">
        <span className="discovery-icon"><Compass size={25} aria-hidden="true"/></span>
        <h2>بينكم شيء مشترك.</h2>
        <p>أغنية، كتاب، أو فكرة. اكتشف أشخاصًا يشاركونك ما تحب.</p>
        <Link href="/discover" className="discovery-link"><span>ابدأ الاكتشاف</span><ArrowUpLeft size={18} aria-hidden="true"/></Link>
      </div>
      <div className="aside-shortcuts">
        <h2>أقرب إلى ذوقك</h2>
        <Link href="/discover/music"><Music2 size={20} aria-hidden="true"/><span>اكتشاف بالموسيقى</span><ArrowUpLeft size={16} aria-hidden="true"/></Link>
        <Link href="/interests"><Compass size={20} aria-hidden="true"/><span>اهتماماتي</span><ArrowUpLeft size={16} aria-hidden="true"/></Link>
        <Link href="/bookmarks"><Bookmark size={20} aria-hidden="true"/><span>المحفوظات</span><ArrowUpLeft size={16} aria-hidden="true"/></Link>
      </div>
      <p className="aside-note">هويتك لون وكود. والمساحة لكلماتك.</p>
      <Link href="/privacy" className="aside-privacy">الخصوصية</Link>
    </aside>}

    <nav
      className="mobile-nav"
      aria-label="التنقل الرئيسي"
      style={mobileIndex >= 0 ? { '--nav-i': mobileIndex } : undefined}
    >
      {mobileNav.map(({ href, label, icon: Icon }) => {
        const isActive = active(href)
        return <Link key={href} href={href} className={`mobile-link${isActive ? ' active' : ''}`} aria-current={isActive ? 'page' : undefined}>
          <Icon size={20} strokeWidth={isActive ? 2.1 : 1.75} aria-hidden="true"/>
          <span>{label}</span>
        </Link>
      })}
    </nav>
  </div>
}
