import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { readJson } from '@/lib/validation'
import {
  INTEREST_LABEL_MAX_LENGTH,
  normalizeInterestKind
} from '@/lib/interests'
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
  if (status >= 500) logError(`v1.interests.${code}`, { code, status })
  return NextResponse.json({ error: message, code }, { status, headers: HEADERS })
}

async function requireUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

function guard(request, scope, userId) {
  const result = consumeRateLimit(rateLimitKey(request, scope, userId), RATE_LIMITS[scope])
  if (result.allowed) return null
  return fail(429, 'rate_limited', 'محاولات كثيرة. حاول بعد قليل.')
}

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = guard(request, 'interestSearch', user.id)
  if (limited) return limited

  const url = new URL(request.url)
  const query = String(url.searchParams.get('q') || '').trim().slice(0, INTEREST_LABEL_MAX_LENGTH)
  const rawKind = url.searchParams.get('kind')
  const kind = rawKind ? normalizeInterestKind(rawKind) : null
  if (rawKind && !kind) return fail(400, 'invalid_kind', 'نوع الاهتمام غير صالح')

  const { data, error } = await supabase.rpc('search_interests', {
    p_query: query || null,
    p_kind: kind,
    p_limit: 30
  })
  if (error) return fail(500, 'search_failed', 'تعذر البحث في الاهتمامات')

  return ok({
    items: (data || []).map(row => ({
      id: row.id,
      kind: row.kind,
      label: row.label,
      subtitle: row.subtitle,
      popularity: Number(row.popularity || 0)
    }))
  })
}

export async function POST(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = guard(request, 'interestWrite', user.id)
  if (limited) return limited

  const parsed = await readJson(request)
  if (parsed.error) return fail(parsed.status, 'invalid_request', parsed.error)

  const kind = normalizeInterestKind(parsed.data.kind)
  const label = String(parsed.data.label || '').trim()
  const subtitle = String(parsed.data.subtitle || '').trim()

  if (!kind) return fail(400, 'invalid_kind', 'نوع الاهتمام غير صالح')
  if (!label || label.length > INTEREST_LABEL_MAX_LENGTH) {
    return fail(400, 'invalid_label', 'اسم الاهتمام غير صالح')
  }
  if (subtitle.length > INTEREST_LABEL_MAX_LENGTH) {
    return fail(400, 'invalid_subtitle', 'التفصيل أطول من المسموح')
  }

  const { data, error } = await supabase.rpc('add_interest', {
    p_kind: kind,
    p_label: label,
    p_subtitle: subtitle || null
  })
  if (error || !data) return fail(400, 'create_failed', 'تعذر إضافة الاهتمام')
  return ok({ item: data })
}
