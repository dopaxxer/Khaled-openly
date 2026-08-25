import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

// Keep the server client and proxy on the same project. Environment variables
// take precedence on Vercel; the fallback is the verified Openly production
// project so a missing Preview variable cannot silently authenticate against a
// different Supabase project.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://rjucldqvuyeahjqrlene.supabase.co'
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_jnnQqwOVGdK2g1Y7LfjnHg_APSaqz5r'

export async function createSupabaseServerClient() {
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
