import assert from 'node:assert/strict'
import test from 'node:test'
import { formatRelativeTime } from '../lib/relativeTime.js'

const now = Date.parse('2026-09-04T12:00:00.000Z')

test('notification age uses useful units instead of an ever-growing minute count', () => {
  assert.equal(formatRelativeTime('2026-09-04T11:55:00.000Z', 'en', now), '5 minutes ago')
  assert.equal(formatRelativeTime('2026-09-04T10:00:00.000Z', 'en', now), '2 hours ago')
  assert.equal(formatRelativeTime('2026-09-01T12:00:00.000Z', 'en', now), '3 days ago')
})

test('notification age follows the selected interface language', () => {
  const arabic = formatRelativeTime('2026-09-04T11:55:00.000Z', 'ar', now)
  assert.match(arabic, /قبل/)
  assert.doesNotMatch(arabic, /ago|minute/i)
  assert.equal(formatRelativeTime('2026-09-04T11:59:45.000Z', 'en', now), 'now')
  assert.equal(formatRelativeTime('not-a-date', 'ar', now), '')
})
