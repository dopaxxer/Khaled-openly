import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { readJson } from '@/lib/validation'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

function profilePayload(payload) {
  const value = payload || {}
  const legacyPublic = !!value.preferencesPublic
  return {
    discoveryOptIn: !!value.discoveryOptIn,
    preferencesPublic: legacyPublic,
    showTracks: typeof value.showTracks === 'boolean' ? value.showTracks : legacyPublic,
    showArtists: typeof value.showArtists === 'boolean' ? value.showArtists : legacyPublic,
    showGenres: typeof value.showGenres === 'boolean' ? value.showGenres : legacyPublic,
    tracks: Array.isArray(value.tracks) ? value.tracks : [],
    artists: Array.isArray(value.artists) ? value.artists : [],
    genres: Array.isArray(value.genres) ? value.genres : []
  }
}

async function viewer(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

function limited(request, scope, userId) {
  const result = consumeRateLimit(rateLimitKey(request, scope, userId), RATE_LIMITS[scope])
  if (result.allowed) return null
  return reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
    'Retry-After': String(result.retryAfterSeconds)
  })
}

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const user = await viewer(supabase)
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)
  const rate = limited(request, 'musicRead', user.id)
  if (rate) return rate

  const { data, error } = await supabase.rpc('get_music_profile')
  if (error) return reply({ error: 'تعذر تحميل إعدادات الظهور', code: 'visibility_failed' }, 500)
  return reply({ profile: profilePayload(data) })
}

export async function PUT(request) {
  const supabase = await createSupabaseServerClient()
  const user = await viewer(supabase)
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)
  const rate = limited(request, 'musicWrite', user.id)
  if (rate) return rate

  const parsed = await readJson(request)
  if (parsed.error) return reply({ error: parsed.error, code: 'invalid_request' }, parsed.status)
  const body = parsed.data
  const fields = ['discoveryOptIn', 'showTracks', 'showArtists', 'showGenres']
  if (fields.some(field => typeof body[field] !== 'boolean')) {
    return reply({ error: 'إعدادات الظهور غير صالحة', code: 'invalid_request' }, 400)
  }

  const { data, error } = await supabase.rpc('set_music_profile_settings', {
    p_discovery_opt_in: body.discoveryOptIn,
    p_show_tracks: body.showTracks,
    p_show_artists: body.showArtists,
    p_show_genres: body.showGenres
  })
  if (error) return reply({ error: 'تعذر حفظ إعدادات الظهور', code: 'visibility_rejected' }, 400)
  return reply({ profile: profilePayload(data) })
}
