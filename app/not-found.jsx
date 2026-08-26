import Link from 'next/link'
import { UserRound } from 'lucide-react'

export const metadata = {
  title: 'الصفحة غير موجودة',
  robots: { index: false, follow: false }
}

export default function NotFound() {
  return <div className="empty-state">
    <div>
      <UserRound size={28} aria-hidden="true" />
      <h1>الصفحة غير موجودة</h1>
      <p>ربما تغيّر الرابط أو حُذف المحتوى.</p>
      <Link href="/" className="primary-button mt16">العودة للرئيسية</Link>
    </div>
  </div>
}
