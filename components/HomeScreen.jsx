'use client'
import { useState } from 'react'
import Link from 'next/link'
import { ArrowUpLeft, Search } from 'lucide-react'
import { Composer } from './Composer'
import { Timeline } from './Timeline'

export function HomeScreen() {
  // Publishing from the card has to refresh the feed below it; the timeline
  // owns its own fetch, so the counter is what tells it to run again.
  const [published, setPublished] = useState(0)

  return <section className="v2-home-screen">
    <header className="home-page-header">
      <div>
        <span className="home-kicker" dir="ltr">OPENLY / COMMUNITY</span>
        <h1>الرئيسية</h1>
        <p>أفكار وموسيقى وأشخاص يستحقون وقتك.</p>
      </div>
      <Link href="/search" className="home-search-link" aria-label="بحث"><Search size={21} aria-hidden="true"/></Link>
    </header>
    <nav className="home-sections" aria-label="أقسام المجتمع">
      <Link href="/" aria-current="page">الكتابات</Link>
      <Link href="/discover/music">الموسيقى</Link>
      <Link href="/discover">الأشخاص</Link>
    </nav>
    <Composer inline onPublished={() => setPublished(count => count + 1)} />
    <div className="home-feed-heading">
      <div><h2>آخر الكتابات</h2><span>الأحدث أولًا</span></div>
      <Link href="/discover"><span>اكتشف أشخاصًا</span><ArrowUpLeft size={17} aria-hidden="true"/></Link>
    </div>
    <div className="v2-home-timeline">
      <Timeline refreshToken={published} />
    </div>
  </section>
}
