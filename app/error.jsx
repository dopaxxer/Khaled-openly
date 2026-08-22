'use client'
import { useEffect } from 'react'

// Raw Postgres/Supabase messages can name tables, columns and constraints, so
// the screen stays generic and the detail goes to the console instead.
export default function Error({ error, reset }) {
  useEffect(() => { console.error(error) }, [error])

  return <div className="empty-state">
    <div>
      <h1>حدث خطأ غير متوقع</h1>
      <p>تعذّر عرض هذه الصفحة. جرّب مرة أخرى.</p>
      <button className="primary-button mt16" onClick={reset}>المحاولة مجددًا</button>
    </div>
  </div>
}
