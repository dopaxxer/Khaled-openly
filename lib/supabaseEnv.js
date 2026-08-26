/**
 * The Supabase project this deployment talks to.
 *
 * There used to be a hardcoded project here as a fallback, so a missing
 * environment variable would not stop a deployment from booting. That turned
 * out to be the worst possible failure mode: the fallback named a project
 * outside this account, so a deployment with an unset variable silently signed
 * people up, mailed them and stored their posts in a database nobody here
 * controls — while every existing account looked deleted and every correct
 * password was rejected.
 *
 * A deployment that cannot name its own database must not serve traffic. The
 * check is deliberately lazy rather than at import time: a build does not need
 * credentials, so CI still builds, while the first request on a misconfigured
 * deployment fails loudly with the variable named. `supabaseConnection` never
 * throws, so `/api/health` can report the misconfiguration instead of dying
 * with it.
 *
 * Kept free of imports so the edge middleware can use it too.
 */

const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || ''
const rawKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  ''

function required(name, value) {
  const trimmed = String(value || '').trim()
  if (trimmed) return trimmed
  throw new Error(
    `[openly] ${name} is not set. Set it on the hosting platform (Vercel → Settings → ` +
    'Environment Variables) to the Supabase project this deployment owns, then redeploy. ' +
    'Refusing to serve rather than connecting to an unknown database. See /api/health.'
  )
}

export function supabaseUrl() {
  return required('NEXT_PUBLIC_SUPABASE_URL', rawUrl)
}

export function supabaseKey() {
  return required('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', rawKey)
}

/**
 * Which project is in use, for `/api/health`. Never throws — reporting that
 * the configuration is missing is the whole point of the endpoint.
 *
 * The ref is already public: the browser sends it on every request. No key
 * material is returned, only whether a key is present at all.
 */
export function supabaseConnection() {
  let projectRef = null
  try {
    projectRef = rawUrl ? new URL(rawUrl).hostname.split('.')[0] || null : null
  } catch {
    projectRef = null
  }
  return {
    projectRef,
    configured: !!rawUrl && !!rawKey,
    hasUrl: !!rawUrl,
    hasKey: !!rawKey,
    siteUrl: process.env.NEXT_PUBLIC_SITE_URL || null
  }
}
