import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { isUuid, readJson } from '@/lib/validation'
import { MAX_INTERESTS_PER_PROFILE } from '@/lib/interests'
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
  if (status >= 500) logError(`v1.interests.preferences.${code}`, { code, status })
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

  const limited = guard(request, 'interestRead', user.id)
  if (limited) return limited

  const { data, error } = await supabase.rpc('get_interest_profile')
  if (error) return fail(500, 'profile_failed', 'تعذر تحميل اهتماماتك')
  return ok({ profile: data || { discoveryOptIn: false, preferencesPublic: false, items: [] } })
}

export async function PUT(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = guard(request, 'interestWrite', user.id)
  if (limited) return limited

  const parsed = await readJson(request)
  if (parsed.error) return fail(parsed.status, 'invalid_request', parsed.error)
  const { discoveryOptIn, preferencesPublic, interestIds } = parsed.data

  if (typeof discoveryOptIn !== 'boolean' || typeof preferencesPublic !== 'boolean') {
    return fail(400, 'invalid_settings', 'إعدادات الظهور غير صالحة')
  }
  if (!Array.isArray(interestIds) || interestIds.length > MAX_INTERESTS_PER_PROFILE) {
    return fail(400, 'invalid_interests', `الحد الأقصى ${MAX_INTERESTS_PER_PROFILE} اهتمامًا`)
  }
  const ids = interestIds.map(value => String(value || ''))
  if (ids.some(id => !isUuid(id)) || new Set(ids).size !== ids.length) {
    return fail(400, 'invalid_interests', 'قائمة الاهتمامات غير صالحة')
  }

  const { data, error } = await supabase.rpc('set_interest_profile', {
    p_discovery_opt_in: discoveryOptIn,
    p_preferences_public: preferencesPublic,
    p_interest_ids: ids
  })
  if (error) return fail(400, 'save_failed', 'تعذر حفظ اهتماماتك')
  return ok({ profile: data })
}
