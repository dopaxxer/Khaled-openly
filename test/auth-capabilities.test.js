import assert from 'node:assert/strict'
import test from 'node:test'
import { mapAuthCapabilities, SAFE_AUTH_CAPABILITIES } from '../lib/authCapabilities.js'

test('auth capabilities fail closed for external providers', () => {
  assert.equal(SAFE_AUTH_CAPABILITIES.google, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.apple, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.phone, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.emailOtp, false)
})

// /api/auth/capabilities answers with the mapped settings or, when Supabase is
// unreachable, with the safe payload. Both branches are the same endpoint, so a
// client may not have to guess which fields it got.
test('both capability payloads expose the same fields', () => {
  const mapped = mapAuthCapabilities(
    { external: { email: true, phone: true, google: true, apple: true } },
    'otp'
  )

  assert.deepEqual(
    Object.keys(SAFE_AUTH_CAPABILITIES).sort(),
    Object.keys(mapped).sort()
  )
  assert.equal(typeof SAFE_AUTH_CAPABILITIES.emailMode, 'string')
})

test('maps Supabase public auth settings and email delivery mode', () => {
  const settings = {
    external: { email: true, phone: false, google: true, apple: false }
  }

  assert.deepEqual(mapAuthCapabilities(settings, 'link'), {
    email: true,
    emailOtp: false,
    emailMode: 'link',
    phone: false,
    google: true,
    apple: false
  })

  assert.equal(mapAuthCapabilities(settings, 'otp').emailOtp, true)
  assert.equal(mapAuthCapabilities(settings).emailOtp, true)
})
