'use client'
import Link from 'next/link'

export function Identity({ code, color, large = false, linked = true }) {
  if (!code) return null
  const content = <>
    <span className="dot" style={{ backgroundColor: color }} aria-hidden="true" />
    <span>{code}</span>
  </>
  return linked ? (
    <Link href={`/u/${code}`} className={`identity${large ? ' large' : ''}`}>
      {content}
    </Link>
  ) : <span className={`identity${large ? ' large' : ''}`}>{content}</span>
}
