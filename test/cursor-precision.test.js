import assert from 'node:assert/strict'
import test from 'node:test'
import { parseCursor } from '../lib/validation.js'
import { parseDirectMessageCursor } from '../lib/directMessages.js'

const id = '123e4567-e89b-42d3-a456-426614174000'

for (const [name, parse] of [['feed', parseCursor], ['messages', parseDirectMessageCursor]]) {
  test(`${name} cursor retains PostgreSQL microseconds across pages`, () => {
    const timestamp = '2026-08-28T12:00:00.123456Z'
    assert.equal(parse(`${timestamp}|${id}`).createdAt, timestamp)
    assert.equal(parse(`2026-08-28T14:00:00.123456+02:00|${id}`).createdAt, timestamp)
    assert.equal(parse(`2026-08-28T12:00:00.000001+00:00|${id}`).createdAt, '2026-08-28T12:00:00.000001Z')
  })
  test(`${name} cursor rejects ambiguous dates and missing time zones`, () => {
    for (const timestamp of ['2026', '08/28/2026', '2026-08-28T12:00:00', 'bad-date']) {
      assert.ok(!parse(`${timestamp}|${id}`))
    }
  })
}
