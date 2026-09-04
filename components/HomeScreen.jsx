'use client'
import { useState } from 'react'
import Link from 'next/link'
import { ArrowUpLeft, Clock3, MessageCircle } from 'lucide-react'
import { Composer } from './Composer'
import { Timeline } from './Timeline'

export function HomeScreen() {
  // Publishing from the card has to refresh the feed below it; the timeline
  // owns its own fetch, so the counter is what tells it to run again.
  const [published, setPublished] = useState(0)

  return <section className="v2-home-screen">
    <header className="home-welcome">
      <div className="home-welcome-copy">
        <span className="home-eyebrow"><span aria-hidden="true"/>المساحة العامة</span>
        <h1>مساحة للكلام الذي يشبهك.</h1>
        <p>فكرة عابرة، أغنية تحبها، أو بداية حديث.</p>
      </div>
      <div className="home-welcome-art" aria-hidden="true"><span className="welcome-orbit"/><span className="welcome-note"><MessageCircle size={32} strokeWidth={1.4}/></span><span className="welcome-spark"/></div>
    </header>
    <Composer inline onPublished={() => setPublished(count => count + 1)} />
    <div className="home-feed-heading">
      <div><h2>آخر الكتابات</h2><span><Clock3 size={13} aria-hidden="true"/>الأحدث أولًا</span></div>
      <Link href="/discover"><span>اكتشف أشخاصًا</span><ArrowUpLeft size={17} aria-hidden="true"/></Link>
    </div>
    <div className="v2-home-timeline">
      <Timeline refreshToken={published} />
    </div>
  </section>
}
