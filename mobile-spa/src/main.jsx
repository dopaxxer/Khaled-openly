import React from 'react'
import { createRoot } from 'react-dom/client'
import { AppShell } from '@/components/AppShell'
import { HomeScreen, ScreenRouter } from '@/components/Screens'
import { usePathname } from 'next/navigation'
import '@/app/globals.css'
import './mobile.css'

const API_ORIGIN = 'https://openly.ink'
const nativeFetch = window.fetch.bind(window)

function remoteApiUrl(value) {
  if (typeof value === 'string' && value.startsWith('/api/')) return `${API_ORIGIN}${value}`
  if (value instanceof URL && value.pathname.startsWith('/api/')) return new URL(`${API_ORIGIN}${value.pathname}${value.search}`)
  return value
}

window.fetch = (input, init = {}) => {
  const resolved = remoteApiUrl(input)
  const requestInit = { ...init }
  if ((typeof resolved === 'string' && resolved.startsWith(API_ORIGIN)) || (resolved instanceof URL && resolved.origin === API_ORIGIN)) {
    requestInit.credentials = init.credentials || 'include'
  }
  return nativeFetch(resolved, requestInit)
}

if (window.location.pathname.endsWith('/index.html')) window.history.replaceState({}, '', '/')

function App() {
  const pathname = usePathname()
  const clean = pathname === '/' ? [] : pathname.split('/').filter(Boolean)
  return <AppShell>{pathname === '/' ? <HomeScreen /> : <ScreenRouter slug={clean} />}</AppShell>
}

createRoot(document.getElementById('root')).render(<App />)
