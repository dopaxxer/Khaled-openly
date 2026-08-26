export const CANONICAL_ORIGIN = 'https://www.openly.ink'

const FALLBACK_PRODUCTION_ORIGIN = CANONICAL_ORIGIN

export const PASSWORD_RECOVERY_COOKIE = 'openly_password_recovery'

function normalizeOrigin(value) {
  const raw = String(value || '').trim()
  if (!raw) return ''

  try {
    const url = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return ''
    return url.origin
  } catch {
    return ''
  }
}

function environmentOrigins(environment) {
  return [
    environment.NEXT_PUBLIC_SITE_URL,
    environment.VERCEL_PROJECT_PRODUCTION_URL,
    environment.URL,
    environment.DEPLOY_PRIME_URL,
    environment.DEPLOY_URL,
    environment.VERCEL_BRANCH_URL,
    environment.VERCEL_URL
  ].map(normalizeOrigin).filter(Boolean)
}

function isLocalOrigin(origin) {
  try {
    const { hostname } = new URL(origin)
    return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]'
  } catch {
    return false
  }
}

export function getPublicOrigin(request, environment = process.env) {
  const configured = normalizeOrigin(environment.NEXT_PUBLIC_SITE_URL)
  if (configured) return configured

  const candidates = environmentOrigins(environment)
  const allowed = new Set([...candidates, FALLBACK_PRODUCTION_ORIGIN])
  const requestOrigin = normalizeOrigin(request.url)

  if (requestOrigin && allowed.has(requestOrigin)) return requestOrigin
  if (environment.NODE_ENV !== 'production' && isLocalOrigin(requestOrigin)) return requestOrigin

  return candidates[0] || FALLBACK_PRODUCTION_ORIGIN
}

export function safeInternalPath(value, fallback = '/') {
  const path = String(value || '')
  if (!path.startsWith('/') || path.startsWith('//') || /[\\\r\n]/.test(path)) return fallback
  return path
}
