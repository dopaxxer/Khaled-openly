'use client'

import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { activeMentionQuery, applyMentionCompletion } from '@/lib/mentions'

// A textarea that offers public-code completions while you type "@".
//
// Built as an ARIA combobox over a listbox so screen readers announce the
// suggestions and the active option; arrow keys, Enter, Tab and Escape all
// behave the way people expect from a mention menu. The menu is a sibling of
// the textarea rather than an overlay inside it, so it never fights the iOS
// keyboard for space.
const DEBOUNCE_MS = 140

export function MentionField({
  value,
  onChange,
  textareaRef,
  className = 'form-control',
  ...textareaProps
}) {
  const listboxId = useId()
  const internalRef = useRef(null)
  const inputRef = textareaRef || internalRef
  const [range, setRange] = useState(null)
  const [items, setItems] = useState([])
  const [activeIndex, setActiveIndex] = useState(0)
  const [open, setOpen] = useState(false)
  const requestId = useRef(0)

  const query = range?.query ?? null

  useEffect(() => {
    if (query === null) {
      setItems([])
      setOpen(false)
      return
    }

    // An empty "@" is a valid thing to be typing but not a useful search.
    if (query.length === 0) {
      setItems([])
      setOpen(false)
      return
    }

    const ticket = ++requestId.current
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(
          `/api/v1/mentions/suggest?q=${encodeURIComponent(query)}`,
          { cache: 'no-store', signal: controller.signal }
        )
        if (!response.ok) throw new Error('suggest failed')
        const data = await response.json()
        // A slower earlier request must not overwrite a newer result.
        if (ticket !== requestId.current) return
        setItems(data.items || [])
        setActiveIndex(0)
        setOpen((data.items || []).length > 0)
      } catch {
        if (ticket === requestId.current) {
          setItems([])
          setOpen(false)
        }
      }
    }, DEBOUNCE_MS)

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [query])

  const syncRange = useCallback(() => {
    const element = inputRef.current
    if (!element) return
    setRange(activeMentionQuery(element.value, element.selectionStart))
  }, [inputRef])

  function handleChange(event) {
    onChange(event.target.value)
    // The caret position is only correct after the value lands, and reading it
    // synchronously here matches what the user just typed.
    setRange(activeMentionQuery(event.target.value, event.target.selectionStart))
  }

  function choose(item) {
    const element = inputRef.current
    if (!element || !range) return
    const result = applyMentionCompletion(element.value, range, item.publicCode)
    onChange(result.value)
    setOpen(false)
    setItems([])
    setRange(null)
    requestAnimationFrame(() => {
      element.focus()
      element.setSelectionRange(result.caret, result.caret)
    })
  }

  function handleKeyDown(event) {
    if (!open || items.length === 0) return

    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setActiveIndex(index => (index + 1) % items.length)
      return
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault()
      setActiveIndex(index => (index - 1 + items.length) % items.length)
      return
    }
    if (event.key === 'Enter' || event.key === 'Tab') {
      event.preventDefault()
      choose(items[activeIndex])
      return
    }
    if (event.key === 'Escape') {
      event.preventDefault()
      setOpen(false)
    }
  }

  const activeOptionId = open && items[activeIndex] ? `${listboxId}-${activeIndex}` : undefined

  return (
    <div className="mention-field">
      <textarea
        {...textareaProps}
        ref={inputRef}
        className={className}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        onKeyUp={syncRange}
        onClick={syncRange}
        onBlur={() => {
          // Let a click on an option land before the menu closes.
          setTimeout(() => setOpen(false), 120)
        }}
        role="combobox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        aria-activedescendant={activeOptionId}
        aria-autocomplete="list"
      />

      {open && items.length > 0 && (
        <ul className="mention-menu" id={listboxId} role="listbox" aria-label="اقتراحات الأكواد">
          {items.map((item, index) => (
            <li
              key={item.publicCode}
              id={`${listboxId}-${index}`}
              role="option"
              aria-selected={index === activeIndex}
              className={`mention-option${index === activeIndex ? ' active' : ''}`}
              onMouseDown={event => event.preventDefault()}
              onMouseEnter={() => setActiveIndex(index)}
              onClick={() => choose(item)}
            >
              <span className="mention-option-dot" style={{ backgroundColor: item.identityColor }} aria-hidden="true" />
              <span className="mention-option-code" dir="ltr">{item.publicCode}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
