'use client'
import Link from 'next/link'
import { Compass, KeyRound, Music, Save, Settings, Shuffle } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Identity } from '../Identity'
import { ThemeControl } from '../Settings'
import { Timeline } from '../Timeline'
import { fetchViewer } from '@/lib/viewer'

const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
const IDENTITY_PALETTE = [
  '#D9484F', '#E85D75', '#F47B5D', '#E8A33F', '#C9A227',
  '#8AA64B', '#4F9D69', '#3E9B8E', '#3D8BB5', '#4A6FA5',
  '#6B5B95', '#8D6E63', '#A07E5C', '#9B6A6A', '#B8336A',
  '#2F4858', '#1B998B', '#5C7AEA', '#7B6EAA', '#D6A2E8'
]

function normalizeCode(value) {
  return String(value || '')
    .toUpperCase()
    .split('')
    .filter(char => CODE_ALPHABET.includes(char))
    .join('')
    .slice(0, 8)
}

function randomCode(length = 4) {
  const values = new Uint32Array(length)
  crypto.getRandomValues(values)
  return Array.from(values, value => CODE_ALPHABET[value % CODE_ALPHABET.length]).join('')
}

export function MeScreen() {
  const router = useRouter()
  const [user, setUser] = useState(undefined)
  const [count, setCount] = useState(null)
  const [following, setFollowing] = useState([])

  useEffect(() => {
    (async () => {
      try {
        const viewer = await fetchViewer()
        setUser(viewer)
        if (viewer) {
          const [a, b] = await Promise.all([
            fetch('/api/me/followers-count', { cache: 'no-store' }),
            fetch('/api/me/following', { cache: 'no-store' })
          ])
          if (a.ok) setCount((await a.json()).count)
          if (b.ok) setFollowing((await b.json()).items || [])
        }
      } catch {
        setUser(null)
      }
    })()
  }, [])

  async function logout() {
    const response = await fetch('/api/auth/logout', { method: 'POST' })
    if (response.ok) window.dispatchEvent(new Event('openly:auth-changed'))
    router.push('/')
    router.refresh()
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (user === null) return <div className="empty-state"><div><p>سجّل الدخول لرؤية حسابك.</p><Link href="/login" className="primary-button mt16">تسجيل الدخول</Link></div></div>

  return <section className="v2-self-profile">
    <section className="profile-hero v2-profile-hero">
      <div className="v2-profile-top">
        <div>
          <Identity code={user.publicCode} color={user.identityColor} large />
          <p className="v2-profile-code-label">رمز عام</p>
        </div>
        <Link href="/settings" className="v2-profile-settings">الإعدادات</Link>
      </div>

      {user.status && <p className="profile-status">{user.status}</p>}
      {user.bio && <p className="profile-bio" data-user-content="">{user.bio}</p>}

      <p className="v2-profile-stats">
        <strong>{count ?? '—'}</strong> followers
        <span aria-hidden="true"> · </span>
        <strong>{following.length}</strong> following
      </p>
    </section>

    <section className="v2-profile-taste">
      <span className="v2-profile-kicker">Taste</span>
      <div className="v2-profile-taste-links">
        <Link href="/music">ذوقي الموسيقي</Link>
        <span aria-hidden="true">·</span>
        <Link href="/interests">اهتماماتي</Link>
        <span aria-hidden="true">·</span>
        <Link href="/bookmarks">المحفوظات</Link>
      </div>
      <p>Music, books and films are part of the profile — not separate badges.</p>
    </section>

    <div className="v2-profile-posts-title">Posts</div>
    <Timeline endpoint={`/api/posts?author=${encodeURIComponent(user.publicCode)}`} empty="لا توجد منشورات." />

    <details className="v2-profile-controls">
      <summary>الإعدادات</summary>
      <div className="row wrap">
        <Link href="/messages" className="secondary-button">الرسائل الخاصة</Link>
        <Link href="/discover" className="secondary-button"><Compass size={15} />اكتشف</Link>
        <Link href="/privacy" className="secondary-button">الخصوصية</Link>
        <button onClick={logout} className="danger-button">تسجيل الخروج</button>
      </div>
    </details>
  </section>
}

export function SettingsScreen() {
  const router = useRouter()
  const [user, setUser] = useState(undefined)
  const [publicCode, setPublicCode] = useState('')
  const [identityColor, setIdentityColor] = useState('#5C7AEA')
  const [status, setStatus] = useState('')
  const [bio, setBio] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    (async () => {
      // The settings form writes back to this profile, so it always reads a
      // fresh answer rather than one a screen a moment ago put in the cache.
      const next = await fetchViewer({ force: true }).catch(() => null)
      setUser(next)
      if (next) {
        setPublicCode(next.publicCode || '')
        setIdentityColor(next.identityColor || '#5C7AEA')
        setStatus(next.status || '')
        setBio(next.bio || '')
      }
    })()
  }, [])

  async function submit(e) {
    e.preventDefault()
    setError('')
    setSaved(false)
    setBusy(true)
    try {
      const r = await fetch('/api/profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ publicCode, identityColor, status, bio })
      })
      const d = await r.json()
      if (r.status === 401) {
        router.push('/login')
        return
      }
      if (!r.ok) throw new Error(d.error || 'تعذر الحفظ')
      setUser(d.user)
      setPublicCode(d.user.publicCode)
      setIdentityColor(d.user.identityColor)
      setStatus(d.user.status || '')
      setBio(d.user.bio || '')
      setSaved(true)
      // The identity that just changed is the one the shell shows and the one
      // every other screen caches, so tell them rather than letting them find
      // out on the next poll.
      window.dispatchEvent(new Event('openly:auth-changed'))
      router.refresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (user === null) return <div className="empty-state"><div><p>سجّل الدخول لتعديل هويتك.</p><Link href="/login" className="primary-button mt16">تسجيل الدخول</Link></div></div>

  return <section className="v2-settings-screen">
    <header className="page-header v2-settings-head">
      <div className="page-title-row"><Settings size={20} /><h1 className="page-title">الإعدادات</h1></div>
      <p className="page-description">عدّل هويتك العامة من دون إضافة اسم حقيقي أو صورة شخصية.</p>
    </header>
    <div className="screen-pad stack v2-settings-body">
      <form className="panel auth-form" onSubmit={submit}>
        <div className="row wrap" style={{ alignItems: 'center', gap: 16 }}>
          <Identity code={publicCode || user.publicCode} color={identityColor} large />
          <span className="small muted">هذه هي الهوية التي يراها الآخرون.</span>
        </div>

        <label className="label">
          كود الهوية
          <div className="row" style={{ gap: 8 }}>
            <input
              className="form-control"
              value={publicCode}
              onChange={e => setPublicCode(normalizeCode(e.target.value))}
              maxLength={8}
              minLength={4}
              required
              dir="ltr"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: '.12em' }}
            />
            <button type="button" className="secondary-button" aria-label="إنشاء كود عشوائي" onClick={() => setPublicCode(randomCode())}>
              <Shuffle size={16} />
            </button>
          </div>
          <span className="tiny subtle">4–8 رموز واضحة؛ لا نستخدم I أو L أو O أو 0 أو 1 لتجنب الالتباس.</span>
        </label>

        <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
          <legend className="label" style={{ marginBottom: 10 }}>لون الهوية</legend>
          <div className="row wrap" style={{ gap: 10 }}>
            {IDENTITY_PALETTE.map(swatch => {
              const selected = swatch.toUpperCase() === String(identityColor).toUpperCase()
              return <button
                key={swatch}
                type="button"
                aria-label={`اختيار اللون ${swatch}`}
                aria-pressed={selected}
                onClick={() => setIdentityColor(swatch)}
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: '50%',
                  background: swatch,
                  border: selected ? '3px solid var(--foreground)' : '2px solid var(--surface)',
                  boxShadow: selected ? '0 0 0 2px var(--line-strong)' : '0 0 0 1px var(--line)',
                  transform: selected ? 'scale(1.08)' : 'none'
                }}
              />
            })}
          </div>
        </fieldset>

        <label className="label">
          الحالة
          <input className="form-control" value={status} onChange={e => setStatus(e.target.value)} maxLength={60} placeholder="جملة قصيرة — اختياري" />
          <span className="tiny subtle" dir="ltr">{status.length} / 60</span>
        </label>

        <label className="label">
          النبذة
          <textarea className="form-control" value={bio} onChange={e => setBio(e.target.value)} maxLength={240} placeholder="اكتب شيئًا مختصرًا عن هذه الهوية — اختياري" style={{ minHeight: 112, resize: 'vertical' }} />
          <span className="tiny subtle" dir="ltr">{bio.length} / 240</span>
        </label>

        {error && <p className="status-message error">{error}</p>}
        {saved && <p className="status-message" style={{ color: 'var(--success)' }}>تم حفظ التغييرات.</p>}
        <button className="primary-button full" disabled={busy || publicCode.length < 4}>
          <Save size={16} />{busy ? 'جارِ الحفظ…' : 'حفظ الهوية'}
        </button>
      </form>

      <div className="panel" style={{ padding: 20 }}>
        <h2 className="page-title" style={{ fontSize: 16 }}>الأمان</h2>
        <p className="small muted mt8">يتطلب التغيير كلمة المرور الحالية، أو رابط استعادة موثّقًا عبر البريد.</p>
        <Link href="/auth/update-password" className="secondary-button mt16"><KeyRound size={16} />تغيير كلمة المرور</Link>
      </div>

      <div className="panel" style={{ padding: 20 }}>
        <ThemeControl />
      </div>
    </div>
  </section>
}


export function PrivacyScreen() {
  const [items, setItems] = useState(undefined)

  async function load() {
    const r = await fetch('/api/privacy', { cache: 'no-store' })
    setItems(r.ok ? (await r.json()).items : null)
  }

  useEffect(() => { load() }, [])

  async function undo(kind, code) {
    await fetch(`/api/users/${code}/relation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ kind, enabled: false })
    })
    await load()
  }

  if (items === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (items === null) return <div className="empty-state"><Link href="/login" className="primary-button">تسجيل الدخول</Link></div>

  return <>
    <header className="page-header">
      <h1 className="page-title">الخصوصية</h1>
      <p className="page-description">إدارة الحسابات المكتومة والمحظورة.</p>
    </header>
    {items.length
      ? items.map((x, i) => <div className="list-row" key={`${x.kind}-${x.publicCode}-${i}`}><div><Identity code={x.publicCode} color={x.identityColor} /><div className="tiny muted mt8">{x.kind === 'mute' ? 'مكتوم' : 'محظور'}</div></div><button className="secondary-button" onClick={() => undo(x.kind === 'mute' ? 'mute' : 'block', x.publicCode)}>إلغاء</button></div>)
      : <div className="empty-state"><p>لا توجد علاقات خصوصية حاليًا.</p></div>}
  </>
}
