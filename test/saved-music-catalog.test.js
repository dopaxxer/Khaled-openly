import test from 'node:test'
import assert from 'node:assert/strict'
import { searchMusicWithFallback, searchSavedMusicTracks, findSavedMusicTrack } from '../lib/savedMusicCatalog.js'

const blue = { id: 'saved-blue', provider: 'apple_music', external_id: '1739659278', title: 'BLUE', artist_name: 'Billie Eilish' }

test('an Apple outage returns saved BLUE and explicitly flags the degraded catalog', async () => {
  const result = await searchMusicWithFallback({
    search: async () => { throw new Error('Apple unavailable') },
    savedSearch: async () => [blue]
  })
  assert.equal(result.catalogUnavailable, true)
  assert.equal(result.source, 'saved')
  assert.equal(result.items[0].title, 'BLUE')
})

test('no saved matches during an outage remains an error, not a successful empty search', async () => {
  const unavailable = new Error('Apple unavailable')
  await assert.rejects(searchMusicWithFallback({ search: async () => { throw unavailable }, savedSearch: async () => [] }), unavailable)
})

test('a genuine empty Apple response does not query the fallback', async () => {
  const result = await searchMusicWithFallback({ search: async () => [], savedSearch: async () => { throw new Error('must not run') } })
  assert.deepEqual(result.items, [])
  assert.equal(result.catalogUnavailable, false)
})

test('saved search escapes wildcard input, bounds rows and deduplicates public metadata', async () => {
  const calls = []
  const db = { from(table) {
    assert.equal(table, 'music_tracks')
    return { select() { return this }, eq(k, v) { assert.equal(k, 'provider'); assert.equal(v, 'apple_music'); return this },
      ilike(k,v) { calls.push([k,v]); return this }, order() { return this }, limit(cap) { assert.equal(cap,20); return {data:[blue]} } }
  } }
  const items = await searchSavedMusicTracks(db, 'blue_%', 100)
  assert.equal(items.length, 1)
  assert.equal(items[0].externalId, '1739659278')
  assert.deepEqual(calls, [['title','%blue\\_\\%%'],['artist_name','%blue\\_\\%%']])
})

test('saved lookup uses both provider and external ID, with no client metadata', async () => {
  const filters = []
  const db = { from() { return { select() { return this }, eq(k,v) { filters.push([k,v]); return this }, maybeSingle: async () => ({data:blue}) } } }
  const saved = await findSavedMusicTrack(db, '1739659278')
  assert.equal(saved.id, 'saved-blue')
  assert.deepEqual(filters, [['provider','apple_music'],['external_id','1739659278']])
})
