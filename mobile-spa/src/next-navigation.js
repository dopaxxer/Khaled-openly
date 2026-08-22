import { useEffect, useState } from 'react'

const NAV_EVENT = 'openly:navigate'

function currentPath() {
  const path = window.location.pathname || '/'
  return path.startsWith('/') ? path : `/${path}`
}

function notify() {
  window.dispatchEvent(new Event(NAV_EVENT))
}

export function navigate(href, replace = false) {
  const url = typeof href === 'string' ? href : href?.pathname || '/'
  if (/^https?:\/\//i.test(url)) {
    window.location.href = url
    return
  }
  if (replace) window.history.replaceState({}, '', url)
  else window.history.pushState({}, '', url)
  notify()
  window.scrollTo({ top: 0, behavior: 'instant' })
}

export function usePathname() {
  const [path, setPath] = useState(() => currentPath())
  useEffect(() => {
    const update = () => setPath(currentPath())
    window.addEventListener('popstate', update)
    window.addEventListener(NAV_EVENT, update)
    return () => {
      window.removeEventListener('popstate', update)
      window.removeEventListener(NAV_EVENT, update)
    }
  }, [])
  return path
}

export function useRouter() {
  return {
    push: href => navigate(href, false),
    replace: href => navigate(href, true),
    back: () => window.history.back(),
    forward: () => window.history.forward(),
    refresh: notify,
    prefetch: async () => {}
  }
}
