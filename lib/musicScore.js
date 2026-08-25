// The compatibility formula used by Music Discovery.
//
// private.discover_music_people computes the score in SQL so that ranking and
// pagination stay in the database. This module is the same formula written
// once in JavaScript: it is the executable specification the unit tests check,
// and the reference the documentation points at. Both are kept in step by the
// shared fixtures in test/music.test.js.

export const ARTIST_WEIGHT = 3
export const GENRE_WEIGHT = 1

// Raw score at which a match is considered fully evidenced. Below it the score
// is scaled down, so one thin overlap cannot read as a strong match: a single
// shared genre tops out at 17% and a single shared artist at 50%.
export const CONFIDENCE_FLOOR = 6

// A pair is only worth showing at all with at least one shared artist or two
// shared genres.
export const MIN_SHARED_ARTISTS = 1
export const MIN_SHARED_GENRES = 2

export function isEligibleMatch({ sharedArtists = 0, sharedGenres = 0 }) {
  return sharedArtists >= MIN_SHARED_ARTISTS || sharedGenres >= MIN_SHARED_GENRES
}

/**
 * compatibility = round(100 x overlap x confidence) where
 *
 *   raw        = 3 x sharedArtists + 1 x sharedGenres
 *   ceiling    = 3 x min(myArtists, theirArtists) + 1 x min(myGenres, theirGenres)
 *   overlap    = ceiling <= 0 ? 0 : min(1, raw / ceiling)
 *   confidence = min(1, raw / 6)
 *
 * `ceiling` is the best score this pair could have scored given how short the
 * shorter list is, which keeps a five-artist profile from being penalised for
 * matching someone who only listed two. It is guarded against zero, so a user
 * with no preferences at all scores 0 rather than dividing by nothing.
 */
export function compatibilityScore({
  sharedArtists = 0,
  sharedGenres = 0,
  myArtists = 0,
  myGenres = 0,
  theirArtists = 0,
  theirGenres = 0
} = {}) {
  const raw = ARTIST_WEIGHT * sharedArtists + GENRE_WEIGHT * sharedGenres
  const ceiling =
    ARTIST_WEIGHT * Math.min(myArtists, theirArtists) +
    GENRE_WEIGHT * Math.min(myGenres, theirGenres)

  if (ceiling <= 0 || raw <= 0) return 0

  const overlap = Math.min(1, raw / ceiling)
  const confidence = Math.min(1, raw / CONFIDENCE_FLOOR)
  return Math.round(100 * overlap * confidence)
}

/**
 * Deterministic ordering: compatibility, then shared artists, then shared
 * genres, then public code. Ties never depend on row order, so a page boundary
 * cannot drop or repeat a result.
 */
export function compareMatches(a, b) {
  return (
    (b.compatibility ?? 0) - (a.compatibility ?? 0) ||
    (b.sharedArtistCount ?? 0) - (a.sharedArtistCount ?? 0) ||
    (b.sharedGenreCount ?? 0) - (a.sharedGenreCount ?? 0) ||
    String(a.publicCode || '').localeCompare(String(b.publicCode || ''))
  )
}
