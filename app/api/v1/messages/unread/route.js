import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function reply(body, status = 200, extraHeaders = {}) {
  return NextResponse.json(body, { status, headers: { ...HEADERS, ...extraHeaders } })
}

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return reply({ error: 'غير مسجل', code: 'unauthorized' }, 401)

  const rate = consumeRateLimit(rateLimitKey(request, 'messageRead', user.id), RATE_LIMITS.messageRead)
  if (!rate.allowed) {
    return reply({ error: 'محاولات كثيرة. حاول بعد قليل.', code: 'rate_limited' }, 429, {
      'Retry-After': String(rate.retryAfterSeconds)
    })
  }

  const { data, error } = await supabase.rpc('get_unread_direct_message_count')
  if (error) return reply({ error: 'تعذر تحميل عدد الرسائل', code: 'unread_failed' }, 500)

  return reply({ unreadCount: Number(data || 0) })
}
