import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { PUBLIC_CODE_PATTERN } from '@/lib/mentions'
import { readJson } from '@/lib/validation'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

export async function PUT(request) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)

  const rate = consumeRateLimit(rateLimitKey(request, 'musicWrite', user.id), RATE_LIMITS.musicWrite)
  if (!rate.allowed) {
    return reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
      'Retry-After': String(rate.retryAfterSeconds)
    })
  }

  const parsed = await readJson(request)
  if (parsed.error) return reply({ error: parsed.error, code: 'invalid_request' }, parsed.status)
  const publicCode = String(parsed.data.publicCode || '').trim().toUpperCase()
  const interested = parsed.data.interested
  if (!PUBLIC_CODE_PATTERN.test(publicCode) || typeof interested !== 'boolean') {
    return reply({ error: 'اختيار المطابقة غير صالح', code: 'invalid_request' }, 400)
  }

  const { data, error } = await supabase.rpc('set_music_match_interest', {
    p_public_code: publicCode,
    p_interested: interested
  })

  if (error) {
    const message = String(error.message || '')
    if (message.includes('Enable music discovery')) {
      return reply({ error: 'فعّل الظهور في اكتشاف الموسيقى أولًا.', code: 'discovery_disabled' }, 409)
    }
    if (message.includes('No eligible music overlap')) {
      return reply({ error: 'لم يعد التشابه الموسيقي كافيًا لهذه المطابقة.', code: 'not_compatible' }, 409)
    }
    if (message.includes('not available')) {
      return reply({ error: 'هذا الحساب لم يعد متاحًا للمطابقة.', code: 'unavailable' }, 409)
    }
    return reply({ error: 'تعذر حفظ اختيارك الآن.', code: 'interest_rejected' }, 400)
  }

  return reply({ state: data })
}
