import assert from 'node:assert/strict'
import test from 'node:test'
import {
  activeMentionQuery,
  applyMentionCompletion,
  isPublicCode,
  MAX_MENTIONS_PER_ITEM,
  parseMentionCodes,
  splitMentionSegments
} from '../lib/mentions.js'

// The parity contract between the three implementations of the mention
// grammar: this table, private.parse_mention_codes in the Supabase migration,
// and MentionParser.codes(in:) on iOS. Every row here was run through the
// database and produced exactly these results. If the grammar ever changes,
// change it in all three places and re-verify against the database.
const PARSER_FIXTURES = [
  ['hi @ABCD and @ef2h, mail me@example.com, @TOOLONGCODE9, @ABCI', ['ABCD', 'EF2H']],
  ['@AAAA @BBBB', ['AAAA', 'BBBB']],
  ['@AAAA@BBBB', ['AAAA']],
  ['start@AAAA', []],
  ['@AAA', []],
  ['@AAAAAAAA', ['AAAAAAAA']],
  ['@AAAAAAAAA', []],
  ['line one\n@BBBB second line', ['BBBB']],
  ['(@AAAA) [@BBBB] "@CCCC"', ['AAAA', 'BBBB', 'CCCC']],
  ['@aaaa @AAAA duplicate', ['AAAA']],
  ['emoji 🎵 @DDDD', ['DDDD']],
  ['@AAAA_underscore', []],
  ['email name@AAAA.com', []],
  ['@@AAAA', []],
  ['<script>@AAAA</script>', ['AAAA']]
]

test('mention parser matches the database grammar on every fixture', () => {
  for (const [input, expected] of PARSER_FIXTURES) {
    assert.deepEqual(parseMentionCodes(input), expected, `input: ${JSON.stringify(input)}`)
  }
})

test('codes outside the identity alphabet never become mentions', () => {
  // The public-code constraint is ^[A-HJ-NP-Z2-9]{4,8}$, so I, O, 0 and 1 can
  // never appear in a code and a token containing one must stay plain text.
  // (The random generator also skips L, but the constraint permits it, so L is
  // a legal code character and must parse.)
  for (const code of ['ABCI', 'ABCO', 'ABC0', 'ABC1']) {
    assert.equal(isPublicCode(code), false)
    assert.deepEqual(parseMentionCodes(`hey @${code} there`), [])
  }
  assert.equal(isPublicCode('ABCD'), true)
  assert.equal(isPublicCode('ABCL'), true)
  assert.deepEqual(parseMentionCodes('hey @ABCL there'), ['ABCL'])
})

test('duplicates collapse and the per-item limit is enforced', () => {
  const many = Array.from({ length: 15 }, (_, index) => `@A${String(index).padStart(3, '2')}`).join(' ')
  assert.ok(parseMentionCodes(many).length <= MAX_MENTIONS_PER_ITEM)

  const repeated = '@ABCD @abcd @AbCd @ABCD'
  assert.deepEqual(parseMentionCodes(repeated), ['ABCD'])

  assert.deepEqual(parseMentionCodes('@ABCD @BCDE @CDEF', 2), ['ABCD', 'BCDE'])
  assert.deepEqual(parseMentionCodes('@ABCD', 0), [])
})

test('malformed input is handled without throwing', () => {
  for (const input of [null, undefined, '', '@', '@@', '@ ', 'no mentions here', '\n\n\n']) {
    assert.deepEqual(parseMentionCodes(input), [])
  }
})

test('only resolved codes are highlighted; the rest stay plain text', () => {
  const segments = splitMentionSegments('hi @ABCD and @ZZZZ', ['ABCD'])
  assert.deepEqual(segments, [
    { type: 'text', value: 'hi ' },
    { type: 'mention', value: '@ABCD', code: 'ABCD' },
    { type: 'text', value: ' and @ZZZZ' }
  ])

  // Nothing resolved means nothing is highlighted.
  assert.deepEqual(splitMentionSegments('hi @ABCD', []), [{ type: 'text', value: 'hi @ABCD' }])
})

test('segments reassemble to exactly the original text', () => {
  // Rendering must never lose or duplicate a character: what the author typed
  // is what a reader sees.
  const inputs = [
    'hi @ABCD and @BCDE done',
    '@ABCD',
    '@ABCD @BCDE',
    'no mentions',
    'punctuation (@ABCD), then @BCDE!',
    'line one\n@ABCD line two'
  ]
  for (const input of inputs) {
    const rebuilt = splitMentionSegments(input, ['ABCD', 'BCDE'])
      .map(segment => segment.value)
      .join('')
    assert.equal(rebuilt, input, `input: ${JSON.stringify(input)}`)
  }
})

test('markup in a body is carried through as text, never as structure', () => {
  const hostile = '<img src=x onerror=alert(1)> @ABCD </script>'
  const segments = splitMentionSegments(hostile, ['ABCD'])
  assert.equal(segments.map(segment => segment.value).join(''), hostile)
  // Mention values are always the literal token, so nothing that reaches the
  // renderer can carry markup of its own.
  for (const segment of segments) {
    if (segment.type === 'mention') assert.match(segment.value, /^@[A-Za-z0-9]{4,8}$/)
  }
})

test('the composer detects the token under the caret', () => {
  assert.deepEqual(activeMentionQuery('hello @ab', 9), { query: 'AB', start: 6, end: 9 })
  assert.deepEqual(activeMentionQuery('hello @', 7), { query: '', start: 6, end: 7 })
  // Caret before the token, and a caret inside an e-mail address.
  assert.equal(activeMentionQuery('hello @ab', 5), null)
  assert.equal(activeMentionQuery('name@example', 12), null)
  // A token longer than a public code is not a mention any more.
  assert.equal(activeMentionQuery('@ABCDEFGHI', 10), null)
})

test('choosing a suggestion inserts the canonical code', () => {
  const range = activeMentionQuery('hello @ab', 9)
  assert.deepEqual(applyMentionCompletion('hello @ab', range, 'abcd'), {
    value: 'hello @ABCD ',
    caret: 12
  })

  // Completing mid-sentence keeps the trailing text intact.
  const middle = activeMentionQuery('hi @ab there', 6)
  assert.deepEqual(applyMentionCompletion('hi @ab there', middle, 'BCDE'), {
    value: 'hi @BCDE  there',
    caret: 9
  })
})
