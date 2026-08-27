import { NextResponse } from 'next/server'
import { createSupabaseServerClient } from '@/lib/supabase'
import { logError } from '@/lib/logger'
import { readJson } from '@/lib/validation'
import {
  INTEREST_LABEL_MAX_LENGTH,
  normalizeInterestKind
} from '@/lib/interests'
import {
  isCatalogProviderForKind,
  lookupAppleInterest,
  searchAppleInterests
} from '@/lib/interestCatalog'
import { consumeRateLimit, RATE_LIMITS, rateLimitKey } from '@/lib/rateLimit'

export const dynamic = 'force-dynamic'

const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Content-Type-Options': 'nosniff'
}

function ok(body) {
  return NextResponse.json(body, { status: 200, headers: HEADERS })
}

function fail(status, code, message) {
  if (status >= 500) logError(`v1.interests.${code}`, { code, status })
  return NextResponse.json({ error: message, code }, { status, headers: HEADERS })
}

async function requireUser(supabase) {
  const { data: { user } } = await supabase.auth.getUser()
  return user || null
}

function guard(request, scope, userId) {
  const result = consumeRateLimit(rateLimitKey(request, scope, userId), RATE_LIMITS[scope])
  if (result.allowed) return null
  return fail(429, 'rate_limited', 'محاولات كثيرة. حاول بعد قليل.')
}

async function withCatalogTimeout(work) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 7000)
  try {
    return await work(controller.signal)
  } finally {
    clearTimeout(timer)
  }
}

function identityKey(item) {
  return [
    String(item?.kind || '').toLowerCase(),
    String(item?.label || '').trim().toLocaleLowerCase(),
    String(item?.subtitle || '').trim().toLocaleLowerCase()
  ].join('|')
}

export async function GET(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = guard(request, 'interestSearch', user.id)
  if (limited) return limited

  const url = new URL(request.url)
  const query = String(url.searchParams.get('q') || '').trim().slice(0, INTEREST_LABEL_MAX_LENGTH)
  const rawKind = url.searchParams.get('kind')
  const kind = rawKind ? normalizeInterestKind(rawKind) : null
  if (rawKind && !kind) return fail(400, 'invalid_kind', 'نوع الاهتمام غير صالح')

  const { data, error } = await supabase.rpc('search_interest_items', {
    p_query: query || null,
    p_kind: kind,
    p_limit: 30
  })
  if (error) return fail(500, 'search_failed', 'تعذر البحث في الاهتمامات')

  const saved = Array.isArray(data) ? data : []
  if (!query || !['book', 'movie'].includes(kind)) return ok({ items: saved })

  const catalogLimited = guard(request, 'interestCatalogSearch', user.id)
  if (catalogLimited) return catalogLimited

  let catalog = []
  try {
    catalog = await withCatalogTimeout(signal => searchAppleInterests(query, kind, 16, signal))
  } catch {
    return ok({ items: saved, catalogUnavailable: true })
  }

  const savedByIdentity = new Map(saved.map(item => [identityKey(item), item]))
  const catalogKeys = new Set(catalog.map(identityKey))
  const enrichedCatalog = catalog.map(item => {
    const existing = savedByIdentity.get(identityKey(item))
    return existing ? { ...item, popularity: existing.popularity || 0 } : item
  })

  return ok({
    items: [
      ...enrichedCatalog,
      ...saved.filter(item => !catalogKeys.has(identityKey(item)))
    ],
    catalog: 'apple'
  })
}

export async function POST(request) {
  const supabase = await createSupabaseServerClient()
  const user = await requireUser(supabase)
  if (!user) return fail(401, 'unauthorized', 'غير مسجل')

  const limited = guard(request, 'interestWrite', user.id)
  if (limited) return limited

  const parsed = await readJson(request)
  if (parsed.error) return fail(parsed.status, 'invalid_request', parsed.error)

  const kind = normalizeInterestKind(parsed.data.kind)
  if (!kind) return fail(400, 'invalid_kind', 'نوع الاهتمام غير صالح')

  const provider = String(parsed.data.provider || '').trim().toLowerCase()
  const externalId = String(parsed.data.externalId || '').trim()

  if (kind === 'book' || kind === 'movie') {
    if (!isCatalogProviderForKind(provider, kind) || !/^\d{1,20}$/.test(externalId)) {
      return fail(400, 'catalog_required', 'اختر الكتاب أو الفيلم من نتائج الكتالوج')
    }

    let catalogItem
    try {
      catalogItem = await withCatalogTimeout(signal => lookupAppleInterest(externalId, kind, signal))
    } catch {
      return fail(502, 'catalog_unavailable', 'تعذر التحقق من الكتالوج الآن')
    }
    if (!catalogItem) return fail(404, 'catalog_item_missing', 'لم يعد هذا العنصر موجودًا في الكتالوج')

    const { data, error } = await supabase.rpc('add_catalog_interest', {
      p_kind: kind,
      p_provider: catalogItem.provider,
      p_external_id: catalogItem.externalId,
      p_label: catalogItem.label,
      p_subtitle: catalogItem.subtitle,
      p_artwork_url: catalogItem.artworkUrl,
      p_release_year: catalogItem.releaseYear,
      p_external_url: catalogItem.externalUrl
    })
    if (error || !data) return fail(400, 'create_failed', 'تعذر حفظ العنصر')
    return ok({ item: { ...data, source: 'saved', popularity: 0 } })
  }

  const label = String(parsed.data.label || '').trim()
  const subtitle = String(parsed.data.subtitle || '').trim()
  if (!label || label.length > INTEREST_LABEL_MAX_LENGTH) {
    return fail(400, 'invalid_label', 'اسم الاهتمام غير صالح')
  }
  if (subtitle.length > INTEREST_LABEL_MAX_LENGTH) {
    return fail(400, 'invalid_subtitle', 'التفصيل أطول من المسموح')
  }

  const { data, error } = await supabase.rpc('add_interest', {
    p_kind: kind,
    p_label: label,
    p_subtitle: subtitle || null
  })
  if (error || !data) return fail(400, 'create_failed', 'تعذر إضافة الاهتمام')
  return ok({ item: { ...data, source: 'saved', popularity: 0 } })
}
