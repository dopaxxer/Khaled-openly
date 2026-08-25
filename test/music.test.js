import assert from 'node:assert/strict'
import test from 'node:test'
import { isSameMusicName, normalizeMusicName } from '../lib/musicNormalize.js'
import {
  ARTIST_WEIGHT,
  compareMatches,
  compatibilityScore,
  CONFIDENCE_FLOOR,
  GENRE_WEIGHT,
  isEligibleMatch
} from '../lib/musicScore.js'

// Verified against private.normalize_music_name on the database: each input
// produced exactly this key. Written as escapes so the file stays ASCII and
// no invisible bidi mark can drift into a fixture. Re-run these through the
// database whenever the folding rules change.
const NORMALIZATION_FIXTURES = [
  ['Radiohead', 'radiohead'],
  ['  RADIO  head!! ', 'radio head'],
  ['Sigur R\u00F3s', 'sigur ros'],
  ['sigur ros', 'sigur ros'],
  ['Beyonc\u00E9', 'beyonce'],
  ['AC/DC', 'ac dc'],
  ['\u0641\u064A\u0631\u0648\u0632', '\u0641\u064A\u0631\u0648\u0632'],
  ['\u0641\u064A\u0640\u0640\u0631\u0648\u0632', '\u0641\u064A\u0631\u0648\u0632'],
  ['\u0639\u064E\u0645\u0652\u0631\u0648 \u062F\u064A\u0627\u0628', '\u0639\u0645\u0631\u0648 \u062F\u064A\u0627\u0628'],
  ['\u0639\u0645\u0631\u0648 \u062F\u064A\u0627\u0628', '\u0639\u0645\u0631\u0648 \u062F\u064A\u0627\u0628'],
  ['\u0623\u0645 \u0643\u0644\u062B\u0648\u0645', '\u0627\u0645 \u0643\u0644\u062B\u0648\u0645'],
  ['\u0627\u0645 \u0643\u0644\u062B\u0648\u0645', '\u0627\u0645 \u0643\u0644\u062B\u0648\u0645'],
  ['\u0645\u0635\u0637\u0641\u0649', '\u0645\u0635\u0637\u0641\u064A'],
  ['\u0645\u0635\u0637\u0641\u064A', '\u0645\u0635\u0637\u0641\u064A'],
  ['!!!', null],
  ['   ', null],
  ['', null]
]

test('music name normalization matches the database on every fixture', () => {
  for (const [input, expected] of NORMALIZATION_FIXTURES) {
    assert.equal(normalizeMusicName(input), expected, `input: ${JSON.stringify(input)}`)
  }
})

test('the variants that would create duplicate artists all collapse', () => {
  // Capitalisation, whitespace, punctuation, Latin accents, Arabic tatweel,
  // diacritics, hamza forms and alef maksura.
  const pairs = [
    ['Radiohead', 'radiohead'],
    ['Sigur R\u00F3s', 'Sigur Ros'],
    ['\u0641\u064A\u0631\u0648\u0632', '\u0641\u064A\u0640\u0640\u0631\u0648\u0632'],
    ['\u0639\u064E\u0645\u0652\u0631\u0648 \u062F\u064A\u0627\u0628', '\u0639\u0645\u0631\u0648 \u062F\u064A\u0627\u0628'],
    ['\u0623\u0645 \u0643\u0644\u062B\u0648\u0645', '\u0627\u0645 \u0643\u0644\u062B\u0648\u0645'],
    ['\u0645\u0635\u0637\u0641\u0649', '\u0645\u0635\u0637\u0641\u064A'],
    ['The Beatles!', 'the beatles'],
    ['  RADIO  head!! ', 'Radio Head']
  ]
  for (const [left, right] of pairs) {
    assert.equal(isSameMusicName(left, right), true, `${left} vs ${right}`)
  }

  // Genuinely different names must not collapse.
  assert.equal(isSameMusicName('Radiohead', 'Radio Head'), false)
  assert.equal(isSameMusicName('!!!', '???'), false)
})

test('normalization never throws on hostile or empty input', () => {
  for (const input of [null, undefined, '', '   ', '<script>alert(1)</script>']) {
    assert.doesNotThrow(() => normalizeMusicName(input))
  }
  assert.equal(normalizeMusicName('<script>alert(1)</script>'), 'script alert 1 script')
})

test('compatibility reproduces the scores the database returned', () => {
  // The staging fixtures: the viewer listed 3 artists and 3 genres.
  // BBBB shares 2 artists and 2 genres out of a 2/2 profile -> 100.
  assert.equal(
    compatibilityScore({ sharedArtists: 2, sharedGenres: 2, myArtists: 3, myGenres: 3, theirArtists: 2, theirGenres: 2 }),
    100
  )
  // CCCC shares 1 artist and no genres out of a 1/1 profile -> 38.
  assert.equal(
    compatibilityScore({ sharedArtists: 1, sharedGenres: 0, myArtists: 3, myGenres: 3, theirArtists: 1, theirGenres: 1 }),
    38
  )
})

test('a single weak match can never read as a strong one', () => {
  const oneGenre = compatibilityScore({
    sharedArtists: 0, sharedGenres: 1, myArtists: 0, myGenres: 1, theirArtists: 0, theirGenres: 1
  })
  assert.equal(oneGenre, 17)

  const oneArtist = compatibilityScore({
    sharedArtists: 1, sharedGenres: 0, myArtists: 1, myGenres: 0, theirArtists: 1, theirGenres: 0
  })
  assert.equal(oneArtist, 50)

  // Reaching 100 takes at least the confidence floor worth of evidence.
  assert.equal(ARTIST_WEIGHT * 2, CONFIDENCE_FLOOR)
  assert.equal(
    compatibilityScore({ sharedArtists: 2, sharedGenres: 0, myArtists: 2, myGenres: 0, theirArtists: 2, theirGenres: 0 }),
    100
  )
})

test('an artist match outweighs a genre match', () => {
  assert.equal(ARTIST_WEIGHT > GENRE_WEIGHT, true)
  const withArtist = compatibilityScore({
    sharedArtists: 1, sharedGenres: 0, myArtists: 3, myGenres: 3, theirArtists: 3, theirGenres: 3
  })
  const withGenre = compatibilityScore({
    sharedArtists: 0, sharedGenres: 1, myArtists: 3, myGenres: 3, theirArtists: 3, theirGenres: 3
  })
  assert.ok(withArtist > withGenre, `${withArtist} should beat ${withGenre}`)
})

test('an empty profile scores zero instead of dividing by zero', () => {
  assert.equal(compatibilityScore({}), 0)
  assert.equal(
    compatibilityScore({ sharedArtists: 0, sharedGenres: 0, myArtists: 0, myGenres: 0, theirArtists: 0, theirGenres: 0 }),
    0
  )
  // The viewer listed nothing, so there is no ceiling to divide by.
  assert.equal(
    compatibilityScore({ sharedArtists: 3, sharedGenres: 3, myArtists: 0, myGenres: 0, theirArtists: 5, theirGenres: 5 }),
    0
  )
  assert.ok(Number.isFinite(compatibilityScore({ sharedArtists: 1, myArtists: 1, theirArtists: 1 })))
})

test('the score never exceeds 100 however lopsided the profiles are', () => {
  for (let shared = 1; shared <= 30; shared += 1) {
    const score = compatibilityScore({
      sharedArtists: shared,
      sharedGenres: shared,
      myArtists: shared,
      myGenres: shared,
      theirArtists: shared * 4,
      theirGenres: shared * 4
    })
    assert.ok(score >= 0 && score <= 100, `score ${score} out of range at shared=${shared}`)
  }
})

test('a pair needs one shared artist or two shared genres to be listed', () => {
  assert.equal(isEligibleMatch({ sharedArtists: 1, sharedGenres: 0 }), true)
  assert.equal(isEligibleMatch({ sharedArtists: 0, sharedGenres: 2 }), true)
  assert.equal(isEligibleMatch({ sharedArtists: 0, sharedGenres: 1 }), false)
  assert.equal(isEligibleMatch({ sharedArtists: 0, sharedGenres: 0 }), false)
})

test('ordering is deterministic down to the public code', () => {
  const rows = [
    { publicCode: 'BBBB', compatibility: 50, sharedArtistCount: 1, sharedGenreCount: 0 },
    { publicCode: 'AAAA', compatibility: 50, sharedArtistCount: 1, sharedGenreCount: 0 },
    { publicCode: 'CCCC', compatibility: 90, sharedArtistCount: 3, sharedGenreCount: 1 },
    { publicCode: 'DDDD', compatibility: 50, sharedArtistCount: 2, sharedGenreCount: 0 }
  ]
  const order = [...rows].sort(compareMatches).map(row => row.publicCode)
  assert.deepEqual(order, ['CCCC', 'DDDD', 'AAAA', 'BBBB'])

  // Sorting a reversed input yields the same order: no tie depends on input
  // order, so a page boundary cannot drop or repeat a result.
  const reversed = [...rows].reverse().sort(compareMatches).map(row => row.publicCode)
  assert.deepEqual(reversed, order)
})
