import { CANONICAL_ORIGIN } from '@/lib/publicOrigin'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'

// The production database is deliberately not available during CI builds.
// A request-time sitemap keeps builds credential-free and lets newly public
// posts and identities appear without a redeploy.
export const dynamic = 'force-dynamic'

export default async function sitemap() {
  const home = [{
    url: CANONICAL_ORIGIN,
    changeFrequency: 'daily',
    priority: 1
  }]

  try {
    const supabase = await createSupabaseServerClient()
    const [profilesResult, postsResult] = await Promise.all([
      supabase
        .from('profiles')
        .select('public_code,created_at')
        .order('created_at', { ascending: false })
        .limit(5000),
      supabase
        .from('posts')
        .select('id,created_at')
        .is('deleted_at', null)
        .order('created_at', { ascending: false })
        .limit(5000)
    ])

    if (profilesResult.error) throw profilesResult.error
    if (postsResult.error) throw postsResult.error

    const profiles = (profilesResult.data || []).map(profile => ({
      url: `${CANONICAL_ORIGIN}/u/${profile.public_code}`,
      lastModified: profile.created_at,
      changeFrequency: 'weekly',
      priority: 0.6
    }))
    const posts = (postsResult.data || []).map(post => ({
      url: `${CANONICAL_ORIGIN}/post/${post.id}`,
      lastModified: post.created_at,
      changeFrequency: 'monthly',
      priority: 0.7
    }))

    return [...home, ...profiles, ...posts]
  } catch (error) {
    // Search engines should still receive a valid sitemap during a transient
    // database failure. The failure remains visible in Vercel logs.
    logError('sitemap.load', error)
    return home
  }
}
