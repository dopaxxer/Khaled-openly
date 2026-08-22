// Selection-based markdown-lite toggles shared by the composer and the
// inline post editor. Each function takes the raw value plus the current
// selection and returns { value, start, end } so the caller can write the
// new value back and restore the selection in one step.

export function toggleWrap(value, start, end, marker) {
  const before = value.slice(0, start)
  const selected = value.slice(start, end)
  const after = value.slice(end)
  const already = before.endsWith(marker) && after.startsWith(marker)

  if (already) {
    return {
      value: before.slice(0, -marker.length) + selected + after.slice(marker.length),
      start: start - marker.length,
      end: end - marker.length
    }
  }

  const insideWrapped = selected.startsWith(marker) && selected.endsWith(marker) && selected.length >= marker.length * 2
  if (insideWrapped) {
    const inner = selected.slice(marker.length, -marker.length)
    return { value: before + inner + after, start, end: start + inner.length }
  }

  const placeholder = selected || 'نص'
  return {
    value: `${before}${marker}${placeholder}${marker}${after}`,
    start: start + marker.length,
    end: start + marker.length + placeholder.length
  }
}

export function toggleListPrefix(value, start, end) {
  const lineStart = value.lastIndexOf('\n', start - 1) + 1
  const nextBreak = value.indexOf('\n', end)
  const lineEnd = nextBreak === -1 ? value.length : nextBreak

  const block = value.slice(lineStart, lineEnd)
  const lines = block.split('\n')
  const allPrefixed = lines.every(l => l.startsWith('- ') || l.trim() === '')

  const nextLines = lines.map(l => {
    if (l.trim() === '') return l
    return allPrefixed ? l.replace(/^- /, '') : (l.startsWith('- ') ? l : `- ${l}`)
  })
  const nextBlock = nextLines.join('\n')

  return {
    value: value.slice(0, lineStart) + nextBlock + value.slice(lineEnd),
    start: lineStart,
    end: lineStart + nextBlock.length
  }
}
