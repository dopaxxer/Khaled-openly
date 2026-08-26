import { ScreenRouter } from '@/components/Screens'
import { classifyAppRoute } from '@/lib/appRoutes'
import { getPublicPostPage, getPublicProfilePage } from '@/lib/publicPageData'
import { notFound } from 'next/navigation'

export const dynamic = 'force-dynamic'

function compact(value, max = 180) {
  const text = String(value || '').replace(/\s+/g, ' ').trim()
  if (text.length <= max) return text
  return `${text.slice(0, max - 1).trimEnd()}…`
}

function publicMetadata({ title, description, path }) {
  return {
    title,
    description,
    alternates: { canonical: path },
    robots: { index: true, follow: true },
    openGraph: {
      type: 'article',
      url: path,
      title,
      description,
      siteName: 'Openly',
      locale: 'ar_AR'
    },
    twitter: { card: 'summary_large_image', title, description }
  }
}

async function publicEntity(route) {
  if (route.kind === 'user') return getPublicProfilePage(route.code)
  if (route.kind === 'post') return getPublicPostPage(route.id)
  return null
}

export async function generateMetadata({ params }) {
  const { slug = [] } = await params
  const route = classifyAppRoute(slug)
  if (!route) notFound()

  if (route.kind === 'private') {
    return {
      title: route.title,
      robots: { index: false, follow: false },
      alternates: { canonical: route.path }
    }
  }

  const entity = await publicEntity(route)
  if (!entity) notFound()

  if (route.kind === 'user') {
    const description = compact(entity.bio || entity.status) || `الصفحة العامة لهوية @${route.code} على Openly.`
    return publicMetadata({ title: `@${route.code}`, description, path: route.path })
  }

  const author = entity.authorCode ? `@${entity.authorCode}` : 'هوية على Openly'
  const music = entity.track ? ` — ${entity.track.title} · ${entity.track.artist_name}` : ''
  const description = compact(`${entity.body}${music}`)
  return publicMetadata({ title: `منشور ${author}`, description, path: route.path })
}

export default async function Page({ params }) {
  const { slug = [] } = await params
  const route = classifyAppRoute(slug)
  if (!route) notFound()

  if (route.kind === 'user' || route.kind === 'post') {
    const entity = await publicEntity(route)
    if (!entity) notFound()
  }

  return <ScreenRouter slug={slug} />
}
