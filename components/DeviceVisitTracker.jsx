'use client'

import { usePathname } from 'next/navigation'
import { useEffect } from 'react'

function detectBrowser(ua) {
  const rules = [
    ['Edge', /EdgA?\/(\d+(?:\.\d+)*)/],
    ['Chrome', /(?:Chrome|CriOS)\/(\d+(?:\.\d+)*)/],
    ['Firefox', /(?:Firefox|FxiOS)\/(\d+(?:\.\d+)*)/],
    ['Safari', /Version\/(\d+(?:\.\d+)*).*Safari/]
  ]
  for (const [name, re] of rules) {
    const match = ua.match(re)
    if (match) return { browser: name, browserVersion: match[1] || null }
  }
  return { browser: 'Other', browserVersion: null }
}

function detectDevice(ua, platform, touchPoints) {
  const isIPad = /iPad/i.test(ua) || (platform === 'MacIntel' && touchPoints > 1)
  if (isIPad) return 'iPad'
  if (/iPhone/i.test(ua)) return 'iPhone'
  if (/Android/i.test(ua)) return /Mobile/i.test(ua) ? 'Android phone' : 'Android tablet'
  if (/Windows/i.test(ua)) return 'Windows PC'
  if (/Macintosh|Mac OS X/i.test(ua)) return 'Mac'
  if (/Linux/i.test(ua)) return 'Linux PC'
  return 'Other'
}

function detectOS(ua, platform, touchPoints) {
  const ipad = /iPad/i.test(ua) || (platform === 'MacIntel' && touchPoints > 1)
  const ios = ua.match(/(?:CPU (?:iPhone )?OS|iPhone OS) ([\d_]+)/i)
  if (ipad || /iPhone/i.test(ua)) return { os: ipad ? 'iPadOS' : 'iOS', osVersion: ios?.[1]?.replaceAll('_', '.') || null }
  const android = ua.match(/Android\s+([\d.]+)/i)
  if (android) return { os: 'Android', osVersion: android[1] }
  const windows = ua.match(/Windows NT\s+([\d.]+)/i)
  if (windows) return { os: 'Windows', osVersion: windows[1] }
  const mac = ua.match(/Mac OS X\s+([\d_]+)/i)
  if (mac) return { os: 'macOS', osVersion: mac[1].replaceAll('_', '.') }
  return { os: platform || 'Other', osVersion: null }
}

async function getClientHints() {
  try {
    if (!navigator.userAgentData?.getHighEntropyValues) return null
    return await navigator.userAgentData.getHighEntropyValues([
      'model',
      'platformVersion',
      'fullVersionList'
    ])
  } catch {
    return null
  }
}

function getSessionId() {
  try {
    const key = 'openly:device-session'
    let id = sessionStorage.getItem(key)
    if (!id && globalThis.crypto?.randomUUID) {
      id = globalThis.crypto.randomUUID()
      sessionStorage.setItem(key, id)
    }
    return id || null
  } catch {
    return null
  }
}

export function DeviceVisitTracker() {
  const pathname = usePathname()

  useEffect(() => {
    if (!pathname) return

    let cancelled = false

    async function track() {
      try {
        const dedupeKey = `openly:last-device-visit:${pathname}`
        const now = Date.now()
        const previous = Number(sessionStorage.getItem(dedupeKey) || 0)
        if (now - previous < 10000) return
        sessionStorage.setItem(dedupeKey, String(now))

        const ua = navigator.userAgent || ''
        const platform = navigator.platform || navigator.userAgentData?.platform || null
        const touchPoints = Number(navigator.maxTouchPoints || 0)
        const hints = await getClientHints()
        if (cancelled) return

        const browserInfo = detectBrowser(ua)
        const osInfo = detectOS(ua, platform, touchPoints)
        const hintedBrowser = hints?.fullVersionList?.[0]

        const payload = {
          sessionId: getSessionId(),
          pagePath: pathname,
          deviceType: detectDevice(ua, platform, touchPoints),
          deviceModel: hints?.model || null,
          os: osInfo.os,
          osVersion: hints?.platformVersion || osInfo.osVersion,
          browser: browserInfo.browser,
          browserVersion: hintedBrowser?.version || browserInfo.browserVersion,
          userAgent: ua,
          platform,
          language: navigator.language || null,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || null,
          screenWidth: window.screen?.width || null,
          screenHeight: window.screen?.height || null,
          pixelRatio: window.devicePixelRatio || null,
          touchPoints
        }

        await fetch('/api/device-visit', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(payload),
          keepalive: true,
          cache: 'no-store'
        }).catch(() => null)
      } catch {
        // Tracking must never interfere with the product experience.
      }
    }

    // Analytics must never be in front of the page it measures: this used to
    // fire during the same tick as the feed's first request, competing with it
    // for the connection and the main thread. Idle time is soon enough.
    const idle = globalThis.requestIdleCallback
      ? globalThis.requestIdleCallback(track, { timeout: 4000 })
      : globalThis.setTimeout(track, 1200)

    return () => {
      cancelled = true
      if (globalThis.cancelIdleCallback && globalThis.requestIdleCallback) globalThis.cancelIdleCallback(idle)
      else globalThis.clearTimeout(idle)
    }
  }, [pathname])

  return null
}
