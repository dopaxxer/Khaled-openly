# Openly

تطبيق اجتماعي نصّي يتكوّن من واجهة Next.js 16 وتطبيق SwiftUI أصلي، ويستخدم Supabase للمصادقة والبيانات. الاستضافة الإنتاجية للموقع وواجهة API هي Cloudflare Workers، عبر محوّل `@opennextjs/cloudflare`.

## التشغيل والتحقق

المتطلبات: Node.js 24، وnpm، وXcode 16.4 مع XcodeGen لبناء iOS.

```bash
npm ci
npm test
npm run build      # يبني Next.js ثم يحوّله إلى Worker في .open-next
npm run cf:preview # تشغيل الـWorker محليًا عبر wrangler
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
- Site URL: `https://openly.ink`
- Redirect URL: `https://openly.ink/api/auth/callback`

انسخ محتوى `supabase/email-templates/confirmation.html` إلى قالب **Confirm signup** في Supabase حتى تحتوي الرسالة على `{{ .Token }}` الذي تتوقعه شاشتا الموقع وiOS.

## النشر

- Cloudflare Workers: الاستضافة الإنتاجية. الـWorker اسمه `openly`، وإعداده في `wrangler.jsonc`
  و`open-next.config.ts`. لا يُنشر بناء Next.js مباشرة: محوّل `@opennextjs/cloudflare` يحوّله إلى
  `.open-next/worker.js` وهو ما تنشره Cloudflare فعليًا.

  `npm run build` يُنتج الـWorker، لا بناء Next.js مجرّدًا. هذا مقصود: كل منصّة تشغّل `npm run build`
  افتراضيًا، وCloudflare منها، فلو أنتج `.next/` فقط فشل النشر بـ
  `The entry-point file at ".open-next/worker.js" was not found` — وهو الخطأ الذي أبقى الإنتاج
  بلا نشر فعليًا.

  التركيب دقيق ولا يُعبث به: المحوّل نفسه ينفّذ سكربت البناء ليُنتج مُخرَج Next.js (انظر
  `buildNextjsApp` في `@opennextjs/aws`، وافتراضه `npm run build`). لذلك يوجّهه
  `buildCommand: 'npm run build:next'` في `open-next.config.ts` إلى `build:next`. بدون هذا التوجيه
  يستدعي `build` نفسه بلا نهاية.

  إعدادات Workers Builds في لوحة Cloudflare — القيم الافتراضية تكفي:

  | الإعداد | القيمة |
  | --- | --- |
  | Build command | `npm run build` |
  | Deploy command | `npx wrangler deploy` للإنتاج، و`npx wrangler versions upload` للمعاينات |
  | Node version | 24 |

  متغيّرات المشروع نوعان، والخلط بينهما لا يُنتج خطأ بل تطبيقًا لا يعمل:

  - **Build variables** في اللوحة. كل ما يبدأ بـ`NEXT_PUBLIC_` يدمجه Next.js داخل الحزمة وقت
    البناء، فضبطه كمتغيّر تشغيل لا يصل إليه الكود إطلاقًا. القيم الإنتاجية المعتمدة:

    | المتغيّر | القيمة |
    | --- | --- |
    | `NEXT_PUBLIC_SITE_URL` | `https://openly.ink` |
    | `NEXT_PUBLIC_SUPABASE_URL` | `https://egwhybfcnlzijomgeebj.supabase.co` |
    | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_pZN6kVnQGZK3QwNdVmG7Ww_vqYqvO_X` |

    معرّف المشروع `egwhybfcnlzijomgeebj` ليس تفصيلًا: نشرٌ يشير إلى مشروع Supabase آخر يسجّل
    الناس ويخزّن منشوراتهم في قاعدة لا يملكها أحد هنا، وتبدو معه كل الحسابات القائمة محذوفة
    وكل كلمة مرور صحيحة مرفوضة. لهذا يرفض `lib/supabaseEnv.js` تقديم الخدمة بلا هذه القيم.
  - **Runtime variables**: `AUTH_EMAIL_MODE` وحده، وهو مثبَّت في `wrangler.jsonc` فلا يحتاج
    ضبطًا في اللوحة.

  `compatibility_date` في `wrangler.jsonc` يجب أن يبقى حديثًا. تاريخ قديم هو سبب رفض الـruntime
  لخيار `cache` في `fetch` وظهور أخطاء 502 من كتالوج Apple.

  ملاحظة معروفة: في Next.js 16 يعمل `proxy.js` على Node.js runtime إجباريًا — التوثيق ينص على أن
  تعيين `runtime` في ملف Proxy يرمي خطأ — ودعم OpenNext لهذا المسار على Cloudflare موصوف بأنه
  تجريبي. البناء ينجح، لكن التحذير متوقَّع ولا يُعالَج من داخل المستودع.
- Supabase: طبّق الملفات المرتبة داخل `supabase/migrations`. جميع الجداول المكشوفة تستخدم RLS، وتُقيّد الكتابة أيضًا على مستوى الأعمدة.
- GitHub: مسار `Web quality and security` يشغّل الاختبارات، ثم يبني الـWorker نفسه الذي تنشره Cloudflare ويتحقق من إنتاج `.open-next/worker.js`، ثم `npm audit`. ومسارا Swift يبنيان التطبيق الأصلي وIPA غير موقّع مع ملف SHA-256.

الـIPA الناتج غير موقّع عمدًا. يجب توقيعه بشهادة وملف provisioning صالحين قبل التثبيت أو النشر في App Store.

## بوابة الإصدار

قبل اعتماد أي إصدار نهائي:

1. نجاح اختبارات Node وبناء Next.js.
2. نجاح بناء Swift Debug وRelease ورفع IPA.
3. نجاح بناء Cloudflare Workers ونشره، وخلو سجلات الـWorker من أخطاء 5xx، واجتياز فحص Supabase Security Advisor.
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


## تحديث الواجهة وبناء iOS 12

- نظام ألوان جرافيت، صفحة منشورات متصلة، وتنقل بخمسة تبويبات على الويب وiOS.
- انتقالات قصيرة تحترم «تقليل الحركة»، مع الحفاظ على موضع قراءة المنشورات عند العودة إلى التبويب.
- البحث الأصلي يتجاهل نتائج الطلبات القديمة؛ تحميل صفحات المنشورات يتوقف عند الخطأ حتى إعادة المحاولة.
- ملف `Openly-native-unsigned.ipa` هو تطبيق SwiftUI أصلي غير موقّع. حجم التنزيل والحجم بعد فك الضغط وحجم الملف التنفيذي تسجل في `Openly-IPA-audit.json`؛ لا تُضاف ملفات لزيادة الحجم.
- تتحقق أداة `ios/ci/verify_ipa.py` من الأرشيف النهائي وملف Mach-O ومعمارية arm64 ومنصة iPhoneOS والأيقونات وشاشة الإقلاع والترجمتين. اختبارات Swift تشمل اختبارات النماذج واختبار فتح شاشة الدخول بالعربية/الفاتح والإنجليزية/الداكن. تُرفق لقطات الشاشة بنتيجة XCTest.
- بناء الأرشيف وتشغيل المحاكي لا يثبتان عمل Apple/Google Sign-In على جهاز حقيقي. يتطلب الإصدار القابل للتثبيت شهادة Apple وملف provisioning يغطي التطبيق والخدمات والجهاز أو طريقة التوزيع، ثم اختبار الدخول والنشر والموسيقى والرسائل بحساب اختبار.

### إيقاف النشر القديم على Netlify

الاستضافة المقصودة هي Cloudflare Workers. حُذفت متغيرات روابط Netlify الاحتياطية من حساب روابط التطبيق. `netlify.toml` يوقف البناء الذي ينطلق من Git عند قراءة هذا الإصدار. هذا الإعداد لا يحذف الموقع المنشور، ولا يفصل GitHub App، ولا يمنع build hooks.

الربط القديم الظاهر في Netlify: `openly-ink`، المعرّف `8cfa765b-3844-4d3b-bf4c-4ae9bf2f1a06`. لإكمال الفصل في حساب Netlify: Project configuration → Build & deploy → Continuous deployment → Repository → Manage repository → Unlink repository. ثم يمكن حذف المشروع القديم من إعداداته بعد مراجعة هدف الحذف. الأوامر المتاحة للاتصال الحالي لا توفر الفصل أو حذف المشروع، لذلك لم يُنفَّذا تلقائيًا.

مرجع بصري تمت مراجعته: [Socially، نموذج واجهات مخصص لـFigma](https://figmaelements.com/social-media-app-ui-kit-figma/). التنفيذ هنا مستقل، ولا يستورد أصول ذلك النموذج. صورة الشعار المطلوبة لم تصل مع الرسالة؛ الأيقونة السابقة باقية حتى توفيرها.
