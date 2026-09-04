/**
 * One answer to "who is looking at this page?" per navigation.
 *
 * The shell, the composer, the timeline and every screen that offers an owner
 * action all need the viewer's public code, and each of them used to ask
 * `/api/auth/me` itself. On the home page that was three identical requests in
 * the same tick, and each one costs the server a session verification plus a
 * profile read. They now share one in-flight request and its result for a few
 * seconds after it lands.
 *
 * The cache lives in the browser only: this module is imported by client
 * components, but a server render must never reuse one visitor's identity for
 * the next. A relative browser API URL is not valid in Node either, so a
 * server-side call safely answers `null` and lets hydration obtain the viewer.
 */

const TTL_MS = 10_000

let inflight = null
let cachedUser = null
let hasCached = false
let cachedAt = 0

function isBrowser() {
  return typeof window !== 'undefined'
}

async function request(signal) {
  const response = await fetch('/api/auth/me', { cache: 'no-store', signal })
  const data = response.ok ? await response.json() : { user: null }
  return data.user || null
}

/**
 * The signed-in profile, or null. `force` skips the cache -- use it after an
 * action that can change the session.
 */
export async function fetchViewer({ signal, force = false } = {}) {
  if (!isBrowser()) return null

  if (!force) {
    if (inflight) return inflight
    // A signed-out viewer is an answer worth keeping too -- that is the case
    // where the page asks the most often.
    if (hasCached && Date.now() - cachedAt < TTL_MS) return cachedUser
  }

  // An abort belongs to the caller that asked for it, so a shared request is
  // never given a caller's signal: one component unmounting must not cancel
  // the answer the others are waiting for.
  inflight = request()
    .then(user => {
      cachedUser = user
      hasCached = true
      cachedAt = Date.now()
      return user
    })
    .catch(error => {
      cachedUser = null
      hasCached = false
      cachedAt = 0
      throw error
    })
    .finally(() => { inflight = null })

  return inflight
}

/** Drops the cached viewer after a sign-in, sign-out or profile change. */
export function forgetViewer() {
  inflight = null
  cachedUser = null
  hasCached = false
  cachedAt = 0
}

if (isBrowser()) {
  window.addEventListener('openly:auth-changed', forgetViewer)
}
