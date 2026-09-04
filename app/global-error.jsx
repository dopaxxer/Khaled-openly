'use client'

import { useEffect } from 'react'

// This boundary also covers failures in the root layout, where app/error.jsx
// cannot render. It owns the document shell as required by the App Router.
export default function GlobalError({ error, reset }) {
  useEffect(() => { console.error(error) }, [error])

  return <html lang="ar" dir="rtl">
    <body>
      <main className="empty-state">
        <div>
          <h1>تعذّر تشغيل Openly</h1>
          <p>حدث خطأ غير متوقع. حاول تحميل التطبيق مرة أخرى.</p>
          <button type="button" className="primary-button mt16" onClick={reset}>المحاولة مجددًا</button>
        </div>
      </main>
    </body>
  </html>
}
