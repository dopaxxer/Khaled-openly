import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { classifyAppRoute } from '../lib/appRoutes.js'

const uuid = '123e4567-e89b-42d3-a456-426614174000'

test('the catch-all accepts only known application routes', () => {
  assert.equal(classifyAppRoute(['login']).kind, 'private')
  assert.equal(classifyAppRoute(['discover']).kind, 'private')
  assert.equal(classifyAppRoute(['interests']).kind, 'private')
  assert.equal(classifyAppRoute(['onboarding', 'interests']).kind, 'private')
  assert.equal(classifyAppRoute(['discover', 'music']).kind, 'private')
  assert.equal(classifyAppRoute(['anything', 'else']), null)
  assert.equal(classifyAppRoute(['robots.txt']), null)
  assert.equal(classifyAppRoute(['sitemap.xml']), null)
})

test('public identity routes normalize and validate identity codes', () => {
  assert.deepEqual(classifyAppRoute(['u', 'ab23']), {
    kind: 'user',
    code: 'AB23',
    path: '/u/AB23'
  })
  assert.equal(classifyAppRoute(['u', 'IL01']), null)
  assert.equal(classifyAppRoute(['u', 'ABC']), null)
})

test('post and report routes require UUIDs', () => {
  assert.equal(classifyAppRoute(['post', uuid]).kind, 'post')
  assert.equal(classifyAppRoute(['post', 'not-a-post']), null)
  assert.equal(classifyAppRoute(['report', 'post', uuid]).kind, 'private')
  assert.equal(classifyAppRoute(['report', 'user', uuid]), null)
})

// The origin the native app really ships with comes from project.yml, which
// XcodeGen writes into Info.plist -- not from the Swift fallback. Checking only
// the Swift file is how a build pointed at a different host once reached main
// with this test still green.
test('production clients use the branded canonical origin', () => {
  const ios = readFileSync(new URL('../ios/Openly/APIClient.swift', import.meta.url), 'utf8')
  const projectYml = readFileSync(new URL('../ios/project.yml', import.meta.url), 'utf8')
  const env = readFileSync(new URL('../.env.example', import.meta.url), 'utf8')
  const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8')
  const publicOrigin = readFileSync(new URL('../lib/publicOrigin.js', import.meta.url), 'utf8')

  assert.match(projectYml, /^\s*OPENLY_API_BASE_URL: "https:\/\/openly\.ink\/api\/"$/m)
  assert.match(ios, /static let canonicalOrigin = "https:\/\/openly\.ink"/)
  assert.match(publicOrigin, /export const CANONICAL_ORIGIN = 'https:\/\/openly\.ink'/)
  assert.match(env, /^NEXT_PUBLIC_SITE_URL=https:\/\/openly\.ink$/m)

  assert.doesNotMatch(
    `${ios}\n${projectYml}\n${env}\n${readme}`,
    /khaled-openly\.vercel\.app/
  )
})

// One origin, written once per platform. A second literal is how the web and
// the native app drift apart without any test noticing.
test('the native origin is not duplicated across the Swift client', () => {
  const ios = readFileSync(new URL('../ios/Openly/APIClient.swift', import.meta.url), 'utf8')
  const literals = ios.match(/"https:\/\/[^"]+"/g) || []

  assert.deepEqual(
    literals,
    ['"https://openly.ink"'],
    `the Swift client should name exactly one origin, found: ${literals.join(' | ')}`
  )
})
