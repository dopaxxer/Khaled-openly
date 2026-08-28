'use client'

import Link from 'next/link'
import { ChevronLeft, MessageCircle, Send } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { Identity } from './Identity'

function formatMessageTime(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return new Intl.DateTimeFormat('ar', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date)
}

function mergeMessages(current, incoming) {
  const byId = new Map(current.map(item => [item.id, item]))
  for (const item of incoming || []) byId.set(item.id, item)
  return [...byId.values()].sort((a, b) => {
    const delta = new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
    return delta || String(a.id).localeCompare(String(b.id))
  })
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
  const pendingRetry = useRef(null)
  const bottomRef = useRef(null)

  const markRead = useCallback(async () => {
    const response = await fetch(`/api/v1/messages/${conversationId}/read`, { method: 'POST' }).catch(() => null)
    if (response?.ok) window.dispatchEvent(new Event('openly:messages-changed'))
  }, [conversationId])

  const loadLatest = useCallback(async ({ silent = false } = {}) => {
    if (!silent) setError('')
    try {
      const response = await fetch(`/api/v1/messages/${conversationId}?limit=100`, { cache: 'no-store' })
      if (response.status === 401) {
        location.href = '/login'
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'المحادثة غير متاحة')
      setConversation(data.conversation)
      setMessages(current => mergeMessages(current, data.items || []))
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
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') loadLatest({ silent: true })
    }, 5000)
    return () => window.clearInterval(timer)
  }, [loadLatest])

  useEffect(() => {
    if (!loading) bottomRef.current?.scrollIntoView({ block: 'end' })
  }, [loading])

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
      setMessages(current => mergeMessages(current, [data.message]))
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
      </Link>
    </header>

    <div className="message-thread-scroll">
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
              onChange={event => setDraft(event.target.value)}
              maxLength={2000}
              rows={2}
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
