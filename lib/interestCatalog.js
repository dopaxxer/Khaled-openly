import { fetchAppleCatalog } from './appleCatalog.js'

const APPLE_SEARCH_URL = 'https://itunes.apple.com/search'
const APPLE_LOOKUP_URL = 'https://itunes.apple.com/lookup'

export const INTEREST_PROVIDER_APPLE_BOOKS = 'apple_books'
export const INTEREST_PROVIDER_APPLE_MOVIES = 'apple_movies'
export const INTEREST_CATALOG_QUERY_MAX_LENGTH = 120
export const INTEREST_CATALOG_RESULT_LIMIT = 16

const cache = new Map()
const CACHE_TTL_MS = 10 * 60 * 1000
const MAX_CACHE_ENTRIES = 300

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
  return safe.replace(/\/\d+x\d+bb\.(jpg|png)(?:\?.*)?$/i, '/600x600bb.$1')
}

function releaseYear(value) {
  const match = String(value || '').match(/^(\d{4})/)
  if (!match) return null
  const year = Number(match[1])
  return year >= 1000 && year <= 3000 ? year : null
}

function providerForKind(kind) {
  if (kind === 'book') return INTEREST_PROVIDER_APPLE_BOOKS
  if (kind === 'movie') return INTEREST_PROVIDER_APPLE_MOVIES
  return null
}

function mediaForKind(kind) {
  if (kind === 'book') return { media: 'ebook', entity: 'ebook' }
  if (kind === 'movie') return { media: 'movie', entity: 'movie' }
  return null
}

export function isCatalogProviderForKind(provider, kind) {
  return providerForKind(kind) === String(provider || '').trim().toLowerCase()
}

export function mapAppleInterest(row, kind) {
  const provider = providerForKind(kind)
  if (!provider || !row) return null

  const externalId = String(row.trackId ?? '').trim()
  const label = String(row.trackName ?? '').trim()
  const subtitle = String(row.artistName ?? '').trim() || null
  if (!/^\d{1,20}$/.test(externalId) || !label) return null

  return {
    id: `catalog:${provider}:${externalId}`,
    source: 'catalog',
    kind,
    provider,
    externalId,
    label: label.slice(0, 160),
    subtitle: subtitle?.slice(0, 160) || null,
    artworkUrl: artworkUrl(row.artworkUrl100 || row.artworkUrl60),
    releaseYear: releaseYear(row.releaseDate),
    externalUrl: httpsUrl(row.trackViewUrl),
    popularity: 0
  }
}

function cacheGet(key) {
  const entry = cache.get(key)
  if (!entry) return null
  if (entry.expiresAt <= Date.now()) {
    cache.delete(key)
    return null
  }
  return entry.value
}

function cacheSet(key, value) {
  if (cache.size >= MAX_CACHE_ENTRIES) {
    const now = Date.now()
    for (const [entryKey, entry] of cache) {
      if (entry.expiresAt <= now) cache.delete(entryKey)
    }
    if (cache.size >= MAX_CACHE_ENTRIES) cache.delete(cache.keys().next().value)
  }
  cache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS })
}

export async function searchAppleInterests(query, kind, limit = INTEREST_CATALOG_RESULT_LIMIT, signal) {
  const config = mediaForKind(kind)
  const term = String(query ?? '').trim().slice(0, INTEREST_CATALOG_QUERY_MAX_LENGTH)
  if (!config || term.length < 2) return []

  const boundedLimit = Math.max(1, Math.min(Number(limit) || INTEREST_CATALOG_RESULT_LIMIT, INTEREST_CATALOG_RESULT_LIMIT))
  const key = `${kind}:${term.toLocaleLowerCase()}:${boundedLimit}`
  const cached = cacheGet(key)
  if (cached) return cached

  const url = new URL(APPLE_SEARCH_URL)
  url.searchParams.set('term', term)
  url.searchParams.set('media', config.media)
  url.searchParams.set('entity', config.entity)
  url.searchParams.set('country', 'US')
  url.searchParams.set('explicit', 'No')
  url.searchParams.set('limit', String(boundedLimit))

  const rows = await fetchAppleCatalog(url, signal)
  const items = rows.map(row => mapAppleInterest(row, kind)).filter(Boolean)
  cacheSet(key, items)
  return items
}

export async function lookupAppleInterest(externalId, kind, signal) {
  const config = mediaForKind(kind)
  const id = String(externalId ?? '').trim()
  if (!config || !/^\d{1,20}$/.test(id)) return null

  const url = new URL(APPLE_LOOKUP_URL)
  url.searchParams.set('id', id)
  url.searchParams.set('entity', config.entity)
  url.searchParams.set('country', 'US')

  const rows = await fetchAppleCatalog(url, signal)
  return rows.map(row => mapAppleInterest(row, kind)).find(item => item?.externalId === id) || null
}
