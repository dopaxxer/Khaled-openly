import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8')

const bridge = read('components/LanguageBridge.jsx')
const composer = read('components/Composer.jsx')
const attachment = read('components/TrackAttachment.jsx')
const preview = read('components/TrackPreview.jsx')
const musicPreferences = read('components/MusicPreferences.jsx')
const interests = read('components/InterestDiscovery.jsx')
const publicProfile = read('components/PublicMusicProfile.jsx')

// Comments carry Arabic prose that never reaches the DOM, so they would
// otherwise look like untranslated interface copy.
const stripComments = source =>
  source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

const hasEntry = value => bridge.includes(`'${value}':`)

/** Every Arabic run the file hands to the DOM, one line at a time. */
function arabicCopy(source) {
  const found = new Set()
  for (const line of stripComments(source).split('\n')) {
    for (const [, quoted] of line.matchAll(/'([^']*[؀-ۿ][^']*)'/g)) found.add(quoted.trim())
    for (const [, quoted] of line.matchAll(/"([^"]*[؀-ۿ][^"]*)"/g)) found.add(quoted.trim())
    for (const [, text] of line.matchAll(/>([^<>{}]*[؀-ۿ][^<>{}]*)</g)) found.add(text.trim())
  }
  return [...found].filter(Boolean)
}

// These two render nothing but track UI, so all of their copy is in scope.
test('every Arabic string in the track components has an English entry', () => {
  const strings = [...arabicCopy(preview), ...arabicCopy(attachment)]
  assert.ok(strings.length > 0, 'the scanner found no Arabic copy to check')

  const missing = strings.filter(value => !hasEntry(value))
  assert.deepEqual(missing, [], `untranslated interface copy: ${missing.join(' | ')}`)
})

// The player lives in one module so that starting a preview stops the one that
// was already playing, wherever on the page it was.
test('every surface that lists a track can play its preview', () => {
  for (const [name, source] of [
    ['TrackAttachment', attachment],
    ['MusicPreferences', musicPreferences],
    ['PublicMusicProfile', publicProfile]
  ]) {
    assert.match(source, /TrackPreviewButton/, `${name} renders no preview control`)
    assert.match(source, /from '\.\/TrackPreview'/, `${name} does not use the shared player`)
  }

  const players = (preview.match(/let activeAudio/g) || []).length
  assert.equal(players, 1, 'the shared player must own exactly one active-audio reference')
})

// The composer is mixed, so only the strings the attachment flow introduced are
// asserted here. Each must stay in both the component and the dictionary.
test('the composer attachment flow is fully translated', () => {
  const strings = [
    'أضف أغنية',
    'ابحث باسم الأغنية أو الفنان',
    'البحث في كتالوج الأغاني',
    'إزالة الأغنية المرفقة',
    'جارِ البحث في كتالوج الموسيقى…',
    'اكتب اسم أغنية أو فنان، ثم اختر نتيجة واحدة.',
    'لا توجد نتائج مطابقة.',
    'جارِ الإرفاق…',
    'اختيار',
    'تعذر إرفاق الأغنية',
    'تعذر البحث عن الأغاني'
  ]

  const unused = strings.filter(value => !composer.includes(value))
  assert.deepEqual(unused, [], `no longer rendered by the composer: ${unused.join(' | ')}`)

  const missing = strings.filter(value => !hasEntry(value))
  assert.deepEqual(missing, [], `untranslated interface copy: ${missing.join(' | ')}`)
})

test('catalog metadata is exempt from the language bridge', () => {
  // Song titles are content, not interface copy. Without the marker a song
  // called "حفظ" would be rewritten to "Save" in English.
  assert.match(attachment, /className="track-attachment-meta"[^>]*data-user-content/)
  assert.match(composer, /className="composer-track-meta"[^>]*data-user-content/)
  assert.match(composer, /className="composer-track-result-main"[^>]*data-user-content/)
  assert.match(musicPreferences, /className="ordered-name"[^>]*data-user-content/)
  assert.match(publicProfile, /data-user-content/)

  // The bridge only honours the marker if it stays in the skip list.
  assert.match(bridge, /\[data-user-content\]/)
})

test('the iOS attachment picker keys exist in both languages', () => {
  const arabic = read('ios/Openly/ar.lproj/Localizable.strings')
  const english = read('ios/Openly/en.lproj/Localizable.strings')
  const picker = read('ios/Openly/ComposerTrackPicker.swift')

  const keys = [...picker.matchAll(/"(composer_track_[a-z_]+|composer_add_track)"/g)]
    .map(match => match[1])

  assert.ok(keys.length > 0, 'no localized keys found in the picker')

  for (const key of new Set(keys)) {
    assert.ok(arabic.includes(`"${key}"`), `missing Arabic string for ${key}`)
    assert.ok(english.includes(`"${key}"`), `missing English string for ${key}`)
  }
})


// The interests screens are the newest surface and were shipped entirely in
// Arabic, so the language switch left them untranslated. They render nothing
// but interest UI, which puts all of their copy in scope.
test('every Arabic string in the interests screens has an English entry', () => {
  const strings = arabicCopy(interests)
  assert.ok(strings.length > 0, 'the scanner found no Arabic copy to check')

  const missing = strings.filter(value => !hasEntry(value))
  assert.deepEqual(missing, [], `untranslated interface copy: ${missing.join(' | ')}`)
})
