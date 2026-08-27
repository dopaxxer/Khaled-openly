export const AUTH_RESEND_COOLDOWN_SECONDS = 60

export function normalizeE164(value) {
  const raw = String(value || '').trim()
  if (!raw) return ''
  const compact = raw.replace(/[\s().-]/g, '')
  return compact.startsWith('+') ? `+${compact.slice(1).replace(/\D/g, '')}` : compact.replace(/\D/g, '')
}

export function isValidE164(value) {
  return /^\+[1-9]\d{7,14}$/.test(normalizeE164(value))
}

export function maskAuthTarget(method, value) {
  const text = String(value || '')
  if (method === 'email') {
    const at = text.indexOf('@')
    if (at <= 1) return '•••'
    return `${text.slice(0, 2)}•••${text.slice(at)}`
  }
  const phone = normalizeE164(text)
  return phone.length > 6 ? `${phone.slice(0, 3)}••••${phone.slice(-3)}` : '•••'
}

const rateLimitCodes = new Set([
  'over_email_send_rate_limit',
  'over_sms_send_rate_limit',
  'over_request_rate_limit',
  'over_request_rate_limit',
  'too_many_requests'
])

export function describeAuthError(error, action = 'request') {
  const code = String(error?.code || '').toLowerCase()
  if (rateLimitCodes.has(code) || Number(error?.status) === 429) {
    return { status: 429, code: code || 'rate_limit', message: 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.' }
  }
  if (code === 'otp_expired' || code === 'otp_expired_or_invalid') {
    return { status: 400, code, message: 'انتهت صلاحية الكود. اطلب كودًا جديدًا.' }
  }
  if (code.includes('invalid') && action === 'verify') {
    return { status: 400, code, message: 'الكود غير صحيح. تحقق منه وحاول مرة أخرى.' }
  }
  if (code.includes('provider_disabled') || code === 'phone_provider_disabled') {
    return { status: 503, code, message: 'طريقة تسجيل الدخول هذه غير مفعّلة حاليًا.' }
  }
  if (code.includes('sms') || code.includes('phone')) {
    return { status: 502, code: code || 'sms_delivery_failed', message: 'تعذر إرسال رسالة SMS الآن. حاول بعد قليل.' }
  }
  if (code.includes('email') || code.includes('smtp') || code.includes('mail')) {
    return { status: 502, code: code || 'email_delivery_failed', message: 'تعذر إرسال كود البريد الآن. حاول بعد قليل.' }
  }
  if (code === 'bad_oauth_state' || code === 'flow_state_not_found') {
    return { status: 400, code, message: 'انتهت جلسة تسجيل الدخول. ابدأ المحاولة من جديد.' }
  }
  return {
    status: Number(error?.status) >= 400 && Number(error?.status) < 600 ? Number(error.status) : 400,
    code: code || 'auth_failed',
    message: action === 'verify' ? 'تعذر التحقق من الكود.' : 'تعذر إكمال تسجيل الدخول.'
  }
}

export function diagnosticPayload(error, details = {}) {
  if (process.env.NODE_ENV !== 'development') return details
  return { ...details, diagnosticCode: String(error?.code || 'auth_failed') }
}
