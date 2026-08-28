import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'
import { isUuid, readJson } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

async function authContext(request, scope = 'messageRead') {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { response: reply({ error: 'غير مسجل', code: 'unauthorized' }, 401) }
  const rate = consumeRateLimit(rateLimitKey(request, scope, user.id), RATE_LIMITS[scope])
  if (!rate.allowed) {
    return { response: reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
      'Retry-After': String(rate.retryAfterSeconds)
    }) }
  }
  return { supabase }
}

async function idFrom(params) {
  const { conversationId } = await params
  const id = String(conversationId || '').toLowerCase()
  return isUuid(id) ? id : null
}

export async function GET(request, { params }) {
  const id = await idFrom(params)
  if (!id) return reply({ error: 'معرّف المحادثة غير صالح', code: 'invalid_conversation' }, 400)
  const auth = await authContext(request)
  if (auth.response) return auth.response
  const { data, error } = await auth.supabase.rpc('get_direct_message_presence', {
    p_conversation_id: id
  })
  if (error) return reply({ error: 'المحادثة غير متاحة', code: 'conversation_unavailable' }, 404)
  return reply(data || { online: false, typing: false, lastSeenAt: null })
}

export async function POST(request, { params }) {
  const id = await idFrom(params)
  if (!id) return reply({ error: 'معرّف المحادثة غير صالح', code: 'invalid_conversation' }, 400)
  const auth = await authContext(request, 'messagePresence')
  if (auth.response) return auth.response
  const parsed = await readJson(request, 1024)
  if (parsed.error) return reply({ error: parsed.error, code: 'invalid_request' }, parsed.status)
  const typing = parsed.data.typing === true
  const { error } = await auth.supabase.rpc('touch_direct_message_presence', {
    p_conversation_id: id,
    p_typing: typing
  })
  if (error) return reply({ error: 'المحادثة غير متاحة', code: 'conversation_unavailable' }, 404)
  return reply({ ok: true })
}
