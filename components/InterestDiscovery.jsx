'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  BookOpen,
  Check,
  Compass,
  Film,
  MessageCircle,
  Plus,
  Search,
  Sparkles
} from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Identity } from './Identity'
import {
  INTEREST_KINDS,
  MAX_INTERESTS_PER_KIND,
  MAX_INTERESTS_PER_PROFILE,
  interestKindLabel
} from '@/lib/interests'

const KIND_META = {
  topic: { label: 'مواضيع الحديث', short: 'مواضيع', icon: MessageCircle },
  book: { label: 'الكتب', short: 'كتب', icon: BookOpen },
  movie: { label: 'الأفلام', short: 'أفلام', icon: Film }
}

function CompatibilityDial({ value }) {
  return <div className="compat" role="img" aria-label={`نسبة التوافق ${value} بالمئة`}>
    <div className="compat-value" dir="ltr">{value}%</div>
    <div className="compat-track" aria-hidden="true">
      <div className="compat-fill" style={{ width: `${Math.max(4, Math.min(100, value))}%` }} />
    </div>
  </div>
}

function KindTabs({ value, onChange, includeAll = false }) {
  const values = includeAll ? ['', ...INTEREST_KINDS] : INTEREST_KINDS
  return <div className="row wrap" role="tablist" aria-label="نوع الاهتمام" style={{ gap: 8 }}>
    {values.map(kind => {
      const active = value === kind
      const label = kind ? KIND_META[kind].short : 'الكل'
      return <button
        key={kind || 'all'}
        type="button"
        role="tab"
        aria-selected={active}
        className={active ? 'primary-button' : 'secondary-button'}
        onClick={() => onChange(kind)}
      >
        {kind === 'topic' && <MessageCircle size={15} />}
        {kind === 'book' && <BookOpen size={15} />}
        {kind === 'movie' && <Film size={15} />}
        {label}
      </button>
    })}
  </div>
}

function SelectedChip({ item, onRemove }) {
  return <button type="button" className="chip selected" onClick={onRemove} title="إزالة">
    <span data-user-content="">{item.label}</span>
    {item.subtitle && <span className="tiny subtle" data-user-content="">· {item.subtitle}</span>}
  </button>
}

export function InterestPreferences({ onboarding = false }) {
  const router = useRouter()
  const [profile, setProfile] = useState(undefined)
  const [selected, setSelected] = useState([])
  const [kind, setKind] = useState('topic')
  const [query, setQuery] = useState('')
  const [results, setResults] = useState([])
  const [discoveryOptIn, setDiscoveryOptIn] = useState(true)
  const [preferencesPublic, setPreferencesPublic] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    const controller = new AbortController()
    fetch('/api/v1/interests/preferences', { cache: 'no-store', signal: controller.signal })
      .then(async response => {
        if (response.status === 401) return null
        const data = await response.json()
        if (!response.ok) throw new Error(data.error || 'تعذر تحميل اهتماماتك')
        return data.profile
      })
      .then(next => {
        if (next === null) {
          setProfile(null)
          return
        }
        const items = Array.isArray(next?.items) ? next.items : []
        setProfile(next || {})
        setSelected(items)
        setDiscoveryOptIn(onboarding && items.length === 0 ? true : !!next?.discoveryOptIn)
        setPreferencesPublic(onboarding && items.length === 0 ? true : !!next?.preferencesPublic)
      })
      .catch(e => {
        if (e.name !== 'AbortError') {
          setError(e.message || 'تعذر تحميل اهتماماتك')
          setProfile({})
        }
      })
    return () => controller.abort()
  }, [onboarding])

  useEffect(() => {
    if (profile === undefined || profile === null) return
    const controller = new AbortController()
    const timer = setTimeout(async () => {
      try {
        const params = new URLSearchParams({ kind })
        if (query.trim()) params.set('q', query.trim())
        const response = await fetch(`/api/v1/interests?${params}`, { cache: 'no-store', signal: controller.signal })
        const data = response.ok ? await response.json() : { items: [] }
        setResults(data.items || [])
      } catch (e) {
        if (e.name !== 'AbortError') setResults([])
      }
    }, query.trim() ? 180 : 0)
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [kind, query, profile])

  const selectedForKind = useMemo(
    () => selected.filter(item => item.kind === kind),
    [selected, kind]
  )

  function add(item) {
    if (selected.some(current => current.id === item.id)) return
    if (selected.length >= MAX_INTERESTS_PER_PROFILE) {
      setError(`الحد الأقصى ${MAX_INTERESTS_PER_PROFILE} اهتمامًا.`)
      return
    }
    if (selectedForKind.length >= MAX_INTERESTS_PER_KIND) {
      setError(`الحد الأقصى ${MAX_INTERESTS_PER_KIND} من فئة ${interestKindLabel(kind)}.`)
      return
    }
    setError('')
    setSaved(false)
    setSelected(current => [...current, item])
    setQuery('')
  }

  function remove(id) {
    setSaved(false)
    setSelected(current => current.filter(item => item.id !== id))
  }

  async function addResult(item) {
    if (item.source !== 'catalog') {
      add(item)
      return
    }
    if (busy) return
    setBusy(item.id)
    setError('')
    try {
      const response = await fetch('/api/v1/interests', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          kind: item.kind,
          provider: item.provider,
          externalId: item.externalId
        })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر حفظ العنصر')
      add(data.item)
    } catch (e) {
      setError(e.message || 'تعذر حفظ العنصر')
    } finally {
      setBusy('')
    }
  }

  async function createAndAddTopic() {
    const label = query.trim()
    if (!label || busy || kind !== 'topic') return
    setBusy('create')
    setError('')
    try {
      const response = await fetch('/api/v1/interests', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ kind, label })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر إضافة الموضوع')
      add(data.item)
    } catch (e) {
      setError(e.message || 'تعذر إضافة الموضوع')
    } finally {
      setBusy('')
    }
  }

  async function save() {
    if (busy) return
    setBusy('save')
    setError('')
    setSaved(false)
    try {
      const response = await fetch('/api/v1/interests/preferences', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          discoveryOptIn,
          preferencesPublic,
          interestIds: selected.map(item => item.id)
        })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر حفظ اهتماماتك')
      setProfile(data.profile)
      setSelected(data.profile?.items || selected)
      setSaved(true)
      if (onboarding) {
        router.push('/first-post')
        router.refresh()
      }
    } catch (e) {
      setError(e.message || 'تعذر حفظ اهتماماتك')
    } finally {
      setBusy('')
    }
  }

  if (profile === undefined) return <div className="screen-pad"><div className="skeleton" /></div>

  if (profile === null) return <div className="empty-state">
    <div>
      <p>سجّل الدخول لاختيار اهتماماتك.</p>
      <Link href="/login" className="primary-button mt16">تسجيل الدخول</Link>
    </div>
  </div>

  const meta = KIND_META[kind]
  const KindIcon = meta.icon
  const exactExists = results.some(item =>
    item.label.localeCompare(query.trim(), undefined, { sensitivity: 'base' }) === 0 &&
    item.kind === kind
  )

  return <>
    <header className="page-header">
      <div className="page-title-row">
        <Sparkles size={20} />
        <h1 className="page-title">{onboarding ? 'ما الذي يهمك؟' : 'اهتماماتي'}</h1>
      </div>
      <p className="page-description">
        {onboarding
          ? 'اختر أشياء تحبها فعلًا. سنستخدمها لإيجاد أشخاص ومواضيع بينكم أرضية مشتركة.'
          : 'الكتب والأفلام ومواضيع الحديث تكمل ذوقك الموسيقي وتكوّن صورة أصدق عن اهتماماتك.'}
      </p>
    </header>

    <div className="screen-pad" style={{ display: 'grid', gap: 20 }}>
      <KindTabs value={kind} onChange={next => {
        setKind(next)
        setQuery('')
        setError('')
      }} />

      <section className="panel music-panel">
        <div className="music-section-title">
          <span className="row" style={{ gap: 8 }}><KindIcon size={18} />{meta.label}</span>
          <span className="tiny subtle">{selectedForKind.length} / {MAX_INTERESTS_PER_KIND}</span>
        </div>

        {selectedForKind.length > 0 && <div className="chip-grid" style={{ marginBottom: 16 }}>
          {selectedForKind.map(item => <SelectedChip key={item.id} item={item} onRemove={() => remove(item.id)} />)}
        </div>}

        <label className="label">
          <span className="row" style={{ gap: 6 }}><Search size={14} />{kind === 'topic' ? 'ابحث أو أضف' : 'ابحث في الكتالوج'}</span>
          <input
            className="form-control"
            value={query}
            maxLength={160}
            placeholder={kind === 'book' ? 'مثال: The Stranger' : kind === 'movie' ? 'مثال: Interstellar' : 'مثال: علم النفس'}
            onChange={event => setQuery(event.target.value)}
          />
        </label>

        {results.length > 0 && <ul className="result-list interest-results">
          {results.map(item => {
            const isSelected = selected.some(current => current.id === item.id)
            const isBusy = busy === item.id
            return <li key={item.id}>
              <button
                className="result-row interest-result-row"
                type="button"
                disabled={isSelected || isBusy}
                onClick={() => addResult(item)}
              >
                {item.artworkUrl
                  ? <img className="interest-artwork" src={item.artworkUrl} alt="" loading="lazy" />
                  : <span className="interest-artwork placeholder" aria-hidden="true">
                      {item.kind === 'book' ? <BookOpen size={18} /> : item.kind === 'movie' ? <Film size={18} /> : <MessageCircle size={18} />}
                    </span>}
                <span className="interest-result-copy">
                  <strong data-user-content="">{item.label}</strong>
                  {[item.subtitle, item.releaseYear].filter(Boolean).length
                    ? <span className="small muted" data-user-content="">
                        {[item.subtitle, item.releaseYear].filter(Boolean).join(' · ')}
                      </span>
                    : <span className="small muted">
                        {item.kind === 'topic' ? 'موضوع' : 'من الكتالوج'}
                      </span>}
                </span>
                <span className="tiny subtle">
                  {isBusy ? '…' : isSelected ? 'مضاف' : item.popularity > 0 ? `${item.popularity} اختيار` : 'إضافة'}
                </span>
              </button>
            </li>
          })}
        </ul>}

        {kind === 'topic' && query.trim() && !exactExists && <button
          type="button"
          className="secondary-button mt16"
          disabled={busy === 'create'}
          onClick={createAndAddTopic}
        >
          <Plus size={15} />{busy === 'create' ? 'جارِ الإضافة…' : `أضف موضوع «${query.trim()}»`}
        </button>}

        {(kind === 'book' || kind === 'movie') && query.trim().length === 1 && <p className="tiny subtle mt12">
          اكتب حرفين على الأقل لبدء البحث في الكتالوج.
        </p>}
      </section>

      <section className="panel music-panel">
        <h2 className="music-section-title">الخصوصية والاكتشاف</h2>
        <label className="music-toggle">
          <input type="checkbox" checked={discoveryOptIn} onChange={event => setDiscoveryOptIn(event.target.checked)} />
          <span>
            <strong>استخدم اهتماماتي في الاكتشاف</strong>
            <span className="small muted">يسمح لـOpenly باقتراح أشخاص بينكم اهتمامات مشتركة.</span>
          </span>
        </label>
        <label className="music-toggle">
          <input type="checkbox" checked={preferencesPublic} onChange={event => setPreferencesPublic(event.target.checked)} />
          <span>
            <strong>اعرض اهتماماتي في ملفي</strong>
            <span className="small muted">إذا أوقفته، يمكن حساب التوافق عند تفعيل الاكتشاف لكن لا نعرض قائمة اهتماماتك.</span>
          </span>
        </label>
      </section>

      {error && <p className="status-message error">{error}</p>}
      {saved && <p className="status-message" style={{ color: 'var(--success)' }}><Check size={15} />تم حفظ اهتماماتك.</p>}

      <div className="row wrap" style={{ gap: 8 }}>
        <button className="primary-button" disabled={busy === 'save'} onClick={save}>
          <Check size={16} />{busy === 'save' ? 'جارِ الحفظ…' : onboarding ? 'احفظ وتابع' : 'حفظ'}
        </button>
        {onboarding && <button type="button" className="secondary-button" onClick={() => router.push('/first-post')}>تخطي الآن</button>}
        {!onboarding && <Link href="/discover" className="secondary-button"><Compass size={16} />اكتشف أشخاصًا</Link>}
      </div>

      <p className="tiny subtle">
        اختر حتى {MAX_INTERESTS_PER_PROFILE} اهتمامًا إجمالًا. الموسيقى تبقى في ملفها الحالي وتدخل في نسبة التوافق فقط عندما تسمح إعداداتها بذلك.
      </p>
    </div>
  </>
}

export function InterestDiscovery() {
  const [kind, setKind] = useState('')
  const [items, setItems] = useState([])
  const [total, setTotal] = useState(0)
  const [hasMore, setHasMore] = useState(false)
  const [state, setState] = useState('loading')
  const [error, setError] = useState('')
  const [loadingMore, setLoadingMore] = useState(false)

  const load = useCallback(async (offset = 0) => {
    offset === 0 ? setState('loading') : setLoadingMore(true)
    setError('')
    try {
      const params = new URLSearchParams({ limit: '20', offset: String(offset) })
      if (kind) params.set('kind', kind)
      const response = await fetch(`/api/v1/interests/discover?${params}`, { cache: 'no-store' })
      if (response.status === 401) {
        setState('anonymous')
        return
      }
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'تعذر تحميل الاقتراحات')
      setItems(current => offset === 0 ? (data.items || []) : [...current, ...(data.items || [])])
      setTotal(data.total || 0)
      setHasMore(!!data.hasMore)
      setState('ready')
    } catch (e) {
      setError(e.message || 'تعذر تحميل الاقتراحات')
      setState(offset === 0 ? 'error' : 'ready')
    } finally {
      setLoadingMore(false)
    }
  }, [kind])

  useEffect(() => { load(0) }, [load])

  return <section className="v2-explore">
    <header className="v2-explore-head">
      <h1>Explore</h1>
      <p>Find people through what they care about</p>
      <Link href="/search" className="v2-explore-search">Search people, music, books, films…</Link>
    </header>

    <div className="v2-explore-filters">
      <KindTabs includeAll value={kind} onChange={setKind} />
    </div>

    {state === 'anonymous' && <div className="empty-state"><div>
      <p>سجّل الدخول لرؤية الاقتراحات المبنية على اهتماماتك.</p>
      <Link href="/login" className="primary-button mt16">تسجيل الدخول</Link>
    </div></div>}

    {error && <div className="screen-pad"><p className="status-message error">{error}</p></div>}
    {state === 'loading' && <div className="screen-pad"><div className="skeleton" /></div>}

    {state === 'ready' && items.length === 0 && <div className="empty-state"><div>
      <Sparkles size={28} />
      <p className="mt12">لا توجد أرضية مشتركة كافية بعد.</p>
      <Link href="/interests" className="primary-button mt16">اختر اهتماماتك</Link>
    </div></div>}

    {state === 'ready' && items.length > 0 && <>
      <div className="v2-explore-section-title">People with similar taste</div>
      <div className="v2-explore-people" aria-live="polite">
        {items.map(match => <Link href={`/u/${match.publicCode}`} className="v2-taste-person" key={match.publicCode}>
          <span className="v2-taste-dot" style={{ backgroundColor: match.identityColor }} aria-hidden="true" />
          <span className="v2-taste-copy">
            <strong>{match.publicCode}</strong>
            <span data-user-content="">
              {match.sharedItems?.slice(0, 3).map(item => item.label).join(' · ') || `${match.compatibility}% shared taste`}
            </span>
          </span>
          <span className="v2-taste-score" dir="ltr">{match.compatibility}%</span>
        </Link>)}
      </div>

      <div className="v2-explore-section-title">Popular cultural threads</div>
      <div className="v2-cultural-threads">
        <Link href="/search?q=songs" className="v2-cultural-thread">songs that feel like leaving</Link>
        <Link href="/search?q=books" className="v2-cultural-thread">books you read too young</Link>
        <Link href="/search?q=films" className="v2-cultural-thread">films that changed after a breakup</Link>
      </div>

      <div className="feed-footer">
        {hasMore
          ? <button className="secondary-button" disabled={loadingMore} onClick={() => load(items.length)}>
              {loadingMore ? 'جارِ التحميل…' : 'عرض المزيد'}
            </button>
          : <span className="tiny subtle">{total} اقتراح</span>}
      </div>
    </>}
  </section>
}

export function PublicInterestProfile({ profile }) {
  if (!profile?.items?.length) return null

  return <section className="screen-pad">
    <div className="panel music-panel">
      <h2 className="music-section-title">اهتمامات</h2>
      {INTEREST_KINDS.map(kind => {
        const items = profile.items.filter(item => item.kind === kind)
        if (!items.length) return null
        return <div key={kind} style={{ marginTop: 14 }}>
          <div className="small muted" style={{ marginBottom: 8 }}>{KIND_META[kind].label}</div>
          <div className="chip-grid">
            {items.map(item => <span className="chip static" key={item.id}>
              <span data-user-content="">{item.label}</span>
              {item.subtitle ? <span className="tiny subtle" data-user-content="">· {item.subtitle}</span> : null}
            </span>)}
          </div>
        </div>
      })}
    </div>
  </section>
}
