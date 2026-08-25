import { NextResponse } from 'next/server'
import { supabaseConnection } from '@/lib/supabase'

export const dynamic = 'force-dynamic'

/**
 * Which Supabase project is this deployment actually talking to?
 *
 * `lib/supabase.js` falls back to a hardcoded project when the environment
 * variable is missing, so a deployment can silently authenticate against a
 * different database than the one being administered — accounts then look
 * deleted and sign-in fails with "wrong credentials" for a real password.
 * There was no way to see that from outside. Now there is.
 *
 * Only the project ref is exposed. It is already public: the browser sends it
 * on every request. No key material is returned.
 */
export async function GET() {
  const { projectRef, source, siteUrl } = supabaseConnection()

  return NextResponse.json(
    {
      ok: true,
      supabase: { projectRef, source },
      siteUrl: siteUrl || null,
      commit: process.env.VERCEL_GIT_COMMIT_SHA || null,
      branch: process.env.VERCEL_GIT_COMMIT_REF || null,
      environment: process.env.VERCEL_ENV || process.env.NODE_ENV || null
    },
    { headers: { 'Cache-Control': 'private, no-store, max-age=0' } }
  )
}
