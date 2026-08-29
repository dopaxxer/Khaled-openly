'use client'

import { Music } from 'lucide-react'
import { TrackPreviewButton } from './TrackPreview'

function PublicTrack({ track }) {
  return <div className="result-row" style={{ gap: 12, alignItems: 'center', cursor: 'default' }}>
    {track.artworkUrl
      ? <img
          src={track.artworkUrl}
          alt=""
          width={52}
          height={52}
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          style={{ width: 52, height: 52, objectFit: 'cover', borderRadius: 10, flex: '0 0 auto' }}
        />
      : <span
          aria-hidden="true"
          style={{ width: 52, height: 52, borderRadius: 10, display: 'grid', placeItems: 'center', background: 'var(--surface-soft)', flex: '0 0 auto' }}
        ><Music size={19} /></span>}
    {/* Catalog metadata is content: the language bridge must not translate it. */}
    <span style={{ minWidth: 0, flex: 1 }} data-user-content="">
      <strong style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{track.title}</strong>
      <span className="tiny subtle" style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {track.artist}{track.album ? ` · ${track.album}` : ''}
      </span>
    </span>
    <TrackPreviewButton previewUrl={track.previewUrl} title={track.title}/>
  </div>
}

export function PublicMusicProfile({ music }) {
  const tracks = Array.isArray(music?.tracks) ? music.tracks : []
  const artists = Array.isArray(music?.artists) ? music.artists : []
  const genres = Array.isArray(music?.genres) ? music.genres : []

  if (!tracks.length && !artists.length && !genres.length) return null

  return <>
    <div className="section-title">الذوق الموسيقي</div>
    <div className="screen-pad">
      <div className="panel music-panel stack">
        {tracks.length > 0 && <div>
          <div className="small muted" style={{ marginBottom: 8 }}>الأغاني المفضلة</div>
          <div className="result-list">
            {tracks.map(track => <PublicTrack key={track.id} track={track} />)}
          </div>
        </div>}
        {genres.length > 0 && <div>
          <div className="small muted" style={{ marginBottom: 8 }}>التصنيفات</div>
          <div className="chip-grid">
            {genres.map(genre => <span className="chip static" key={genre.id}>{genre.nameAr}</span>)}
          </div>
        </div>}
        {artists.length > 0 && <p className="small">
          <span className="muted">الفنانون: </span>{artists.map(artist => artist.name).join('، ')}
        </p>}
      </div>
    </div>
  </>
}
