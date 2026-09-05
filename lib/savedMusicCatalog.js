import { MUSIC_PROVIDER_APPLE, MUSIC_CATALOG_RESULT_LIMIT } from './musicCatalog.js'

// Public song metadata only. Never query user_music_tracks or listening history.
const COLUMNS = 'id,provider,external_id,title,artist_name,album_name,artwork_url,external_url,preview_url,duration_ms,primary_genre'

export function savedCatalogTrack(row) {
  return {
    id: row.id, provider: row.provider, externalId: row.external_id,
    title: row.title, artist: row.artist_name, album: row.album_name,
    artworkUrl: row.artwork_url, externalUrl: row.external_url,
    previewUrl: row.preview_url, durationMs: row.duration_ms, genre: row.primary_genre
  }
}

export async function searchSavedMusicTracks(supabase, query, limit = MUSIC_CATALOG_RESULT_LIMIT) {
  const term = String(query ?? '').trim().slice(0, 120)
  if (term.length < 2) return []
  const cap = Math.max(1, Math.min(Number(limit) || MUSIC_CATALOG_RESULT_LIMIT, MUSIC_CATALOG_RESULT_LIMIT))
  const pattern = `%${term.replace(/[\\%_]/g, '\\$&')}%`
  // Separate typed filters keep user input out of PostgREST's raw OR grammar.
  const responses = await Promise.all(['title', 'artist_name'].map(column => supabase
    .from('music_tracks').select(COLUMNS).eq('provider', MUSIC_PROVIDER_APPLE)
    .ilike(column, pattern).order('title').limit(cap)))
  const byID = new Map()
  for (const response of responses) {
    if (response.error) throw response.error
    for (const row of response.data || []) byID.set(row.external_id, savedCatalogTrack(row))
  }
  return [...byID.values()].slice(0, cap)
}

export async function findSavedMusicTrack(supabase, externalId) {
  const { data, error } = await supabase.from('music_tracks').select(COLUMNS)
    .eq('provider', MUSIC_PROVIDER_APPLE).eq('external_id', externalId).maybeSingle()
  if (error) throw error
  return data ? savedCatalogTrack(data) : null
}

export async function searchMusicWithFallback({ search, savedSearch, onUnavailable = () => {} }) {
  try {
    return { items: await search(), provider: MUSIC_PROVIDER_APPLE, catalogUnavailable: false }
  } catch (error) {
    onUnavailable(error)
    const items = await savedSearch()
    // An outage with no saved matches is NOT a successful empty catalog search.
    if (!items.length) throw error
    return { items, provider: MUSIC_PROVIDER_APPLE, catalogUnavailable: true, source: 'saved' }
  }
}
