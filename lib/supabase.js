import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

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
    likeCount: Number(row.like_count || 0)
  }
}
