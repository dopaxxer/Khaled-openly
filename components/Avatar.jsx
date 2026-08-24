'use client'

export function Avatar({ code, color, size = 40 }) {
  return (
    <span
      className="avatar"
      aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.34), backgroundColor: color }}
    >
      {String(code || '').slice(0, 2)}
    </span>
  )
}
