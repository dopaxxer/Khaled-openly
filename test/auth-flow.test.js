import assert from 'node:assert/strict'
import test from 'node:test'
import { describeAuthError, isValidE164, maskAuthTarget, normalizeE164 } from '../lib/authFlow.js'

test('normalizes and validates E.164 phone numbers', () => {
  assert.equal(normalizeE164('+49 (123) 456-7890'), '+491234567890')
  assert.equal(isValidE164('+491234567890'), true)
  assert.equal(isValidE164('00491234567890'), false)
  assert.equal(isValidE164('+01234567890'), false)
  assert.equal(isValidE164('+49abc'), false)
})

test('masks auth targets without changing delivery value', () => {
  assert.equal(maskAuthTarget('email', 'example@gmail.com'), 'ex•••@gmail.com')
  assert.equal(maskAuthTarget('phone', '+491234567890'), '+49••••890')
})

test('maps rate limit and expired OTP errors to actionable safe messages', () => {
  assert.equal(describeAuthError({ code: 'over_email_send_rate_limit' }).status, 429)
  assert.match(describeAuthError({ code: 'otp_expired' }, 'verify').message, /انتهت/)
  assert.equal(describeAuthError({ code: 'phone_provider_disabled' }).status, 503)
})
