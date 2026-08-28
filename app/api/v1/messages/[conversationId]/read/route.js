import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'
import { isUuid } from '@/lib/validation'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

export async function POST(request, { params }) {
  const { conversationId } = await params
  const id = String(conversationId || '').toLowerCase()
  if (!isUuid(id)) return reply({ error: 'معرّف المحادثة غير صالح', code: 'invalid_conversation' }, 400)

  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)

  const rate = consumeRateLimit(rateLimitKey(request, 'messageWrite', user.id), RATE_LIMITS.messageWrite)
  if (!rate.allowed) {
    return reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
      'Retry-After': String(rate.retryAfterSeconds)
    })
  }

  const { data, error } = await supabase.rpc('mark_direct_conversation_read', {
    p_conversation_id: id
  })
  if (error) return reply({ error: 'المحادثة غير متاحة', code: 'conversation_unavailable' }, 404)

  return reply({ ok: true, readCount: Number(data || 0) })
}
