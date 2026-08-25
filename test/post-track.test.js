import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { mapPost } from '../lib/supabase.js'
import { isUuid } from '../lib/validation.js'

const baseRow = {
  id: '11111111-1111-4111-8111-111111111111',
  body: 'plain post',
  created_at: '2026-08-25T12:00:00.000Z',
  author_code: 'BCDE',
  author_color: '#3F7CAC',
  comment_count: 0,
  like_count: 0
}

test('mapPost returns a null track when track_id is absent', () => {
  const post = mapPost({ ...baseRow, track_id: null })
  assert.equal(post.track, null)
})

test('mapPost builds the complete post track object', () => {
  const post = mapPost({
    ...baseRow,
    track_id: '22222222-2222-4222-8222-222222222222',
    track_title: 'Test Song',
    track_artist: 'Test Artist',
    track_artwork_url: 'https://is1-ssl.mzstatic.com/test.jpg',
    track_preview_url: 'https://audio-ssl.mzstatic.com/test.m4a',
    track_external_url: 'https://music.apple.com/test'
  })

  assert.deepEqual(post.track, {
    id: '22222222-2222-4222-8222-222222222222',
    title: 'Test Song',
    artist: 'Test Artist',
    artworkUrl: 'https://is1-ssl.mzstatic.com/test.jpg',
    previewUrl: 'https://audio-ssl.mzstatic.com/test.m4a',
    externalUrl: 'https://music.apple.com/test'
  })
})

test('the post API UUID contract rejects an invalid trackId', () => {
  const invalidTrackId = 'apple_music:123456'
  assert.equal(isUuid(invalidTrackId), false)
  assert.equal(isUuid('22222222-2222-4222-8222-222222222222'), true)

  const source = readFileSync(new URL('../app/api/[...path]/route.js', import.meta.url), 'utf8')
  const guards = source.match(/trackId !== null && !isUuid\(trackId\)/g) || []
  assert.equal(guards.length, 2, 'POST and PATCH both reject a non-UUID trackId')
})
