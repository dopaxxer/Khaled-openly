import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { getPublicOrigin, safeInternalPath } from '../lib/publicOrigin.js'
import { isStrongPassword, isValidEmail, identitySearchNeedle, parseCursor, readJson } from '../lib/validation.js'
import { fetchViewer } from '../lib/viewer.js'

test('public origin ignores an untrusted request host', () => {
  const request = new Request('https://attacker.example/api/auth/register')
  assert.equal(getPublicOrigin(request, { NODE_ENV: 'production' }), 'https://openly.ink')
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

test('identity search strips ILIKE wildcards before they reach Postgres', () => {
  assert.equal(identitySearchNeedle('%'), '')
  assert.equal(identitySearchNeedle('_abc'), 'ABC')
  assert.equal(identitySearchNeedle('k7m2'), 'K7M2')
  assert.equal(identitySearchNeedle('@@K7M2!!'), 'K7M2')
  assert.equal(identitySearchNeedle('abcdefghijk'), 'ABCDEFGH')
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

test('a server render never issues a relative viewer request', async () => {
  assert.equal(await fetchViewer(), null)
})

test('a JSON body with no declared length is read, not discarded', async () => {
  // `Number(null)` is 0, so an absent Content-Length used to read as a
  // zero-length body: a chunked or streamed request lost every field it sent
  // and the route rejected it for input the caller had actually supplied.
  const body = JSON.stringify({ publicCode: 'ABCD', enabled: true })
  const request = new Request('https://openly.ink/api/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(body))
        controller.close()
      }
    }),
    duplex: 'half'
  })

  assert.equal(request.headers.get('content-length'), null, 'a streamed body declares no length')
  assert.deepEqual(await readJson(request), { data: { publicCode: 'ABCD', enabled: true } })
})

test('an undeclared body over the cap is still refused', async () => {
  const oversized = JSON.stringify({ body: 'x'.repeat(4096) })
  const request = new Request('https://openly.ink/api/posts', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(oversized))
        controller.close()
      }
    }),
    duplex: 'half'
  })

  assert.equal((await readJson(request, 1024)).status, 413)
})

test('CSP permits Apple previews without weakening script-src', () => {
  const source = readFileSync(new URL('../proxy.js', import.meta.url), 'utf8')
  assert.match(source, /"media-src 'self' https:\/\/\*\.mzstatic\.com"/)

  const scriptDirective = source.match(/`script-src[^`]+`/)?.[0]
  assert.ok(scriptDirective, 'script-src directive is present')
  assert.doesNotMatch(scriptDirective, /unsafe-inline/)
})

test('no Supabase project is hardcoded as a fallback', () => {
  // A hardcoded fallback let a deployment with an unset variable authenticate
  // people against a project this account does not own: accounts looked
  // deleted and correct passwords were rejected. Missing configuration has to
  // fail, not resolve to somebody else's database.
  for (const name of ['lib/supabaseEnv.js', 'lib/supabase.js', 'proxy.js']) {
    const source = readFileSync(new URL(`../${name}`, import.meta.url), 'utf8')
    assert.doesNotMatch(source, /https:\/\/[a-z]{20}\.supabase\.co/, `${name} names a Supabase project`)
    assert.doesNotMatch(source, /sb_publishable_[A-Za-z0-9_-]+/, `${name} carries a publishable key`)
  }

  const env = readFileSync(new URL('../lib/supabaseEnv.js', import.meta.url), 'utf8')
  assert.match(env, /throw new Error/, 'missing configuration must throw')
})


// vercel.json used to pin the canonical Supabase project, and a test asserted
// it. The file is gone with Vercel, but the invariant it protected is not: a
// deployment pointed at a different project signs people up and stores their
// posts in a database nobody here controls, while every existing account looks
// deleted. The README is where that value lives now.
test('the canonical Supabase project stays documented', () => {
  const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8')

  assert.match(readme, /https:\/\/egwhybfcnlzijomgeebj\.supabase\.co/)
  assert.match(readme, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/)
})

// Documentation is not configuration. NEXT_PUBLIC_* are inlined at build time,
// so a build that cannot see them ships a bundle with an empty Supabase URL --
// and because lib/supabaseEnv.js refuses to guess, every single request then
// answers Internal Server Error. That is exactly what the first successful
// Cloudflare deploy did. The values have to be committed, not just written down.
test('the production build pins the canonical Supabase project', () => {
  const env = readFileSync(new URL('../.env.production', import.meta.url), 'utf8')

  assert.match(env, /^NEXT_PUBLIC_SITE_URL=https:\/\/openly\.ink$/m)
  assert.match(env, /^NEXT_PUBLIC_SUPABASE_URL=https:\/\/egwhybfcnlzijomgeebj\.supabase\.co$/m)
  assert.match(env, /^NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_[A-Za-z0-9_-]+$/m)

  // Only publishable values belong in a committed file: the service_role key
  // bypasses every row-level security policy in the database. Checked against
  // the assignments alone, since the comments name what must never be here.
  const assignments = env
    .split('\n')
    .filter(line => line.trim() && !line.trim().startsWith('#'))

  assert.ok(assignments.length >= 3, `expected the three build variables, found ${assignments.length}`)
  for (const line of assignments) {
    assert.match(line, /^NEXT_PUBLIC_[A-Z_]+=/, `not a public build variable: ${line}`)
    assert.doesNotMatch(line, /service_role/i, `service_role key committed: ${line}`)
  }
})

// The proxy runs on every route. If it throws when configuration is missing,
// /api/health -- the one endpoint that can name what is missing -- dies with it,
// and the whole site is a blank error with no way in.
test('a misconfigured deployment can still report why', () => {
  const source = readFileSync(new URL('../proxy.js', import.meta.url), 'utf8')
  const body = source.slice(source.indexOf('export async function proxy'))

  assert.match(body, /try\s*\{/, 'the session refresh must not take the request down with it')
  assert.match(body, /catch/)
  assert.match(body, /proxy\.session_refresh_skipped/, 'the skipped refresh must be recorded')
})


test('retired Netlify environment URLs do not become trusted auth origins', () => {
  const request = { url: 'https://old-preview.netlify.app/login' }
  assert.equal(getPublicOrigin(request, {
    NODE_ENV: 'production',
    URL: 'https://old-preview.netlify.app',
    DEPLOY_PRIME_URL: 'https://old-preview.netlify.app',
    DEPLOY_URL: 'https://old-preview.netlify.app'
  }), 'https://openly.ink')
})
