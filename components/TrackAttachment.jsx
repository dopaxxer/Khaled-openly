'use client'

import { Music2, Pause, Play } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'

// The module is shared by every rendered attachment on the page. Keeping the
// active element here guarantees that starting one preview stops the previous
// one without adding a page-wide state library.
let activeAudio = null

function isHttps(value) {
  return /^https:\/\//i.test(String(value || ''))
}

export function TrackAttachment({ track }) {
  const audioRef = useRef(null)
  const [playing, setPlaying] = useState(false)
  const artworkUrl = isHttps(track?.artworkUrl) ? track.artworkUrl : null
  const previewUrl = isHttps(track?.previewUrl) ? track.previewUrl : null

  useEffect(() => () => {
    const audio = audioRef.current
    if (!audio) return
    audio.pause()
    if (activeAudio === audio) activeAudio = null
  }, [])

  async function togglePreview() {
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
      if (activeAudio === audio) activeAudio = null
      setPlaying(false)
    }
  }

  function finishPreview() {
    const audio = audioRef.current
    if (audio) audio.currentTime = 0
    if (activeAudio === audio) activeAudio = null
    setPlaying(false)
  }

  return <div className="track-attachment">
    {artworkUrl
      ? <img
          className="track-artwork"
          src={artworkUrl}
          alt=""
          width={48}
          height={48}
          loading="lazy"
          referrerPolicy="no-referrer"
        />
      : <span className="track-artwork track-artwork-fallback" aria-hidden="true"><Music2 size={19}/></span>}

    <span className="track-attachment-meta" dir="auto">
      <strong>{track.title}</strong>
      <span>{track.artist}</span>
    </span>

    {previewUrl && <>
      <button
        type="button"
        className="track-play-button"
        onClick={togglePreview}
        aria-label={playing ? 'إيقاف معاينة الأغنية' : 'تشغيل معاينة الأغنية'}
        aria-pressed={playing}
      >
        {playing ? <Pause size={17} fill="currentColor"/> : <Play size={17} fill="currentColor"/>}
      </button>
      <audio
        ref={audioRef}
        className="track-audio"
        src={previewUrl}
        preload="none"
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={finishPreview}
      />
    </>}
  </div>
}
