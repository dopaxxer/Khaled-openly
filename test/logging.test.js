import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { logError } from '../lib/logger.js'

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8')

function captureError(run) {
  const original = console.error
  const lines = []
  console.error = (...args) => lines.push(args.join(' '))
  try { run() } finally { console.error = original }
  return lines
}

test('an error is recorded as one parseable line with its provider code', () => {
  const [line] = captureError(() =>
    logError('timeline.load', { code: 'PGRST202', message: 'function not found', status: 404 })
  )

  assert.ok(line.startsWith('[openly] '), 'entries must share a searchable prefix')
  const entry = JSON.parse(line.slice('[openly] '.length))
  assert.equal(entry.level, 'error')
  assert.equal(entry.event, 'timeline.load')
  assert.equal(entry.code, 'PGRST202')
  assert.equal(entry.status, 404)
})

test('an error with no detail still records the failing route', () => {
  const [line] = captureError(() => logError('engagement', undefined))
  const entry = JSON.parse(line.slice('[openly] '.length))

  assert.equal(entry.event, 'engagement')
  assert.deepEqual(Object.keys(entry).sort(), ['event', 'level'])
})

test('long provider messages are truncated', () => {
  const [line] = captureError(() => logError('x', { message: 'م'.repeat(1000) }))
  const entry = JSON.parse(line.slice('[openly] '.length))

  assert.equal(entry.message.length, 300)
})

// The reason the logger exists: routes that answered 500 without recording
// anything could only be discovered by someone complaining about them.
test('no API route answers 500 without recording why', () => {
  for (const name of ['app/api/[...path]/route.js', 'app/api/v1/[...path]/route.js']) {
    // The helper itself answers 500 — after recording. Everything else has to
    // go through it.
    const source = read(name).replace(/const serverError = \([\s\S]*?\n}\n/, '')
    // `}, 500)` is the shape of a JSON response literal. A bare 500 elsewhere
    // is a bound or a comparison, not a status.
    const silent = source
      .split('\n')
      .filter(line => line.includes('}, 500)') && !line.includes('serverError'))

    assert.deepEqual(silent, [], `${name} still fails silently:\n${silent.join('\n')}`)
  }
})
