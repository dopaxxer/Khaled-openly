import assert from 'node:assert/strict'
import test from 'node:test'

test('session changes isolate cached and in-flight viewer requests', async t => {
  t.mock.method(globalThis, 'fetch', () => new Promise(resolve => pending.push(resolve)))
  const previousWindow = globalThis.window
  globalThis.window = new EventTarget()
  t.after(() => {
    if (previousWindow === undefined) delete globalThis.window
    else globalThis.window = previousWindow
  })
  const pending = []
  const { fetchViewer, forgetViewer } = await import('../lib/viewer.js')
  const reply = user => ({ ok: true, json: async () => ({ user }) })

  const beforeLogout = fetchViewer()
  globalThis.window.dispatchEvent(new Event('openly:auth-changed'))
  const afterLogout = fetchViewer()
  pending[1](reply(null))
  await afterLogout
  pending[0](reply({ publicCode: 'OLD2' }))
  assert.equal(await beforeLogout, null, 'waiting components must not receive the previous identity')
  assert.equal(await fetchViewer(), null, 'old response must not restore a signed-out identity')

  forgetViewer()
  const older = fetchViewer()
  const newer = fetchViewer({ force: true })
  pending[2](reply({ publicCode: 'OLD2' }))
  await new Promise(resolve => setImmediate(resolve))
  const shared = fetchViewer()
  assert.equal(pending.length, 4, 'an old completion must not discard the newer shared request')
  pending[3](reply({ publicCode: 'NEW2' }))
  assert.deepEqual(await older, { publicCode: 'NEW2' })
  assert.deepEqual(await newer, { publicCode: 'NEW2' })
  assert.deepEqual(await shared, { publicCode: 'NEW2' })
  assert.deepEqual(await fetchViewer(), { publicCode: 'NEW2' })
})
