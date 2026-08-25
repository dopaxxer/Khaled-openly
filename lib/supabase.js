import { createServerClient } from '@supabase/ssr'

// Keep the server client and proxy on the same project. Environment variables
// take precedence on Vercel; the fallback is the verified Openly production
// project so a missing Preview variable cannot silently authenticate against a
// different Supabase project.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://rjucldqvuyeahjqrlene.supabase.co'
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_jnnQqwOVGdK2g1Y7LfjnHg_APSaqz5r'

/**
 * Which project this process will authenticate against, and whether that came
 * from the environment or from the fallback above.
 *
 * The fallback exists so a missing Preview variable cannot point the app at an
 * unknown project — but it also means a *misconfigured* deployment silently
 * uses a different database instead of failing, which looks to people like
 * their account was deleted. `/api/health` reports this so the mismatch is
 * visible from outside. The ref is public; the key never leaves here.
 */
export function supabaseConnection() {
  const configured = !!process.env.NEXT_PUBLIC_SUPABASE_URL
  let projectRef = null
  try {
    projectRef = new URL(url).hostname.split('.')[0] || null
  } catch {
    projectRef = null
  }
  return {
    projectRef,
    source: configured ? 'environment' : 'hardcoded-fallback',
    siteUrl: process.env.NEXT_PUBLIC_SITE_URL || null
  }
}

if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
  console.warn(
    '[supabase] NEXT_PUBLIC_SUPABASE_URL is not set; using the hardcoded fallback project. ' +
    'If this is production, accounts will appear missing. Check /api/health.'
  )
}

export async function createSupabaseServerClient() {
  // Keep the pure response mappers importable by the node:test suite. The
  // Next-only module is loaded only when a request actually needs cookies.
  const { cookies } = await import('next/headers')
  const cookieStore = await cookies()
  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options)
          }
        } catch {
          // Server Components cannot always mutate cookies; Route Handlers can.
        }
      }
    }
  })
}

export function mapPost(row) {
  return {
    id: row.id,
    body: row.body,
    createdAt: row.created_at,
    authorCode: row.author_code,
    authorColor: row.author_color,
    commentCount: Number(row.comment_count || 0),
    likeCount: Number(row.like_count || 0),
    track: row.track_id ? {
      id: row.track_id,
      title: row.track_title,
      artist: row.track_artist,
      artworkUrl: row.track_artwork_url,
      previewUrl: row.track_preview_url,
      externalUrl: row.track_external_url
    } : null,
    mentions: []
  }
}

/**
 * Resolved mentions for a batch of posts or comments, keyed by source id.
 *
 * Clients highlight only the codes that come back here, which is what keeps a
 * misspelt, deleted or blocked mention rendering as plain text. Read through
 * the RPC rather than the table so the blocked/muted/soft-deleted rules are
 * applied in one place.
 */
export async function mentionsBySource(supabase, sourceType, ids) {
  const sourceIds = [...new Set((ids || []).filter(Boolean))]
  if (!sourceIds.length) return {}

  const { data, error } = await supabase.rpc('get_mentions', {
    p_source_type: sourceType,
    p_source_ids: sourceIds
  })
  // Mentions are decoration: if the lookup fails the content still renders,
  // just without highlighting.
  if (error) return {}

  const grouped = {}
  for (const row of data || []) {
    const list = grouped[row.source_id] || (grouped[row.source_id] = [])
    list.push({ publicCode: row.public_code, identityColor: row.identity_color })
  }
  return grouped
}

/** Attaches `mentions` to already-mapped items in place and returns them. */
export async function withMentions(supabase, items, sourceType) {
  const list = items || []
  if (!list.length) return list
  const grouped = await mentionsBySource(supabase, sourceType, list.map(item => item.id))
  for (const item of list) item.mentions = grouped[item.id] || []
  return list
}
