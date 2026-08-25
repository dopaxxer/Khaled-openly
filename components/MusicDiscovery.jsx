'use client'

import Link from 'next/link'
import { Check, Compass, Heart, RotateCcw, Sparkles, Users, X } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { Identity } from './Identity'

const PAGE_SIZE = 20

function CompatibilityDial({ value }) {
  return (
    <div className="compat" role="img" aria-label={`نسبة التشابه ${value} بالمئة`}>
      <div className="compat-value" dir="ltr">{value}%</div>
      <div className="compat-track" aria-hidden="true">
        <div className="compat-fill" style={{ width: `${Math.max(4, Math.min(100, value))}%` }} />
      </div>
    </div>
  )
}

function MatchReasons({ match }) {
  return <div className="match-reasons">
    {match.sharedArtists.length > 0 && <p className="small">
      <span className="muted">فنانون مشتركون: </span>
      {match.sharedArtists.map(artist => artist.name).join('، ')}
    </p>}
    {match.sharedGenres.length > 0 && <p className="small">
      <span className="muted">تصنيفات مشتركة: </span>
      {match.sharedGenres.map(genre => genre.nameAr).join('، ')}
    </p>}
    <p className="tiny subtle">
      التشابه الحالي مبني على {match.sharedArtistCount} فنان و{match.sharedGenreCount} تصنيف مشترك.
    </p>
  </div>
}

export function MusicDiscovery() {
  const [mode, setMode] = useState('suggestions')
  const [items, setItems] = useState([])
  const [total, setTotal] = useState(0)
  const [hasMore, setHasMore] = useState(false)
  const [matches, setMatches] = useState([])
  const [matchTotal, setMatchTotal] = useState(0)
  const [matchesLoaded, setMatchesLoaded] = useState(false)
  const [state, setState] = useState('loading')
  const [error, setError] = useState('')
  const [banner, setBanner] = useState('')
  const [genres, setGenres] = useState([])
  const [genreId, setGenreId] = useState('')
  const [artistQuery, setArtistQuery] = useState('')
  const [artistOptions, setArtistOptions] = useState([])
  const [artistId, setArtistId] = useState('')
  const [loadingMore, setLoadingMore] = useState(false)
  const [busyCode, setBusyCode] = useState('')
  const searchTicket = useRef(0)

  const loadSuggestions = useCallback(async (offset = 0) => {
    offset === 0 ? setState('loading') : setLoadingMore(true)
    setError('')
    try {
      const params = new URLSearchParams({ limit: String(PAGE_SIZE), offset: String(offset) })
      if (artistId) params.set('artistId', artistId)
      if (genreId) params.set('genreId', genreId)

      const response = await fetch(`/api/v1/music/match-suggestions?${params}`, { cache: 'no-store' })
      if (response.status === 401) {
        setState('anonymous')
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الاقتراحات')

      setItems(previous => offset === 0 ? (data.items || []) : [...previous, ...(data.items || [])])
      setTotal(data.total || 0)
      setHasMore(!!data.hasMore)
      setState('ready')
    } catch (e) {
      setError(e.message || 'تعذر تحميل الاقتراحات')
      setState(offset === 0 ? 'error' : 'ready')
    } finally {
      setLoadingMore(false)
    }
  }, [artistId, genreId])

  const loadMatches = useCallback(async () => {
    setError('')
    try {
      const response = await fetch(`/api/v1/music/matches?limit=50&offset=0`, { cache: 'no-store' })
      if (response.status === 401) {
        setState('anonymous')
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الماتشات')
      setMatches(data.items || [])
      setMatchTotal(data.total || 0)
      setMatchesLoaded(true)
    } catch (e) {
      setError(e.message || 'تعذر تحميل الماتشات')
    }
  }, [])

  useEffect(() => {
    fetch('/api/v1/music/genres', { cache: 'no-store' })
      .then(response => response.ok ? response.json() : { items: [] })
      .then(data => setGenres(data.items || []))
      .catch(() => {})
  }, [])

  useEffect(() => { loadSuggestions(0) }, [loadSuggestions])

  useEffect(() => {
    if (mode === 'matches' && !matchesLoaded) loadMatches()
  }, [mode, matchesLoaded, loadMatches])

  useEffect(() => {
    const term = artistQuery.trim()
    if (!term) {
      setArtistOptions([])
      return
    }
    const ticket = ++searchTicket.current
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(`/api/v1/music/artists?q=${encodeURIComponent(term)}`, {
          cache: 'no-store',
          signal: controller.signal
        })
        const data = response.ok ? await response.json() : { items: [] }
        if (ticket === searchTicket.current) setArtistOptions(data.items || [])
      } catch {
        if (ticket === searchTicket.current) setArtistOptions([])
      }
    }, 200)
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [artistQuery])

  function clearFilters() {
    setArtistId('')
    setArtistQuery('')
    setGenreId('')
  }

  async function setInterest(match, interested) {
    if (busyCode) return
    setBusyCode(match.publicCode)
    setError('')
    setBanner('')
    try {
      const response = await fetch('/api/v1/music/match-interest', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ publicCode: match.publicCode, interested })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر حفظ اختيارك')
      const next = data.state || {}
      setItems(current => current.map(item => item.publicCode === match.publicCode
        ? { ...item, interested: !!next.interested, matched: !!next.matched }
        : item))
      if (next.matched) {
        setBanner(`حدث تطابق بينك وبين ${match.publicCode}. الاختيار كان متبادلًا.`)
        await loadMatches()
      }
    } catch (e) {
      setError(e.message || 'تعذر حفظ اختيارك')
    } finally {
      setBusyCode('')
    }
  }

  async function removeMatch(match) {
    if (busyCode) return
    if (!confirm(`إلغاء التطابق مع ${match.publicCode}؟`)) return
    setBusyCode(match.publicCode)
    setError('')
    try {
      const response = await fetch(`/api/v1/music/matches?publicCode=${encodeURIComponent(match.publicCode)}`, { method: 'DELETE' })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر إلغاء التطابق')
      setMatches(current => current.filter(item => item.publicCode !== match.publicCode))
      setMatchTotal(current => Math.max(0, current - 1))
      setItems(current => current.map(item => item.publicCode === match.publicCode
        ? { ...item, interested: false, matched: false }
        : item))
    } catch (e) {
      setError(e.message || 'تعذر إلغاء التطابق')
    } finally {
      setBusyCode('')
    }
  }

  const header = <header className="page-header">
    <div className="page-title-row"><Compass size={20} /><h1 className="page-title">اكتشاف بالموسيقى</h1></div>
    <p className="page-description">
      اختيار متبادل وهادئ: اهتمامك يبقى سريًا، ولا يظهر التطابق إلا إذا اختارك الطرف الآخر أيضًا.
    </p>
  </header>

  if (state === 'anonymous') {
    return <>
      {header}
      <div className="empty-state">
        <div>
          <p>سجّل الدخول لرؤية من يشاركك ذوقك.</p>
          <Link href="/login" className="primary-button mt16">تسجيل الدخول</Link>
        </div>
      </div>
    </>
  }

  return <>
    {header}

    <div className="screen-pad">
      <div className="row" role="tablist" aria-label="نوع قائمة المطابقة" style={{ gap: 8 }}>
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'suggestions'}
          className={mode === 'suggestions' ? 'primary-button' : 'secondary-button'}
          onClick={() => setMode('suggestions')}
        >
          <Sparkles size={16} />اقتراحات
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'matches'}
          className={mode === 'matches' ? 'primary-button' : 'secondary-button'}
          onClick={() => setMode('matches')}
        >
          <Users size={16} />الماتشات {matchTotal > 0 ? `(${matchTotal})` : ''}
        </button>
      </div>
    </div>

    {banner && <div className="screen-pad"><p className="status-message" style={{ color: 'var(--success)' }}><Check size={15} /> {banner}</p></div>}
    {error && <div className="screen-pad"><p className="status-message error">{error}</p></div>}

    {mode === 'suggestions' && <>
      <div className="screen-pad">
        <div className="filter-bar">
          <label className="label">
            التصنيف
            <select className="form-control" value={genreId} onChange={event => setGenreId(event.target.value)}>
              <option value="">كل التصنيفات</option>
              {genres.map(genre => <option key={genre.id} value={genre.id}>{genre.nameAr}</option>)}
            </select>
          </label>

          <label className="label">
            الفنان
            <input
              className="form-control"
              list="discover-artist-options"
              value={artistQuery}
              placeholder="اكتب اسم فنان"
              aria-label="تصفية حسب فنان"
              onChange={event => {
                const text = event.target.value
                setArtistQuery(text)
                const match = artistOptions.find(option => option.name === text)
                setArtistId(match ? match.id : '')
              }}
            />
            <datalist id="discover-artist-options">
              {artistOptions.map(option => <option key={option.id} value={option.name} />)}
            </datalist>
            {artistQuery.trim() && !artistId && <span className="tiny subtle">اختر اسمًا من القائمة لتفعيل التصفية.</span>}
          </label>

          {(artistId || genreId) && <button type="button" className="secondary-button" onClick={clearFilters}>إزالة التصفية</button>}
        </div>
      </div>

      {state === 'loading' && <div className="screen-pad"><div className="skeleton" /></div>}

      {state === 'error' && <div className="empty-state">
        <div>
          <p>{error || 'تعذر تحميل الاقتراحات.'}</p>
          <button className="secondary-button mt16" onClick={() => loadSuggestions(0)}><RotateCcw size={16} />المحاولة مجددًا</button>
        </div>
      </div>}

      {state === 'ready' && items.length === 0 && <div className="empty-state">
        <div>
          <p>لا توجد نتائج مطابقة بعد.</p>
          <p className="small muted mt12">أضف فنانين وتصنيفات وفعّل الظهور في الاكتشاف.</p>
          <Link href="/music" className="primary-button mt16"><Sparkles size={16} />عدّل ذوقك الموسيقي</Link>
        </div>
      </div>}

      {state === 'ready' && items.length > 0 && <div aria-live="polite">
        <div className="section-title" dir="rtl">{total} اقتراح</div>
        {items.map(match => (
          <article className="match-card" key={match.publicCode}>
            <div className="match-head">
              <Identity code={match.publicCode} color={match.identityColor} />
              <CompatibilityDial value={match.compatibility} />
            </div>
            <MatchReasons match={match} />
            <div className="row wrap" style={{ gap: 8 }}>
              {match.matched
                ? <span className="status-message" style={{ color: 'var(--success)', margin: 0 }}><Check size={14} />تطابق متبادل</span>
                : <button
                    type="button"
                    className={match.interested ? 'secondary-button' : 'primary-button'}
                    disabled={busyCode === match.publicCode}
                    onClick={() => setInterest(match, !match.interested)}
                  >
                    <Heart size={15} fill={match.interested ? 'currentColor' : 'none'} />
                    {busyCode === match.publicCode ? '…' : match.interested ? 'إلغاء الاهتمام' : 'مهتم بهذا التوافق'}
                  </button>}
              <Link href={`/u/${match.publicCode}`} className="secondary-button">عرض الكتابات</Link>
            </div>
            {!match.matched && match.interested && <p className="tiny subtle mt8">اختيارك سري. لن يعرف الطرف الآخر إلا إذا اختارك أيضًا.</p>}
          </article>
        ))}

        <div className="feed-footer">
          {hasMore
            ? <button className="secondary-button" disabled={loadingMore} onClick={() => loadSuggestions(items.length)}>
                {loadingMore ? 'جارِ التحميل…' : 'عرض المزيد'}
              </button>
            : <span className="tiny subtle">هذه كل الاقتراحات المتاحة.</span>}
        </div>
      </div>}
    </>}

    {mode === 'matches' && <>
      {!matchesLoaded && <div className="screen-pad"><div className="skeleton" /></div>}
      {matchesLoaded && matches.length === 0 && <div className="empty-state">
        <div>
          <Users size={28} />
          <p className="mt12">لا توجد ماتشات متبادلة بعد.</p>
          <p className="small muted mt12">اختر من الاقتراحات. إذا اختارك الطرف الآخر أيضًا سيظهر هنا فقط.</p>
          <button className="primary-button mt16" onClick={() => setMode('suggestions')}>عرض الاقتراحات</button>
        </div>
      </div>}
      {matchesLoaded && matches.length > 0 && <div>
        <div className="section-title">{matchTotal} ماتش</div>
        {matches.map(match => (
          <article className="match-card" key={match.publicCode}>
            <div className="match-head">
              <Identity code={match.publicCode} color={match.identityColor} />
              <div>
                <CompatibilityDial value={match.compatibility} />
                {match.matchedAt && <div className="tiny subtle mt8">تطابق {new Intl.DateTimeFormat('ar', { dateStyle: 'medium' }).format(new Date(match.matchedAt))}</div>}
              </div>
            </div>
            <MatchReasons match={match} />
            <div className="row wrap" style={{ gap: 8 }}>
              <Link href={`/u/${match.publicCode}`} className="primary-button">فتح الملف</Link>
              <button type="button" className="danger-button" disabled={busyCode === match.publicCode} onClick={() => removeMatch(match)}>
                <X size={15} />إلغاء التطابق
              </button>
            </div>
          </article>
        ))}
      </div>}
    </>}
  </>
}
