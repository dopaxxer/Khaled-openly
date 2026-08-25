// A tiny, safe rendering pass for post/comment bodies. It only ever builds
// React elements from plain-text runs — never dangerouslySetInnerHTML — so
// there is no HTML-injection surface no matter what a user types. Supported
// syntax is intentionally small: **bold**, *italic*, "- " list lines, and
// @CODE mentions.
//
// Mentions are highlighted only when the server said the code resolves to a
// profile the viewer may see. A typo, a deleted account or a block therefore
// leaves the text exactly as written instead of producing a dead link.

import Link from 'next/link'
import { splitMentionSegments } from './mentions'

function renderMentions(text, resolved, keyPrefix) {
  if (!resolved || resolved.size === 0) return text
  const segments = splitMentionSegments(text, resolved)
  if (segments.length === 1 && segments[0].type === 'text') return text

  return segments.map((segment, index) => {
    if (segment.type !== 'mention') return segment.value
    return (
      <Link
        key={`${keyPrefix}-m${index}`}
        href={`/u/${segment.code}`}
        className="mention"
        dir="ltr"
        aria-label={`الملف الشخصي للكود ${segment.code}`}
      >
        {segment.value}
      </Link>
    )
  })
}

function renderInline(text, keyPrefix, resolved) {
  // Bold first, then italic, so "**x**" isn't first split by its inner "*"s.
  const boldSplit = text.split(/(\*\*[^*\n]+\*\*)/g)
  const nodes = []
  boldSplit.forEach((chunk, i) => {
    const boldMatch = chunk.match(/^\*\*([^*\n]+)\*\*$/)
    if (boldMatch) {
      nodes.push(<strong key={`${keyPrefix}-b${i}`}>{renderMentions(boldMatch[1], resolved, `${keyPrefix}-b${i}`)}</strong>)
      return
    }
    const italicSplit = chunk.split(/(\*[^*\n]+\*)/g)
    italicSplit.forEach((part, j) => {
      const italicMatch = part.match(/^\*([^*\n]+)\*$/)
      if (italicMatch) nodes.push(<em key={`${keyPrefix}-i${i}-${j}`}>{renderMentions(italicMatch[1], resolved, `${keyPrefix}-i${i}-${j}`)}</em>)
      else if (part) nodes.push(<span key={`${keyPrefix}-t${i}-${j}`}>{renderMentions(part, resolved, `${keyPrefix}-t${i}-${j}`)}</span>)
    })
  })
  return nodes
}

export function renderRichText(body, options = {}) {
  const resolved = new Set(
    (options.mentions || [])
      .map(mention => String(mention?.publicCode || '').toUpperCase())
      .filter(Boolean)
  )

  const lines = String(body || '').split('\n')
  const blocks = []
  let listItems = null

  function flushList() {
    if (listItems) {
      blocks.push(<ul key={`ul${blocks.length}`}>{listItems}</ul>)
      listItems = null
    }
  }

  lines.forEach((line, i) => {
    const listMatch = line.match(/^-\s+(.*)$/)
    if (listMatch) {
      if (!listItems) listItems = []
      listItems.push(<li key={`li${i}`}>{renderInline(listMatch[1], `li${i}`, resolved)}</li>)
      return
    }
    flushList()
    if (line === '') {
      blocks.push(<br key={`br${i}`} />)
    } else {
      blocks.push(<span key={`ln${i}`}>{renderInline(line, `ln${i}`, resolved)}{i < lines.length - 1 ? <br /> : null}</span>)
    }
  })
  flushList()

  return blocks
}
