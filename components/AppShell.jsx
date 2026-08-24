'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Bell, CircleUserRound, House, LogIn, Search, SquarePen } from 'lucide-react'
import { useEffect, useState } from 'react'

const nav = [
  { href: '/', label: 'الرئيسية', icon: House },
  { href: '/search', label: 'بحث', icon: Search },
  { href: '/write', label: 'اكتب', icon: SquarePen },
  { href: '/me', label: 'حسابي', icon: CircleUserRound }
]

function Brand() {
  return <Link href="/" className="brand" aria-label="open — الرئيسية" dir="ltr">
    <span className="brand-mark" aria-hidden="true">O</span>
    <span>open</span>
  </Link>
}

export function AppShell({ children }) {
  const pathname = usePathname()
  const [user, setUser] = useState(undefined)
  const [unread, setUnread] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    fetch('/api/auth/me', { cache: 'no-store', signal: controller.signal })
      .then(r => r.ok ? r.json() : { user: null })
      .then(async data => {
        setUser(data.user || null)
        if (data.user) {
          const n = await fetch('/api/notifications', { cache: 'no-store', signal: controller.signal }).catch(() => null)
          if (n?.ok) setUnread((await n.json()).unreadCount || 0)
        } else setUnread(0)
      })
      .catch(() => setUser(null))
    return () => controller.abort()
  }, [pathname])

  const active = href => href === '/' ? pathname === '/' : pathname.startsWith(href)

  return <div className="app-shell">
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
        {user && <Link href="/notifications" className={`nav-link${active('/notifications') ? ' active' : ''}`} aria-current={active('/notifications') ? 'page' : undefined}>
          <Bell size={20} strokeWidth={1.75} aria-hidden="true"/>
          <span>الإشعارات</span>
          {unread > 0 && <span className="nav-badge">{unread > 99 ? '99+' : unread}</span>}
        </Link>}
      </nav>
      <div className="sidebar-foot">
        {user
          ? <Link href={`/u/${user.publicCode}`} className="identity-chip" dir="ltr"><span className="identity-dot" style={{ backgroundColor: user.identityColor }}/><span>{user.publicCode}</span></Link>
          : user === null
            ? <Link href="/login" className="nav-link"><LogIn size={20} aria-hidden="true"/><span>تسجيل الدخول</span></Link>
            : <span className="sidebar-user-skeleton" aria-label="جارِ تحميل الحساب"/>}
        <p>كلمات عامة، بلا خوارزمية.</p>
      </div>
    </aside>

    <div className="mobile-header">
      <Brand />
      <div className="mobile-header-actions">
        {user && <Link href="/notifications" className="icon-button" aria-label="الإشعارات">
          <Bell size={20} aria-hidden="true"/>
          {unread > 0 && <span className="icon-badge">{unread > 9 ? '9+' : unread}</span>}
        </Link>}
        {user
          ? <Link href={`/u/${user.publicCode}`} className="identity-chip compact" dir="ltr"><span className="identity-dot" style={{ backgroundColor: user.identityColor }}/><span>{user.publicCode}</span></Link>
          : <Link href="/login" className="icon-button" aria-label="تسجيل الدخول"><LogIn size={20} aria-hidden="true"/></Link>}
      </div>
    </div>

    <main className="content-column"><div key={pathname} className="route-stage">{children}</div></main>

    <nav className="mobile-nav" aria-label="التنقل الرئيسي">
      {nav.map(({ href, label, icon: Icon }) => {
        const isActive = active(href)
        return <Link key={href} href={href} className={`mobile-link${isActive ? ' active' : ''}`} aria-current={isActive ? 'page' : undefined}>
          <Icon size={20} strokeWidth={isActive ? 2.1 : 1.75} aria-hidden="true"/>
          <span>{label}</span>
        </Link>
      })}
    </nav>
  </div>
}
