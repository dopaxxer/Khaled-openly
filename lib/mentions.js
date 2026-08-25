// The mention grammar, shared by the composer, the renderer and the API.
//
// It is deliberately identical to private.parse_mention_codes in
// supabase/migrations/20260824190000_user_mentions.sql and to
// MentionSupport.swift, so all three agree on what counts as a mention:
//
//   (^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])
//
// The leading boundary is consumed and the trailing one is a lookahead, which
// is what lets "@AAAA @BBBB" match twice. Lookbehind is avoided on purpose —
// Safari only gained it in 16.4 and this has to work on older mobile Safari.
// The server is still the authority: it re-parses the stored body and resolves
// the codes itself, so nothing here can grant a mention that the database
// would not have created on its own.

export const MENTION_PATTERN = /(^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])/g
export const PUBLIC_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{4,8}$/
export const MENTION_CODE_MIN_LENGTH = 4
export const MENTION_CODE_MAX_LENGTH = 8
export const MAX_MENTIONS_PER_ITEM = 10

export function isPublicCode(value) {
  return PUBLIC_CODE_PATTERN.test(String(value || ''))
}

/**
 * Every distinct, well-formed public code mentioned in `body`, uppercased and
 * in first-appearance order. Codes using the letters the identity alphabet
 * leaves out (I, L, O, 0, 1) are dropped here so they stay plain text instead
 * of turning into a lookup that can never succeed.
 */
export function parseMentionCodes(body, limit = MAX_MENTIONS_PER_ITEM) {
  const text = String(body || '')
  const cap = Math.max(0, Math.min(Number(limit) || 0, 25))
  if (!text || cap === 0) return []

  const codes = []
  const pattern = new RegExp(MENTION_PATTERN.source, 'g')
  let match
  while ((match = pattern.exec(text)) !== null) {
    const code = match[2].toUpperCase()
    if (!PUBLIC_CODE_PATTERN.test(code)) continue
    if (codes.includes(code)) continue
    codes.push(code)
    if (codes.length >= cap) break
  }
  return codes
}

/**
 * Splits a plain-text run into text and mention segments for rendering.
 * `resolvedCodes` is the set the server confirmed exists and is visible; a
 * code outside it is returned as ordinary text, which is how an invalid or
 * deleted mention stays unhighlighted.
 *
 * Returns segments, never markup — the caller builds React elements from
 * them, so there is no HTML-injection surface.
 */
export function splitMentionSegments(text, resolvedCodes) {
  const source = String(text || '')
  if (!source) return []

  const resolved = resolvedCodes instanceof Set
    ? resolvedCodes
    : new Set((resolvedCodes || []).map(value => String(value).toUpperCase()))
  if (resolved.size === 0) return [{ type: 'text', value: source }]

  const segments = []
  const pattern = new RegExp(MENTION_PATTERN.source, 'g')
  let cursor = 0
  let match

  while ((match = pattern.exec(source)) !== null) {
    const [full, boundary, rawCode] = match
    const code = rawCode.toUpperCase()
    if (!resolved.has(code)) continue

    const mentionStart = match.index + boundary.length
    if (mentionStart > cursor) {
      segments.push({ type: 'text', value: source.slice(cursor, mentionStart) })
    }
    segments.push({ type: 'mention', value: `@${rawCode}`, code })
    cursor = match.index + full.length
  }

  if (cursor < source.length) {
    segments.push({ type: 'text', value: source.slice(cursor) })
  }
  return segments
}

/**
 * The token being typed at `caretIndex`, or null when the caret is not inside
 * one. Drives the composer autocomplete. A partial token is allowed to be
 * shorter than a real code so suggestions appear from the first character.
 */
export function activeMentionQuery(value, caretIndex) {
  const text = String(value || '')
  const caret = Math.max(0, Math.min(Number(caretIndex) || 0, text.length))
  const before = text.slice(0, caret)
  const match = before.match(/(^|[^A-Za-z0-9_@])@([A-Za-z0-9]{0,8})$/)
  if (!match) return null

  // Typing past the maximum code length is no longer a mention.
  const next = text.charAt(caret)
  if (next && /[A-Za-z0-9_]/.test(next)) return null

  const query = match[2]
  return {
    query: query.toUpperCase(),
    start: caret - query.length - 1,
    end: caret
  }
}

/** Replaces the token being typed with the canonical `@CODE` form. */
export function applyMentionCompletion(value, range, code) {
  const text = String(value || '')
  const canonical = `@${String(code || '').toUpperCase()}`
  const nextValue = `${text.slice(0, range.start)}${canonical} ${text.slice(range.end)}`
  const caret = range.start + canonical.length + 1
  return { value: nextValue, caret }
}
