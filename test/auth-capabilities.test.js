import assert from 'node:assert/strict'
import test from 'node:test'
import { mapAuthCapabilities, SAFE_AUTH_CAPABILITIES } from '../lib/authCapabilities.js'

test('auth capabilities fail closed for external providers', () => {
  assert.equal(SAFE_AUTH_CAPABILITIES.google, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.apple, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.phone, false)
  assert.equal(SAFE_AUTH_CAPABILITIES.emailOtp, false)
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
