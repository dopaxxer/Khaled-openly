import './globals.css'
import './ios-polish.css'
import { AppShell } from '@/components/AppShell'
import { DeviceVisitTracker } from '@/components/DeviceVisitTracker'
import { LanguageBridge } from '@/components/LanguageBridge'
import { CANONICAL_ORIGIN } from '@/lib/publicOrigin'
import { THEME_BOOT_SCRIPT } from '@/lib/theme'
import { headers } from 'next/headers'

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
    { media: '(prefers-color-scheme: light)', color: '#f3f1ec' },
    { media: '(prefers-color-scheme: dark)', color: '#111113' }
  ]
}

export default async function RootLayout({ children }) {
  const nonce = (await headers()).get('x-nonce') || undefined
  return (
    <html lang="ar" dir="rtl" suppressHydrationWarning>
      <head><script nonce={nonce} dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }}/></head>
      <body>
        <LanguageBridge />
        <DeviceVisitTracker />
        <AppShell>{children}</AppShell>
      </body>
    </html>
  )
}
