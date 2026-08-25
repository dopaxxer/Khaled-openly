// Artist/genre name folding, mirroring private.normalize_music_name in
// supabase/migrations/20260824190500_music_taste_profiles.sql and
// MusicSupport.swift.
//
// The database is the authority — it recomputes the key on write and the
// unique index on it is what actually prevents duplicates. This copy exists so
// the clients can preview a match before a round trip and so the rules are
// unit-testable without a database.

// U+0629 -> U+0647 (teh marbuta to heh), U+0649 -> U+064A (alef maksura
// to yeh), U+0671 -> U+0627 (alef wasla to alef). These three do not
// decompose under NFD, unlike the hamza forms whose hamza becomes a
// combining mark that the strip step below removes. Everything here is
// written as escapes because many of these characters are invisible.
const LETTER_FOLDS = [
  [/\u0629/g, '\u0647'],
  [/\u0649/g, '\u064A'],
  [/\u0671/g, '\u0627']
]

// U+0300-U+036F Latin combining marks, U+0610-U+061A, U+064B-U+065F, U+0670,
// U+06D6-U+06ED Arabic marks, and U+0640 tatweel.
const COMBINING_MARKS = /[\u0300-\u036F\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]/g

// Keep Latin letters, digits and the Arabic block; collapse everything else.
const NON_NAME_CHARACTERS = /[^a-z0-9\u0600-\u06FF]+/g

export const ARTIST_NAME_MAX_LENGTH = 80
export const MAX_ARTISTS_PER_PROFILE = 30
export const MAX_GENRES_PER_PROFILE = 15
export const MAX_TRACKS_PER_PROFILE = 12

/** The comparison key for a display name, or null when nothing is left. */
export function normalizeMusicName(value) {
  const lowered = String(value ?? '').trim().toLowerCase()
  if (!lowered) return null

  let folded = lowered.normalize('NFD')
  for (const [pattern, replacement] of LETTER_FOLDS) {
    folded = folded.replace(pattern, replacement)
  }

  const cleaned = folded
    .replace(COMBINING_MARKS, '')
    .replace(NON_NAME_CHARACTERS, ' ')
    .trim()

  return cleaned || null
}

/** True when two display names would collapse to the same catalog entry. */
export function isSameMusicName(left, right) {
  const a = normalizeMusicName(left)
  return a !== null && a === normalizeMusicName(right)
}
