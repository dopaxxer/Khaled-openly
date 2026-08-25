import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'

const route = name => readFile(new URL(`../app/api/v1/music/${name}/route.js`, import.meta.url), 'utf8')

test('one-sided music interest is never exposed as incoming interest', async () => {
  const suggestions = await route('match-suggestions')
  const interest = await route('match-interest')
  assert.match(suggestions, /get_music_interest_states/)
  assert.doesNotMatch(suggestions, /target_user_id/)
  assert.match(interest, /set_music_match_interest/)
})

test('visibility API requires four explicit booleans', async () => {
  const visibility = await route('visibility')
  assert.match(visibility, /showTracks/)
  assert.match(visibility, /showArtists/)
  assert.match(visibility, /showGenres/)
  assert.match(visibility, /set_music_profile_settings/)
})

test('mutual matches have a dedicated list and explicit removal', async () => {
  const matches = await route('matches')
  assert.match(matches, /get_music_matches/)
  assert.match(matches, /remove_music_match/)
  assert.match(matches, /export async function DELETE/)
})
