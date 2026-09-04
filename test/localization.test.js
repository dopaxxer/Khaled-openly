import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import test from 'node:test'

const componentsDir = new URL('../components/', import.meta.url)

// Screens live in components/screens/ since the router started code-splitting
// them, so the scan walks the tree instead of one flat directory -- copy that
// moves into a subfolder must not fall out of the checks below.
function componentFiles(dir = componentsDir, prefix = '') {
  const found = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      found.push(...componentFiles(new URL(`${entry.name}/`, dir), `${prefix}${entry.name}/`))
    } else if (entry.name.endsWith('.jsx')) {
      found.push(`${prefix}${entry.name}`)
    }
  }
  return found
}
const bridge = readFileSync(new URL('LanguageBridge.jsx', componentsDir), 'utf8')

const stripComments = source =>
  source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

// The scanner reads source text, so a multi-element JSX line can produce a
// "string" that is really markup with Arabic inside it. Those carry syntax no
// interface copy ever contains, and each real string inside them is picked up
// on its own, so dropping them loses nothing.
const isSourceFragment = value => /[<>{}=]/.test(value)

function arabicCopy(source) {
  const found = new Set()
  for (const line of stripComments(source).split('\n')) {
    for (const [, quoted] of line.matchAll(/'([^']*[؀-ۿ][^']*)'/g)) found.add(quoted.trim())
    for (const [, quoted] of line.matchAll(/"([^"]*[؀-ۿ][^"]*)"/g)) found.add(quoted.trim())
    for (const [, text] of line.matchAll(/>([^<>{}]*[؀-ۿ][^<>{}]*)</g)) found.add(text.trim())
  }
  return [...found].filter(value => value && !isSourceFragment(value))
}

const hasEntry = value => bridge.includes(`'${value}':`)

// The English switch rewrites text nodes against one dictionary, so a phrase
// with no entry simply stays in Arabic. That is invisible in review and only
// shows up to someone actually using the site in English -- which is how the
// interests and music screens shipped untranslated. This asserts the whole
// surface instead of one component at a time.
test('every component ships its Arabic copy with an English entry', () => {
  const components = componentFiles().filter(name => name !== 'LanguageBridge.jsx')

  assert.ok(components.length > 10, `only found ${components.length} components to scan`)

  const missing = []
  for (const name of components) {
    const source = readFileSync(new URL(name, componentsDir), 'utf8')
    for (const value of arabicCopy(source)) {
      if (!hasEntry(value)) missing.push(`${name}: ${value}`)
    }
  }

  assert.deepEqual(missing, [], `untranslated interface copy:\n${missing.join('\n')}`)
})

// A phrase declared twice is silently dropped by the object literal, and the
// second reading is the one that survives -- so a later, wrong translation can
// quietly replace a correct one.
test('the dictionary declares each phrase exactly once', () => {
  const block = bridge.slice(bridge.indexOf('const EN = {'), bridge.indexOf('\n}'))
  const keys = [...block.matchAll(/^ {2}'((?:[^'\\]|\\.)*)':/gm)].map(match => match[1])
  const seen = new Set()
  const duplicates = keys.filter(key => seen.size === seen.add(key).size)

  assert.ok(keys.length > 300, `the dictionary looks truncated: ${keys.length} keys`)
  assert.deepEqual(duplicates, [], `duplicated keys: ${duplicates.join(' | ')}`)
})

// Anything a person typed must be exempt from the dictionary. The switch
// rewrites whole text nodes, so an interest named "الفنانون" or a bio reading
// "مصر" would silently come back as "Artists" or "Egypt" -- the reader would
// see words their author never wrote. Short, common entries make this easy to
// hit, so the exemptions are asserted rather than assumed.
test('text a person authored is exempt from the language bridge', () => {
  const shielded = /data-user-content|className="(?:post-body|comment-body)"/

  const patterns = [
    /\{user\.bio &&[^\n]*\}/g,
    /\{item\.label\}|\{item\.subtitle\}/g
  ]

  let checked = 0
  for (const pattern of patterns) {
    for (const name of componentFiles()) {
      const source = readFileSync(new URL(name, componentsDir), 'utf8')
      for (const line of source.split('\n')) {
        pattern.lastIndex = 0
        if (!pattern.test(line)) continue
        checked += 1
        assert.match(
          line,
          shielded,
          `${name} renders authored text without a data-user-content shield: ${line.trim()}`
        )
      }
    }
  }

  // A pattern that stops matching anything would make this test pass by
  // scanning nothing, which is exactly how the shield would go missing.
  assert.ok(checked >= patterns.length, `the shield scan matched only ${checked} lines`)

  // The skip list is what makes the shield work at all.
  const bridge = readFileSync(new URL('LanguageBridge.jsx', componentsDir), 'utf8')
  assert.match(bridge, /\.post-body/)
  assert.match(bridge, /\.comment-body/)
  assert.match(bridge, /\[data-user-content\]/)
})

test('Arabic-first components do not ship fixed English interface copy', () => {
  const source = componentFiles()
    .filter(name => name !== 'LanguageBridge.jsx')
    .map(name => stripComments(readFileSync(new URL(name, componentsDir), 'utf8')))
    .join('\n')

  const fixedEnglishCopy = [
    'Welcome to openly',
    'A public space for thoughts, taste and conversation.',
    'Continue with Apple',
    'Continue with Google',
    '>Post<',
    'First post',
    'New post',
    'Write first. Add context only if it helps.',
    '>Notifications<',
    'Only things that need your attention',
    'liked your post',
    'mentioned you',
    'replied to your post',
    'No badges for noise.',
    '>Bookmarks<',
    'Private. Only you can see what you save.',
    '>Taste<',
    'Music, books and films are part of the profile',
    '>Posts<',
    'Popular cultural threads',
    'songs that feel like leaving',
    'books you read too young',
    'films that changed after a breakup',
    'shared taste'
  ]

  const found = fixedEnglishCopy.filter(value => source.includes(value))
  assert.deepEqual(found, [], `fixed English copy bypasses Arabic localization: ${found.join(' | ')}`)
})
