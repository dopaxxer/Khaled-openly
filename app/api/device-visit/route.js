import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const text = (value, max) => {
  if (value === null || value === undefined) return null
  const result = String(value).trim()
  return result ? result.slice(0, max) : null
}
const int = (value, max = 100000) => {
  const n = Number(value)
  return Number.isFinite(n) ? Math.max(0, Math.min(max, Math.round(n))) : null
}
const decimal = value => {
  const n = Number(value)
  return Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : null
}

export async function POST(request) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()

  // Only associate telemetry with an authenticated Openly account.
  if (!user) return new NextResponse(null, { status: 204 })

  const parsed = await readJson(request, 16 * 1024)
  if (parsed.error) return NextResponse.json({ error: parsed.error }, {
    status: parsed.status,
    headers: { 'Cache-Control': 'private, no-store, max-age=0' }
  })
  const body = parsed.data
  const pagePath = text(body.pagePath, 1024)
  if (!pagePath || !pagePath.startsWith('/')) return new NextResponse(null, { status: 204 })

  const sessionId = text(body.sessionId, 64)
  const headerUserAgent = text(request.headers.get('user-agent'), 2048)

  const { error } = await supabase.from('device_visits').insert({
    user_id: user.id,
    session_id: sessionId && uuidPattern.test(sessionId) ? sessionId : null,
    page_path: pagePath,
    device_type: text(body.deviceType, 64),
    device_model: text(body.deviceModel, 256),
    os: text(body.os, 64),
    os_version: text(body.osVersion, 64),
    browser: text(body.browser, 64),
    browser_version: text(body.browserVersion, 128),
    user_agent: headerUserAgent || text(body.userAgent, 2048),
    platform: text(body.platform, 128),
    language: text(body.language, 32),
    timezone: text(body.timezone, 128),
    screen_width: int(body.screenWidth),
    screen_height: int(body.screenHeight),
    pixel_ratio: decimal(body.pixelRatio),
    touch_points: int(body.touchPoints, 100)
  })

  if (error) {
    console.error('device_visit_insert_failed', error.code)
    return NextResponse.json({ error: 'تعذر حفظ بيانات الجهاز' }, {
      status: 500,
      headers: { 'Cache-Control': 'private, no-store, max-age=0' }
    })
  }

  return new NextResponse(null, { status: 204 })
}
