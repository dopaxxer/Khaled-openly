import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { getPublicOrigin, safeInternalPath } from '../lib/publicOrigin.js'
import { isStrongPassword, isValidEmail, parseCursor, readJson } from '../lib/validation.js'

test('public origin ignores an untrusted request host', () => {
  const request = new Request('https://attacker.example/api/auth/register')
  assert.equal(getPublicOrigin(request, { NODE_ENV: 'production' }), 'https://khaled-openly.vercel.app')
})

test('public origin uses only configured deployment origins', () => {
  const request = new Request('https://preview.example/api/auth/register')
  const environment = { NODE_ENV: 'production', VERCEL_URL: 'preview.example' }
  assert.equal(getPublicOrigin(request, environment), 'https://preview.example')
})

test('canonical site URL wins over request headers', () => {
  const request = new Request('https://preview.example/api/auth/register')
  const environment = { NODE_ENV: 'production', NEXT_PUBLIC_SITE_URL: 'https://openly.example/path' }
  assert.equal(getPublicOrigin(request, environment), 'https://openly.example')
})

test('internal redirects reject protocol-relative and newline paths', () => {
  assert.equal(safeInternalPath('/post/123?from=email'), '/post/123?from=email')
  assert.equal(safeInternalPath('//attacker.example'), '/')
  assert.equal(safeInternalPath('/\\attacker.example'), '/')
  assert.equal(safeInternalPath('/safe\r\nLocation: https://attacker.example'), '/')
})

test('cursor parser accepts an ISO timestamp and UUID only', () => {
  const uuid = '123e4567-e89b-42d3-a456-426614174000'
  assert.deepEqual(parseCursor(`2026-08-24T12:00:00.000Z|${uuid}`), {
    createdAt: '2026-08-24T12:00:00.000Z',
    id: uuid
  })
  assert.equal(parseCursor('not-a-date|not-a-uuid'), null)
})

test('account inputs enforce normalized email and strong password rules', () => {
  assert.equal(isValidEmail(' User@Example.com '), true)
  assert.equal(isValidEmail('invalid@example'), false)
  assert.equal(isStrongPassword('عبارة-آمنة-2026'), true)
  assert.equal(isStrongPassword('onlyletterslong'), false)
})

test('bodyless actions accept a zero-length runtime stream', async () => {
  const request = {
    headers: new Headers({ 'content-length': '0' }),
    body: new ReadableStream(),
    text: async () => ''
  }
  assert.deepEqual(await readJson(request), { data: {} })
})

test('CSP permits Apple previews without weakening script-src', () => {
  const source = readFileSync(new URL('../proxy.js', import.meta.url), 'utf8')
  assert.match(source, /"media-src 'self' https:\/\/\*\.mzstatic\.com"/)

  const scriptDirective = source.match(/`script-src[^`]+`/)?.[0]
  assert.ok(scriptDirective, 'script-src directive is present')
  assert.doesNotMatch(scriptDirective, /unsafe-inline/)
})
