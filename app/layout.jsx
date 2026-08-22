import './globals.css'
import './ios-polish.css'
import { AppShell } from '@/components/AppShell'
import { THEME_BOOT_SCRIPT } from '@/lib/theme'

export const metadata = {
  title: 'Openly',
  description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.',
  applicationName: 'Openly',
  robots: { index: true, follow: true },
  manifest: '/manifest.webmanifest'
}

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f5f5f4' },
    { media: '(prefers-color-scheme: dark)', color: '#05070f' }
  ]
}

export default function RootLayout({ children }) {
  return (
    <html lang="ar" dir="rtl" suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }}/></head>
      <body><AppShell>{children}</AppShell></body>
    </html>
  )
}
