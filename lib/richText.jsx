// A tiny, safe rendering pass for post/comment bodies. It only ever builds
// React elements from plain-text runs — never dangerouslySetInnerHTML — so
// there is no HTML-injection surface no matter what a user types. Supported
// syntax is intentionally small: **bold**, *italic*, and "- " list lines.

function renderInline(text, keyPrefix) {
  // Bold first, then italic, so "**x**" isn't first split by its inner "*"s.
  const boldSplit = text.split(/(\*\*[^*\n]+\*\*)/g)
  const nodes = []
  boldSplit.forEach((chunk, i) => {
    const boldMatch = chunk.match(/^\*\*([^*\n]+)\*\*$/)
    if (boldMatch) {
      nodes.push(<strong key={`${keyPrefix}-b${i}`}>{boldMatch[1]}</strong>)
      return
    }
    const italicSplit = chunk.split(/(\*[^*\n]+\*)/g)
    italicSplit.forEach((part, j) => {
      const italicMatch = part.match(/^\*([^*\n]+)\*$/)
      if (italicMatch) nodes.push(<em key={`${keyPrefix}-i${i}-${j}`}>{italicMatch[1]}</em>)
      else if (part) nodes.push(part)
    })
  })
  return nodes
}

export function renderRichText(body) {
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
      listItems.push(<li key={`li${i}`}>{renderInline(listMatch[1], `li${i}`)}</li>)
      return
    }
    flushList()
    if (line === '') {
      blocks.push(<br key={`br${i}`} />)
    } else {
      blocks.push(<span key={`ln${i}`}>{renderInline(line, `ln${i}`)}{i < lines.length - 1 ? <br /> : null}</span>)
    }
  })
  flushList()

  return blocks
}
