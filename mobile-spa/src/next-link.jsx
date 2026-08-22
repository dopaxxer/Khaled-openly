import React from 'react'
import { navigate } from './next-navigation'

export default function Link({ href = '/', onClick, children, target, ...props }) {
  const url = typeof href === 'string' ? href : href?.pathname || '/'
  const external = /^https?:\/\//i.test(url) || url.startsWith('mailto:') || url.startsWith('tel:')

  return <a
    href={url}
    target={target}
    {...props}
    onClick={event => {
      onClick?.(event)
      if (event.defaultPrevented || external || target === '_blank' || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      event.preventDefault()
      navigate(url)
    }}
  >{children}</a>
}
