import React from 'react'
import { createRoot } from 'react-dom/client'
import { AppShell } from '@/components/AppShell'
import { HomeScreen, ScreenRouter } from '@/components/Screens'
import { usePathname } from 'next/navigation'
import '@/app/globals.css'
import './mobile.css'

const API_ORIGIN = 'https://openly.ink'
const webFetch = window.fetch.bind(window)
const pendingNativeRequests = new Map()

function apiPath(input) {
  if (typeof input === 'string' && input.startsWith('/api/')) return input
  if (input instanceof URL && input.origin === API_ORIGIN && input.pathname.startsWith('/api/')) return `${input.pathname}${input.search}`
  if (typeof Request !== 'undefined' && input instanceof Request) {
    const url = new URL(input.url)
    if (url.origin === API_ORIGIN && url.pathname.startsWith('/api/')) return `${url.pathname}${url.search}`
  }
  return null
}

window.__openlyNativeResolve = (id, payload) => {
  const pending = pendingNativeRequests.get(id)
  if (!pending) return
  pendingNativeRequests.delete(id)
  clearTimeout(pending.timer)
  const status = Number(payload?.status || 500)
  const body = [204, 205, 304].includes(status) ? null : String(payload?.body ?? '')
  pending.resolve(new Response(body, { status, headers: payload?.headers || {} }))
}

function nativeApiFetch(path, init = {}) {
  const bridge = window.webkit?.messageHandlers?.openlyApi
  if (!bridge) {
    return webFetch(`${API_ORIGIN}${path}`, { ...init, credentials: init.credentials || 'include' })
  }

  const id = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
  const headers = Object.fromEntries(new Headers(init.headers || {}).entries())
  let body = init.body ?? null
  if (body instanceof URLSearchParams) body = body.toString()
  if (body != null && typeof body !== 'string') body = JSON.stringify(body)

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pendingNativeRequests.delete(id)
      reject(new Error('انتهت مهلة الاتصال بالخادم'))
    }, 45000)
    pendingNativeRequests.set(id, { resolve, reject, timer })
    bridge.postMessage({
      id,
      path,
      method: String(init.method || 'GET').toUpperCase(),
      headers,
      body
    })
  })
}

window.fetch = (input, init = {}) => {
  const path = apiPath(input)
  return path ? nativeApiFetch(path, init) : webFetch(input, init)
}

if (window.location.pathname.endsWith('/index.html')) window.history.replaceState({}, '', '/')

function App() {
  const pathname = usePathname()
  const clean = pathname === '/' ? [] : pathname.split('/').filter(Boolean)
  return <AppShell>{pathname === '/' ? <HomeScreen /> : <ScreenRouter slug={clean} />}</AppShell>
}

createRoot(document.getElementById('root')).render(<App />)
