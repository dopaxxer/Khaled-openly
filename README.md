# Openly

تطبيق اجتماعي نصّي يتكوّن من واجهة Next.js 16 وتطبيق SwiftUI أصلي، ويستخدم Supabase للمصادقة والبيانات. نقطة API الرسمية لتطبيق iOS هي مشروع Vercel `khaled-openly`؛ ويمكن استخدام Netlify كمعاينة مستقلة.

## التشغيل والتحقق

المتطلبات: Node.js 24، وnpm، وXcode 16.4 مع XcodeGen لبناء iOS.

```bash
npm ci
npm test
npm run build
npm start
```

لا توجد مفاتيح سرية مطلوبة في المتصفح أو تطبيق iOS. استخدم فقط مفتاح Supabase القابل للنشر، ولا تضف `service_role` أو أي مفتاح سري إلى متغير يبدأ بـ`NEXT_PUBLIC_`.

انسخ `.env.example` واضبط القيم التالية على منصة الاستضافة:

- `NEXT_PUBLIC_SITE_URL`: الرابط العام النهائي الذي تستقبله روابط البريد.
- `NEXT_PUBLIC_SUPABASE_URL`: رابط مشروع Supabase.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: المفتاح القابل للنشر للمشروع.

## النشر

- Vercel: إطار العمل Next.js، أمر البناء `npm run build`، وإصدار Node.js 24.
- Netlify: الإعدادات موجودة في `netlify.toml`، مع نفس متغيرات البيئة.
- Supabase: طبّق الملفات المرتبة داخل `supabase/migrations`. جميع الجداول المكشوفة تستخدم RLS، وتُقيّد الكتابة أيضًا على مستوى الأعمدة.
- GitHub: مسار `Web quality and security` يشغّل الاختبارات والبناء و`npm audit`، ومسارا Swift يبنيان التطبيق الأصلي وIPA غير موقّع مع ملف SHA-256.

الـIPA الناتج غير موقّع عمدًا. يجب توقيعه بشهادة وملف provisioning صالحين قبل التثبيت أو النشر في App Store.

## بوابة الإصدار

قبل اعتماد أي إصدار نهائي:

1. نجاح اختبارات Node وبناء Next.js.
2. نجاح بناء Swift Debug وRelease ورفع IPA.
3. خلو سجلات Vercel من أخطاء 5xx، واجتياز فحص Supabase Security Advisor.
4. اختبار التسجيل، تأكيد البريد، استعادة كلمة المرور، النشر، التعليق، الحذف، الحظر والإبلاغ بحساب اختبار.
5. توقيع IPA والتحقق من بصمته بعد التنزيل.
