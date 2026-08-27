import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { isUuid, readJson } from '@/lib/validation'
import {
  MENTION_CODE_MAX_LENGTH,
  MAX_MENTIONS_PER_ITEM,
  PUBLIC_CODE_PATTERN
} from '@/lib/mentions'
import {
  ARTIST_NAME_MAX_LENGTH,
  MAX_ARTISTS_PER_PROFILE,
  MAX_GENRES_PER_PROFILE,
  MAX_TRACKS_PER_PROFILE
} from '@/lib/musicNormalize'
import {
  lookupAppleTrack,
  MUSIC_CATALOG_MIN_QUERY_LENGTH,
  MUSIC_CATALOG_QUERY_MAX_LENGTH,
  MUSIC_CATALOG_RESULT_LIMIT,
  MUSIC_PROVIDER_APPLE,
  searchAppleTracks
} from '@/lib/musicCatalog'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

// Version 1 of the shared contract. The unversioned routes under /api are
// untouched so existing clients keep working; both the website and the iOS app
// use these endpoints for mentions and music.
//
// Every response carries private, no-store. None of these payloads are the
// same for two viewers — discovery, preferences and even mention autocomplete
// are all computed against auth.uid() — so a shared cache entry would be a
// cross-user leak.
const POST_LIMIT_HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function ok(body, extraHeaders = {}) {
  return NextResponse.json(body, { status: 200, headers: { ...POST_LIMIT_HEADERS, ...extraHeaders } })
}

// One error shape everywhere: `error` stays a plain string so the existing iOS
// decoder keeps working, and `code` gives clients something stable to branch
// on without parsing Arabic copy.
function fail(status, code, message, extraHeaders = {}) {
  // A 4xx is the client being told no, which is routine. A 5xx is this service
  // failing, and nothing here used to record that it had — the v1 routes were
  // entirely silent.
  if (status >= 500) logError(`v1.${code}`, { code, status })
  return NextResponse.json(
    { error: message, code },
    { status, headers: { ...POST_LIMIT_HEADERS, ...extraHeaders } }
  )
}

const unauthorized = () => fail(401, 'unauthorized', 'غير مسجل')
const notFound = () => fail(404, 'not_found', 'المسار غير موجود')

async function requireUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

function guard(request, scope, userId) {
  const result = consumeRateLimit(rateLimitKey(request, scope, userId), RATE_LIMITS[scope])
  if (result.allowed) return null
  return fail(429, 'rate_limited', 'محاولات كثيرة. حاول بعد قليل.', {
    'Retry-After': String(result.retryAfterSeconds)
  })
}

function boundedInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(min, Math.min(parsed, max))
}

function mentionList(rows) {
  return (rows || []).map(row => ({
    publicCode: row.public_code,
    identityColor: row.identity_color
  }))
}

function musicProfile(payload) {
  const value = payload || {}
  return {
    discoveryOptIn: !!value.discoveryOptIn,
    preferencesPublic: !!value.preferencesPublic,
    tracks: Array.isArray(value.tracks) ? value.tracks : [],
    artists: Array.isArray(value.artists) ? value.artists : [],
    genres: Array.isArray(value.genres) ? value.genres : []
  }
}

function savedTrack(row) {
  return {
    id: row.id,
    provider: row.provider,
    externalId: row.external_id,
    title: row.title,
    artist: row.artist_name,
    album: row.album_name,
    artworkUrl: row.artwork_url,
    externalUrl: row.external_url,
    previewUrl: row.preview_url,
    durationMs: row.duration_ms,
    genre: row.primary_genre
  }
}

// Only accepts a list of well-formed UUIDs within the documented cap. The
// database re-checks that each id exists and enforces the cap again, so a
// crafted payload cannot inflate a profile.
function idList(value, cap) {
  if (!Array.isArray(value)) return { error: 'قائمة غير صالحة' }
  if (value.length > cap) return { error: `الحد الأقصى ${cap} عنصرًا` }
  const ids = value.map(entry => String(entry || ''))
  if (ids.some(id => !isUuid(id))) return { error: 'معرّف غير صالح' }
  return { ids: [...new Set(ids)] }
}

async function withCatalogTimeout(work) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 7000)
  try {
    return await work(controller.signal)
  } finally {
    clearTimeout(timer)
  }
}

export async function GET(request, { params }) {
  const { path = [] } = await params
  const route = path.join('/')
  const url = new URL(request.url)
  const supabase = await createSupabaseServerClient()

  if (route === 'mentions/suggest') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'mentionSuggest', user.id)
    if (limited) return limited

    const query = String(url.searchParams.get('q') || '').trim().toUpperCase()
    if (!query || query.length > MENTION_CODE_MAX_LENGTH) return ok({ items: [] })
    if (!/^[A-HJ-NP-Z2-9]+$/.test(query)) return ok({ items: [] })

    const { data, error } = await supabase.rpc('suggest_mentions', {
      p_query: query,
      p_limit: boundedInt(url.searchParams.get('limit'), 8, 1, 10)
    })
    if (error) return fail(500, 'suggest_failed', 'تعذر تحميل الاقتراحات')
    return ok({ items: mentionList(data) })
  }

  if (route === 'music/genres') {
    const limited = guard(request, 'musicSearch', null)
    if (limited) return limited
    const query = String(url.searchParams.get('q') || '').trim().slice(0, ARTIST_NAME_MAX_LENGTH)
    const { data, error } = await supabase.rpc('search_music_genres', {
      p_query: query || null,
      p_limit: boundedInt(url.searchParams.get('limit'), 30, 1, 50)
    })
    if (error) return fail(500, 'genre_search_failed', 'تعذر تحميل التصنيفات')
    return ok({
      items: (data || []).map(row => ({
        id: row.id,
        slug: row.slug,
        name: row.display_name,
        nameAr: row.display_name_ar
      }))
    })
  }

  if (route === 'music/artists') {
    const limited = guard(request, 'musicSearch', null)
    if (limited) return limited
    const query = String(url.searchParams.get('q') || '').trim().slice(0, ARTIST_NAME_MAX_LENGTH)
    if (!query) return ok({ items: [] })
    const { data, error } = await supabase.rpc('search_music_artists', {
      p_query: query,
      p_limit: boundedInt(url.searchParams.get('limit'), 20, 1, 25)
    })
    if (error) return fail(500, 'artist_search_failed', 'تعذر تحميل الفنانين')
    return ok({
      items: (data || []).map(row => ({
        id: row.id,
        name: row.display_name,
        listenerCount: Number(row.listener_count || 0)
      }))
    })
  }

  if (route === 'music/catalog' || route === 'music/tracks/search') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'musicSearch', user.id)
    if (limited) return limited

    const query = String(url.searchParams.get('q') || '').trim().slice(0, MUSIC_CATALOG_QUERY_MAX_LENGTH)
    if (query.length < MUSIC_CATALOG_MIN_QUERY_LENGTH) return ok({ items: [], provider: MUSIC_PROVIDER_APPLE })
    const limit = boundedInt(url.searchParams.get('limit'), MUSIC_CATALOG_RESULT_LIMIT, 1, MUSIC_CATALOG_RESULT_LIMIT)

    try {
      const items = await withCatalogTimeout(signal => searchAppleTracks(query, limit, signal))
      return ok({ items, provider: MUSIC_PROVIDER_APPLE })
    } catch (error) {
      logError('v1.catalog_upstream', error)
      return fail(502, 'catalog_unavailable', 'تعذر الوصول إلى كتالوج الموسيقى الآن')
    }
  }

  if (route === 'music/preferences') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'musicRead', user.id)
    if (limited) return limited

    const { data, error } = await supabase.rpc('get_music_profile')
    if (error) return fail(500, 'preferences_failed', 'تعذر تحميل تفضيلاتك')
    return ok({ profile: musicProfile(data) })
  }

  if (route === 'music/discover') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'musicDiscovery', user.id)
    if (limited) return limited

    const artistId = url.searchParams.get('artistId')
    const genreId = url.searchParams.get('genreId')
    if (artistId && !isUuid(artistId)) return fail(400, 'invalid_request', 'معرّف الفنان غير صالح')
    if (genreId && !isUuid(genreId)) return fail(400, 'invalid_request', 'معرّف التصنيف غير صالح')

    const limit = boundedInt(url.searchParams.get('limit'), 20, 1, 50)
    const offset = boundedInt(url.searchParams.get('offset'), 0, 0, 500)

    const { data, error } = await supabase.rpc('discover_music_people', {
      p_artist_id: artistId || null,
      p_genre_id: genreId || null,
      p_limit: limit,
      p_offset: offset
    })
    if (error) return fail(500, 'discovery_failed', 'تعذر تحميل الاقتراحات')

    const rows = data || []
    const total = rows.length ? Number(rows[0].total_matches || 0) : 0
    return ok({
      items: rows.map(row => ({
        publicCode: row.public_code,
        identityColor: row.identity_color,
        compatibility: Number(row.compatibility || 0),
        sharedArtistCount: Number(row.shared_artist_count || 0),
        sharedGenreCount: Number(row.shared_genre_count || 0),
        sharedArtists: row.shared_artists || [],
        sharedGenres: row.shared_genres || []
      })),
      total,
      limit,
      offset,
      hasMore: offset + rows.length < total
    })
  }

  if (path[0] === 'users' && path[1] && path[2] === 'music' && path.length === 3) {
    const limited = guard(request, 'musicRead', null)
    if (limited) return limited
    const code = String(path[1] || '').trim().toUpperCase()
    if (!PUBLIC_CODE_PATTERN.test(code)) return fail(400, 'invalid_request', 'الكود غير صالح')

    const { data, error } = await supabase.rpc('get_public_music_profile', { p_public_code: code })
    if (error) return fail(500, 'music_profile_failed', 'تعذر تحميل الملف الموسيقي')
    // A user who has not published their list is indistinguishable from one
    // who has no list at all.
    if (!data) return ok({ profile: null })
    return ok({
      profile: {
        publicCode: data.publicCode,
        identityColor: data.identityColor,
        tracks: Array.isArray(data.tracks) ? data.tracks : [],
        artists: Array.isArray(data.artists) ? data.artists : [],
        genres: Array.isArray(data.genres) ? data.genres : []
      }
    })
  }

  return notFound()
}

export async function POST(request, { params }) {
  const { path = [] } = await params
  const route = path.join('/')
  const supabase = await createSupabaseServerClient()

  const parsed = await readJson(request)
  if (parsed.error) return fail(parsed.status, 'invalid_request', parsed.error)
  const body = parsed.data

  if (route === 'mentions/resolve') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'mentionResolve', user.id)
    if (limited) return limited

    const text = String(body.text || '')
    if (text.length > 3000) return fail(400, 'invalid_request', 'النص أطول من المسموح')

    const { data, error } = await supabase.rpc('resolve_mentions', { p_body: text })
    if (error) return fail(500, 'resolve_failed', 'تعذر تحليل الإشارات')
    return ok({ items: mentionList(data), maxPerItem: MAX_MENTIONS_PER_ITEM })
  }

  if (route === 'music/artists') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'artistCreate', user.id)
    if (limited) return limited

    const name = String(body.name || '').trim()
    if (!name || name.length > ARTIST_NAME_MAX_LENGTH) {
      return fail(400, 'invalid_request', `اسم الفنان يجب أن يكون بين 1 و${ARTIST_NAME_MAX_LENGTH} حرفًا`)
    }

    const { data, error } = await supabase.rpc('add_music_artist', { p_name: name })
    if (error) return fail(400, 'artist_rejected', 'تعذر إضافة الفنان')
    const row = (data || [])[0]
    if (!row) return fail(400, 'artist_rejected', 'تعذر إضافة الفنان')
    return ok({ artist: { id: row.id, name: row.display_name }, created: !!row.created })
  }

  if (route === 'music/tracks') {
    const user = await requireUser(supabase)
    if (!user) return unauthorized()
    const limited = guard(request, 'musicWrite', user.id)
    if (limited) return limited

    const provider = String(body.provider || '').trim().toLowerCase()
    const externalId = String(body.externalId || '').trim()
    if (provider !== MUSIC_PROVIDER_APPLE || !/^\d{1,20}$/.test(externalId)) {
      return fail(400, 'invalid_request', 'الأغنية أو مزود الموسيقى غير صالح')
    }

    let track
    try {
      track = await withCatalogTimeout(signal => lookupAppleTrack(externalId, signal))
    } catch (error) {
      logError('v1.catalog_lookup_upstream', error)
      return fail(502, 'catalog_unavailable', 'تعذر التحقق من الأغنية الآن')
    }
    if (!track) return fail(404, 'track_not_found', 'لم تعد الأغنية موجودة في الكتالوج')

    const { data, error } = await supabase.rpc('add_music_track', {
      p_provider: track.provider,
      p_external_id: track.externalId,
      p_title: track.title,
      p_artist_name: track.artist,
      p_album_name: track.album,
      p_artwork_url: track.artworkUrl,
      p_external_url: track.externalUrl,
      p_preview_url: track.previewUrl,
      p_duration_ms: track.durationMs,
      p_primary_genre: track.genre
    })
    if (error) return fail(400, 'track_rejected', 'تعذر حفظ بيانات الأغنية')
    const row = (data || [])[0]
    if (!row) return fail(400, 'track_rejected', 'تعذر حفظ بيانات الأغنية')
    return ok({ track: savedTrack(row) })
  }

  return notFound()
}

export async function PUT(request, { params }) {
  const { path = [] } = await params
  const route = path.join('/')
  const supabase = await createSupabaseServerClient()

  const user = await requireUser(supabase)
  if (!user) return unauthorized()
  const limited = guard(request, 'musicWrite', user.id)
  if (limited) return limited

  const parsed = await readJson(request)
  if (parsed.error) return fail(parsed.status, 'invalid_request', parsed.error)
  const body = parsed.data

  if (route === 'music/preferences') {
    if (typeof body.discoveryOptIn !== 'boolean' || typeof body.preferencesPublic !== 'boolean') {
      return fail(400, 'invalid_request', 'قيم الإعدادات غير صالحة')
    }
    const { data, error } = await supabase.rpc('set_music_settings', {
      p_discovery_opt_in: body.discoveryOptIn,
      p_preferences_public: body.preferencesPublic
    })
    if (error) return fail(400, 'settings_rejected', 'تعذر حفظ الإعدادات')
    return ok({ profile: musicProfile(data) })
  }

  if (route === 'music/preferences/tracks') {
    const list = idList(body.trackIds, MAX_TRACKS_PER_PROFILE)
    if (list.error) return fail(400, 'invalid_request', list.error)
    const { data, error } = await supabase.rpc('set_music_tracks', { p_track_ids: list.ids })
    if (error) return fail(400, 'tracks_rejected', 'تعذر حفظ الأغاني')
    return ok({ profile: musicProfile(data) })
  }

  if (route === 'music/preferences/artists') {
    const list = idList(body.artistIds, MAX_ARTISTS_PER_PROFILE)
    if (list.error) return fail(400, 'invalid_request', list.error)
    const { data, error } = await supabase.rpc('set_music_artists', { p_artist_ids: list.ids })
    if (error) return fail(400, 'artists_rejected', 'تعذر حفظ الفنانين')
    return ok({ profile: musicProfile(data) })
  }

  if (route === 'music/preferences/genres') {
    const list = idList(body.genreIds, MAX_GENRES_PER_PROFILE)
    if (list.error) return fail(400, 'invalid_request', list.error)
    const { data, error } = await supabase.rpc('set_music_genres', { p_genre_ids: list.ids })
    if (error) return fail(400, 'genres_rejected', 'تعذر حفظ التصنيفات')
    return ok({ profile: musicProfile(data) })
  }

  return notFound()
}

export async function DELETE(request, { params }) {
  const { path = [] } = await params
  const route = path.join('/')
  const supabase = await createSupabaseServerClient()

  const user = await requireUser(supabase)
  if (!user) return unauthorized()
  const limited = guard(request, 'musicWrite', user.id)
  if (limited) return limited

  if (route === 'music/preferences') {
    const { data, error } = await supabase.rpc('clear_music_preferences')
    if (error) return fail(400, 'clear_failed', 'تعذر حذف تفضيلاتك')
    return ok({ profile: musicProfile(data) })
  }

  return notFound()
}
