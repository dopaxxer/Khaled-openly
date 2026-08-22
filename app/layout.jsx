import './globals.css'
import './ios-polish.css'
import { AppShell } from '@/components/AppShell'

export const metadata = {
  title: 'Openly',
  description: 'شبكة نصية عامة بلا رسائل خاصة وبلا خوارزمية ترتيب.',
  applicationName: 'Openly',
  robots: { index: true, follow: true },
  manifest: '/manifest.webmanifest',
  icons: {
    icon: '/openly-mark.webp',
    apple: '/openly-mark.webp'
  }
}

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f7f8fb' },
    { media: '(prefers-color-scheme: dark)', color: '#090b10' }
  ]
}

export default function RootLayout({ children }) {
  return (
    <html lang="ar" dir="rtl">
      <body><AppShell>{children}</AppShell></body>
    </html>
  )
}
