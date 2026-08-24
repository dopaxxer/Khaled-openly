import './globals.css'
import './ios-polish.css'
import { AppShell } from '@/components/AppShell'
import { DeviceVisitTracker } from '@/components/DeviceVisitTracker'
import { THEME_BOOT_SCRIPT } from '@/lib/theme'
import { headers } from 'next/headers'

export const dynamic = 'force-dynamic'

export const metadata = {
  title: 'open',
  description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.',
  applicationName: 'open',
  robots: { index: true, follow: true },
  manifest: '/manifest.webmanifest'
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
        <DeviceVisitTracker />
        <AppShell>{children}</AppShell>
      </body>
    </html>
  )
}
