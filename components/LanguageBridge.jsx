'use client'

import { Languages } from 'lucide-react'
import { useEffect, useState } from 'react'

export const LANGUAGE_STORAGE_KEY = 'openly.language'

const EN = {
  'الرئيسية': 'Home',
  'بحث': 'Search',
  'اكتب': 'Write',
  'موسيقى': 'Music',
  'حسابي': 'Account',
  'الإشعارات': 'Notifications',
  'تسجيل الدخول': 'Sign in',
  'تسجيل الخروج': 'Sign out',
  'كلمات عامة، بلا خوارزمية.': 'Public words, no ranking algorithm.',
  'المساحة العامة': 'Public space',
  'الأحدث أولًا. بلا خوارزمية ترتيب.': 'Newest first. No ranking algorithm.',
  'الإعدادات': 'Settings',
  'المظهر': 'Appearance',
  'كيف يظهر التطبيق على هذا الجهاز.': 'How the app looks on this device.',
  'حسب الجهاز': 'System',
  'فاتح': 'Light',
  'داكن': 'Dark',
  'لون التمييز': 'Accent color',
  'مرحبًا بعودتك': 'Welcome back',
  'أنشئ هويتك': 'Create your identity',
  'ادخل إلى هويتك وكلماتك.': 'Return to your identity and words.',
  'سنمنحك كودًا ولونًا ثابتين؛ لا اسم عرض ولا صورة شخصية.': 'You get a fixed code and color — no display name or profile photo.',
  'البريد الإلكتروني': 'Email',
  'كلمة المرور': 'Password',
  'إنشاء الحساب': 'Create account',
  'نسيت كلمة المرور؟': 'Forgot password?',
  'ليس لديك حساب؟': 'No account yet?',
  'لديك حساب؟': 'Already have an account?',
  'تحقق من بريدك': 'Check your email',
  'كود التحقق': 'Verification code',
  'تأكيد': 'Confirm',
  'أُرسل كود جديد إلى بريدك.': 'A new code was sent to your email.',
  'لم يصلك الكود؟ إعادة الإرسال': 'Didn’t get the code? Resend',
  'العودة لتسجيل الدخول': 'Back to sign in',
  'جارِ التنفيذ…': 'Working…',
  'جارِ التحقق…': 'Verifying…',
  'جارِ الإرسال…': 'Sending…',
  'جارِ التحميل…': 'Loading…',
  'عرض المزيد': 'Show more',
  'المحاولة مجددًا': 'Try again',
  'تعليق': 'Comment',
  'إعجاب': 'Like',
  'حفظ': 'Save',
  'محفوظ': 'Saved',
  'تعديل': 'Edit',
  'حذف': 'Delete',
  'إلغاء': 'Cancel',
  'إبلاغ': 'Report',
  'عريض': 'Bold',
  'مائل': 'Italic',
  'قائمة نقطية': 'Bulleted list',
  'تنسيق النص': 'Text formatting',
  'تعديل المنشور': 'Edit post',
  'فتح المنشور والتعليقات': 'Open post and comments',
  'أضف أغنية': 'Add a song',
  'ابحث باسم الأغنية أو الفنان': 'Search by song or artist',
  'البحث في كتالوج الأغاني': 'Search the song catalog',
  'إزالة الأغنية المرفقة': 'Remove the attached song',
  'جارِ البحث في كتالوج الموسيقى…': 'Searching the music catalog…',
  'اكتب اسم أغنية أو فنان، ثم اختر نتيجة واحدة.': 'Type a song or artist, then pick one result.',
  'لا توجد نتائج مطابقة.': 'No matching results.',
  'جارِ الإرفاق…': 'Attaching…',
  'اختيار': 'Choose',
  'تعذر إرفاق الأغنية': 'The song could not be attached',
  'تعذر البحث عن الأغاني': 'The song search failed',
  'تشغيل معاينة الأغنية': 'Play song preview',
  'إيقاف معاينة الأغنية': 'Pause song preview',
  'البريد أو كلمة المرور غير صحيحة. إن نسيت كلمة المرور فأعد تعيينها، وإن لم يكن لديك حساب فأنشئ هويتك.':
    'Wrong email or password. Reset your password if you forgot it, or create an identity if you don’t have an account.',
  'أكد بريدك الإلكتروني أولًا. ابحث عن رسالة التحقق أو اطلب كودًا جديدًا.':
    'Confirm your email first. Look for the verification message, or request a new code.',
  'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.': 'Too many attempts. Wait a moment and try again.',
  'هذا الحساب موقوف. تواصل معنا إن كنت تظن أن هذا خطأ.':
    'This account is suspended. Contact us if you believe that is a mistake.',
  'تعذر إرسال الكود الآن. حاول بعد قليل أو تواصل معنا.':
    'The code could not be sent right now. Try again shortly, or contact us.',
  'تعذر إرسال كود التحقق الآن. المشكلة عندنا — حاول بعد قليل.':
    'The verification code could not be sent right now. That is on us — try again shortly.',
  'اكتشاف بالموسيقى': 'Music discovery',
  'التوافق الموسيقي': 'Music compatibility',
  'اختيار متبادل وهادئ: اهتمامك يبقى سريًا، ولا يظهر التطابق إلا إذا اختارك الطرف الآخر أيضًا.': 'A quiet mutual choice: your interest stays private, and a connection appears only if the other person chooses you too.',
  'سجّل الدخول لرؤية من يشاركك ذوقك.': 'Sign in to find people who share your taste.',
  'اقتراحات': 'Suggestions',
  'التوافقات': 'Connections',
  'نوع قائمة المطابقة': 'Compatibility list type',
  'التصنيف': 'Genre',
  'كل التصنيفات': 'All genres',
  'الفنان': 'Artist',
  'اكتب اسم فنان': 'Type an artist name',
  'تصفية حسب فنان': 'Filter by artist',
  'اختر اسمًا من القائمة لتفعيل التصفية.': 'Choose a name from the list to apply the filter.',
  'إزالة التصفية': 'Clear filters',
  'لا توجد نتائج مطابقة بعد.': 'No compatible results yet.',
  'أضف فنانين وتصنيفات وفعّل الظهور في الاكتشاف.': 'Add artists and genres, then enable discovery visibility.',
  'عدّل ذوقك الموسيقي': 'Edit your music taste',
  'توافق متبادل': 'Mutual connection',
  'إلغاء التوافق': 'Remove connection',
  'إلغاء الاهتمام': 'Remove interest',
  'مهتم بهذا التوافق': 'Interested in this connection',
  'عرض الكتابات': 'View posts',
  'فتح الملف': 'Open profile',
  'اختيارك سري. لن يعرف الطرف الآخر إلا إذا اختارك أيضًا.': 'Your choice is private. The other person will only know if they choose you too.',
  'هذه كل الاقتراحات المتاحة.': 'That’s every available suggestion.',
  'لا توجد توافقات متبادلة بعد.': 'No mutual connections yet.',
  'اختر من الاقتراحات. إذا اختارك الطرف الآخر أيضًا سيظهر هنا فقط.': 'Choose from the suggestions. If they choose you too, the connection will appear here.',
  'عرض الاقتراحات': 'View suggestions',
  'فنانون مشتركون:': 'Shared artists:',
  'تصنيفات مشتركة:': 'Shared genres:',
  'ذوقي الموسيقي': 'My music taste',
  'ما يظهر في ملفي': 'Profile visibility',
  'تعديل ذوقي': 'Edit my taste',
  'الخصوصية': 'Privacy',
  'كتاباتي': 'My posts',
  'المحفوظات': 'Bookmarks',
  'الأكواد التي أتابعها': 'Codes I follow',
  'لا توجد إشعارات': 'No notifications',
  'لا توجد منشورات': 'No posts',
  'لا توجد محفوظات': 'No bookmarks',
  'متابعة': 'Follow',
  'إلغاء المتابعة': 'Unfollow',
  'كتم': 'Mute',
  'إلغاء الكتم': 'Unmute',
  'حظر': 'Block',
  'إلغاء الحظر': 'Unblock'
}

function normalizeTerminology(value) {
  return value
    .replaceAll('الماتشات', 'التوافقات')
    .replaceAll('ماتشات', 'توافقات')
    .replace(/(\d+)\s+ماتش\b/g, '$1 توافق')
    .replaceAll('تعذر تحميل الماتشات', 'تعذر تحميل التوافقات')
    .replaceAll('تطابق متبادل', 'توافق متبادل')
    .replaceAll('إلغاء التطابق', 'إلغاء التوافق')
}

function englishDynamic(value) {
  let match = value.match(/^(\d+) اقتراح$/)
  if (match) return `${match[1]} suggestion${match[1] === '1' ? '' : 's'}`
  match = value.match(/^(\d+) توافق$/)
  if (match) return `${match[1]} connection${match[1] === '1' ? '' : 's'}`
  match = value.match(/^انضم في (.+)$/)
  if (match) return `Joined ${match[1]}`
  match = value.match(/^(\d+) متابع$/)
  if (match) return `${match[1]} follower${match[1] === '1' ? '' : 's'}`
  match = value.match(/^تطابق (.+)$/)
  if (match) return `Connected ${match[1]}`
  match = value.match(/^حدث تطابق بينك وبين (.+)\. الاختيار كان متبادلًا\.$/)
  if (match) return `You and ${match[1]} chose each other.`
  return null
}

function translateValue(raw, language) {
  if (typeof raw !== 'string' || !raw.trim()) return raw
  const leading = raw.match(/^\s*/)?.[0] || ''
  const trailing = raw.match(/\s*$/)?.[0] || ''
  const core = normalizeTerminology(raw.trim())
  if (language === 'ar') return `${leading}${core}${trailing}`
  const dynamic = englishDynamic(core)
  const translated = dynamic || EN[core] || core
  return `${leading}${translated}${trailing}`
}

function shouldSkip(node) {
  const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
  return !!element?.closest('script, style, code, pre, .post-body, .comment-body, [data-user-content]')
}

function translateElement(element, language) {
  if (!(element instanceof Element) || shouldSkip(element)) return
  for (const attribute of ['aria-label', 'title', 'placeholder']) {
    if (element.hasAttribute(attribute)) {
      const current = element.getAttribute(attribute)
      const next = translateValue(current, language)
      if (next !== current) element.setAttribute(attribute, next)
    }
  }
}

function translateSubtree(root, language) {
  if (!root || shouldSkip(root)) return
  if (root.nodeType === Node.TEXT_NODE) {
    const current = root.nodeValue
    const next = translateValue(current, language)
    if (next !== current) root.nodeValue = next
    return
  }
  if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) return
  if (root.nodeType === Node.ELEMENT_NODE) translateElement(root, language)

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
  let node = walker.nextNode()
  while (node) {
    if (!shouldSkip(node)) {
      if (node.nodeType === Node.TEXT_NODE) {
        const current = node.nodeValue
        const next = translateValue(current, language)
        if (next !== current) node.nodeValue = next
      } else {
        translateElement(node, language)
      }
    }
    node = walker.nextNode()
  }
}

export function LanguageBridge() {
  useEffect(() => {
    let language = 'ar'
    try {
      language = localStorage.getItem(LANGUAGE_STORAGE_KEY) === 'en' ? 'en' : 'ar'
    } catch {}

    document.documentElement.lang = language
    document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr'
    document.documentElement.dataset.language = language
    translateSubtree(document.body, language)

    const observer = new MutationObserver(records => {
      for (const record of records) {
        if (record.type === 'characterData') translateSubtree(record.target, language)
        for (const node of record.addedNodes || []) translateSubtree(node, language)
      }
    })
    observer.observe(document.body, { subtree: true, childList: true, characterData: true })
    return () => observer.disconnect()
  }, [])

  return null
}

export function LanguageControl() {
  const [language, setLanguage] = useState('ar')

  useEffect(() => {
    try { setLanguage(localStorage.getItem(LANGUAGE_STORAGE_KEY) === 'en' ? 'en' : 'ar') } catch {}
  }, [])

  function choose(next) {
    if (next === language) return
    try { localStorage.setItem(LANGUAGE_STORAGE_KEY, next) } catch {}
    setLanguage(next)
    window.location.reload()
  }

  return <section aria-labelledby="language-heading" style={{ marginBottom: 28 }}>
    <div className="page-title-row">
      <Languages size={18} aria-hidden="true" />
      <h2 className="page-title" id="language-heading" style={{ fontSize: 16 }}>اللغة / Language</h2>
    </div>
    <p className="small muted mt8">اختر لغة واجهة Openly. / Choose the Openly interface language.</p>
    <div className="row wrap mt16" role="radiogroup" aria-label="لغة الواجهة / Interface language" style={{ gap: 8 }}>
      <button type="button" role="radio" aria-checked={language === 'ar'} onClick={() => choose('ar')} className={language === 'ar' ? 'primary-button' : 'secondary-button'}>العربية</button>
      <button type="button" role="radio" aria-checked={language === 'en'} onClick={() => choose('en')} className={language === 'en' ? 'primary-button' : 'secondary-button'}>English</button>
    </div>
  </section>
}
