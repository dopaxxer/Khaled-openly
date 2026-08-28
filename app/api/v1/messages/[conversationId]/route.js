import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import {
  directMessageCursor,
  mapDirectMessage,
  normalizeDirectMessageBody,
  parseDirectMessageCursor,
  validDirectMessageNonce
} from '@/lib/directMessages'
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

async function conversationId(params) {
  const { conversationId } = await params
  const value = String(conversationId || '').toLowerCase()
  return isUuid(value) ? value : null
}

export async function GET(request, { params }) {
  const id = await conversationId(params)
  if (!id) return reply({ error: 'معرّف المحادثة غير صالح', code: 'invalid_conversation' }, 400)

  const auth = await authenticated(request, 'messageRead')
  if (auth.response) return auth.response

  const url = new URL(request.url)
  const limit = boundedInt(url.searchParams.get('limit'), 50, 1, 100)
  const cursor = parseDirectMessageCursor(url.searchParams.get('cursor'))
  const after = parseDirectMessageCursor(url.searchParams.get('after'))
  if (cursor === undefined || after === undefined || (cursor && after)) {
    return reply({ error: 'مؤشر الرسائل غير صالح', code: 'invalid_cursor' }, 400)
  }

  const messageRequest = after
    ? auth.supabase.rpc('get_direct_messages_after', {
        p_conversation_id: id,
        p_after: after.createdAt,
        p_after_id: after.id,
        p_limit: limit
      })
    : auth.supabase.rpc('get_direct_messages_page', {
        p_conversation_id: id,
        p_before: cursor?.createdAt || null,
        p_before_id: cursor?.id || null,
        p_limit: limit + 1
      })

  const [metaResult, messagesResult] = await Promise.all([
    auth.supabase.rpc('get_direct_conversation', { p_conversation_id: id }),
    messageRequest
  ])

  if (metaResult.error || messagesResult.error || !metaResult.data) {
    return reply({ error: 'المحادثة غير متاحة', code: 'conversation_unavailable' }, 404)
  }

  const rows = messagesResult.data || []
  if (after) {
    return reply({
      conversation: metaResult.data,
      items: rows.map(mapDirectMessage),
      nextCursor: null,
      hasMore: false
    })
  }

  const hasMore = rows.length > limit
  const page = rows.slice(0, limit)
  const oldest = page.length ? page[page.length - 1] : null
  return reply({
    conversation: metaResult.data,
    items: page.map(mapDirectMessage).reverse(),
    nextCursor: hasMore ? directMessageCursor(oldest) : null,
    hasMore
  })
}

export async function POST(request, { params }) {
  const id = await conversationId(params)
  if (!id) return reply({ error: 'معرّف المحادثة غير صالح', code: 'invalid_conversation' }, 400)

  const auth = await authenticated(request, 'messageWrite')
  if (auth.response) return auth.response

  const parsed = await readJson(request, 8 * 1024)
  if (parsed.error) return reply({ error: parsed.error, code: 'invalid_request' }, parsed.status)

  const body = normalizeDirectMessageBody(parsed.data.body)
  const clientNonce = String(parsed.data.clientNonce || '').toLowerCase()
  if (!body || !validDirectMessageNonce(clientNonce)) {
    return reply({ error: 'الرسالة غير صالحة', code: 'invalid_message' }, 400)
  }

  const { data, error } = await auth.supabase.rpc('send_direct_message', {
    p_conversation_id: id,
    p_body: body,
    p_client_nonce: clientNonce
  })

  if (error) {
    const message = String(error.message || '')
    if (message.includes('Messaging unavailable')) {
      return reply({ error: 'لا يمكنك إرسال رسالة في هذه المحادثة الآن.', code: 'messaging_unavailable' }, 409)
    }
    if (message.includes('Conversation unavailable')) {
      return reply({ error: 'المحادثة غير متاحة', code: 'conversation_unavailable' }, 404)
    }
    return reply({ error: 'تعذر إرسال الرسالة', code: 'send_failed' }, 400)
  }

  return reply({ message: data }, 201)
}
