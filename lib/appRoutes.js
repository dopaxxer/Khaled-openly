import { isUuid } from './validation.js'

const PUBLIC_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{4,8}$/

const STATIC_ROUTES = new Map([
  ['login', 'تسجيل الدخول'],
  ['register', 'إنشاء حساب'],
  ['forgot-password', 'استعادة كلمة المرور'],
  ['auth/update-password', 'تحديث كلمة المرور'],
  ['write', 'اكتب'],
  ['first-post', 'منشورك الأول'],
  ['search', 'البحث'],
  ['me', 'حسابي'],
  ['settings', 'الإعدادات'],
  ['notifications', 'الإشعارات'],
  ['bookmarks', 'المحفوظات'],
  ['privacy', 'الخصوصية'],
  ['music', 'تفضيلات الموسيقى'],
  ['discover/music', 'اكتشاف الموسيقى'],
  ['admin/reports', 'إدارة البلاغات']
])

function cleanSegments(slug) {
  if (!Array.isArray(slug) || !slug.length) return null
  if (slug.some(segment => typeof segment !== 'string' || !segment || segment.length > 128)) return null
  return slug
}

/**
 * Classifies every route served by the catch-all page.
 *
 * Keeping this allow-list on the server prevents arbitrary paths from being
 * rendered as a client-side "not found" screen with an HTTP 200 response.
 */
export function classifyAppRoute(slug) {
  const segments = cleanSegments(slug)
  if (!segments) return null

  const key = segments.join('/')
  const staticTitle = STATIC_ROUTES.get(key)
  if (staticTitle) {
    return { kind: 'private', key, path: `/${key}`, title: staticTitle }
  }

  if (segments.length === 2 && segments[0] === 'u') {
    const code = segments[1].toUpperCase()
    if (!PUBLIC_CODE_PATTERN.test(code)) return null
    return { kind: 'user', code, path: `/u/${code}` }
  }

  if (segments.length === 2 && segments[0] === 'post') {
    const id = segments[1].toLowerCase()
    if (!isUuid(id)) return null
    return { kind: 'post', id, path: `/post/${id}` }
  }

  if (
    segments.length === 3 &&
    segments[0] === 'report' &&
    ['post', 'comment'].includes(segments[1]) &&
    isUuid(segments[2])
  ) {
    return {
      kind: 'private',
      key,
      path: `/${key}`,
      title: segments[1] === 'post' ? 'إبلاغ عن منشور' : 'إبلاغ عن تعليق'
    }
  }

  return null
}
