'use client'
import Link from 'next/link'
import { CircleCheck, KeyRound, LogIn } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { isStrongPassword, PASSWORD_MAX_LENGTH, PASSWORD_MIN_LENGTH } from '@/lib/validation'

const COUNTRY_DIAL_CODES = [
  ['ألمانيا', '+49'],
  ['السعودية', '+966'],
  ['اليمن', '+967'],
  ['الإمارات', '+971'],
  ['مصر', '+20'],
  ['العراق', '+964'],
  ['الأردن', '+962'],
  ['الكويت', '+965'],
  ['قطر', '+974'],
  ['البحرين', '+973'],
  ['عُمان', '+968'],
  ['تركيا', '+90'],
  ['المملكة المتحدة', '+44'],
  ['فرنسا', '+33'],
  ['إيطاليا', '+39'],
  ['إسبانيا', '+34'],
  ['هولندا', '+31'],
  ['السويد', '+46'],
  ['الولايات المتحدة / كندا', '+1'],
  ['أخرى — أدخل + ورمز الدولة', '']
]

async function authRequest(url, body) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 15000)
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || `تعذر إكمال العملية (${response.status})`)
    return data
  } catch (error) {
    if (error?.name === 'AbortError') throw new Error('استغرق الاتصال وقتًا طويلًا. تحقق من الشبكة وحاول مجددًا.')
    throw error
  } finally {
    clearTimeout(timeout)
  }
}

export function AuthScreen() {
  const router = useRouter()
  const [method, setMethod] = useState('email')
  const [step, setStep] = useState('entry')
  const [email, setEmail] = useState('')
  const [countryCode, setCountryCode] = useState('+49')
  const [phone, setPhone] = useState('')
  const [verificationValue, setVerificationValue] = useState('')
  const [maskedTarget, setMaskedTarget] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState(false)
  const [resendBusy, setResendBusy] = useState(false)
  const [countdown, setCountdown] = useState(0)
  const [capabilities, setCapabilities] = useState({
    email: true,
    emailOtp: false,
    emailMode: 'link',
    phone: false,
    google: false,
    apple: false
  })

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.get('error')) setError('تعذر إكمال تسجيل الدخول الخارجي. حاول مرة أخرى.')

    fetch('/api/auth/capabilities', { cache: 'no-store' })
      .then(response => response.ok ? response.json() : null)
      .then(value => {
        if (!value) return
        setCapabilities(value)
        if (!value.phone) setMethod('email')
      })
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (countdown <= 0) return undefined
    const timer = setInterval(() => setCountdown(value => Math.max(0, value - 1)), 1000)
    return () => clearInterval(timer)
  }, [countdown])

  function normalizedPhone() {
    if (!countryCode) {
      const compact = phone.replace(/[\s().-]/g, '')
      return compact.startsWith('+')
        ? `+${compact.slice(1).replace(/\D/g, '')}`
        : compact.replace(/\D/g, '')
    }
    return `${countryCode}${phone.replace(/\D/g, '')}`
  }

  async function requestCode(event, resend = false) {
    event?.preventDefault()
    if (busy || resendBusy || (resend && countdown > 0)) return

    resend ? setResendBusy(true) : setBusy(true)
    setError('')
    setNotice('')
    const value = method === 'email' ? email.trim() : normalizedPhone()

    try {
      const data = await authRequest('/api/auth/otp/request', method === 'email'
        ? { method, email: value }
        : { method, phone: value })
      setVerificationValue(value)
      setMaskedTarget(data.target || value)
      const delivery = method === 'email'
        ? (data.delivery || capabilities.emailMode || 'link')
        : 'otp'
      setStep(delivery === 'link' ? 'email-link' : 'otp')
      setCountdown(Number(data.cooldownSeconds || 60))
      if (resend) setNotice(delivery === 'link' ? 'أرسلنا رابطًا جديدًا.' : 'أُرسل كود جديد.')
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      resend ? setResendBusy(false) : setBusy(false)
    }
  }

  async function verify(event) {
    event.preventDefault()
    if (busy || code.length !== 6) return
    setBusy(true)
    setError('')
    try {
      const data = await authRequest('/api/auth/otp/verify', method === 'email'
        ? { method, email: verificationValue, token: code }
        : { method, phone: verificationValue, token: code })
      window.dispatchEvent(new Event('openly:auth-changed'))
      router.push(data.next || '/onboarding/interests')
      router.refresh()
    } catch (verifyError) {
      setError(verifyError.message)
    } finally {
      setBusy(false)
    }
  }

  if (step === 'email-link') {
    return <div className="auth-wrap v2-auth">
      <div className="auth-head v2-auth-head">
        <div className="auth-icon"><CircleCheck size={21} /></div>
        <h1 className="auth-title">تحقق من بريدك</h1>
        <p className="auth-sub">أرسلنا رابط تسجيل دخول إلى {maskedTarget}. افتح الرسالة واضغط الرابط لإكمال الدخول.</p>
      </div>
      <div className="panel auth-form v2-auth-card">
        {error && <p className="status-message error" role="alert">{error}</p>}
        {notice && <p className="status-message" style={{ color: 'var(--success)' }}>{notice}</p>}
        <button
          type="button"
          className="secondary-button full"
          onClick={event => requestCode(event, true)}
          disabled={resendBusy || countdown > 0}
        >
          {resendBusy ? 'جارِ الإرسال…' : countdown > 0 ? `إعادة الإرسال بعد ${countdown}ث` : 'إعادة إرسال الرابط'}
        </button>
        <button
          type="button"
          className="center small muted"
          style={{ background: 'none', border: 0, textDecoration: 'underline' }}
          onClick={() => {
            setStep('entry')
            setError('')
            setNotice('')
          }}
        >
          تغيير البريد الإلكتروني
        </button>
      </div>
    </div>
  }

  if (step === 'otp') {
    return <div className="auth-wrap v2-auth">
      <div className="auth-head v2-auth-head">
        <div className="auth-icon"><CircleCheck size={21} /></div>
        <h1 className="auth-title">أدخل رمز التحقق</h1>
        <p className="auth-sub">أرسلنا رمزًا من 6 أرقام إلى {maskedTarget}.</p>
      </div>
      <form className="panel auth-form v2-auth-card v2-otp-card" onSubmit={verify}>
        <label className="label">
          رمز التحقق
          <input
            className="form-control v2-otp-input"
            value={code}
            onChange={event => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric"
            autoComplete="one-time-code"
            dir="ltr"
            maxLength={6}
            placeholder="000000"
            style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', letterSpacing: '.3em', textAlign: 'center', fontSize: 20 }}
            required
          />
        </label>
        {error && <p className="status-message error" role="alert">{error}</p>}
        {notice && <p className="status-message" style={{ color: 'var(--success)' }}>{notice}</p>}
        <button className="primary-button full" disabled={busy || code.length !== 6}>
          {busy ? 'جارِ التحقق…' : 'تأكيد والدخول'}
        </button>
        <button
          type="button"
          className="secondary-button full"
          onClick={event => requestCode(event, true)}
          disabled={resendBusy || countdown > 0}
        >
          {resendBusy ? 'جارِ الإرسال…' : countdown > 0 ? `إعادة الإرسال بعد ${countdown}ث` : 'إعادة إرسال الكود'}
        </button>
        <button
          type="button"
          className="center small muted"
          style={{ background: 'none', border: 0, textDecoration: 'underline' }}
          onClick={() => {
            setStep('entry')
            setCode('')
            setError('')
            setNotice('')
          }}
        >
          تغيير {method === 'email' ? 'البريد' : 'رقم الهاتف'}
        </button>
      </form>
    </div>
  }

  return <div className="auth-wrap v2-auth">
    <div className="auth-head v2-auth-head">
      <div className="auth-icon"><LogIn size={21} /></div>
      <h1 className="auth-title">مرحبًا بك في Openly</h1>
      <p className="auth-sub">مساحة عامة للأفكار والذوق والمحادثة.</p>
    </div>

    <div className="panel auth-form v2-auth-card">
      {capabilities.apple && <a className="secondary-button full" href="/api/auth/oauth/apple?next=/">
        <span aria-hidden="true"></span> المتابعة عبر Apple
      </a>}
      {capabilities.google && <a className="secondary-button full" href="/api/auth/oauth/google?next=/">
        <span aria-hidden="true">G</span> المتابعة عبر Google
      </a>}

      {(capabilities.apple || capabilities.google) && <div className="center small muted" aria-hidden="true">──────── أو ────────</div>}

      {method === 'email' ? <form className="stack" onSubmit={requestCode}>
        <label className="label">
          البريد الإلكتروني
          <input
            className="form-control"
            type="email"
            autoComplete="email"
            value={email}
            onChange={event => setEmail(event.target.value)}
            required
            dir="ltr"
            placeholder="example@email.com"
          />
        </label>
        {error && <p className="status-message error" role="alert">{error}</p>}
        <button className="primary-button full" disabled={busy || !email.trim()}>
          {busy ? (capabilities.emailMode === 'otp' ? 'جارِ إرسال الكود…' : 'جارِ إرسال الرابط…') : 'متابعة'}
        </button>
        {capabilities.phone && <button
          type="button"
          className="center small muted"
          style={{ background: 'none', border: 0, textDecoration: 'underline' }}
          onClick={() => { setMethod('phone'); setError('') }}
        >
          المتابعة برقم الهاتف
        </button>}
      </form> : <form className="stack" onSubmit={requestCode}>
        <label className="label">
          رمز الدولة
          <select className="form-control" value={countryCode} onChange={event => setCountryCode(event.target.value)} dir="ltr">
            {COUNTRY_DIAL_CODES.map(([label, dial]) => <option key={label} value={dial}>{dial ? `${label}  ${dial}` : label}</option>)}
          </select>
        </label>
        <label className="label">
          رقم الهاتف
          <input
            className="form-control"
            type="tel"
            autoComplete="tel"
            value={phone}
            onChange={event => setPhone(event.target.value)}
            required
            dir="ltr"
            placeholder={countryCode ? '1234567890' : '+491234567890'}
          />
        </label>
        <p className="tiny subtle">استخدم رقمًا قادرًا على استقبال SMS. الصيغة النهائية E.164.</p>
        {error && <p className="status-message error" role="alert">{error}</p>}
        <button className="primary-button full" disabled={busy || !phone.trim()}>
          {busy ? 'جارِ إرسال SMS…' : 'إرسال رمز SMS'}
        </button>
        <button
          type="button"
          className="center small muted"
          style={{ background: 'none', border: 0, textDecoration: 'underline' }}
          onClick={() => { setMethod('email'); setError('') }}
        >
          العودة للبريد الإلكتروني
        </button>
      </form>}
    </div>
  </div>
}

export function ForgotPasswordScreen() {
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

  return <div className="auth-wrap v2-auth">
    <div className="auth-head v2-auth-head">
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

export function UpdatePasswordScreen() {
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

  return <div className="auth-wrap v2-auth">
    <div className="auth-head v2-auth-head">
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
