import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import {
  INTEREST_PROVIDER_APPLE_BOOKS,
  INTEREST_PROVIDER_APPLE_MOVIES,
  isCatalogProviderForKind,
  mapAppleInterest
} from '../lib/interestCatalog.js'

test('Apple book catalog rows map to verified interest metadata', () => {
  const item = mapAppleInterest({
    wrapperType: 'track',
    kind: 'ebook',
    trackId: 12345,
    trackName: 'The Example Book',
    artistName: 'Example Author',
    artworkUrl100: 'https://is1-ssl.mzstatic.com/image/thumb/Book/1/2/3/100x100bb.jpg',
    trackViewUrl: 'https://books.apple.com/us/book/id12345',
    releaseDate: '2020-04-03T07:00:00Z'
  }, 'book')

  assert.equal(item.provider, INTEREST_PROVIDER_APPLE_BOOKS)
  assert.equal(item.externalId, '12345')
  assert.equal(item.label, 'The Example Book')
  assert.equal(item.subtitle, 'Example Author')
  assert.equal(item.releaseYear, 2020)
  assert.match(item.artworkUrl, /600x600bb\.jpg$/)
})

test('Apple movie catalog rows map to movie interests', () => {
  const item = mapAppleInterest({
    wrapperType: 'track',
    kind: 'feature-movie',
    trackId: 67890,
    trackName: 'Example Movie',
    artistName: 'Example Director',
    artworkUrl100: 'https://is1-ssl.mzstatic.com/image/thumb/Video/1/2/3/100x100bb.jpg',
    trackViewUrl: 'https://tv.apple.com/movie/example',
    releaseDate: '2014-11-07T08:00:00Z'
  }, 'movie')

  assert.equal(item.provider, INTEREST_PROVIDER_APPLE_MOVIES)
  assert.equal(item.subtitle, 'Example Director')
  assert.equal(item.releaseYear, 2014)
  assert.equal(isCatalogProviderForKind(item.provider, 'movie'), true)
  assert.equal(isCatalogProviderForKind(item.provider, 'book'), false)
})

test('book and movie creation is verified server-side before persistence', async () => {
  const route = await readFile(new URL('../app/api/v1/interests/route.js', import.meta.url), 'utf8')
  assert.match(route, /lookupAppleInterest/)
  assert.match(route, /add_catalog_interest/)
  assert.match(route, /catalog_required/)
  assert.match(route, /searchAppleInterests/)
})

test('catalog metadata is additive and keeps public tables behind RPC access', async () => {
  const migration = await readFile(
    new URL('../supabase/migrations/20260827035000_interest_catalog_metadata.sql', import.meta.url),
    'utf8'
  )
  assert.match(migration, /add column if not exists provider text/)
  assert.match(migration, /interests_provider_external_id_unique/)
  assert.match(migration, /private\.add_catalog_interest/)
  assert.match(migration, /revoke execute on function public\.add_catalog_interest/)
})
