function firstHeaderValue(value) {
  return String(value || '').split(',')[0].trim()
}

function normalizeUrl(value) {
  const raw = String(value || '').trim().replace(/\/+$/, '')
  if (!raw) return ''
  return raw.startsWith('http://') || raw.startsWith('https://') ? raw : `https://${raw}`
}

function isLocalHost(host) {
  const value = String(host || '').toLowerCase()
  return value === 'localhost' || value.startsWith('localhost:') || value === '127.0.0.1' || value.startsWith('127.0.0.1:')
}

export function getPublicOrigin(request) {
  const forwardedHost = firstHeaderValue(request.headers.get('x-forwarded-host'))
  const host = forwardedHost || firstHeaderValue(request.headers.get('host'))
  const forwardedProto = firstHeaderValue(request.headers.get('x-forwarded-proto'))

  if (host && !isLocalHost(host)) {
    const protocol = forwardedProto || 'https'
    return `${protocol}://${host}`
  }

  const environmentOrigin = normalizeUrl(
    process.env.NEXT_PUBLIC_SITE_URL ||
    process.env.VERCEL_BRANCH_URL ||
    process.env.VERCEL_URL ||
    'https://openly.ink'
  )
  if (environmentOrigin) return environmentOrigin

  if (host) {
    const protocol = forwardedProto || 'http'
    return `${protocol}://${host}`
  }

  return new URL(request.url).origin
}
