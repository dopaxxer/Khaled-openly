import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { PUBLIC_CODE_PATTERN } from '@/lib/mentions'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

function boundedInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(min, Math.min(parsed, max))
}

async function authenticated(request, scope) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { response: reply({ error: 'غير مسجل', code: 'unauthorized' }, 401) }
  const rate = consumeRateLimit(rateLimitKey(request, scope, user.id), RATE_LIMITS[scope])
  if (!rate.allowed) {
    return {
      response: reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
        'Retry-After': String(rate.retryAfterSeconds)
      })
    }
  }
  return { supabase, user }
}

export async function GET(request) {
  const auth = await authenticated(request, 'musicDiscovery')
  if (auth.response) return auth.response
  const url = new URL(request.url)
  const limit = boundedInt(url.searchParams.get('limit'), 20, 1, 50)
  const offset = boundedInt(url.searchParams.get('offset'), 0, 0, 500)

  const { data, error } = await auth.supabase.rpc('get_music_matches', {
    p_limit: limit,
    p_offset: offset
  })
  if (error) return reply({ error: 'تعذر تحميل الماتشات', code: 'matches_failed' }, 500)

  const rows = data || []
  const total = rows.length ? Number(rows[0].total_matches || 0) : 0
  return reply({
    items: rows.map(row => ({
      publicCode: row.public_code,
      identityColor: row.identity_color,
      compatibility: Number(row.compatibility || 0),
      sharedArtistCount: Number(row.shared_artist_count || 0),
      sharedGenreCount: Number(row.shared_genre_count || 0),
      sharedArtists: row.shared_artists || [],
      sharedGenres: row.shared_genres || [],
      matchedAt: row.matched_at
    })),
    total,
    limit,
    offset,
    hasMore: offset + rows.length < total
  })
}

export async function DELETE(request) {
  const auth = await authenticated(request, 'musicWrite')
  if (auth.response) return auth.response
  const url = new URL(request.url)
  const publicCode = String(url.searchParams.get('publicCode') || '').trim().toUpperCase()
  if (!PUBLIC_CODE_PATTERN.test(publicCode)) {
    return reply({ error: 'كود المطابقة غير صالح', code: 'invalid_request' }, 400)
  }

  const { data, error } = await auth.supabase.rpc('remove_music_match', { p_public_code: publicCode })
  if (error) return reply({ error: 'تعذر إلغاء المطابقة', code: 'remove_failed' }, 400)
  return reply({ ok: !!data })
}
