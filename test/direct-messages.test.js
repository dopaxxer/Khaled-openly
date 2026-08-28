import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  DIRECT_MESSAGE_MAX_LENGTH,
  mapDirectConversation,
  mapDirectMessage,
  normalizeDirectMessageBody,
  parseMessageBefore,
  validDirectMessageNonce
} from '../lib/directMessages.js'

test('direct message bodies are trimmed and bounded', () => {
  assert.equal(normalizeDirectMessageBody('  مرحبًا  '), 'مرحبًا')
  assert.equal(normalizeDirectMessageBody('   '), null)
  assert.equal(normalizeDirectMessageBody('x'.repeat(DIRECT_MESSAGE_MAX_LENGTH + 1)), null)
})

test('direct message request idempotency requires a UUID nonce', () => {
  assert.equal(validDirectMessageNonce('123e4567-e89b-42d3-a456-426614174000'), true)
  assert.equal(validDirectMessageNonce('retry-1'), false)
})

test('direct message cursor parsing rejects invalid timestamps', () => {
  assert.equal(parseMessageBefore('not-a-date'), undefined)
  assert.equal(parseMessageBefore(''), null)
  assert.equal(parseMessageBefore('2026-08-28T12:00:00Z'), '2026-08-28T12:00:00.000Z')
})

test('direct message mappers keep private database names out of clients', () => {
  assert.deepEqual(mapDirectConversation({
    conversation_id: 'c',
    public_code: 'AB23',
    identity_color: '#123456',
    last_message_body: 'hello',
    last_message_at: '2026-08-28T12:00:00Z',
    last_message_is_mine: false,
    unread_count: '2',
    can_message: true
  }), {
    conversationId: 'c',
    publicCode: 'AB23',
    identityColor: '#123456',
    lastMessageBody: 'hello',
    lastMessageAt: '2026-08-28T12:00:00Z',
    lastMessageIsMine: false,
    unreadCount: 2,
    canMessage: true
  })

  assert.equal(mapDirectMessage({ id: 'm', body: 'x', created_at: 't', read_at: null, sender_code: 'AB23', sender_color: '#123456', is_mine: true }).isMine, true)
})

test('message endpoints use RPCs rather than direct private-table access', () => {
  const files = [
    '../app/api/v1/messages/route.js',
    '../app/api/v1/messages/[conversationId]/route.js',
    '../app/api/v1/messages/[conversationId]/read/route.js',
    '../app/api/v1/messages/unread/route.js'
  ]
  const source = files.map(path => readFileSync(new URL(path, import.meta.url), 'utf8')).join('\n')
  assert.doesNotMatch(source, /\.from\(['"](?:direct_messages|direct_conversations)['"]\)/)
  assert.match(source, /send_direct_message/)
  assert.match(source, /get_unread_direct_message_count/)
})

test('message migration enforces privacy, block checks and idempotency', () => {
  const migration = readFileSync(new URL('../supabase/migrations/20260828141500_private_direct_messages.sql', import.meta.url), 'utf8')
  assert.match(migration, /alter table private\.direct_messages enable row level security/i)
  assert.match(migration, /revoke all on table private\.direct_messages from public, anon, authenticated/i)
  assert.match(migration, /direct_messages_idempotency/)
  assert.match(migration, /public\.blocks/)
  assert.match(migration, /message\.sender_id <> viewer/)
})
