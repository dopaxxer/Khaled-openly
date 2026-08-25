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

### بريد التحقق عبر Resend

إعدادات Supabase Auth الإنتاجية:

- Sender: `Openly <auth@openly.ink>`
- SMTP host: `smtp.resend.com`
- SMTP port: `465`
- SMTP username: `resend`
- SMTP password: مفتاح Resend السري؛ يُحفظ في لوحة Supabase فقط ولا يُضاف إلى GitHub.
- Site URL: `https://khaled-openly.vercel.app`
- Redirect URL: `https://khaled-openly.vercel.app/api/auth/callback`

انسخ محتوى `supabase/email-templates/confirmation.html` إلى قالب **Confirm signup** في Supabase حتى تحتوي الرسالة على `{{ .Token }}` الذي تتوقعه شاشتا الموقع وiOS.

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

## الإشارات (@) واكتشاف الموسيقى

### قواعد الإشارة

الصيغة الوحيدة المعتمدة، وهي متطابقة حرفيًا في ثلاثة أماكن — `private.parse_mention_codes`
في مجلد الترحيلات، و`lib/mentions.js` للويب، و`MentionParser` في تطبيق iOS:

```
(^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])
```

- الحد الأقصى 10 إشارات لكل منشور أو تعليق.
- الخادم وحده يحلّل النص المخزَّن ويحوّله إلى إشارات، معتمدًا على `auth.uid()`؛ لا يُقبل أي
  معرّف يرسله العميل.
- الإنشاء والتحليل يجريان داخل معاملة واحدة (`public.create_post`، `public.create_comment`،
  `public.update_own_post`)، فلا يوجد منشور بلا صفوف إشاراته.
- كود غير موجود، أو كود لمستخدم حظرك، يبقى نصًا عاديًا بلا رابط.
- التعديل الذي يزيل إشارة يزيل صفّها وإشعارها معًا؛ والحذف الناعم للمنشور أو التعليق ينظّف
  الإشارات والإشعارات المرتبطة بها.
- الإشعار لا يُرسل لصاحب النص نفسه، ولا لمن كتم الكاتب، ولا يتكرّر (فهارس فريدة جزئية).

### معادلة التوافق الموسيقي

محسوبة في `private.discover_music_people`، وموصّفة أيضًا في `lib/musicScore.js`
و`MusicScore` على iOS:

```
raw        = 3 × الفنانون المشتركون + 1 × التصنيفات المشتركة
ceiling    = 3 × min(فنانيك, فنانيه) + 1 × min(تصنيفاتك, تصنيفاته)
overlap    = ceiling ≤ 0 ? 0 : min(1, raw / ceiling)
confidence = min(1, raw / 6)
score      = round(100 × overlap × confidence)
```

- الفنان يزن ثلاثة أضعاف التصنيف.
- `ceiling` يقيس أفضل نتيجة ممكنة بالنظر إلى أقصر القائمتين، وهو محميّ من القسمة على صفر.
- `confidence` يمنع تطابقًا ضعيفًا واحدًا من الظهور كتطابق تام: تصنيف واحد مشترك لا يتجاوز
  17%، وفنان واحد مشترك لا يتجاوز 50%.
- لا يظهر أي شخص ما لم يشارك فنانًا واحدًا على الأقل أو تصنيفين.
- الترتيب حتمي: النسبة، ثم عدد الفنانين، ثم عدد التصنيفات، ثم الكود العام.
- كل نتيجة تُرجع الفنانين والتصنيفات المشتركة التي صنعت النسبة، فلا توجد توصية غير مفسَّرة.
  لا نجمع سجل استماع ولا نستخدم أي نموذج توصية.

### الخصوصية والظهور

خياران مستقلان في `public.music_preferences`:

- `discovery_opt_in`: الظهور في صفحة اكتشاف الموسيقى. لا يُعرض عندها إلا الكود العام
  ولون الهوية والمشترك بينكما والنسبة.
- `preferences_public`: عرض القائمة كاملة في الصفحة العامة للهوية.

إلغاء الاشتراك يسري فورًا لأن الاستعلام يقرأ العلامة مباشرة. و`clear_music_preferences`
يحذف كل بيانات الموسيقى من الحساب.

### واجهة API الإصدار الأول

يستخدمها الموقع وتطبيق iOS معًا بنفس النماذج. المسارات القديمة تحت `/api` باقية كما هي.

| المسار | الطريقة | الوصف |
| --- | --- | --- |
| `/api/v1/mentions/suggest?q=` | GET | إكمال تلقائي للأكواد العامة (يتطلب تسجيل الدخول) |
| `/api/v1/mentions/resolve` | POST | تحليل نص وإرجاع الإشارات القابلة للحل |
| `/api/v1/music/genres?q=` | GET | كتالوج التصنيفات |
| `/api/v1/music/artists?q=` | GET | البحث في الفنانين |
| `/api/v1/music/artists` | POST | إضافة فنان جديد مع منع التكرار |
| `/api/v1/music/preferences` | GET / PUT / DELETE | قراءة وتحديث وحذف تفضيلاتك |
| `/api/v1/music/preferences/artists` | PUT | استبدال قائمة الفنانين بترتيبها |
| `/api/v1/music/preferences/genres` | PUT | استبدال قائمة التصنيفات |
| `/api/v1/music/discover` | GET | الاقتراحات مع التصفية والصفحات |
| `/api/v1/users/{code}/music` | GET | القائمة العامة لهوية نشرتها |

كل الاستجابات تحمل `Cache-Control: private, no-store`، وشكل الخطأ موحّد
`{ "error": "رسالة", "code": "machine_code" }`. الحدود على البحث والإكمال والكتابة
مطبَّقة في `lib/rateLimit.js`.

### الاختبارات

```bash
npm test                                              # المحلّل والتطبيع والمعادلة والحدود
psql "$DATABASE_URL" -f supabase/tests/rls_authorization.sql   # صلاحيات RLS
```

سكربت RLS يعمل داخل معاملة واحدة وينتهي بـ`ROLLBACK`، فينشئ بياناته ويزيلها بنفسه.
اختبارات iOS في `ios/OpenlyTests` وتعمل ضمن مسار `Swift` في GitHub Actions.
