import assert from 'node:assert/strict'
import test from 'node:test'
import { fetchAppleCatalog } from '../lib/appleCatalog.js'
import { searchAppleTracks } from '../lib/musicCatalog.js'
import { searchAppleInterests } from '../lib/interestCatalog.js'

function stubFetch(handler) {
  const original = globalThis.fetch
  const calls = []
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init })
    return handler(url, init)
  }
  return { calls, restore: () => { globalThis.fetch = original } }
}

const jsonResponse = body => new Response(JSON.stringify(body), {
  status: 200,
  headers: { 'content-type': 'application/json' }
})

// Cloudflare Workers send no User-Agent unless one is set, and iTunes refuses
// an anonymous client. That is the whole reason catalog search answered 502 on
// the Worker while working everywhere else, so it is asserted rather than
// trusted to survive the next edit.
test('every Apple catalog request identifies itself', async () => {
  const stub = stubFetch(() => jsonResponse({ results: [] }))
  try {
    await fetchAppleCatalog(new URL('https://itunes.apple.com/search?term=x'))

    const [{ init }] = stub.calls
    assert.equal(init.headers['User-Agent'], 'Openly/1.0 (+https://openly.ink)')
    assert.equal(init.headers.Accept, 'application/json')
  } finally {
    stub.restore()
  }
})

test('both catalogs go through the shared fetch, so both send the header', async () => {
  const stub = stubFetch(() => jsonResponse({ results: [] }))
  try {
    await searchAppleTracks('test song')
    await searchAppleInterests('test book', 'book')

    assert.equal(stub.calls.length, 2, 'each catalog should make one request')
    for (const { init } of stub.calls) {
      assert.equal(init.headers['User-Agent'], 'Openly/1.0 (+https://openly.ink)')
    }
  } finally {
    stub.restore()
  }
})

// A bare "request failed" in the logs cannot distinguish a blocked client from
// a malformed query. The upstream status and its explanation must survive.
test('an upstream refusal carries its status and reason', async () => {
  const stub = stubFetch(() => new Response('Forbidden: blocked client', { status: 403 }))
  try {
    await assert.rejects(
      () => fetchAppleCatalog(new URL('https://itunes.apple.com/search?term=x')),
      error => {
        assert.equal(error.status, 403)
        assert.match(error.message, /403/)
        assert.match(error.details, /Forbidden/)
        return true
      }
    )
  } finally {
    stub.restore()
  }
})

// RequestInit.cache is rejected by Workers on some compatibility dates, and
// each catalog keeps its own TTL cache instead.
test('the catalog never passes a fetch cache mode', async () => {
  const stub = stubFetch(() => jsonResponse({ results: [] }))
  try {
    await fetchAppleCatalog(new URL('https://itunes.apple.com/search?term=x'))
    assert.equal('cache' in stub.calls[0].init, false)
  } finally {
    stub.restore()
  }
})
