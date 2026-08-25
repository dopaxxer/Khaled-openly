import assert from 'node:assert/strict'
import test from 'node:test'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey, resetRateLimits } from '../lib/rateLimit.js'

test('a bucket allows exactly its limit then refuses', () => {
  resetRateLimits()
  const options = { limit: 3, windowMs: 60_000 }
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    assert.equal(consumeRateLimit('scope:test', options).allowed, true, `attempt ${attempt}`)
  }
  const refused = consumeRateLimit('scope:test', options)
  assert.equal(refused.allowed, false)
  assert.ok(refused.retryAfterSeconds >= 1, 'a refusal must tell the caller when to retry')
})

test('buckets are per key, so one caller cannot exhaust another', () => {
  resetRateLimits()
  const options = { limit: 1, windowMs: 60_000 }
  assert.equal(consumeRateLimit('scope:user:a', options).allowed, true)
  assert.equal(consumeRateLimit('scope:user:a', options).allowed, false)
  assert.equal(consumeRateLimit('scope:user:b', options).allowed, true)
})

test('a window that has elapsed starts a fresh allowance', () => {
  resetRateLimits()
  const options = { limit: 1, windowMs: 1 }
  assert.equal(consumeRateLimit('scope:expiring', options).allowed, true)
  assert.equal(consumeRateLimit('scope:expiring', options).allowed, false)

  const later = Date.now() + 5
  while (Date.now() < later) { /* let the 1ms window lapse */ }
  assert.equal(consumeRateLimit('scope:expiring', options).allowed, true)
})

test('a signed-in caller is limited by account, anonymous by address', () => {
  const request = new Request('https://openly.test/api/v1/mentions/suggest', {
    headers: { 'x-forwarded-for': '203.0.113.4, 70.41.3.18' }
  })
  assert.equal(rateLimitKey(request, 'mentionSuggest', 'user-1'), 'mentionSuggest:user:user-1')
  // Only the client-most address is used; the rest of the chain is proxies.
  assert.equal(rateLimitKey(request, 'mentionSuggest', null), 'mentionSuggest:ip:203.0.113.4')

  const bare = new Request('https://openly.test/api/v1/music/genres')
  assert.equal(rateLimitKey(bare, 'musicSearch', null), 'musicSearch:ip:unknown')
})

test('every scope the API uses has a configured budget', () => {
  const scopes = [
    'mentionSuggest',
    'mentionResolve',
    'musicSearch',
    'musicDiscovery',
    'musicRead',
    'musicWrite',
    'artistCreate'
  ]
  for (const scope of scopes) {
    const budget = RATE_LIMITS[scope]
    assert.ok(budget, `${scope} has no budget`)
    assert.ok(budget.limit > 0 && budget.windowMs > 0, `${scope} budget is not positive`)
  }
  // Writes must stay tighter than reads, otherwise the limiter is decorative.
  assert.ok(RATE_LIMITS.artistCreate.limit < RATE_LIMITS.musicSearch.limit)
  assert.ok(RATE_LIMITS.musicWrite.limit < RATE_LIMITS.musicSearch.limit)
})
