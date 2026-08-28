// A small fixed-window limiter for the search, autocomplete and mutation
// endpoints.
//
// Scope and honesty about it: this counts inside one server instance. On
// Vercel a burst spread across several lambdas gets a proportionally higher
// effective ceiling, so treat it as abuse damping — enough to stop a single
// client from walking the identity space through the autocomplete endpoint —
// not as a hard quota. The real authorization boundaries are the RLS policies
// and the definer functions; this only limits volume.

const buckets = new Map()

// Bounded so a flood of distinct keys cannot grow the map without limit.
const MAX_TRACKED_KEYS = 5000

function sweep(now) {
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key)
  }
}

/**
 * Records a hit for `key` and reports whether it is allowed.
 * Returns { allowed, remaining, retryAfterSeconds }.
 */
export function consumeRateLimit(key, { limit, windowMs }) {
  const now = Date.now()
  const bucket = buckets.get(key)

  if (!bucket || bucket.resetAt <= now) {
    if (buckets.size >= MAX_TRACKED_KEYS) sweep(now)
    buckets.set(key, { count: 1, resetAt: now + windowMs })
    return { allowed: true, remaining: limit - 1, retryAfterSeconds: 0 }
  }

  bucket.count += 1
  const retryAfterSeconds = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000))
  if (bucket.count > limit) {
    return { allowed: false, remaining: 0, retryAfterSeconds }
  }
  return { allowed: true, remaining: limit - bucket.count, retryAfterSeconds }
}

/**
 * Identifies the caller for limiting. A signed-in user is limited by their own
 * id so that one abusive account cannot spend a shared NAT's budget; anonymous
 * callers fall back to the forwarded address.
 */
export function rateLimitKey(request, scope, userId) {
  if (userId) return `${scope}:user:${userId}`
  const forwarded = String(request.headers.get('x-forwarded-for') || '')
  const address = forwarded.split(',')[0].trim() || 'unknown'
  return `${scope}:ip:${address}`
}

// Per-scope budgets. Reads are generous enough for keystroke-driven
// autocomplete; writes are tight enough that mention or artist spam is not
// practical.
export const RATE_LIMITS = {
  mentionSuggest: { limit: 60, windowMs: 60_000 },
  mentionResolve: { limit: 60, windowMs: 60_000 },
  musicSearch: { limit: 90, windowMs: 60_000 },
  musicCatalogSearch: { limit: 20, windowMs: 60_000 },
  musicDiscovery: { limit: 40, windowMs: 60_000 },
  musicRead: { limit: 60, windowMs: 60_000 },
  musicWrite: { limit: 30, windowMs: 60_000 },
  artistCreate: { limit: 10, windowMs: 60_000 },
  interestSearch: { limit: 60, windowMs: 60_000 },
  interestCatalogSearch: { limit: 20, windowMs: 60_000 },
  interestDiscovery: { limit: 40, windowMs: 60_000 },
  interestRead: { limit: 60, windowMs: 60_000 },
  interestWrite: { limit: 30, windowMs: 60_000 },
  messageRead: { limit: 120, windowMs: 60_000 },
  messageWrite: { limit: 40, windowMs: 60_000 }
}

/** Clears all counters. Test-only. */
export function resetRateLimits() {
  buckets.clear()
}
