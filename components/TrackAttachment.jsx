'use client'

import { Music2 } from 'lucide-react'
import { TrackPreviewButton } from './TrackPreview'

function artwork(value) {
  return /^https:\/\//i.test(String(value || '')) ? String(value) : null
}

export function TrackAttachment({ track }) {
  const artworkUrl = artwork(track?.artworkUrl)

  return <div className="track-attachment">
    {artworkUrl
      ? <img
          className="track-artwork"
          src={artworkUrl}
          alt=""
          width={48}
          height={48}
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
        />
      : <span className="track-artwork track-artwork-fallback" aria-hidden="true"><Music2 size={19}/></span>}

    {/* Catalog metadata is content, not interface copy. Without the marker the
        language bridge would run a song called "حفظ" through its dictionary and
        render it as "Save". */}
    <span className="track-attachment-meta" dir="auto" data-user-content="">
      <strong>{track.title}</strong>
      <span>{track.artist}</span>
    </span>

    <TrackPreviewButton previewUrl={track.previewUrl} title={track.title}/>
  </div>
}
