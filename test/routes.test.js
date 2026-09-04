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

test('production clients use approved Cloudflare origins', () => {
  const ios = readFileSync(new URL('../ios/Openly/APIClient.swift', import.meta.url), 'utf8')
  const iosProject = readFileSync(new URL('../ios/project.yml', import.meta.url), 'utf8')
  const env = readFileSync(new URL('../.env.example', import.meta.url), 'utf8')
  const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8')

  assert.match(ios, /https:\/\/openly\.nootjetzt\.workers\.dev\/api\//)
  assert.match(iosProject, /OPENLY_API_BASE_URL: "https:\/\/openly\.nootjetzt\.workers\.dev\/api\/"/)
  assert.match(env, /^NEXT_PUBLIC_SITE_URL=https:\/\/openly\.ink$/m)
  assert.doesNotMatch(`${ios}\n${iosProject}\n${env}\n${readme}`, /khaled-openly\.vercel\.app/)
})

test('visit deduplication uses one bounded session storage value', () => {
  const tracker = readFileSync(new URL('../components/DeviceVisitTracker.jsx', import.meta.url), 'utf8')

  assert.match(tracker, /openly:recent-device-visits/)
  assert.match(tracker, /MAX_RECENT_VISITS = 32/)
  assert.doesNotMatch(tracker, /openly:last-device-visit:\$\{pathname\}/)
})

test('production metadata reflects the current product', () => {
  const layout = readFileSync(new URL('../app/layout.jsx', import.meta.url), 'utf8')
  const manifest = readFileSync(new URL('../app/manifest.js', import.meta.url), 'utf8')
  const globalError = readFileSync(new URL('../app/global-error.jsx', import.meta.url), 'utf8')

  assert.doesNotMatch(layout, /بلا رسائل خاصة/)
  assert.match(manifest, /name: 'Openly'/)
  assert.match(globalError, /<html lang="ar" dir="rtl">/)
})
