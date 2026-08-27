import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { normalizeInterestKind } from '@/lib/interests'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function ok(body) {
  return NextResponse.json(body, { status: 200, headers: HEADERS })
}

function fail(status, code, message) {
  if (status >= 500) logError(`v1.interests.discover.${code}`, { code, status })
  return NextResponse.json({ error: message, code }, { status, headers: HEADERS })
}

async function requireUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

function boundedInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(min, Math.min(parsed, max))
}

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = consumeRateLimit(
    rateLimitKey(request, 'interestDiscovery', user.id),
    RATE_LIMITS.interestDiscovery
  )
  if (!limited.allowed) return fail(429, 'rate_limited', 'محاولات كثيرة. حاول بعد قليل.')

  const url = new URL(request.url)
  const rawKind = url.searchParams.get('kind')
  const kind = rawKind ? normalizeInterestKind(rawKind) : null
  if (rawKind && !kind) return fail(400, 'invalid_kind', 'نوع الاهتمام غير صالح')

  const limit = boundedInt(url.searchParams.get('limit'), 20, 1, 50)
  const offset = boundedInt(url.searchParams.get('offset'), 0, 0, 500)

  const { data, error } = await supabase.rpc('discover_interest_people', {
    p_kind: kind,
    p_limit: limit,
    p_offset: offset
  })
  if (error) return fail(500, 'discovery_failed', 'تعذر تحميل الاقتراحات')

  const rows = data || []
  const total = rows.length ? Number(rows[0].total_matches || 0) : 0

  return ok({
    items: rows.map(row => ({
      publicCode: row.public_code,
      identityColor: row.identity_color,
      compatibility: Number(row.compatibility || 0),
      sharedBookCount: Number(row.shared_book_count || 0),
      sharedMovieCount: Number(row.shared_movie_count || 0),
      sharedTopicCount: Number(row.shared_topic_count || 0),
      sharedItems: Array.isArray(row.shared_items) ? row.shared_items : [],
      musicCompatibility: Number(row.music_compatibility || 0)
    })),
    total,
    limit,
    offset,
    hasMore: offset + rows.length < total
  })
}
