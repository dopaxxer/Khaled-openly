'use client'
import { useEffect, useState } from 'react'
import { COLOR_THEME_STORAGE_KEY, COLOR_THEMES, THEME_STORAGE_KEY, isColorTheme, isThemePreference } from '@/lib/theme'

const OPTIONS = [
  { value: 'system', label: 'حسب الجهاز' },
  { value: 'light', label: 'فاتح' },
  { value: 'dark', label: 'داكن' }
]

// Kept in the browser rather than on the profile: a theme belongs to the screen
// you are reading on, not to who you are. The same person wants dark on a
// phone at night and light at a desk at noon.
function applyMode(preference) {
  const root = document.documentElement
  if (preference === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', preference)

  const resolved = preference === 'system'
    ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : preference

  // The <meta> pair is media-query based, so it keeps following the device
  // after an override — resolve and write it through, or the phone's status
  // bar ends up the opposite of the page.
  for (const meta of document.querySelectorAll('meta[name="theme-color"]')) {
    meta.content = resolved === 'dark' ? '#05070f' : '#f5f5f4'
  }

  try {
    if (preference === 'system') localStorage.removeItem(THEME_STORAGE_KEY)
    else localStorage.setItem(THEME_STORAGE_KEY, preference)
  } catch {
    // Private browsing and blocked site data both throw. The theme still
    // applies for this visit; it just will not be remembered.
  }
}

function applyColor(value) {
  const root = document.documentElement
  if (value === 'ultramarine') root.removeAttribute('data-color-theme')
  else root.setAttribute('data-color-theme', value)

  try {
    if (value === 'ultramarine') localStorage.removeItem(COLOR_THEME_STORAGE_KEY)
    else localStorage.setItem(COLOR_THEME_STORAGE_KEY, value)
  } catch {
    // Same as the mode preference above — applies for this visit only.
  }
}

export function ThemeControl() {
  // Both start at their default on server and client alike so the first
  // render matches the server markup — reading storage during render would
  // be a hydration mismatch. The page is already correct by then: the boot
  // script in app/layout.jsx stamped both attributes before paint.
  const [preference, setPreference] = useState('system')
  const [color, setColor] = useState('ultramarine')

  useEffect(() => {
    try {
      const stored = localStorage.getItem(THEME_STORAGE_KEY)
      if (isThemePreference(stored)) setPreference(stored)
      const storedColor = localStorage.getItem(COLOR_THEME_STORAGE_KEY)
      if (isColorTheme(storedColor)) setColor(storedColor)
    } catch {
      // Unreadable storage just means the defaults, already in state.
    }
  }, [])

  function chooseMode(next) {
    setPreference(next)
    applyMode(next)
  }

  function chooseColor(next) {
    setColor(next)
    applyColor(next)
  }

  return <section aria-labelledby="theme-heading">
    <h2 className="page-title" id="theme-heading" style={{ fontSize: 16 }}>المظهر</h2>
    <p className="small muted mt8">كيف يظهر Openly على هذا الجهاز.</p>

    <div className="row wrap mt16" role="radiogroup" aria-label="وضع الإضاءة" style={{ gap: 8 }}>
      {OPTIONS.map(option => {
        const active = preference === option.value
        return <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={active}
          onClick={() => chooseMode(option.value)}
          className={active ? 'primary-button' : 'secondary-button'}
        >
          {option.label}
        </button>
      })}
    </div>

    <p className="small muted mt20">لون التمييز</p>
    <div className="row wrap mt8" role="radiogroup" aria-label="لون التمييز" style={{ gap: 10 }}>
      {COLOR_THEMES.map(theme => {
        const active = color === theme.value
        return <button
          key={theme.value}
          type="button"
          role="radio"
          aria-checked={active}
          aria-label={theme.label}
          title={theme.label}
          onClick={() => chooseColor(theme.value)}
          className={`swatch${active ? ' active' : ''}`}
          style={{ backgroundColor: theme.swatch }}
        />
      })}
    </div>
  </section>
}
