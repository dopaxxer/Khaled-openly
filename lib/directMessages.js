import { isUuid } from './validation.js'

export const DIRECT_MESSAGE_MAX_LENGTH = 2000

export function normalizeDirectMessageBody(value) {
  const body = String(value ?? '').trim()
  if (!body || body.length > DIRECT_MESSAGE_MAX_LENGTH) return null
  return body
}

export function validDirectMessageNonce(value) {
  return isUuid(value)
}

export function mapDirectConversation(row) {
  return {
    conversationId: row.conversation_id,
    publicCode: row.public_code,
    identityColor: row.identity_color,
    lastMessageBody: row.last_message_body ?? null,
    lastMessageAt: row.last_message_at ?? null,
    lastMessageIsMine: !!row.last_message_is_mine,
    unreadCount: Number(row.unread_count || 0),
    canMessage: row.can_message !== false
  }
}

export function mapDirectMessage(row) {
  return {
    id: row.id,
    body: row.body,
    createdAt: row.created_at,
    readAt: row.read_at ?? null,
    senderCode: row.sender_code,
    senderColor: row.sender_color,
    isMine: !!row.is_mine
  }
}

export function parseMessageBefore(value) {
  if (!value) return null
  const time = Date.parse(String(value))
  return Number.isFinite(time) ? new Date(time).toISOString() : undefined
}
