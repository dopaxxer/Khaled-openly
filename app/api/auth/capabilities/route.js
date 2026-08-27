import { NextResponse } from 'next/server'
import { mapAuthCapabilities, SAFE_AUTH_CAPABILITIES } from '@/lib/authCapabilities'
import { supabaseKey, supabaseUrl } from '@/lib/supabaseEnv'

export const dynamic = 'force-dynamic'

export async function GET() {
  try {
    const response = await fetch(`${supabaseUrl()}/auth/v1/settings`, {
      headers: {
        apikey: supabaseKey(),
        Accept: 'application/json'
      },
      cache: 'no-store'
    })

    if (!response.ok) {
      return NextResponse.json(SAFE_AUTH_CAPABILITIES, {
        status: 200,
        headers: { 'Cache-Control': 'private, no-store, max-age=0' }
      })
    }

    const settings = await response.json()
    return NextResponse.json(mapAuthCapabilities(settings), {
      headers: { 'Cache-Control': 'private, no-store, max-age=0' }
    })
  } catch {
    return NextResponse.json(SAFE_AUTH_CAPABILITIES, {
      status: 200,
      headers: { 'Cache-Control': 'private, no-store, max-age=0' }
    })
  }
}
