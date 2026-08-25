'use client'

import Link from 'next/link'
import { ChevronDown, ChevronUp, Music, Plus, Save, Search, Trash2, X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { TrackPreviewButton } from './TrackPreview'
import {
  MAX_ARTISTS_PER_PROFILE,
  MAX_GENRES_PER_PROFILE,
  MAX_TRACKS_PER_PROFILE,
  ARTIST_NAME_MAX_LENGTH
} from '@/lib/musicNormalize'

async function callApi(path, options = {}) {
  const response = await fetch(path, { cache: 'no-store', ...options })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || 'تعذر إكمال العملية')
  return data
}

function normalizeProfile(value, previous = null) {
  const next = value || {}
  const legacyPublic = !!next.preferencesPublic
  return {
    ...next,
    discoveryOptIn: !!next.discoveryOptIn,
    preferencesPublic: legacyPublic,
    showTracks: typeof next.showTracks === 'boolean' ? next.showTracks : (previous?.showTracks ?? legacyPublic),
    showArtists: typeof next.showArtists === 'boolean' ? next.showArtists : (previous?.showArtists ?? legacyPublic),
    showGenres: typeof next.showGenres === 'boolean' ? next.showGenres : (previous?.showGenres ?? legacyPublic),
    tracks: Array.isArray(next.tracks) ? next.tracks : [],
    artists: Array.isArray(next.artists) ? next.artists : [],
    genres: Array.isArray(next.genres) ? next.genres : []
  }
}

function trackKey(track) {
  return `${track.provider}:${track.externalId}`
}

function Cover({ track, size = 52 }) {
  return track.artworkUrl
    ? <img
        src={track.artworkUrl}
        alt=""
        width={size}
        height={size}
        loading="lazy"
        referrerPolicy="no-referrer"
        style={{ width: size, height: size, objectFit: 'cover', borderRadius: 10, flex: '0 0 auto' }}
      />
    : <span
        aria-hidden="true"
        style={{ width: size, height: size, borderRadius: 10, display: 'grid', placeItems: 'center', background: 'var(--surface-soft)' }}
      ><Music size={20} /></span>
}

export function MusicPreferences() {
  const [profile, setProfile] = useState(undefined)
  const [genres, setGenres] = useState([])

  const [trackQuery, setTrackQuery] = useState('')
  const [trackResults, setTrackResults] = useState([])
  const [trackSearching, setTrackSearching] = useState(false)
  const trackSearchTicket = useRef(0)

  const [query, setQuery] = useState('')
  const [results, setResults] = useState([])
  const [searching, setSearching] = useState(false)
  const searchTicket = useRef(0)

  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [saved, setSaved] = useState('')

  useEffect(() => {
    (async () => {
      try {
        const [me, catalog] = await Promise.all([
          fetch('/api/v1/music/visibility', { cache: 'no-store' }),
          fetch('/api/v1/music/genres', { cache: 'no-store' })
        ])
        if (me.status === 401) {
          setProfile(null)
          return
        }
        const mine = await me.json()
        setProfile(normalizeProfile(mine.profile))
        if (catalog.ok) setGenres((await catalog.json()).items || [])
      } catch {
        setError('تعذر تحميل تفضيلاتك الموسيقية.')
        setProfile(null)
      }
    })()
  }, [])

  useEffect(() => {
    const term = trackQuery.trim()
    if (!term) {
      setTrackResults([])
      setTrackSearching(false)
      return
    }
    const ticket = ++trackSearchTicket.current
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      setTrackSearching(true)
      try {
        const data = await callApi(`/api/v1/music/catalog?q=${encodeURIComponent(term)}`, { signal: controller.signal })
        if (ticket === trackSearchTicket.current) setTrackResults(data.items || [])
      } catch {
        if (ticket === trackSearchTicket.current) setTrackResults([])
      } finally {
        if (ticket === trackSearchTicket.current) setTrackSearching(false)
      }
    }, 260)
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [trackQuery])

  useEffect(() => {
    const term = query.trim()
    if (!term) {
      setResults([])
      return
    }
    const ticket = ++searchTicket.current
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      setSearching(true)
      try {
        const data = await callApi(`/api/v1/music/artists?q=${encodeURIComponent(term)}`, { signal: controller.signal })
        if (ticket === searchTicket.current) setResults(data.items || [])
      } catch {
        if (ticket === searchTicket.current) setResults([])
      } finally {
        if (ticket === searchTicket.current) setSearching(false)
      }
    }, 200)
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [query])

  function announce(message) {
    setSaved(message)
    setError('')
    setTimeout(() => setSaved(current => (current === message ? '' : current)), 2600)
  }

  async function saveSettings(overrides) {
    const next = {
      discoveryOptIn: profile.discoveryOptIn,
      showTracks: profile.showTracks,
      showArtists: profile.showArtists,
      showGenres: profile.showGenres,
      ...overrides
    }
    setBusy('settings')
    setError('')
    try {
      const data = await callApi('/api/v1/music/visibility', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(next)
      })
      setProfile(current => normalizeProfile(data.profile, current))
      announce('تم حفظ ما يظهر في ملفك.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  async function saveTracks(tracks) {
    setBusy('tracks')
    setError('')
    try {
      const data = await callApi('/api/v1/music/preferences/tracks', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trackIds: tracks.map(track => track.id) })
      })
      setProfile(current => normalizeProfile(data.profile, current))
      announce('تم حفظ الأغاني المفضلة.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  async function addCatalogTrack(track) {
    const current = profile.tracks || []
    if (current.some(item => trackKey(item) === trackKey(track))) return
    if (current.length >= MAX_TRACKS_PER_PROFILE) {
      setError(`يمكنك إضافة ${MAX_TRACKS_PER_PROFILE} أغنية كحد أقصى.`)
      return
    }

    setBusy('track-import')
    setError('')
    try {
      const imported = await callApi('/api/v1/music/tracks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: track.provider, externalId: track.externalId })
      })
      const next = [...current, imported.track]
      const data = await callApi('/api/v1/music/preferences/tracks', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trackIds: next.map(item => item.id) })
      })
      setProfile(existing => normalizeProfile(data.profile, existing))
      setTrackQuery('')
      setTrackResults([])
      announce('تمت إضافة الأغنية.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  function moveTrack(index, delta) {
    const next = [...(profile.tracks || [])]
    const target = index + delta
    if (target < 0 || target >= next.length) return
    ;[next[index], next[target]] = [next[target], next[index]]
    saveTracks(next)
  }

  async function saveArtists(artists) {
    setBusy('artists')
    setError('')
    try {
      const data = await callApi('/api/v1/music/preferences/artists', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ artistIds: artists.map(artist => artist.id) })
      })
      setProfile(current => normalizeProfile(data.profile, current))
      announce('تم حفظ قائمة الفنانين.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  async function saveGenres(selected) {
    setBusy('genres')
    setError('')
    try {
      const data = await callApi('/api/v1/music/preferences/genres', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ genreIds: selected.map(genre => genre.id) })
      })
      setProfile(current => normalizeProfile(data.profile, current))
      announce('تم حفظ التصنيفات.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  async function addExistingArtist(artist) {
    if (profile.artists.some(item => item.id === artist.id)) return
    if (profile.artists.length >= MAX_ARTISTS_PER_PROFILE) {
      setError(`يمكنك إضافة ${MAX_ARTISTS_PER_PROFILE} فنانًا كحد أقصى.`)
      return
    }
    setQuery('')
    setResults([])
    await saveArtists([...profile.artists, { id: artist.id, name: artist.name }])
  }

  async function createArtist() {
    const name = query.trim()
    if (!name) return
    if (profile.artists.length >= MAX_ARTISTS_PER_PROFILE) {
      setError(`يمكنك إضافة ${MAX_ARTISTS_PER_PROFILE} فنانًا كحد أقصى.`)
      return
    }
    setBusy('create')
    setError('')
    try {
      const data = await callApi('/api/v1/music/artists', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name })
      })
      await addExistingArtist(data.artist)
    } catch (e) {
      setError(e.message)
      setBusy('')
    }
  }

  function moveArtist(index, delta) {
    const next = [...profile.artists]
    const target = index + delta
    if (target < 0 || target >= next.length) return
    ;[next[index], next[target]] = [next[target], next[index]]
    saveArtists(next)
  }

  async function clearAll() {
    if (!confirm('حذف كل بيانات ذوقك الموسيقي؟ لا يمكن التراجع.')) return
    setBusy('clear')
    setError('')
    try {
      const data = await callApi('/api/v1/music/preferences', { method: 'DELETE' })
      setProfile({ ...normalizeProfile(data.profile), showTracks: false, showArtists: false, showGenres: false })
      announce('تم حذف كل بيانات الموسيقى.')
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy('')
    }
  }

  if (profile === undefined) return <div className="screen-pad"><div className="skeleton" /></div>
  if (profile === null) {
    return <div className="empty-state">
      <div>
        <p>سجّل الدخول لإضافة ذوقك الموسيقي.</p>
        <Link href="/login" className="primary-button mt16">تسجيل الدخول</Link>
      </div>
    </div>
  }

  const tracks = profile.tracks || []
  const selectedTrackKeys = new Set(tracks.map(trackKey))
  const selectedGenreIds = new Set(profile.genres.map(genre => genre.id))
  const alreadyListed = new Set(profile.artists.map(artist => artist.id))
  const exactMatch = results.some(item => item.name.trim().toLowerCase() === query.trim().toLowerCase())

  return <>
    <header className="page-header">
      <div className="page-title-row"><Music size={20} /><h1 className="page-title">ذوقي الموسيقي</h1></div>
      <p className="page-description">اختر أغاني حقيقية من الكتالوج، ثم قرر بنفسك ما الذي يظهر للآخرين في ملفك.</p>
    </header>

    <div className="screen-pad stack">
      <section className="panel music-panel">
        <h2 className="music-section-title">الظهور والمطابقة</h2>
        <label className="music-toggle">
          <input
            type="checkbox"
            checked={profile.discoveryOptIn}
            disabled={busy === 'settings'}
            onChange={event => saveSettings({ discoveryOptIn: event.target.checked })}
          />
          <span>
            <strong>أظهرني في اقتراحات المطابقة</strong>
            <span className="tiny subtle">يسمح للأشخاص المتشابهين معك بالعثور على كودك. اهتمام أي طرف يبقى سريًا حتى يحدث اختيار متبادل.</span>
          </span>
        </label>

        <div style={{ height: 1, background: 'var(--line)', margin: '8px 0' }} />
        <p className="small muted">اختر ما يظهر في صفحتك العامة. هذه الخيارات مستقلة عن دخولك في المطابقة.</p>

        <label className="music-toggle">
          <input
            type="checkbox"
            checked={profile.showTracks}
            disabled={busy === 'settings'}
            onChange={event => saveSettings({ showTracks: event.target.checked })}
          />
          <span>
            <strong>إظهار الأغاني المفضلة</strong>
            <span className="tiny subtle">يعرض اسم الأغنية والفنان والغلاف الذي اخترته.</span>
          </span>
        </label>
        <label className="music-toggle">
          <input
            type="checkbox"
            checked={profile.showArtists}
            disabled={busy === 'settings'}
            onChange={event => saveSettings({ showArtists: event.target.checked })}
          />
          <span>
            <strong>إظهار الفنانين</strong>
            <span className="tiny subtle">يمكنك استخدامها للمطابقة حتى لو أخفيتها من ملفك.</span>
          </span>
        </label>
        <label className="music-toggle">
          <input
            type="checkbox"
            checked={profile.showGenres}
            disabled={busy === 'settings'}
            onChange={event => saveSettings({ showGenres: event.target.checked })}
          />
          <span>
            <strong>إظهار التصنيفات</strong>
            <span className="tiny subtle">مثل روك، راب أو طرب؛ إخفاؤها لا يمنع استخدامها لحساب التشابه.</span>
          </span>
        </label>
      </section>

      <section className="panel music-panel">
        <h2 className="music-section-title">الأغاني المفضلة <span className="tiny subtle" dir="ltr">{tracks.length} / {MAX_TRACKS_PER_PROFILE}</span></h2>
        <p className="small muted">ابحث باسم الأغنية أو الفنان، ثم اختر النتيجة الأصلية من الكتالوج.</p>

        <label className="label">
          ابحث عن أغنية
          <div className="row" style={{ gap: 8 }}>
            <input
              className="form-control"
              value={trackQuery}
              onChange={event => setTrackQuery(event.target.value.slice(0, 120))}
              placeholder="مثال: Fairuz Nassam Alayna El Hawa"
              aria-label="بحث عن أغنية"
              maxLength={120}
            />
            <span className="search-adornment" aria-hidden="true"><Search size={16} /></span>
          </div>
        </label>

        {trackSearching && <p className="tiny subtle">جارِ البحث في الكتالوج…</p>}

        {trackResults.length > 0 && <ul className="result-list" aria-label="نتائج الأغاني">
          {trackResults.map(track => {
            const selected = selectedTrackKeys.has(trackKey(track))
            return <li key={trackKey(track)}>
              <button
                type="button"
                className="result-row"
                style={{ gap: 12, alignItems: 'center', textAlign: 'start' }}
                disabled={selected || !!busy || tracks.length >= MAX_TRACKS_PER_PROFILE}
                onClick={() => addCatalogTrack(track)}
              >
                <Cover track={track} />
                <span style={{ minWidth: 0, flex: 1 }}>
                  <strong style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{track.title}</strong>
                  <span className="tiny subtle" style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {track.artist}{track.album ? ` · ${track.album}` : ''}
                  </span>
                </span>
                <span className="tiny subtle">{selected ? 'مضافة' : <><Plus size={14} /> إضافة</>}</span>
              </button>
            </li>
          })}
        </ul>}

        {tracks.length > 0
          ? <ol className="ordered-list" aria-label="أغانيك المفضلة">
              {tracks.map((track, index) => (
                <li key={track.id} className="ordered-row" style={{ gap: 10 }}>
                  <span className="ordered-index" dir="ltr">{index + 1}</span>
                  <Cover track={track} size={46} />
                  {/* Catalog metadata is content: the language bridge must not translate it. */}
                  <span className="ordered-name" style={{ minWidth: 0 }} data-user-content="">
                    <strong style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{track.title}</strong>
                    <span className="tiny subtle" style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{track.artist}</span>
                  </span>
                  <span className="row" style={{ gap: 4 }}>
                    <TrackPreviewButton previewUrl={track.previewUrl} title={track.title}/>
                    <button type="button" className="icon-button" aria-label={`نقل ${track.title} للأعلى`} disabled={index === 0 || !!busy} onClick={() => moveTrack(index, -1)}><ChevronUp size={16} /></button>
                    <button type="button" className="icon-button" aria-label={`نقل ${track.title} للأسفل`} disabled={index === tracks.length - 1 || !!busy} onClick={() => moveTrack(index, 1)}><ChevronDown size={16} /></button>
                    <button type="button" className="icon-button danger-action" aria-label={`إزالة ${track.title}`} disabled={!!busy} onClick={() => saveTracks(tracks.filter(item => item.id !== track.id))}><X size={16} /></button>
                  </span>
                </li>
              ))}
            </ol>
          : <p className="tiny subtle">لم تختر أي أغنية بعد.</p>}
      </section>

      <section className="panel music-panel">
        <h2 className="music-section-title">التصنيفات <span className="tiny subtle" dir="ltr">{profile.genres.length} / {MAX_GENRES_PER_PROFILE}</span></h2>
        <div className="chip-grid" role="group" aria-label="تصنيفات الموسيقى">
          {genres.map(genre => {
            const selected = selectedGenreIds.has(genre.id)
            return <button
              key={genre.id}
              type="button"
              className={`chip${selected ? ' selected' : ''}`}
              aria-pressed={selected}
              disabled={busy === 'genres' || (!selected && profile.genres.length >= MAX_GENRES_PER_PROFILE)}
              onClick={() => saveGenres(selected ? profile.genres.filter(item => item.id !== genre.id) : [...profile.genres, genre])}
            >
              {genre.nameAr}<span className="tiny subtle" dir="ltr"> {genre.name}</span>
            </button>
          })}
        </div>
      </section>

      <section className="panel music-panel">
        <h2 className="music-section-title">الفنانون <span className="tiny subtle" dir="ltr">{profile.artists.length} / {MAX_ARTISTS_PER_PROFILE}</span></h2>

        <label className="label">
          ابحث عن فنان أو أضف واحدًا جديدًا
          <div className="row" style={{ gap: 8 }}>
            <input
              className="form-control"
              value={query}
              onChange={event => setQuery(event.target.value.slice(0, ARTIST_NAME_MAX_LENGTH))}
              placeholder="مثال: فيروز أو Radiohead"
              aria-label="بحث عن فنان"
              maxLength={ARTIST_NAME_MAX_LENGTH}
            />
            <span className="search-adornment" aria-hidden="true"><Search size={16} /></span>
          </div>
        </label>

        {searching && <p className="tiny subtle">جارِ البحث…</p>}

        {results.length > 0 && <ul className="result-list" aria-label="نتائج البحث">
          {results.map(artist => (
            <li key={artist.id}>
              <button
                type="button"
                className="result-row"
                disabled={alreadyListed.has(artist.id) || busy === 'artists'}
                onClick={() => addExistingArtist(artist)}
              >
                <span>{artist.name}</span>
                <span className="tiny subtle">{alreadyListed.has(artist.id) ? 'مضاف' : <><Plus size={14} /> إضافة</>}</span>
              </button>
            </li>
          ))}
        </ul>}

        {query.trim() && !searching && !exactMatch && <button
          type="button"
          className="secondary-button"
          onClick={createArtist}
          disabled={busy === 'create'}
        >
          <Plus size={16} />
          {busy === 'create' ? 'جارِ الإضافة…' : `أضف «${query.trim()}» كفنان جديد`}
        </button>}

        {profile.artists.length > 0
          ? <ol className="ordered-list" aria-label="فنانوك المفضلون">
              {profile.artists.map((artist, index) => (
                <li key={artist.id} className="ordered-row">
                  <span className="ordered-index" dir="ltr">{index + 1}</span>
                  <span className="ordered-name">{artist.name}</span>
                  <span className="row" style={{ gap: 4 }}>
                    <button type="button" className="icon-button" aria-label={`نقل ${artist.name} للأعلى`} disabled={index === 0 || !!busy} onClick={() => moveArtist(index, -1)}><ChevronUp size={16} /></button>
                    <button type="button" className="icon-button" aria-label={`نقل ${artist.name} للأسفل`} disabled={index === profile.artists.length - 1 || !!busy} onClick={() => moveArtist(index, 1)}><ChevronDown size={16} /></button>
                    <button type="button" className="icon-button danger-action" aria-label={`إزالة ${artist.name}`} disabled={!!busy} onClick={() => saveArtists(profile.artists.filter(item => item.id !== artist.id))}><X size={16} /></button>
                  </span>
                </li>
              ))}
            </ol>
          : <p className="tiny subtle">لم تضف أي فنان بعد.</p>}
      </section>

      <div aria-live="polite">
        {error && <p className="status-message error">{error}</p>}
        {saved && <p className="status-message" style={{ color: 'var(--success)' }}><Save size={14} /> {saved}</p>}
      </div>

      <section className="panel music-panel">
        <h2 className="music-section-title">حذف البيانات</h2>
        <p className="small muted">يحذف أغانيك وتصنيفاتك وفنانيك وإعدادات الاكتشاف من حسابك نهائيًا.</p>
        <button type="button" className="danger-button mt16" onClick={clearAll} disabled={busy === 'clear'}>
          <Trash2 size={16} />
          {busy === 'clear' ? 'جارِ الحذف…' : 'حذف كل بيانات الموسيقى'}
        </button>
      </section>

      <p className="center small muted">
        <Link href="/discover/music" style={{ textDecoration: 'underline' }}>اذهب إلى المطابقة بالموسيقى</Link>
      </p>
    </div>
  </>
}
