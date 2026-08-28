import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { PUBLIC_CODE_PATTERN } from '@/lib/mentions'
import { mapDirectConversation } from '@/lib/directMessages'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'
import { readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

function boundedInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(min, Math.min(parsed, max))
}

async function authenticated(request, scope) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { response: reply({ error: 'غير مسجل', code: 'unauthorized' }, 401) }

  const rate = consumeRateLimit(rateLimitKey(request, scope, user.id), RATE_LIMITS[scope])
  if (!rate.allowed) {
    return {
      response: reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
        'Retry-After': String(rate.retryAfterSeconds)
      })
    }
  }
  return { supabase, user }
}

export async function GET(request) {
  const auth = await authenticated(request, 'messageRead')
  if (auth.response) return auth.response

  const url = new URL(request.url)
  const limit = boundedInt(url.searchParams.get('limit'), 30, 1, 50)
  const offset = boundedInt(url.searchParams.get('offset'), 0, 0, 500)

  const { data, error } = await auth.supabase.rpc('get_direct_conversations', {
    p_limit: limit,
    p_offset: offset
  })
  if (error) return reply({ error: 'تعذر تحميل الرسائل', code: 'messages_failed' }, 500)

  const rows = data || []
  const total = rows.length ? Number(rows[0].total_conversations || 0) : 0
  return reply({
    items: rows.map(mapDirectConversation),
    total,
    limit,
    offset,
    hasMore: offset + rows.length < total
  })
}

export async function POST(request) {
  const auth = await authenticated(request, 'messageWrite')
  if (auth.response) return auth.response

  const parsed = await readJson(request)
  if (parsed.error) return reply({ error: parsed.error, code: 'invalid_request' }, parsed.status)

  const publicCode = String(parsed.data.publicCode || '').trim().toUpperCase()
  if (!PUBLIC_CODE_PATTERN.test(publicCode)) {
    return reply({ error: 'كود الهوية غير صالح', code: 'invalid_code' }, 400)
  }

  const { data, error } = await auth.supabase.rpc('start_direct_conversation', {
    p_public_code: publicCode
  })

  if (error) {
    const message = String(error.message || '')
    if (message.includes('Messaging unavailable') || message.includes('target unavailable')) {
      return reply({ error: 'لا يمكن بدء محادثة مع هذه الهوية الآن.', code: 'messaging_unavailable' }, 409)
    }
    return reply({ error: 'تعذر بدء المحادثة', code: 'start_failed' }, 400)
  }

  return reply({ conversation: data }, 201)
}
