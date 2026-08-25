import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { isUuid } from '@/lib/validation'
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

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)

  const rate = consumeRateLimit(rateLimitKey(request, 'musicDiscovery', user.id), RATE_LIMITS.musicDiscovery)
  if (!rate.allowed) {
    return reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
      'Retry-After': String(rate.retryAfterSeconds)
    })
  }

  const url = new URL(request.url)
  const artistId = url.searchParams.get('artistId')
  const genreId = url.searchParams.get('genreId')
  if (artistId && !isUuid(artistId)) return reply({ error: 'معرّف الفنان غير صالح', code: 'invalid_request' }, 400)
  if (genreId && !isUuid(genreId)) return reply({ error: 'معرّف التصنيف غير صالح', code: 'invalid_request' }, 400)

  const limit = boundedInt(url.searchParams.get('limit'), 20, 1, 50)
  const offset = boundedInt(url.searchParams.get('offset'), 0, 0, 500)

  const { data, error } = await supabase.rpc('discover_music_people', {
    p_artist_id: artistId || null,
    p_genre_id: genreId || null,
    p_limit: limit,
    p_offset: offset
  })
  if (error) return reply({ error: 'تعذر تحميل الاقتراحات', code: 'discovery_failed' }, 500)

  const rows = data || []
  const codes = rows.map(row => row.public_code)
  const states = new Map()
  if (codes.length) {
    const { data: stateRows } = await supabase.rpc('get_music_interest_states', { p_public_codes: codes })
    for (const row of stateRows || []) {
      states.set(row.public_code, { interested: !!row.interested, matched: !!row.matched })
    }
  }

  const total = rows.length ? Number(rows[0].total_matches || 0) : 0
  return reply({
    items: rows.map(row => {
      const state = states.get(row.public_code) || { interested: false, matched: false }
      return {
        publicCode: row.public_code,
        identityColor: row.identity_color,
        compatibility: Number(row.compatibility || 0),
        sharedArtistCount: Number(row.shared_artist_count || 0),
        sharedGenreCount: Number(row.shared_genre_count || 0),
        sharedArtists: row.shared_artists || [],
        sharedGenres: row.shared_genres || [],
        interested: state.interested,
        matched: state.matched
      }
    }),
    total,
    limit,
    offset,
    hasMore: offset + rows.length < total
  })
}
