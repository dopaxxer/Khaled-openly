import { CANONICAL_ORIGIN } from '@/lib/publicOrigin'

export default function robots() {
  return {
    rules: {
      userAgent: '*',
      allow: ['/', '/u/', '/post/'],
      disallow: [
        '/api/',
        '/admin/',
        '/auth/',
        '/bookmarks',
        '/discover/music',
        '/first-post',
        '/forgot-password',
        '/login',
        '/me',
        '/music',
        '/notifications',
        '/privacy',
        '/register',
        '/report/',
        '/search',
        '/settings',
        '/write'
      ]
    },
    sitemap: `${CANONICAL_ORIGIN}/sitemap.xml`,
    host: CANONICAL_ORIGIN
  }
}
