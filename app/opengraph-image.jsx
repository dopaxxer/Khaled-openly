import { ImageResponse } from 'next/og'

export const alt = 'Openly — openly.ink'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default function OpenGraphImage() {
  return new ImageResponse(
    <div style={{
      width: '100%',
      height: '100%',
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'space-between',
      background: '#F3F1EC',
      color: '#111113',
      padding: '72px 84px'
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
        <div style={{
          width: 92,
          height: 92,
          borderRadius: 999,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#173DCE',
          color: '#FFFFFF',
          fontSize: 48,
          fontWeight: 700
        }}>O</div>
        <div style={{ fontSize: 72, fontWeight: 700, letterSpacing: -3 }}>Openly</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div style={{ fontSize: 42, fontWeight: 600 }}>Public words. Human order.</div>
        <div style={{ fontSize: 30, color: '#52525B' }}>openly.ink</div>
      </div>
    </div>,
    size
  )
}
