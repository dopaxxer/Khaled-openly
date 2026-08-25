import test from 'node:test'
import assert from 'node:assert/strict'
import { mapAppleTrack } from '../lib/musicCatalog.js'

test('maps an Apple song into the provider-neutral catalog shape', () => {
  const track = mapAppleTrack({
    wrapperType: 'track',
    kind: 'song',
    trackId: 123456789,
    trackName: 'Test Song',
    artistName: 'Test Artist',
    collectionName: 'Test Album',
    artworkUrl100: 'https://is1-ssl.mzstatic.com/image/thumb/Music/test/100x100bb.jpg',
    trackViewUrl: 'https://music.apple.com/us/album/test/123?i=123456789',
    previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/test.m4a',
    trackTimeMillis: 215000,
    primaryGenreName: 'Pop'
  })

  assert.deepEqual(track, {
    provider: 'apple_music',
    externalId: '123456789',
    title: 'Test Song',
    artist: 'Test Artist',
    album: 'Test Album',
    artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/test/600x600bb.jpg',
    externalUrl: 'https://music.apple.com/us/album/test/123?i=123456789',
    previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/test.m4a',
    durationMs: 215000,
    genre: 'Pop'
  })
})

test('rejects non-song and malformed catalog rows', () => {
  assert.equal(mapAppleTrack({ wrapperType: 'collection', collectionId: 1 }), null)
  assert.equal(mapAppleTrack({ wrapperType: 'track', kind: 'song', trackId: 'bad', trackName: 'x', artistName: 'y' }), null)
  assert.equal(mapAppleTrack({ wrapperType: 'track', kind: 'song', trackId: 1, trackName: '', artistName: 'y' }), null)
})

test('drops non-https external media URLs', () => {
  const track = mapAppleTrack({
    wrapperType: 'track',
    kind: 'song',
    trackId: 42,
    trackName: 'Safe Song',
    artistName: 'Safe Artist',
    artworkUrl100: 'http://example.com/100x100bb.jpg',
    trackViewUrl: 'javascript:alert(1)',
    previewUrl: 'http://example.com/file.m4a'
  })

  assert.equal(track.artworkUrl, null)
  assert.equal(track.externalUrl, null)
  assert.equal(track.previewUrl, null)
})
