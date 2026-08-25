'use client'

import Link from 'next/link'
import { Compass, RotateCcw, Sparkles } from 'lucide-react'
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

export function MusicDiscovery() {
  const [items, setItems] = useState([])
  const [total, setTotal] = useState(0)
  const [hasMore, setHasMore] = useState(false)
  const [state, setState] = useState('loading')
  const [error, setError] = useState('')
  const [genres, setGenres] = useState([])
  const [genreId, setGenreId] = useState('')
  const [artistQuery, setArtistQuery] = useState('')
  const [artistOptions, setArtistOptions] = useState([])
  const [artistId, setArtistId] = useState('')
  const [loadingMore, setLoadingMore] = useState(false)
  const searchTicket = useRef(0)

  const load = useCallback(async (offset = 0) => {
    offset === 0 ? setState('loading') : setLoadingMore(true)
    setError('')
    try {
      const params = new URLSearchParams({ limit: String(PAGE_SIZE), offset: String(offset) })
      if (artistId) params.set('artistId', artistId)
      if (genreId) params.set('genreId', genreId)

      const response = await fetch(`/api/v1/music/discover?${params}`, { cache: 'no-store' })
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

  useEffect(() => {
    fetch('/api/v1/music/genres', { cache: 'no-store' })
      .then(response => response.ok ? response.json() : { items: [] })
      .then(data => setGenres(data.items || []))
      .catch(() => {})
  }, [])

  useEffect(() => { load(0) }, [load])

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

  const header = <header className="page-header">
    <div className="page-title-row"><Compass size={20} /><h1 className="page-title">اكتشاف بالموسيقى</h1></div>
    <p className="page-description">
      أشخاص اختاروا الظهور هنا ويشاركونك الذوق. المساحة العامة تبقى زمنية كما هي.
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
        <p>{error}</p>
        <button className="secondary-button mt16" onClick={() => load(0)}><RotateCcw size={16} aria-hidden="true" />المحاولة مجددًا</button>
      </div>
    </div>}

    {state === 'ready' && items.length === 0 && <div className="empty-state">
      <div>
        <p>لا توجد نتائج مطابقة بعد.</p>
        <p className="small muted mt12">
          أضف فنانين وتصنيفات إلى ملفك، وفعّل خيار الظهور، لتبدأ المطابقة.
        </p>
        <Link href="/music" className="primary-button mt16"><Sparkles size={16} aria-hidden="true" />عدّل ذوقك الموسيقي</Link>
      </div>
    </div>}

    {state === 'ready' && items.length > 0 && <div aria-live="polite">
      <div className="section-title" dir="rtl">{total} نتيجة</div>
      {items.map(match => (
        <article className="match-card" key={match.publicCode}>
          <div className="match-head">
            <Identity code={match.publicCode} color={match.identityColor} />
            <CompatibilityDial value={match.compatibility} />
          </div>

          <div className="match-reasons">
            {match.sharedArtists.length > 0 && <p className="small">
              <span className="muted">فنانون مشتركون: </span>
              {match.sharedArtists.map(artist => artist.name).join('، ')}
            </p>}
            {match.sharedGenres.length > 0 && <p className="small">
              <span className="muted">تصنيفات مشتركة: </span>
              {match.sharedGenres.map(genre => genre.nameAr).join('، ')}
            </p>}
            <p className="tiny subtle">
              نسبة التشابه محسوبة من {match.sharedArtistCount} فنان و{match.sharedGenreCount} تصنيف مشترك؛ الفنان يزن ثلاثة أضعاف التصنيف.
            </p>
          </div>

          <Link href={`/u/${match.publicCode}`} className="secondary-button">عرض الكتابات</Link>
        </article>
      ))}

      <div className="feed-footer">
        {hasMore
          ? <button className="secondary-button" disabled={loadingMore} onClick={() => load(items.length)}>
              {loadingMore ? 'جارِ التحميل…' : 'عرض المزيد'}
            </button>
          : <span className="tiny subtle">هذه كل النتائج المتاحة.</span>}
        {error && <p className="tiny danger-text">{error}</p>}
      </div>
    </div>}
  </>
}
