import './globals.css'
import './ios-polish.css'
import './openly-v2.css'
import { AppShell } from '@/components/AppShell'
import { DeviceVisitTracker } from '@/components/DeviceVisitTracker'
import { LanguageBridge } from '@/components/LanguageBridge'
import { CANONICAL_ORIGIN } from '@/lib/publicOrigin'
import { THEME_BOOT_SCRIPT } from '@/lib/theme'
import { Noto_Sans_Arabic } from 'next/font/google'
import { headers } from 'next/headers'

// Figma V2 / native iOS use SF Pro Text + SF Arabic. Do not attach next/font's
// className to <body> — that would override the system stack on Apple devices
// (the IBM Plex experiment did exactly that). The webfont is a fallback only.
const arabicFallback = Noto_Sans_Arabic({
  subsets: ['arabic', 'latin'],
  weight: ['400', '500', '600', '700'],
  display: 'swap',
  variable: '--font-arabic',
  adjustFontFallback: false
})

export const dynamic = 'force-dynamic'

export const metadata = {
  metadataBase: new URL(CANONICAL_ORIGIN),
  title: {
    default: 'Openly',
    template: '%s · Openly'
  },
  description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.',
  applicationName: 'Openly',
  alternates: { canonical: '/' },
  robots: { index: true, follow: true },
  manifest: '/manifest.webmanifest',
  openGraph: {
    type: 'website',
    url: '/',
    siteName: 'Openly',
    title: 'Openly',
    description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.',
    locale: 'ar_AR',
    alternateLocale: ['en_US']
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Openly',
    description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.'
  }
}

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f7f4ee' },
    { media: '(prefers-color-scheme: dark)', color: '#111113' }
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
