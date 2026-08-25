const APPLE_SEARCH_URL = 'https://itunes.apple.com/search'
const APPLE_LOOKUP_URL = 'https://itunes.apple.com/lookup'

export const MUSIC_PROVIDER_APPLE = 'apple_music'
export const MUSIC_CATALOG_QUERY_MAX_LENGTH = 120
export const MUSIC_CATALOG_RESULT_LIMIT = 20

function httpsUrl(value) {
  if (!value) return null
  try {
    const url = new URL(String(value))
    return url.protocol === 'https:' ? url.toString() : null
  } catch {
    return null
  }
}

function artworkUrl(value) {
  const safe = httpsUrl(value)
  if (!safe) return null
  // iTunes commonly returns 100x100 artwork. The same CDN supports a larger
  // rendition at the same path, which stays crisp on Retina displays.
  return safe.replace(/\/\d+x\d+bb\.(jpg|png)(?:\?.*)?$/i, '/600x600bb.$1')
}

export function mapAppleTrack(row) {
  if (!row || row.wrapperType !== 'track' || row.kind !== 'song') return null
  const externalId = String(row.trackId ?? '').trim()
  const title = String(row.trackName ?? '').trim()
  const artist = String(row.artistName ?? '').trim()
  if (!/^\d+$/.test(externalId) || !title || !artist) return null

  const duration = Number(row.trackTimeMillis)
  return {
    provider: MUSIC_PROVIDER_APPLE,
    externalId,
    title: title.slice(0, 200),
    artist: artist.slice(0, 200),
    album: String(row.collectionName ?? '').trim().slice(0, 200) || null,
    artworkUrl: artworkUrl(row.artworkUrl100 || row.artworkUrl60),
    externalUrl: httpsUrl(row.trackViewUrl),
    previewUrl: httpsUrl(row.previewUrl),
    durationMs: Number.isInteger(duration) && duration > 0 ? duration : null,
    genre: String(row.primaryGenreName ?? '').trim().slice(0, 80) || null
  }
}

async function fetchApple(url, signal) {
  const response = await fetch(url, {
    cache: 'no-store',
    signal,
    headers: { Accept: 'application/json' }
  })
  if (!response.ok) throw new Error(`Apple catalog returned ${response.status}`)
  const payload = await response.json()
  return Array.isArray(payload?.results) ? payload.results : []
}

export async function searchAppleTracks(query, limit = MUSIC_CATALOG_RESULT_LIMIT, signal) {
  const term = String(query ?? '').trim().slice(0, MUSIC_CATALOG_QUERY_MAX_LENGTH)
  if (!term) return []

  const url = new URL(APPLE_SEARCH_URL)
  url.searchParams.set('term', term)
  url.searchParams.set('entity', 'song')
  url.searchParams.set('media', 'music')
  url.searchParams.set('limit', String(Math.max(1, Math.min(Number(limit) || MUSIC_CATALOG_RESULT_LIMIT, MUSIC_CATALOG_RESULT_LIMIT))))

  const rows = await fetchApple(url, signal)
  return rows.map(mapAppleTrack).filter(Boolean)
}

export async function lookupAppleTrack(externalId, signal) {
  const id = String(externalId ?? '').trim()
  if (!/^\d{1,20}$/.test(id)) return null

  const url = new URL(APPLE_LOOKUP_URL)
  url.searchParams.set('id', id)
  url.searchParams.set('entity', 'song')

  const rows = await fetchApple(url, signal)
  return rows.map(mapAppleTrack).find(track => track?.externalId === id) || null
}
