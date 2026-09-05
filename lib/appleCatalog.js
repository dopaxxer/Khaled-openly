// The single HTTP door to Apple's iTunes catalog, shared by the music and
// interest catalogs so both behave identically against it.
//
// Two things here are load-bearing on Cloudflare Workers:
//
// 1. `User-Agent`. Workers send no default one, unlike Node, and iTunes rejects
//    an anonymous client outright. That is why catalog search worked in local
//    and Node-hosted builds and answered 502 within ~200ms on the Worker.
// 2. No `RequestInit.cache`. Workers reject unsupported cache modes depending
//    on the deployed compatibility date. Each catalog keeps its own bounded TTL
//    cache instead.

const CATALOG_USER_AGENT = 'Openly/1.0 (+https://openly.ink)'

/**
 * Fetches one Apple catalog URL and returns its `results` array.
 *
 * A non-2xx answer throws with the upstream status attached, so `logError`
 * records which status Apple actually returned rather than a bare failure. A
 * short slice of the body rides along: Apple explains a refusal in the body,
 * and without it a 403 for a blocked client and a 403 for a malformed query
 * look the same in the logs.
 */
export async function fetchAppleCatalog(url, signal) {
  const response = await fetch(url, {
    signal,
    headers: {
      Accept: 'application/json',
      'User-Agent': CATALOG_USER_AGENT
    }
  })

  if (!response.ok) {
    const error = new Error(`Apple catalog returned ${response.status}`)
    error.status = response.status
    error.details = (await response.text().catch(() => '')).slice(0, 200) || undefined
    throw error
  }

  const payload = await response.json()
  if (!Array.isArray(payload?.results)) {
    throw new Error('Apple catalog returned an invalid results payload')
  }
  return payload.results
}

export { CATALOG_USER_AGENT }
