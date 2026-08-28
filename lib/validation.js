export const POST_MAX_LENGTH = 3000
export const COMMENT_MAX_LENGTH = 2000
export const REPORT_MAX_LENGTH = 1000
export const PASSWORD_MIN_LENGTH = 12
export const PASSWORD_MAX_LENGTH = 128

export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

/** Identity codes are Crockford-ish. Strip ILIKE metacharacters so a search
 *  for "%" cannot enumerate every public_code. */
export const identityAlphabetPattern = /[^A-HJ-NP-Z2-9]/g

export function isUuid(value) {
  return uuidPattern.test(String(value || ''))
}

export function identitySearchNeedle(value) {
  return String(value || '').trim().toUpperCase().replace(identityAlphabetPattern, '').slice(0, 8)
}

export function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase()
}

export function isValidEmail(value) {
  const email = normalizeEmail(value)
  if (!email || email.length > 320 || /[\r\n]/.test(email)) return false
  const at = email.lastIndexOf('@')
  return at > 0 && at < email.length - 1 && email.slice(at + 1).includes('.')
}

export function isStrongPassword(value) {
  const password = String(value || '')
  return password.length >= PASSWORD_MIN_LENGTH &&
    password.length <= PASSWORD_MAX_LENGTH &&
    /\p{L}/u.test(password) &&
    /\p{N}/u.test(password)
}

export function parseCursor(value) {
  if (!value) return { createdAt: null, id: null }
  const parts = String(value).split('|')
  if (parts.length !== 2 || !isUuid(parts[1])) return null
  const timestamp = Date.parse(parts[0])
  if (!Number.isFinite(timestamp)) return null
  return { createdAt: new Date(timestamp).toISOString(), id: parts[1] }
}

export async function readJson(request, maxBytes = 64 * 1024) {
  const declaredLength = Number(request.headers.get('content-length'))
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return { error: 'حجم الطلب أكبر من المسموح', status: 413 }
  }

  // Some runtimes expose an empty POST body as a readable stream. Honor an
  // explicit zero length before requiring a JSON content type so bodyless
  // actions such as logout remain interoperable.
  if (!request.body || declaredLength === 0) return { data: {} }

  const contentType = String(request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase()
  if (contentType !== 'application/json') {
    return { error: 'نوع محتوى الطلب غير مدعوم', status: 415 }
  }

  let raw
  try {
    raw = await request.text()
  } catch {
    return { error: 'تعذر قراءة الطلب', status: 400 }
  }

  if (new TextEncoder().encode(raw).byteLength > maxBytes) {
    return { error: 'حجم الطلب أكبر من المسموح', status: 413 }
  }
  if (!raw.trim()) return { data: {} }

  try {
    const data = JSON.parse(raw)
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('invalid body')
    return { data }
  } catch {
    return { error: 'صيغة JSON غير صالحة', status: 400 }
  }
}

/**
 * Supabase reports a broken mail sender through these codes. They all mean
 * "the server could not send", never "this address is wrong", so surfacing
 * them reveals nothing about who has an account and stops someone waiting for
 * a message that was never sent.
 */
export const MAIL_DELIVERY_ERROR_CODES = new Set([
  'error_sending_confirmation_email',
  'error_sending_email',
  'email_provider_disabled',
  'unexpected_failure'
])

export function isMailDeliveryFailure(errorCode) {
  return MAIL_DELIVERY_ERROR_CODES.has(String(errorCode || ''))
}
