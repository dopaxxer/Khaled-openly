'use client'
import Link from 'next/link'

export function Identity({ code, color, large = false }) {
  if (!code) return null
  return (
    <Link href={`/u/${code}`} className={`identity${large ? ' large' : ''}`}>
      <span className="dot" style={{ backgroundColor: color }} aria-hidden="true" />
      <span>{code}</span>
    </Link>
  )
}
