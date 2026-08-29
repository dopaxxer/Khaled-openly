'use client'
import { useState } from 'react'
import { Composer } from './Composer'
import { Timeline } from './Timeline'

export function HomeScreen() {
  // Publishing from the card has to refresh the feed below it; the timeline
  // owns its own fetch, so the counter is what tells it to run again.
  const [published, setPublished] = useState(0)

  return <section className="v2-home-screen">
    <Composer inline onPublished={() => setPublished(count => count + 1)} />
    <div className="v2-home-timeline">
      <Timeline refreshToken={published} />
    </div>
  </section>
}
