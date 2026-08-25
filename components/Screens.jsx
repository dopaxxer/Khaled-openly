'use client'

import Link from 'next/link'
import {
  Bell,
  Bookmark,
  CircleCheck,
  Compass,
  Flag,
  KeyRound,
  LogIn,
  Music,
  Save,
  Search,
  Settings,
  ShieldCheck,
  Shuffle,
  Sparkles,
  UserRound
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { CommentThread } from './CommentThread'
import { Composer } from './Composer'
import { Identity } from './Identity'
import { MentionField } from './MentionField'
import { MusicDiscovery } from './MusicDiscovery'
import { MusicPreferences } from './MusicPreferences'
import { PostCard } from './PostCard'
import { ThemeControl } from './Settings'
import { Timeline } from './Timeline'
import {
  COMMENT_MAX_LENGTH,
  isStrongPassword,
  PASSWORD_MAX_LENGTH,
  PASSWORD_MIN_LENGTH
} from '@/lib/validation'

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

export function HomeScreen() {
  return <>
    <header className="page-header">
      <h1 className="page-title">المساحة العامة</h1>
      <p className="page-description">الأحدث أولًا. بلا خوارزمية ترتيب.</p>
    </header>
    <Timeline />
  </>
}

export function ScreenRouter({ slug }) {
  const key = slug.join('/')
  if (key === 'login') return <AuthScreen mode="login" />
  if (key === 'register') return <AuthScreen mode="register" />
  if (key === 'forgot-password') return <ForgotPasswordScreen />
  if (key === 'auth/update-password') return <UpdatePasswordScreen />
  if (key === 'write') return <Composer />
  if (key === 'first-post') return <Composer firstPost />
  if (key === 'search') return <SearchScreen />
  if (key === 'me') return <MeScreen />
  if (key === 'settings') return <SettingsScreen />
  if (key === 'notifications') return <NotificationsScreen />
  if (key === 'bookmarks') return <BookmarksScreen />
  if (key === 'privacy') return <PrivacyScreen />
  if (key === 'music') return <MusicPreferences />
  if (key === 'discover/music') return <MusicDiscovery />
  if (key === 'admin/reports') return <AdminReportsScreen />
  if (slug[0] === 'u' && slug[1]) return <UserScreen code={slug[1]} />
  if (slug[0] === 'post' && slug[1]) return <PostScreen id={slug[1]} />
  if (slug[0] === 'report' && slug[1] === 'post' && slug[2]) return <ReportScreen targetType="post" id={slug[2]} />
  if (slug[0] === 'report' && slug[1] === 'comment' && slug[2]) return <ReportScreen targetType="comment" id={slug[2]} />
  return <NotFound />
}

function AuthScreen({ mode }) {
  const router = useRouter()
  const login = mode === 'login'
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [confirm, setConfirm] = useState(false)
  const [email, setEmail] = useState('')

  async function submit(e) {
    e.preventDefault()
    setError('')
    setBusy(true)
    const fd = new FormData(e.currentTarget)
    const enteredEmail = String(fd.get('email') || '')
    try {
      const res = await fetch(`/api/auth/${login ? 'login' : 'register'}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: enteredEmail, password: fd.get('password') })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'تعذر إكمال العملية')
      if (data.requiresEmailConfirmation) {
        setEmail(enteredEmail)
        setConfirm(true)
        return
      }
      router.push(login ? '/' : '/first-post')
      router.refresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (confirm) return <SignupCodeScreen email={email} />

  return <div className="auth-wrap">
    <div className="auth-head">
      <div className="auth-icon">{login ? <LogIn size={21} /> : <Sparkles size={21} />}</div>
      <h1 className="auth-title">{login ? 'مرحبًا بعودتك' : 'أنشئ هويتك'}</h1>
      <p className="auth-sub">{login ? 'ادخل إلى هويتك وكلماتك.' : 'سنمنحك كودًا ولونًا ثابتين؛ لا اسم عرض ولا صورة شخصية.'}</p>
    </div>
    <form className="panel auth-form" onSubmit={submit}>
      <label className="label">
        البريد الإلكتروني
        <input className="form-control" type="email" name="email" autoComplete="email" required dir="ltr" placeholder="name@example.com" />
      </label>
      <label className="label">
        كلمة المرور
        <input className="form-control" type="password" name="password" autoComplete={login ? 'current-password' : 'new-password'} minLength={login ? undefined : PASSWORD_MIN_LENGTH} maxLength={PASSWORD_MAX_LENGTH} required dir="ltr" placeholder="••••••••••••" />
        {!login && <span className="tiny subtle">{PASSWORD_MIN_LENGTH} حرفًا على الأقل، مع حرف ورقم.</span>}
      </label>
      {error && <p className="status-message error">{error}</p>}
      <button className="primary-button full" disabled={busy}>{busy ? 'جارِ التنفيذ…' : login ? 'تسجيل الدخول' : 'إنشاء الحساب'}</button>
      {login && <Link href="/forgot-password" className="center small muted" style={{ textDecoration: 'underline' }}>نسيت كلمة المرور؟</Link>}
    </form>
    <p className="center muted small mt20">
      {login ? 'ليس لديك حساب؟ ' : 'لديك حساب؟ '}
      <Link href={login ? '/register' : '/login'} style={{ textDecoration: 'underline' }}>{login ? 'أنشئ هويتك' : 'تسجيل الدخول'}</Link>
    </p>
  </div>
}

function SignupCodeScreen({ email }) {
  const router = useRouter()
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [resent, setResent] = useState(false)
  const [resendBusy, setResendBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      const res = await fetch('/api/auth/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, token: code })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'الكود غير صحيح')
      router.push('/first-post')
      router.refresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  async function resend() {
    if (resendBusy) return
    setResendBusy(true)
    setResent(false)
    setError('')
    try {
      const res = await fetch('/api/auth/resend-code', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })
      if (!res.ok) throw new Error((await res.json()).error || 'تعذر إعادة الإرسال')
      setResent(true)
    } catch (e) {
      setError(e.message)
    } finally {
      setResendBusy(false)
    }
  }

  return <div className="auth-wrap">
    <div className="auth-head">
      <div className="auth-icon"><CircleCheck size={21} /></div>
      <h1 className="auth-title">تحقق من بريدك</h1>
      <p className="auth-sub">أرسلنا كودًا مكوّنًا من 6 أرقام إلى {email}. أدخله هنا لإكمال إنشاء حسابك.</p>
    </div>
    <form className="panel auth-form" onSubmit={submit}>
      <label className="label">
        كود التحقق
        <input
          className="form-control"
          value={code}
          onChange={e => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          inputMode="numeric"
          autoComplete="one-time-code"
          dir="ltr"
          maxLength={6}
          placeholder="000000"
          style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: '.3em', textAlign: 'center', fontSize: 20 }}
          required
        />
      </label>
      {error && <p className="status-message error">{error}</p>}
      {resent && <p className="status-message" style={{ color: 'var(--success)' }}>أُرسل كود جديد إلى بريدك.</p>}
      <button className="primary-button full" disabled={busy || code.length !== 6}>{busy ? 'جارِ التحقق…' : 'تأكيد'}</button>
      <button type="button" className="center small muted" style={{ textDecoration: 'underline', background: 'none', border: 0 }} onClick={resend} disabled={resendBusy}>
        {resendBusy ? 'جارِ الإرسال…' : 'لم يصلك الكود؟ إعادة الإرسال'}
      </button>
    </form>
  </div>
}

function ForgotPasswordScreen() {
  const [email, setEmail] = useState('')
  const [error, setError] = useState('')
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      const res = await fetch('/api/auth/request-password-reset', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'تعذر إرسال الرابط')
      setSent(true)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (sent) {
    return <div className="auth-wrap center">
      <div className="panel" style={{ padding: 28 }}>
        <CircleCheck size={38} />
        <h1 className="auth-title mt16">تحقق من بريدك</h1>
        <p className="auth-sub">إذا كان هناك حساب بهذا البريد، أرسلنا رابطًا لاختيار كلمة مرور جديدة.</p>
        <Link href="/login" className="secondary-button full mt20">العودة لتسجيل الدخول</Link>
      </div>
    </div>
  }

  return <div className="auth-wrap">
    <div className="auth-head">
      <div className="auth-icon"><KeyRound size={21} /></div>
      <h1 className="auth-title">استعادة كلمة المرور</h1>
      <p className="auth-sub">أدخل البريد المرتبط بحسابك وسنرسل لك رابط الاستعادة.</p>
    </div>
    <form className="panel auth-form" onSubmit={submit}>
      <label className="label">
        البريد الإلكتروني
        <input className="form-control" type="email" autoComplete="email" required dir="ltr" value={email} onChange={e => setEmail(e.target.value)} placeholder="name@example.com" />
      </label>
      {error && <p className="status-message error">{error}</p>}
      <button className="primary-button full" disabled={busy}>{busy ? 'جارِ الإرسال…' : 'إرسال رابط الاستعادة'}</button>
      <Link href="/login" className="center small muted">العودة لتسجيل الدخول</Link>
    </form>
  </div>
}

function UpdatePasswordScreen() {
  const router = useRouter()
  const [recovery, setRecovery] = useState(undefined)
  const [currentPassword, setCurrentPassword] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    fetch('/api/auth/password-mode', { cache: 'no-store' })
      .then(response => response.ok ? response.json() : { recovery: false })
      .then(data => setRecovery(!!data.recovery))
      .catch(() => setRecovery(false))
  }, [])

  async function submit(e) {
    e.preventDefault()
    setError('')
    if (password !== confirmPassword) {
      setError('كلمتا المرور غير متطابقتين')
      return
    }
    setBusy(true)
    try {
      const res = await fetch('/api/auth/update-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password, currentPassword })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'تعذر تحديث كلمة المرور')
      router.push('/me')
      router.refresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return <div className="auth-wrap">
    <div className="auth-head">
      <div className="auth-icon"><KeyRound size={21} /></div>
      <h1 className="auth-title">كلمة مرور جديدة</h1>
      <p className="auth-sub">اختر كلمة مرور جديدة لا تقل عن {PASSWORD_MIN_LENGTH} حرفًا وتضم حرفًا ورقمًا.</p>
    </div>
    <form className="panel auth-form" onSubmit={submit}>
      {recovery === false && <label className="label">
        كلمة المرور الحالية
        <input className="form-control" type="password" autoComplete="current-password" required maxLength={PASSWORD_MAX_LENGTH} dir="ltr" value={currentPassword} onChange={e => setCurrentPassword(e.target.value)} />
      </label>}
      <label className="label">
        كلمة المرور الجديدة
        <input className="form-control" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN_LENGTH} maxLength={PASSWORD_MAX_LENGTH} dir="ltr" value={password} onChange={e => setPassword(e.target.value)} />
      </label>
      <label className="label">
        تأكيد كلمة المرور
        <input className="form-control" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN_LENGTH} maxLength={PASSWORD_MAX_LENGTH} dir="ltr" value={confirmPassword} onChange={e => setConfirmPassword(e.target.value)} />
      </label>
      {error && <p className="status-message error">{error}</p>}
      <button className="primary-button full" disabled={busy || recovery === undefined || !isStrongPassword(password) || (recovery === false && !currentPassword)}>{busy ? 'جارِ الحفظ…' : 'حفظ كلمة المرور'}</button>
    </form>
  </div>
}

function SearchScreen() {
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

  return <>
    <header className="page-header">
      <div className="page-title-row"><Search size={20} /><h1 className="page-title">بحث</h1></div>
      <p className="page-description">ابحث عن كلمات عامة أو كود هوية.</p>
    </header>
    <form className="search-box row" onSubmit={run}>
      <input className="form-control" value={q} onChange={e => setQ(e.target.value)} maxLength={120} placeholder="ابحث…" />
      <button className="primary-button" disabled={busy || !q.trim()}>{busy ? '…' : 'بحث'}</button>
    </form>
    {error && <p className="status-message error mt16">{error}</p>}
    {users.length > 0 && <>
      <div className="section-title">الهويات</div>
      {users.map(u => <div className="list-row" key={u.publicCode}>
        <Identity code={u.publicCode} color={u.identityColor} />
        <Link className="small muted" href={`/u/${u.publicCode}`}>عرض</Link>
      </div>)}
    </>}
    {posts.length > 0 && <>
      <div className="section-title">المنشورات</div>
      {posts.map(p => <PostCard key={p.id} post={p} />)}
    </>}
    {done && !users.length && !posts.length && <div className="empty-state"><p>لا توجد نتائج.</p></div>}
  </>
}

function MeScreen() {
  const router = useRouter()
  const [user, setUser] = useState(undefined)
  const [count, setCount] = useState(null)
  const [following, setFollowing] = useState([])

  useEffect(() => {
    (async () => {
      const m = await fetch('/api/auth/me', { cache: 'no-store' })
      const md = m.ok ? await m.json() : { user: null }
      setUser(md.user || null)
      if (md.user) {
        const [a, b] = await Promise.all([
          fetch('/api/me/followers-count', { cache: 'no-store' }),
          fetch('/api/me/following', { cache: 'no-store' })
        ])
        if (a.ok) setCount((await a.json()).count)
        if (b.ok) setFollowing((await b.json()).items || [])
      }
    })()
  }, [])

  async function logout() {
    await fetch('/api/auth/logout', { method: 'POST' })
    router.push('/')
    router.refresh()
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (user === null) return <div className="empty-state"><div><p>سجّل الدخول لرؤية حسابك.</p><Link href="/login" className="primary-button mt16">تسجيل الدخول</Link></div></div>

  return <>
    <header className="page-header">
      <h1 className="page-title">حسابي</h1>
      <p className="page-description">هويتك الخاصة وإعدادات علاقاتك العامة.</p>
    </header>
    <section className="profile-hero">
      <Identity code={user.publicCode} color={user.identityColor} large />
      {user.status && <p className="profile-status">{user.status}</p>}
      {user.bio && <p className="profile-bio">{user.bio}</p>}
      <div className="stat-grid">
        <div className="panel stat"><span className="small muted">الأشخاص المهتمون بما تكتب</span><strong>{count ?? '—'}</strong></div>
        <div className="panel stat"><span className="small muted">خاص بك فقط</span><p className="small mt12">لا نعرض عدد متابَعاتك للآخرين.</p></div>
      </div>
      <div className="row wrap mt20">
        <Link href={`/u/${user.publicCode}`} className="secondary-button">صفحة كتاباتي</Link>
        <Link href="/settings" className="secondary-button"><Settings size={15} />الإعدادات</Link>
        <Link href="/bookmarks" className="secondary-button"><Bookmark size={15} />المحفوظات</Link>
        <Link href="/music" className="secondary-button"><Music size={15} />ذوقي الموسيقي</Link>
        <Link href="/discover/music" className="secondary-button"><Compass size={15} />اكتشاف بالموسيقى</Link>
        <Link href="/privacy" className="secondary-button">الخصوصية</Link>
        <button onClick={logout} className="danger-button">تسجيل الخروج</button>
      </div>
    </section>
    <div className="section-title">الأكواد التي أتابعها</div>
    {following.length
      ? following.map(x => <div key={x.publicCode} className="list-row"><Identity code={x.publicCode} color={x.identityColor} /><Link href={`/u/${x.publicCode}`} className="small muted">عرض</Link></div>)
      : <div className="empty-state"><p>لم تتابع أي كود بعد.</p></div>}
  </>
}

function SettingsScreen() {
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
      const r = await fetch('/api/auth/me', { cache: 'no-store' })
      const d = r.ok ? await r.json() : { user: null }
      const next = d.user || null
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
      router.refresh()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (user === null) return <div className="empty-state"><div><p>سجّل الدخول لتعديل هويتك.</p><Link href="/login" className="primary-button mt16">تسجيل الدخول</Link></div></div>

  return <>
    <header className="page-header">
      <div className="page-title-row"><Settings size={20} /><h1 className="page-title">الإعدادات</h1></div>
      <p className="page-description">عدّل هويتك العامة من دون إضافة اسم حقيقي أو صورة شخصية.</p>
    </header>
    <div className="screen-pad stack">
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
  </>
}

function UserScreen({ code }) {
  const [user, setUser] = useState(undefined)
  const [posts, setPosts] = useState([])
  const [music, setMusic] = useState(null)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    (async () => {
      const [u, p, m] = await Promise.all([
        fetch(`/api/users/${encodeURIComponent(code)}`, { cache: 'no-store' }),
        fetch(`/api/posts?author=${encodeURIComponent(code)}`, { cache: 'no-store' }),
        fetch(`/api/v1/users/${encodeURIComponent(code)}/music`, { cache: 'no-store' })
      ])
      setUser(u.ok ? (await u.json()).user : null)
      if (p.ok) setPosts((await p.json()).items || [])
      // Absent unless this user chose to publish their list.
      setMusic(m.ok ? (await m.json()).profile : null)
    })()
  }, [code])

  async function relation(kind, enabled) {
    if (busy) return
    setBusy(kind)
    setError('')
    try {
      const r = await fetch(`/api/users/${code}/relation`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ kind, enabled })
      })
      if (r.status === 401) {
        location.href = '/login'
        return
      }
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || 'تعذر تحديث العلاقة')
      setUser(u => ({ ...u, [kind === 'follow' ? 'viewerIsFollowing' : kind === 'mute' ? 'viewerHasMuted' : 'viewerHasBlocked']: enabled }))
    } catch (e) {
      setError(e.message || 'تعذر تحديث العلاقة')
    } finally {
      setBusy('')
    }
  }

  if (user === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (!user) return <NotFound />

  return <>
    <section className="profile-hero">
      <Identity code={user.publicCode} color={user.identityColor} large />
      {user.status && <p className="profile-status">{user.status}</p>}
      {user.bio && <p className="profile-bio">{user.bio}</p>}
      <p className="profile-meta">انضم في {new Intl.DateTimeFormat('ar', { dateStyle: 'medium' }).format(new Date(user.createdAt))}</p>
      {!user.isSelf && <div className="row wrap mt20">
        <button className="primary-button" disabled={busy === 'follow'} onClick={() => relation('follow', !user.viewerIsFollowing)}>{user.viewerIsFollowing ? 'إلغاء المتابعة' : 'متابعة'}</button>
        <button className="secondary-button" disabled={busy === 'mute'} onClick={() => relation('mute', !user.viewerHasMuted)}>{user.viewerHasMuted ? 'إلغاء الكتم' : 'كتم'}</button>
        <button className="danger-button" disabled={busy === 'block'} onClick={() => relation('block', !user.viewerHasBlocked)}>{user.viewerHasBlocked ? 'إلغاء الحظر' : 'حظر'}</button>
      </div>}
      {error && <p className="status-message error mt16">{error}</p>}
    </section>
    {music && (music.artists.length > 0 || music.genres.length > 0) && <>
      <div className="section-title">الذوق الموسيقي</div>
      <div className="screen-pad">
        <div className="panel music-panel">
          {music.genres.length > 0 && <div className="chip-grid">
            {music.genres.map(genre => <span className="chip static" key={genre.id}>{genre.nameAr}</span>)}
          </div>}
          {music.artists.length > 0 && <p className="small mt12">
            <span className="muted">الفنانون: </span>{music.artists.map(artist => artist.name).join('، ')}
          </p>}
        </div>
      </div>
    </>}
    <div className="section-title">الكتابات</div>
    {posts.length
      ? posts.map(p => <PostCard key={p.id} post={p} viewerCode={user.isSelf ? user.publicCode : null} />)
      : <div className="empty-state"><p>لا توجد منشورات.</p></div>}
  </>
}

function PostScreen({ id }) {
  const [post, setPost] = useState(undefined)
  const [comments, setComments] = useState([])
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState(false)
  const [viewerCode, setViewerCode] = useState(null)
  const [commentError, setCommentError] = useState('')

  async function load() {
    const r = await fetch(`/api/posts/${id}`, { cache: 'no-store' })
    if (!r.ok) {
      setPost(null)
      return
    }
    const d = await r.json()
    setPost(d.post)
    setComments(d.comments || [])
  }

  useEffect(() => { load() }, [id])

  useEffect(() => {
    fetch('/api/auth/me', { cache: 'no-store' })
      .then(r => r.ok ? r.json() : { user: null })
      .then(d => setViewerCode(d.user?.publicCode || null))
      .catch(() => {})
  }, [])

  async function comment(e) {
    e.preventDefault()
    if (!body.trim()) return
    setBusy(true)
    setCommentError('')
    try {
      const r = await fetch(`/api/posts/${id}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body })
      })
      if (r.status === 401) {
        location.href = '/login'
        return
      }
      const data = await r.json()
      if (!r.ok) throw new Error(data.error || 'تعذر إضافة التعليق')
      setBody('')
      await load()
    } catch (e) {
      setCommentError(e.message || 'تعذر إضافة التعليق')
    } finally {
      setBusy(false)
    }
  }

  if (post === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (!post) return <NotFound />

  return <>
    <PostCard post={post} viewerCode={viewerCode} onChanged={load} />
    <form className="comment-form" onSubmit={comment}>
      <MentionField maxLength={COMMENT_MAX_LENGTH} value={body} onChange={setBody} placeholder="اكتب تعليقًا… استخدم @ للإشارة" aria-label="نص التعليق" />
      <div className="row between"><span className="tiny subtle" dir="ltr">{body.length} / {COMMENT_MAX_LENGTH}</span><button className="primary-button" disabled={busy || !body.trim()}>{busy ? 'جارِ الإرسال…' : 'تعليق'}</button></div>
      {commentError && <p className="status-message error">{commentError}</p>}
    </form>
    <div className="section-title">التعليقات</div>
    <CommentThread comments={comments} postId={id} viewerCode={viewerCode} onChanged={load} />
  </>
}

function NotificationsScreen() {
  const [items, setItems] = useState(undefined)

  async function load() {
    const r = await fetch('/api/notifications', { cache: 'no-store' })
    if (r.status === 401) {
      setItems(null)
      return
    }
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

  return <>
    <header className="page-header">
      <div className="page-title-row"><Bell size={20} /><h1 className="page-title">الإشعارات</h1></div>
      <p className="page-description">التفاعلات والردود المرتبطة بك.</p>
    </header>
    {items.length
      ? items.map(n => <Link
          // A mention inside a comment deep-links to that comment so the
          // notification lands on the exact thing that mentioned you.
          href={n.commentId ? `/post/${n.postId}#comment-${n.commentId}` : `/post/${n.postId}`}
          className={`notification${n.readAt ? '' : ' unread'}`}
          key={n.id}
        >
          <span className="notification-icon">{n.kind === 'like' ? '♥' : n.kind === 'mention' ? '@' : '↩'}</span>
          <div className="notification-main">
            <p>
              <Identity code={n.actorCode} color={n.actorColor} linked={false} />
              {' '}
              {n.kind === 'like' ? 'أعجب بمنشورك' : n.kind === 'mention' ? (n.commentId ? 'أشار إليك في تعليق' : 'أشار إليك في منشور') : 'رد على منشورك'}
            </p>
            <time>{new Intl.DateTimeFormat('ar', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(n.createdAt))}</time>
          </div>
        </Link>)
      : <div className="empty-state"><p>لا توجد إشعارات.</p></div>}
  </>
}

function BookmarksScreen() {
  return <>
    <header className="page-header">
      <div className="page-title-row"><Bookmark size={20} /><h1 className="page-title">المحفوظات</h1></div>
      <p className="page-description">منشورات محفوظة لك فقط.</p>
    </header>
    <Timeline endpoint="/api/bookmarks" empty="لا توجد منشورات محفوظة." />
  </>
}

function PrivacyScreen() {
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

function ReportScreen({ targetType, id }) {
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

function AdminReportsScreen() {
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

function NotFound() {
  return <div className="empty-state"><div><UserRound size={28} /><h1>الصفحة غير موجودة</h1><p>ربما تغيّر الرابط أو حُذف المحتوى.</p><Link href="/" className="primary-button mt16">العودة للرئيسية</Link></div></div>
}
