'use client'
import { ArrowLeft, Bold, Italic, List, Music2, Search, Send, X } from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'
import { Avatar } from './Avatar'
import { MentionField } from './MentionField'
import { toggleListPrefix, toggleWrap } from '@/lib/textFormatting'
import { POST_MAX_LENGTH } from '@/lib/validation'
import { fetchViewer } from '@/lib/viewer'

const MAX_LENGTH = POST_MAX_LENGTH

/**
 * `inline` renders the composer as a card at the top of a feed instead of a
 * page: no page heading, collapsed until it is tapped, and publishing refreshes
 * the feed in place rather than navigating. The native app has always opened
 * with this card; the web sent people to a separate screen for the same act.
 */
export function Composer({ firstPost = false, inline = false, onPublished = null }) {
  const router = useRouter()
  const [open, setOpen] = useState(!inline)
  const [body, setBody] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [viewer, setViewer] = useState(null)
  const [showTrackSearch, setShowTrackSearch] = useState(false)
  const [trackQuery, setTrackQuery] = useState('')
  const [trackResults, setTrackResults] = useState([])
  const [trackSearching, setTrackSearching] = useState(false)
  const [trackSearchDone, setTrackSearchDone] = useState(false)
  const [trackSaving, setTrackSaving] = useState('')
  const [trackError, setTrackError] = useState('')
  const [selectedTrack, setSelectedTrack] = useState(null)
  const textareaRef = useRef(null)
  const trackSearchTicket = useRef(0)

  useEffect(() => {
    let cancelled = false
    fetchViewer()
      .then(user => { if (!cancelled) setViewer(user) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    const term = trackQuery.trim()
    if (!showTrackSearch || !term) {
      setTrackResults([])
      setTrackSearching(false)
      setTrackSearchDone(false)
      return
    }

    const ticket = ++trackSearchTicket.current
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      setTrackSearching(true)
      setTrackSearchDone(false)
      setTrackError('')
      try {
        const response = await fetch(
          `/api/v1/music/tracks/search?q=${encodeURIComponent(term)}`,
          { cache: 'no-store', signal: controller.signal }
        )
        const data = await response.json().catch(() => ({}))
        if (!response.ok) throw new Error(data.error || 'تعذر البحث عن الأغاني')
        if (ticket === trackSearchTicket.current) {
          setTrackResults(Array.isArray(data.items) ? data.items : [])
          setTrackSearchDone(true)
        }
      } catch (searchError) {
        if (searchError.name !== 'AbortError' && ticket === trackSearchTicket.current) {
          setTrackResults([])
          setTrackSearchDone(true)
          setTrackError(searchError.message || 'تعذر البحث عن الأغاني')
        }
      } finally {
        if (ticket === trackSearchTicket.current) setTrackSearching(false)
      }
    }, 260)

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [showTrackSearch, trackQuery])

  // Starts small and grows with the text instead of opening as one large box —
  // the CSS max-height caps it so a long post scrolls internally rather than
  // pushing the publish button off screen.
  function grow(el) {
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }

  function format(kind) {
    const el = textareaRef.current
    if (!el) return
    const result = kind === 'list'
      ? toggleListPrefix(body, el.selectionStart, el.selectionEnd)
      : toggleWrap(body, el.selectionStart, el.selectionEnd, kind === 'bold' ? '**' : '*')
    setBody(result.value)
    // The value only updates on the next render; the selection restore has
    // to wait for that, and growing again keeps the box matching the new text.
    requestAnimationFrame(() => {
      el.focus()
      el.setSelectionRange(result.start, result.end)
      grow(el)
    })
  }

  async function chooseTrack(track) {
    if (trackSaving) return
    const key = `${track.provider}:${track.externalId}`
    setTrackSaving(key)
    setTrackError('')
    try {
      const response = await fetch('/api/v1/music/tracks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: track.provider, externalId: track.externalId })
      })
      const data = await response.json().catch(() => ({}))
      if (response.status === 401) {
        router.push('/login')
        return
      }
      if (!response.ok || !data.track?.id) throw new Error(data.error || 'تعذر إرفاق الأغنية')
      setSelectedTrack(data.track)
      setShowTrackSearch(false)
      setTrackQuery('')
      setTrackResults([])
    } catch (trackSaveError) {
      setTrackError(trackSaveError.message || 'تعذر إرفاق الأغنية')
    } finally {
      setTrackSaving('')
    }
  }

  async function publish() {
    if (!body.trim() || busy) return
    setBusy(true)
    setError('')
    try {
      const res = await fetch('/api/posts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body, trackId: selectedTrack?.id || null })
      })
      const data = await res.json()
      if (res.status === 401) {
        router.push('/login')
        return
      }
      if (!res.ok) throw new Error(data.error || 'تعذر النشر')
      if (inline) {
        setBody('')
        setSelectedTrack(null)
        setShowTrackSearch(false)
        setOpen(false)
        onPublished?.()
        return
      }
      router.push('/')
      router.refresh()
    } catch (e) {
      setError(e.message || 'تعذر النشر')
    } finally {
      setBusy(false)
    }
  }

  if (inline && !open) {
    return <button type="button" className="composer-prompt panel v2-composer-prompt" onClick={() => setOpen(true)}>
      <span className="v2-composer-prompt-copy">ماذا تريد أن تقول؟</span>
      <span className="v2-composer-prompt-tools" aria-hidden="true">+ موسيقى</span>
      <span className="v2-composer-prompt-post">نشر</span>
    </button>
  }

  return <section>
    {!inline && <header className="v2-composer-page-head">
      <Link href="/" className="v2-back-link">‹ العودة</Link>
      <div>
        <h1>{firstPost ? 'منشورك الأول' : 'منشور جديد'}</h1>
        <p>سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.</p>
      </div>
    </header>}
    <div className={`composer panel${inline ? ' v2-composer-expanded openly-composer-enter' : ''}`}>
      <div className="composer-toolbar" role="toolbar" aria-label="تنسيق النص">
        <button type="button" className="toolbar-button" aria-label="عريض" title="عريض" onClick={() => format('bold')}><Bold size={16}/></button>
        <button type="button" className="toolbar-button" aria-label="مائل" title="مائل" onClick={() => format('italic')}><Italic size={16}/></button>
        <button type="button" className="toolbar-button" aria-label="قائمة نقطية" title="قائمة نقطية" onClick={() => format('list')}><List size={16}/></button>
      </div>
      <div className="composer-row">
        {viewer && <Avatar code={viewer.publicCode} color={viewer.identityColor} size={40}/>}
        <MentionField
          textareaRef={textareaRef}
          className=""
          autoFocus
          value={body}
          onChange={next => { setBody(next); grow(textareaRef.current) }}
          maxLength={MAX_LENGTH}
          rows={3}
          placeholder="ماذا تريد أن تقول؟ اكتب @ للإشارة إلى كود"
          aria-label="نص المنشور"
        />
      </div>
      <div className="composer-attachments">
        {selectedTrack
          ? <div className="composer-track-selection">
              {selectedTrack.artworkUrl
                ? <img
                    className="track-artwork"
                    src={selectedTrack.artworkUrl}
                    alt=""
                    width={48}
                    height={48}
                    decoding="async"
                    referrerPolicy="no-referrer"
                  />
                : <span className="track-artwork track-artwork-fallback" aria-hidden="true"><Music2 size={19}/></span>}
              <span className="composer-track-meta" dir="auto" data-user-content="">
                <strong>{selectedTrack.title}</strong>
                <span className="tiny subtle">{selectedTrack.artist}</span>
              </span>
              <button
                type="button"
                className="track-remove-button"
                aria-label="إزالة الأغنية المرفقة"
                onClick={() => { setSelectedTrack(null); setTrackError('') }}
              ><X size={17}/></button>
            </div>
          : <>
              <button
                type="button"
                className="secondary-button composer-add-track"
                onClick={() => { setShowTrackSearch(open => !open); setTrackError('') }}
                aria-expanded={showTrackSearch}
              >
                <Music2 size={16}/>
                أضف أغنية
              </button>

              {showTrackSearch && <div className="composer-track-search panel">
                <label className="track-search-field">
                  <Search size={16} aria-hidden="true"/>
                  <input
                    className="form-control"
                    value={trackQuery}
                    onChange={event => setTrackQuery(event.target.value)}
                    placeholder="ابحث باسم الأغنية أو الفنان"
                    aria-label="البحث في كتالوج الأغاني"
                    autoFocus
                  />
                </label>

                {trackSearching && <p className="tiny subtle">جارِ البحث في كتالوج الموسيقى…</p>}
                {!trackQuery.trim() && <p className="tiny subtle">اكتب اسم أغنية أو فنان، ثم اختر نتيجة واحدة.</p>}
                {trackSearchDone && !trackSearching && !trackResults.length && !trackError && <p className="tiny subtle">لا توجد نتائج مطابقة.</p>}

                {trackResults.length > 0 && <ul className="result-list composer-track-results">
                  {trackResults.map(track => {
                    const key = `${track.provider}:${track.externalId}`
                    return <li key={key}>
                      <button
                        type="button"
                        className="result-row"
                        onClick={() => chooseTrack(track)}
                        disabled={!!trackSaving}
                      >
                        {track.artworkUrl
                          ? <img
                              className="track-artwork"
                              src={track.artworkUrl}
                              alt=""
                              width={48}
                              height={48}
                              loading="lazy"
                              decoding="async"
                              referrerPolicy="no-referrer"
                            />
                          : <span className="track-artwork track-artwork-fallback" aria-hidden="true"><Music2 size={19}/></span>}
                        <span className="composer-track-result-main" dir="auto" data-user-content="">
                          <strong>{track.title}</strong>
                          <span className="tiny subtle">{track.artist}</span>
                        </span>
                        <span className="tiny subtle">{trackSaving === key ? 'جارِ الإرفاق…' : 'اختيار'}</span>
                      </button>
                    </li>
                  })}
                </ul>}
              </div>}
            </>}
        {trackError && <p className="status-message error composer-track-error">{trackError}</p>}
      </div>
      <div className="composer-foot">
        <span className={`tiny ${body.length > MAX_LENGTH - 40 ? 'danger-text' : 'subtle'}`} dir="ltr">{body.length} / {MAX_LENGTH}</span>
        <span className="row" style={{ gap: 8 }}>
          {inline && <button
            type="button"
            className="secondary-button"
            onClick={() => { setOpen(false); setError('') }}
            disabled={busy}
          >إلغاء</button>}
          <button className="primary-button" onClick={publish} disabled={busy || !body.trim()}>
            <Send size={16} aria-hidden="true"/>
            {busy ? 'جارِ النشر…' : 'نشر'}
          </button>
        </span>
      </div>
      {error && <p className="status-message error composer-message">{error}</p>}
      {firstPost && <button className="action-button muted composer-skip" onClick={() => router.push('/')}>
        التخطي الآن <ArrowLeft size={16} aria-hidden="true"/>
      </button>}
    </div>
  </section>
}
