'use client'

import Link from 'next/link'
import { ChevronLeft, MessageCircle, Send } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { Identity } from './Identity'

// A thread re-renders on every poll, so this runs once per message every few
// seconds. Constructing the formatter is the expensive part; the format never
// changes, so it is built once for the module.
const messageTimeFormat = new Intl.DateTimeFormat('ar', {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit'
})

function formatMessageTime(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return messageTimeFormat.format(date)
}

function mergeMessages(current, incoming) {
  const byId = new Map(current.map(item => [item.id, item]))
  for (const item of incoming || []) byId.set(item.id, item)
  return [...byId.values()].sort((a, b) => {
    const delta = new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
    return delta || String(a.id).localeCompare(String(b.id))
  })
}

function messageCursor(message) {
  return message?.createdAt && message?.id ? `${message.createdAt}|${message.id}` : null
}

// The thread polls every 2.5 seconds and a quiet conversation answers with
// nothing new every time. Handing React a fresh array or a fresh conversation
// object regardless re-rendered every bubble on screen twenty-four times a
// minute for no change at all, so each poll now keeps the state it already has
// unless something in it actually moved.
function sameMessages(current, merged) {
  if (current === merged) return true
  if (current.length !== merged.length) return false
  return current.every((message, index) => message === merged[index])
}

function sameConversation(current, incoming) {
  if (current === incoming) return true
  if (!current || !incoming) return false
  const keys = new Set([...Object.keys(current), ...Object.keys(incoming)])
  for (const key of keys) {
    if (current[key] !== incoming[key]) return false
  }
  return true
}

export function MessagesInbox() {
  const [state, setState] = useState({ loading: true, unauthorized: false, items: [], error: '' })

  const load = useCallback(async () => {
    try {
      const response = await fetch('/api/v1/messages?limit=50', { cache: 'no-store' })
      if (response.status === 401) {
        setState({ loading: false, unauthorized: true, items: [], error: '' })
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الرسائل')
      setState({ loading: false, unauthorized: false, items: data.items || [], error: '' })
    } catch (error) {
      setState(previous => ({ ...previous, loading: false, error: error.message || 'تعذر تحميل الرسائل' }))
    }
  }, [])

  useEffect(() => { load() }, [load])

  if (state.unauthorized) {
    return <div className="empty-state"><div>
      <p>سجّل الدخول لرؤية رسائلك.</p>
      <Link href="/login" className="primary-button mt16">تسجيل الدخول</Link>
    </div></div>
  }

  return <>
    <header className="page-header">
      <div className="page-title-row"><MessageCircle size={20} /><h1 className="page-title">الرسائل</h1></div>
      <p className="page-description">محادثاتك الخاصة بين هويات Openly. لا يظهر بريدك أو اسمك الحقيقي.</p>
    </header>

    {state.loading
      ? <div className="screen-pad"><div className="skeleton" /></div>
      : state.error
        ? <div className="empty-state"><div><p>{state.error}</p><button className="secondary-button mt16" onClick={load}>المحاولة مجددًا</button></div></div>
        : state.items.length
          ? <div className="message-conversation-list">
              {state.items.map(item => <Link key={item.conversationId} href={`/messages/${item.conversationId}`} className="message-conversation-row">
                <Identity code={item.publicCode} color={item.identityColor} />
                <div className="message-conversation-copy">
                  <div className="message-conversation-head">
                    <strong dir="ltr">{item.publicCode}</strong>
                    <span className="tiny subtle">{formatMessageTime(item.lastMessageAt)}</span>
                  </div>
                  <div className="message-conversation-preview">
                    {item.lastMessageBody
                      ? <><span className="tiny subtle">{item.lastMessageIsMine ? 'أنت: ' : ''}</span><span className="small muted" data-user-content="">{item.lastMessageBody}</span></>
                      : <span className="small muted">لا توجد رسائل في هذه المحادثة بعد.</span>}
                  </div>
                </div>
                {item.unreadCount > 0 && <span className="nav-badge">{item.unreadCount > 99 ? '99+' : item.unreadCount}</span>}
                <ChevronLeft size={16} className="message-chevron" aria-hidden="true" />
              </Link>)}
            </div>
          : <div className="empty-state"><div>
              <MessageCircle size={28} />
              <p>لا توجد رسائل بعد.</p>
              <p className="small muted mt8">ابدأ من صفحة أي هوية واضغط «رسالة خاصة».</p>
            </div></div>}
  </>
}

export function MessageThread({ conversationId }) {
  const [conversation, setConversation] = useState(undefined)
  const [messages, setMessages] = useState([])
  const [olderCursor, setOlderCursor] = useState(null)
  const [hasMore, setHasMore] = useState(false)
  const [draft, setDraft] = useState('')
  const [loading, setLoading] = useState(true)
  const [loadingOlder, setLoadingOlder] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState('')
  const [presence, setPresence] = useState({ online: false, typing: false })
  const pendingRetry = useRef(null)
  const bottomRef = useRef(null)
  const scrollerRef = useRef(null)
  const latestCursor = useRef(null)
  const refreshBusy = useRef(false)
  const lastTypingSentAt = useRef(0)
  const typingStopTimer = useRef(null)

  const markRead = useCallback(async () => {
    const response = await fetch(`/api/v1/messages/${conversationId}/read`, { method: 'POST' }).catch(() => null)
    if (response?.ok) window.dispatchEvent(new Event('openly:messages-changed'))
  }, [conversationId])

  const loadLatest = useCallback(async ({ silent = false } = {}) => {
    if (!silent) setError('')
    try {
      const query = silent && latestCursor.current
        ? `?limit=50&after=${encodeURIComponent(latestCursor.current)}`
        : '?limit=60'
      const response = await fetch(`/api/v1/messages/${conversationId}${query}`, { cache: 'no-store' })
      if (response.status === 401) {
        location.href = '/login'
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'المحادثة غير متاحة')
      setConversation(current => sameConversation(current, data.conversation) ? current : data.conversation)
      setMessages(current => {
        const merged = mergeMessages(current, data.items || [])
        latestCursor.current = messageCursor(merged[merged.length - 1])
        return sameMessages(current, merged) ? current : merged
      })
      if (!silent) {
        setOlderCursor(data.nextCursor || null)
        setHasMore(!!data.hasMore)
      }
      if (Number(data.conversation?.unreadCount || 0) > 0) await markRead()
    } catch (loadError) {
      if (!silent) setError(loadError.message || 'المحادثة غير متاحة')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [conversationId, markRead])

  useEffect(() => {
    setConversation(undefined)
    setMessages([])
    setLoading(true)
    loadLatest()
  }, [loadLatest])

  useEffect(() => {
    const timer = window.setInterval(async () => {
      if (document.visibilityState !== 'visible' || refreshBusy.current) return
      refreshBusy.current = true
      try { await loadLatest({ silent: true }) } finally { refreshBusy.current = false }
    }, 2500)
    return () => window.clearInterval(timer)
  }, [loadLatest])

  const touchPresence = useCallback(async (typing = false) => {
    await fetch(`/api/v1/messages/${conversationId}/presence`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ typing }),
      keepalive: true
    }).catch(() => null)
  }, [conversationId])

  const loadPresence = useCallback(async () => {
    const response = await fetch(`/api/v1/messages/${conversationId}/presence`, { cache: 'no-store' }).catch(() => null)
    if (!response?.ok) return
    const data = await response.json().catch(() => null)
    if (!data) return
    const online = !!data.online
    const typing = !!data.typing
    setPresence(current => current.online === online && current.typing === typing
      ? current
      : { online, typing })
  }, [conversationId])

  useEffect(() => {
    touchPresence(false)
    loadPresence()
    const heartbeat = window.setInterval(() => touchPresence(false), 15_000)
    const status = window.setInterval(() => {
      if (document.visibilityState === 'visible') loadPresence()
    }, 3000)
    return () => {
      window.clearInterval(heartbeat)
      window.clearInterval(status)
      if (typingStopTimer.current) window.clearTimeout(typingStopTimer.current)
      touchPresence(false)
    }
  }, [loadPresence, touchPresence])

  useEffect(() => {
    if (loading) return
    const last = messages[messages.length - 1]
    if (!last) return
    const node = scrollerRef.current
    const nearBottom = !node || (node.scrollHeight - node.scrollTop - node.clientHeight) < 80
    if (nearBottom) bottomRef.current?.scrollIntoView({ block: 'end' })
  }, [loading, messages])

  async function loadOlder() {
    if (!olderCursor || loadingOlder) return
    setLoadingOlder(true)
    try {
      const response = await fetch(`/api/v1/messages/${conversationId}?limit=100&cursor=${encodeURIComponent(olderCursor)}`, { cache: 'no-store' })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الرسائل')
      setMessages(current => mergeMessages(current, data.items || []))
      setOlderCursor(data.nextCursor || null)
      setHasMore(!!data.hasMore)
    } catch (loadError) {
      setError(loadError.message || 'تعذر تحميل الرسائل')
    } finally {
      setLoadingOlder(false)
    }
  }

  function updateDraft(value) {
    setDraft(value)
    const hasText = !!value.trim()
    const now = Date.now()
    if (hasText && now - lastTypingSentAt.current > 1100) {
      lastTypingSentAt.current = now
      touchPresence(true)
    }
    if (typingStopTimer.current) window.clearTimeout(typingStopTimer.current)
    typingStopTimer.current = window.setTimeout(() => touchPresence(false), 2200)
  }

  async function send(event) {
    event.preventDefault()
    const body = draft.trim()
    if (!body || sending || conversation?.canMessage === false) return

    const retry = pendingRetry.current
    const clientNonce = retry?.body === body ? retry.clientNonce : crypto.randomUUID()
    pendingRetry.current = { body, clientNonce }
    setSending(true)
    setError('')

    try {
      const response = await fetch(`/api/v1/messages/${conversationId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body, clientNonce })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر إرسال الرسالة')
      pendingRetry.current = null
      setDraft('')
      setMessages(current => {
        const merged = mergeMessages(current, [data.message])
        latestCursor.current = messageCursor(merged[merged.length - 1])
        return merged
      })
      touchPresence(false)
      window.dispatchEvent(new Event('openly:messages-changed'))
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }))
    } catch (sendError) {
      setError(sendError.message || 'تعذر إرسال الرسالة')
    } finally {
      setSending(false)
    }
  }

  if (loading) return <div className="screen-pad"><div className="skeleton" /></div>
  if (!conversation) return <div className="empty-state"><div><p>{error || 'المحادثة غير متاحة'}</p><Link href="/messages" className="secondary-button mt16">العودة إلى الرسائل</Link></div></div>

  return <div className="message-thread">
    <header className="message-thread-header">
      <Link href="/messages" className="icon-button" aria-label="العودة إلى الرسائل"><ChevronLeft size={20} /></Link>
      <Link href={`/u/${conversation.publicCode}`} className="message-peer">
        <Identity code={conversation.publicCode} color={conversation.identityColor} />
        <span className="message-peer-copy">
          <strong dir="ltr">{conversation.publicCode}</strong>
          <span className={`message-presence${presence.online ? ' online' : ''}`}>
            <span className="message-presence-dot" aria-hidden="true" />
            {presence.typing ? 'يكتب…' : presence.online ? 'متصل الآن' : 'غير متصل'}
          </span>
        </span>
      </Link>
    </header>

    <div className="message-thread-scroll" ref={scrollerRef}>
      {hasMore && <button className="secondary-button message-load-older" onClick={loadOlder} disabled={loadingOlder}>
        {loadingOlder ? 'جارِ التحميل…' : 'عرض رسائل أقدم'}
      </button>}

      {!messages.length && <div className="empty-state compact"><p>لا توجد رسائل في هذه المحادثة بعد.</p></div>}

      <div className="message-bubbles">
        {messages.map(message => <div key={message.id} className={`message-bubble-row${message.isMine ? ' mine' : ''}`}>
          <div className={`message-bubble${message.isMine ? ' mine' : ''}`}>
            <p data-user-content="">{message.body}</p>
            <span className="message-time">{formatMessageTime(message.createdAt)}</span>
          </div>
        </div>)}
        <div ref={bottomRef} />
      </div>
    </div>

    <div className="message-composer">
      {conversation.canMessage === false
        ? <p className="small muted">لا يمكن إرسال رسائل جديدة في هذه المحادثة.</p>
        : <form onSubmit={send} className="message-compose-form">
            <textarea
              className="form-control"
              value={draft}
              onChange={event => {
                updateDraft(event.target.value)
                event.currentTarget.style.height = '44px'
                event.currentTarget.style.height = Math.min(event.currentTarget.scrollHeight, 140) + 'px'
              }}
              maxLength={2000}
              rows={1}
              placeholder="اكتب رسالة خاصة…"
              aria-label="اكتب رسالة خاصة…"
            />
            <button className="primary-button" disabled={sending || !draft.trim()} aria-label="إرسال">
              <Send size={17} aria-hidden="true" />{sending ? 'جارِ الإرسال…' : 'إرسال'}
            </button>
          </form>}
      {error && <p className="status-message error">{error}</p>}
    </div>
  </div>
}
