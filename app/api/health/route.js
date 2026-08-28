import { NextResponse } from 'next/server'
import { supabaseConnection } from '@/lib/supabaseEnv'

export const dynamic = 'force-dynamic'

/**
 * Which Supabase project is this deployment actually talking to?
 *
 * A deployment whose `NEXT_PUBLIC_SUPABASE_URL` is unset used to fall back to a
 * hardcoded project, so it could authenticate people against a database this
 * account does not own — accounts then look deleted and a correct password is
 * rejected. The fallback is gone, but the question "which project is this?"
 * still had no answer from outside. Now it does.
 *
 * Only the project ref is exposed; it is already public, since the browser
 * sends it on every request. Key material is never returned — only whether a
 * key is present.
 */
export async function GET() {
  const { projectRef, configured, hasUrl, hasKey, siteUrl } = supabaseConnection()

  return NextResponse.json(
    {
      ok: configured,
      supabase: { projectRef, configured, hasUrl, hasKey },
      siteUrl,
      // Cloudflare Workers Builds names, replacing the Vercel ones this used to
      // read. Both are build-time values, so they are only reported if the
      // project forwards them; unset simply reads as null, as before.
      commit: process.env.WORKERS_CI_COMMIT_SHA || null,
      branch: process.env.WORKERS_CI_BRANCH || null,
      environment: process.env.NODE_ENV || null
    },
    {
      status: configured ? 200 : 503,
      headers: { 'Cache-Control': 'private, no-store, max-age=0' }
    }
  )
}
