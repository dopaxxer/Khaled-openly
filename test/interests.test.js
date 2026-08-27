import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import {
  INTEREST_KINDS,
  MAX_INTERESTS_PER_KIND,
  MAX_INTERESTS_PER_PROFILE,
  interestKindLabel,
  normalizeInterestKind
} from '../lib/interests.js'

test('interest kinds are intentionally small and stable', () => {
  assert.deepEqual(INTEREST_KINDS, ['book', 'movie', 'topic'])
  assert.equal(normalizeInterestKind(' BOOK '), 'book')
  assert.equal(normalizeInterestKind('music'), null)
  assert.equal(interestKindLabel('movie'), 'أفلام')
  assert.equal(MAX_INTERESTS_PER_KIND, 12)
  assert.equal(MAX_INTERESTS_PER_PROFILE, 36)
})

test('interest APIs keep reads private and validate profile identifiers', async () => {
  const preferences = await readFile(new URL('../app/api/v1/interests/preferences/route.js', import.meta.url), 'utf8')
  const discovery = await readFile(new URL('../app/api/v1/interests/discover/route.js', import.meta.url), 'utf8')
  assert.match(preferences, /private, no-store/)
  assert.match(preferences, /set_interest_profile/)
  assert.match(discovery, /discover_interest_people/)
  assert.match(discovery, /interestDiscovery/)
})

test('the interest graph is additive and direct table access stays closed', async () => {
  const migration = await readFile(
    new URL('../supabase/migrations/20260827032000_common_ground_interests.sql', import.meta.url),
    'utf8'
  )

  assert.match(migration, /create table if not exists public\.interests/)
  assert.match(migration, /create table if not exists public\.user_interests/)
  assert.match(migration, /create table if not exists public\.interest_preferences/)
  assert.match(migration, /alter table public\.interests enable row level security/)
  assert.match(migration, /revoke all on table public\.interests from public, anon, authenticated/)
  assert.match(migration, /private\.taste_similarity_to/)
  assert.match(migration, /private\.music_similarity_to/)
})

test('new signups enter interest onboarding before the first post', async () => {
  const screens = await readFile(new URL('../components/Screens.jsx', import.meta.url), 'utf8')
  assert.match(screens, /\/onboarding\/interests/)
  assert.match(screens, /<InterestPreferences onboarding \/>/)
  assert.match(screens, /<PublicInterestProfile profile=\{interests\} \/>/)
})
