'use client'

import { Pause, Play } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'

// One module, one playing preview. Every place that renders a preview button
// shares this reference, so starting a song in the music page stops one that
// was playing in a post card.
let activeAudio = null

/** The catalog only ever stores https previews; anything else is not played. */
export function playablePreview(value) {
  return /^https:\/\//i.test(String(value || '')) ? String(value) : null
}

/**
 * Play/pause control for a 30 second catalog preview.
 *
 * Renders nothing when the track has no preview, which is why every caller can
 * drop it in unconditionally.
 */
export function TrackPreviewButton({ previewUrl, title = '' }) {
  const audioRef = useRef(null)
  const [playing, setPlaying] = useState(false)
  const url = playablePreview(previewUrl)

  useEffect(() => () => {
    const audio = audioRef.current
    if (!audio) return
    audio.pause()
    if (activeAudio === audio) activeAudio = null
  }, [])

  if (!url) return null

  async function toggle() {
    const audio = audioRef.current
    if (!audio) return

    if (!audio.paused) {
      audio.pause()
      return
    }

    if (activeAudio && activeAudio !== audio) {
      activeAudio.pause()
      try { activeAudio.currentTime = 0 } catch { }
    }
    activeAudio = audio

    try {
      await audio.play()
    } catch {
      // Autoplay policies and network errors both land here. Leaving the button
      // in its resting state is the honest result.
      if (activeAudio === audio) activeAudio = null
      setPlaying(false)
    }
  }

  function finish() {
    const audio = audioRef.current
    if (audio) audio.currentTime = 0
    if (activeAudio === audio) activeAudio = null
    setPlaying(false)
  }

  const label = playing ? 'إيقاف معاينة الأغنية' : 'تشغيل معاينة الأغنية'
  return <>
    <button
      type="button"
      className="track-play-button"
      onClick={toggle}
      aria-label={title ? `${label}: ${title}` : label}
      aria-pressed={playing}
      title={label}
    >
      {playing ? <Pause size={17} fill="currentColor"/> : <Play size={17} fill="currentColor"/>}
    </button>
    <audio
      ref={audioRef}
      className="track-audio"
      src={url}
      preload="none"
      onPlay={() => setPlaying(true)}
      onPause={() => setPlaying(false)}
      onEnded={finish}
    />
  </>
}
