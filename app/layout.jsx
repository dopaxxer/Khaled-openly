import './globals.css'
import './ios-polish.css'
import './openly-v2.css'
import './interface.css'
import { AppShell } from '@/components/AppShell'
import { DeviceVisitTracker } from '@/components/DeviceVisitTracker'
import { LanguageBridge } from '@/components/LanguageBridge'
import { CANONICAL_ORIGIN } from '@/lib/publicOrigin'
import { THEME_BOOT_SCRIPT } from '@/lib/theme'
import { Vazirmatn } from 'next/font/google'
import { headers } from 'next/headers'

// Figma V2 frames and native iOS use SF Pro Text + SF Arabic (Boutros).
// Named SF faces must sit in front of -apple-system: on Linux/Android the
// system UI font already has Arabic glyphs (usually Noto), so a webfont
// listed after -apple-system never loads. Apple still hits local SF first.
// Vazirmatn is the variable webfont fallback — same humanist Arabic sans as
// SF Arabic, with real weights for 450/650 so the UI does not faux-bold.
// Apple devices now resolve San Francisco through `-apple-system` (see the
// @supports block in openly-v2.css) and never reference this face, so it is
// no longer preloaded: an iPhone was downloading a webfont it would not draw
// a single glyph with. Everywhere else the browser still fetches it as soon
// as it parses the stylesheet that uses it.
const arabicFallback = Vazirmatn({
  subsets: ['arabic', 'latin'],
  display: 'swap',
  variable: '--font-arabic',
  adjustFontFallback: false,
  preload: false
})

export const dynamic = 'force-dynamic'

export const metadata = {
  metadataBase: new URL(CANONICAL_ORIGIN),
  title: {
    default: 'Openly',
    template: '%s · Openly'
  },
  description: 'شبكة نصية عامة للأفكار والذوق والمحادثة، بلا خوارزمية ترتيب.',
  applicationName: 'Openly',
  alternates: { canonical: '/' },
  robots: { index: true, follow: true },
  manifest: '/manifest.webmanifest',
  openGraph: {
    type: 'website',
    url: '/',
    siteName: 'Openly',
    title: 'Openly',
    description: 'شبكة نصية عامة للأفكار والذوق والمحادثة، بلا خوارزمية ترتيب.',
    locale: 'ar_AR',
    alternateLocale: ['en_US']
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Openly',
    description: 'شبكة نصية عامة للأفكار والذوق والمحادثة، بلا خوارزمية ترتيب.'
  }
}

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f5f6fa' },
    { media: '(prefers-color-scheme: dark)', color: '#111521' }
  ]
}

export default async function RootLayout({ children }) {
  const nonce = (await headers()).get('x-nonce') || undefined
  return (
    <html lang="ar" dir="rtl" className={arabicFallback.variable} suppressHydrationWarning>
      <head><script nonce={nonce} dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }}/></head>
      <body>
        <LanguageBridge />
        <DeviceVisitTracker />
        <AppShell>{children}</AppShell>
      </body>
    </html>
  )
}
