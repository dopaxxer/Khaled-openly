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
  'ماذا تريد أن تقول؟': 'What do you want to say?',
  '+ موسيقى': '+ music',
  'منشورك الأول': 'Your first post',
  'منشور جديد': 'New post',
  'سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.':
    'Your words appear to everyone under your colored identity. There are no private drafts here.',
  'التخطي الآن': 'Skip for now',
  'نشر': 'Publish',
  'جارِ النشر…': 'Publishing…',
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
  'إرفاق أغنية': 'Attach a song',
  'ابحث في كتالوج Apple Music واختر نتيجة واحدة.': 'Search Apple Music and choose one result.',
  'إغلاق البحث عن الأغاني': 'Close song search',
  'سجّل الدخول لإرفاق أغنية': 'Sign in to attach a song',
  'يلزم حساب Openly لحفظ الأغنية ونشرها مع كلماتك.': 'You need an Openly account to save the song and publish it with your words.',
  'سجّل الدخول للمشاركة': 'Sign in to join in',
  'اكتب منشورًا وأرفق أغنية تحبها.': 'Write a post and attach a song you love.',
  'دخول': 'Sign in',
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
  'مرحبًا بك في Openly': 'Welcome to Openly',
  'مساحة عامة للأفكار والذوق والمحادثة.': 'A public space for thoughts, taste and conversation.',
  'المتابعة عبر Apple': 'Continue with Apple',
  'المتابعة عبر Google': 'Continue with Google',
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
  'ما يحتاج إلى انتباهك فقط.': 'Only things that need your attention.',
  'أشار إليك': 'mentioned you',
  'لا شارات للضوضاء؛ يظهر هنا النشاط المهم فقط.': 'No badges for noise. Only meaningful activity appears here.',
  'لا توجد منشورات': 'No posts',
  'لا توجد محفوظات': 'No bookmarks',
  'خاصة بك؛ أنت وحدك ترى ما تحفظه.': 'Private. Only you can see what you save.',
  'متابعة': 'Follow',
  'إلغاء المتابعة': 'Unfollow',
  'كتم': 'Mute',
  'إلغاء الكتم': 'Unmute',
  'حظر': 'Block',
  'إلغاء الحظر': 'Unblock',

  // Interests: the books, films and conversation topics screens, plus the
  // people-discovery surface built on them.
  'مواضيع الحديث': 'Conversation topics',
  'مواضيع': 'Topics',
  'موضوع': 'Topic',
  'الكتب': 'Books',
  'كتب': 'Books',
  'الأفلام': 'Films',
  'أفلام': 'Films',
  'اهتمامات': 'Interests',
  'اهتماماتي': 'My interests',
  'نوع الاهتمام': 'Interest type',
  'الكل': 'All',
  'إزالة': 'Remove',
  'ما الذي يهمك؟': 'What matters to you?',
  'اختر أشياء تحبها فعلًا. سنستخدمها لإيجاد أشخاص ومواضيع بينكم أرضية مشتركة.':
    'Pick things you genuinely love. We use them to find people and topics you share common ground with.',
  'الكتب والأفلام ومواضيع الحديث تكمل ذوقك الموسيقي وتكوّن صورة أصدق عن اهتماماتك.':
    'Books, films and conversation topics round out your music taste into a truer picture of what you care about.',
  'ابحث أو أضف': 'Search or add',
  'ابحث في الكتالوج': 'Search the catalog',
  'مثال: The Stranger': 'Example: The Stranger',
  'مثال: Interstellar': 'Example: Interstellar',
  'مثال: علم النفس': 'Example: psychology',
  'من الكتالوج': 'From the catalog',
  'مضاف': 'Added',
  'إضافة': 'Add',
  'جارِ الإضافة…': 'Adding…',
  'الخصوصية والاكتشاف': 'Privacy and discovery',
  'استخدم اهتماماتي في الاكتشاف': 'Use my interests for discovery',
  'يسمح لـOpenly باقتراح أشخاص بينكم اهتمامات مشتركة.':
    'Lets Openly suggest people who share your interests.',
  'اعرض اهتماماتي في ملفي': 'Show my interests on my profile',
  'إذا أوقفته، يمكن حساب التوافق عند تفعيل الاكتشاف لكن لا نعرض قائمة اهتماماتك.':
    'Turn this off and compatibility can still be calculated while discovery is on, but your list stays hidden.',
  'تم حفظ اهتماماتك.': 'Your interests were saved.',
  'جارِ الحفظ…': 'Saving…',
  'احفظ وتابع': 'Save and continue',
  'تخطي الآن': 'Skip for now',
  'اكتشف أشخاصًا': 'Discover people',
  'اكتشف': 'Discover',
  'أنت': 'You',
  'مساحة عامة · الأحدث أولًا': 'Public space · newest first',
  'أشخاص يشاركونك الذوق، بلا ترتيب بعدد المتابعين.':
    'People who share your taste — never ranked by follower count.',
  'ابحث عن أشخاص، موسيقى، كتب، أفلام…': 'Search people, music, books, films…',
  'أشخاص بذوق قريب': 'People with similar taste',
  'مواضيع ثقافية رائجة': 'Popular cultural threads',
  'أغانٍ تشبه شعور الرحيل': 'Songs that feel like leaving',
  'كتب قرأتها في سن مبكرة جدًا': 'Books you read too young',
  'أفلام تغيّرت بعد الانفصال': 'Films that changed after a breakup',
  'أشخاص، منشورات، وسياق ثقافي': 'People, posts and cultural context',
  'ابحث عن هوية أو منشور…': 'Search an identity or a post…',
  'جرّب البحث': 'Try searching',
  'افتح الملف': 'Open profile',
  'المنشور': 'Post',
  'أضف ردًا…': 'Add a reply…',
  'الردود': 'Replies',
  'رمز عام': 'Public code',
  'متابعون': 'followers',
  'يتابعهم': 'following',
  'الذوق': 'Taste',
  'الموسيقى والكتب والأفلام جزء من الملف، وليست شارات منفصلة.':
    'Music, books and films are part of the profile — not separate badges.',
  'العودة': 'Back',
  '‹ العودة': '‹ Back',
  'أشخاص': 'People',
  'منشورات': 'Posts',
  'تعذر تحديث المنشور. حاول مجددًا.': 'Could not refresh the post. Try again.',
  'تعذر فتح المنشور.': 'Could not open this post.',
  'تعذر فتح الملف': 'Could not open this profile',
  'اختر اهتماماتك': 'Choose your interests',
  'مشترك بينكما:': 'You both share:',
  'التوافق الموسيقي:': 'Music compatibility:',
  'قائمة الاهتمامات مخفية، لكن صاحب الحساب سمح باستخدامها في الاكتشاف.':
    'This list is hidden, but its owner allows it to be used for discovery.',
  'عرض الملف والكتابات': 'View profile and posts',
  'لا توجد أرضية مشتركة كافية بعد.': 'Not enough common ground yet.',
  'أضف بعض الكتب والأفلام ومواضيع الحديث التي تهمك.':
    'Add a few books, films and conversation topics you care about.',
  'سجّل الدخول لاختيار اهتماماتك.': 'Sign in to choose your interests.',
  'سجّل الدخول لرؤية الاقتراحات المبنية على اهتماماتك.':
    'Sign in to see suggestions based on your interests.',
  'تعذر تحميل اهتماماتك': 'Could not load your interests',
  'تعذر حفظ اهتماماتك': 'Could not save your interests',
  'تعذر حفظ العنصر': 'Could not save this item',
  'تعذر إضافة الموضوع': 'Could not add the topic',
  'تعذر تحميل الاقتراحات': 'Could not load suggestions',
  'تعذر تحميل الاقتراحات.': 'Could not load suggestions.',

  // Phone country picker.
  'ألمانيا': 'Germany',
  'السعودية': 'Saudi Arabia',
  'اليمن': 'Yemen',
  'الإمارات': 'United Arab Emirates',
  'مصر': 'Egypt',
  'العراق': 'Iraq',
  'الأردن': 'Jordan',
  'الكويت': 'Kuwait',
  'قطر': 'Qatar',
  'البحرين': 'Bahrain',
  'عُمان': 'Oman',
  'تركيا': 'Türkiye',
  'المملكة المتحدة': 'United Kingdom',
  'فرنسا': 'France',
  'إيطاليا': 'Italy',
  'إسبانيا': 'Spain',
  'هولندا': 'Netherlands',
  'السويد': 'Sweden',
  'الولايات المتحدة / كندا': 'United States / Canada',
  'أخرى — أدخل + ورمز الدولة': 'Other — enter + and the country code',

  // Sign-in, verification and password recovery.
  'استغرق الاتصال وقتًا طويلًا. تحقق من الشبكة وحاول مجددًا.':
    'That took too long. Check your connection and try again.',
  'تعذر إكمال تسجيل الدخول الخارجي. حاول مرة أخرى.':
    'Could not finish signing in with that provider. Try again.',
  'أرسلنا رابطًا جديدًا.': 'We sent a new link.',
  'أُرسل كود جديد.': 'A new code was sent.',
  'إعادة إرسال الرابط': 'Resend the link',
  'إعادة إرسال الكود': 'Resend the code',
  'أدخل رمز التحقق': 'Enter your verification code',
  'تأكيد والدخول': 'Confirm and sign in',
  'البريد': 'Email',
  'رقم الهاتف': 'Phone number',
  'دخول بسيط وآمن. لا تحتاج إلى كلمة مرور.': 'Simple, secure sign-in. No password needed.',
  '──────── أو ────────': '──────── or ────────',
  'جارِ إرسال الكود…': 'Sending the code…',
  'جارِ إرسال الرابط…': 'Sending the link…',
  'جارِ إرسال SMS…': 'Sending the SMS…',
  'إرسال رمز SMS': 'Send an SMS code',
  'استخدم رقمًا قادرًا على استقبال SMS. الصيغة النهائية E.164.':
    'Use a number that can receive SMS. The final format is E.164.',
  'تعذر إرسال الرابط': 'Could not send the link',
  'إذا كان هناك حساب بهذا البريد، أرسلنا رابطًا لاختيار كلمة مرور جديدة.':
    'If an account exists for that email, we sent a link to choose a new password.',
  'استعادة كلمة المرور': 'Reset your password',
  'أدخل البريد المرتبط بحسابك وسنرسل لك رابط الاستعادة.':
    'Enter the email on your account and we’ll send you a reset link.',
  'إرسال رابط الاستعادة': 'Send the reset link',
  'كلمتا المرور غير متطابقتين': 'The passwords do not match',
  'تعذر تحديث كلمة المرور': 'Could not update the password',
  'كلمة مرور جديدة': 'New password',
  'حفظ كلمة المرور': 'Save password',

  // Search.
  'تعذر إكمال البحث': 'Could not complete the search',
  'ابحث عن كلمات عامة أو كود هوية.': 'Search public words or an identity code.',
  'ابحث…': 'Search…',
  'الهويات': 'Identities',
  'عرض': 'View',
  'المنشورات': 'Posts',
  'لا توجد نتائج.': 'No results.',

  // Account and identity.
  'سجّل الدخول لرؤية حسابك.': 'Sign in to see your account.',
  'سجّل الدخول لتعديل هويتك.': 'Sign in to edit your identity.',
  'هويتك الخاصة وإعدادات علاقاتك العامة.': 'Your private identity and public relationship settings.',
  'الأشخاص المهتمون بما تكتب': 'People interested in what you write',
  'خاص بك فقط': 'Only visible to you',
  'لا نعرض عدد متابَعاتك للآخرين.': 'We never show your follower count to anyone else.',
  'صفحة كتاباتي': 'My posts page',
  'لم تتابع أي كود بعد.': 'You aren’t following any code yet.',
  'تعذر الحفظ': 'Could not save',
  'عدّل هويتك العامة من دون إضافة اسم حقيقي أو صورة شخصية.':
    'Edit your public identity without adding a real name or a photo.',
  'هذه هي الهوية التي يراها الآخرون.': 'This is the identity other people see.',
  'إنشاء كود عشوائي': 'Generate a random code',
  '4–8 رموز واضحة؛ لا نستخدم I أو L أو O أو 0 أو 1 لتجنب الالتباس.':
    '4–8 unambiguous characters. I, L, O, 0 and 1 are excluded to avoid confusion.',
  'لون الهوية': 'Identity color',
  'جملة قصيرة — اختياري': 'A short line — optional',
  'اكتب شيئًا مختصرًا عن هذه الهوية — اختياري': 'Say something brief about this identity — optional',
  'تم حفظ التغييرات.': 'Your changes were saved.',
  'حفظ الهوية': 'Save identity',
  'الأمان': 'Security',
  'يتطلب التغيير كلمة المرور الحالية، أو رابط استعادة موثّقًا عبر البريد.':
    'Changing it needs your current password, or a reset link verified by email.',
  'تغيير كلمة المرور': 'Change password',
  'تعذر تحديث العلاقة': 'Could not update that relationship',

  // Posts, comments and notifications.
  'الكتابات': 'Posts',
  'لا توجد منشورات.': 'No posts.',
  'تعذر إضافة التعليق': 'Could not add the comment',
  'تعذر إضافة الرد': 'Could not add the reply',
  'اكتب تعليقًا… استخدم @ للإشارة': 'Write a comment… use @ to mention',
  'اكتب ردك… استخدم @ للإشارة': 'Write your reply… use @ to mention',
  'نص التعليق': 'Comment text',
  'نص الرد': 'Reply text',
  'نص المنشور': 'Post text',
  'التعليقات': 'Comments',
  'لا توجد تعليقات بعد.': 'No comments yet.',
  'رد': 'Reply',
  'إرسال': 'Send',
  'التفاعلات والردود المرتبطة بك.': 'Reactions and replies involving you.',
  'أعجب بمنشورك': 'liked your post',
  'أشار إليك في تعليق': 'mentioned you in a comment',
  'أشار إليك في منشور': 'mentioned you in a post',
  'رد على منشورك': 'replied to your post',
  'لا توجد إشعارات.': 'No notifications.',
  'منشورات محفوظة لك فقط.': 'Posts you saved, visible only to you.',
  'لا توجد منشورات محفوظة.': 'No saved posts.',
  'تعذر حفظ التفاعل': 'Could not save that reaction',
  'تعذر التعديل': 'Could not save the edit',
  'حذف هذا المنشور؟ لا يمكن التراجع.': 'Delete this post? This cannot be undone.',
  'حذف هذا التعليق؟ لا يمكن التراجع.': 'Delete this comment? This cannot be undone.',
  'تعذر الحذف': 'Could not delete',
  'جارِ الحذف…': 'Deleting…',
  'تعذر النشر': 'Could not publish',
  'ماذا تريد أن تقول؟ اكتب @ للإشارة إلى كود': 'What do you want to say? Type @ to mention a code',
  'جارِ تحميل المنشورات': 'Loading posts',
  'تعذر تحميل المنشورات': 'Could not load posts',
  'لا توجد منشورات بعد. كن أول من يكتب.': 'No posts yet. Be the first to write.',
  'هذه كل المنشورات المتاحة.': 'That’s every available post.',

  // Privacy, reports and moderation.
  'إدارة الحسابات المكتومة والمحظورة.': 'Manage muted and blocked accounts.',
  'مكتوم': 'Muted',
  'محظور': 'Blocked',
  'لا توجد علاقات خصوصية حاليًا.': 'No privacy relationships right now.',
  'تعذر إرسال البلاغ.': 'Could not send the report.',
  'إبلاغ عن تعليق': 'Report a comment',
  'إبلاغ عن منشور': 'Report a post',
  'البلاغات خاصة ويطّلع عليها فريق الإشراف فقط.': 'Reports are private and seen only by moderators.',
  'محتوى مزعج أو مكرر': 'Spam or repetitive content',
  'مضايقة': 'Harassment',
  'خطاب كراهية': 'Hate speech',
  'تهديد': 'Threat',
  'محتوى جنسي': 'Sexual content',
  'محتوى غير قانوني': 'Illegal content',
  'سبب آخر': 'Another reason',
  'تفاصيل إضافية': 'More detail',
  'اختياري': 'Optional',
  'إرسال البلاغ': 'Send report',
  'غير مصرح لك.': 'You do not have access.',
  'تعذر تحميل البلاغات.': 'Could not load reports.',
  'البلاغات': 'Reports',
  'حذف المحتوى': 'Delete content',
  'تعليق الحساب': 'Suspend account',
  'حظر الحساب': 'Ban account',
  'حل': 'Resolve',
  'رفض البلاغ': 'Dismiss report',
  'لا توجد بلاغات.': 'No reports.',

  // Not found.
  'الصفحة غير موجودة': 'Page not found',
  'ربما تغيّر الرابط أو حُذف المحتوى.': 'The link may have changed, or the content was deleted.',
  'العودة للرئيسية': 'Back to home',

  // Music taste.
  'تعذر إكمال العملية': 'Could not complete that',
  'تعذر تحميل تفضيلاتك الموسيقية.': 'Could not load your music preferences.',
  'تم حفظ ما يظهر في ملفك.': 'Your profile visibility was saved.',
  'تم حفظ الأغاني المفضلة.': 'Your favourite songs were saved.',
  'تمت إضافة الأغنية.': 'Song added.',
  'تم حفظ قائمة الفنانين.': 'Your artist list was saved.',
  'تم حفظ التصنيفات.': 'Your genres were saved.',
  'حذف كل بيانات ذوقك الموسيقي؟ لا يمكن التراجع.':
    'Delete all of your music taste data? This cannot be undone.',
  'تم حذف كل بيانات الموسيقى.': 'All music data was deleted.',
  'سجّل الدخول لإضافة ذوقك الموسيقي.': 'Sign in to add your music taste.',
  'اختر أغاني حقيقية من الكتالوج، ثم قرر بنفسك ما الذي يظهر للآخرين في ملفك.':
    'Pick real songs from the catalog, then decide for yourself what others see on your profile.',
  'الظهور والمطابقة': 'Visibility and matching',
  'أظهرني في اقتراحات المطابقة': 'Show me in match suggestions',
  'يسمح للأشخاص المتشابهين معك بالعثور على كودك. اهتمام أي طرف يبقى سريًا حتى يحدث اختيار متبادل.':
    'Lets people with similar taste find your code. Either side’s interest stays private until the choice is mutual.',
  'اختر ما يظهر في صفحتك العامة. هذه الخيارات مستقلة عن دخولك في المطابقة.':
    'Choose what appears on your public page. These are independent of taking part in matching.',
  'إظهار الأغاني المفضلة': 'Show favourite songs',
  'يعرض اسم الأغنية والفنان والغلاف الذي اخترته.': 'Shows the song, artist and artwork you picked.',
  'إظهار الفنانين': 'Show artists',
  'يمكنك استخدامها للمطابقة حتى لو أخفيتها من ملفك.':
    'They can still be used for matching even when hidden from your profile.',
  'إظهار التصنيفات': 'Show genres',
  'مثل روك، راب أو طرب؛ إخفاؤها لا يمنع استخدامها لحساب التشابه.':
    'Like rock, rap or tarab. Hiding them does not stop them counting towards similarity.',
  'الأغاني المفضلة': 'Favourite songs',
  'ابحث باسم الأغنية أو الفنان، ثم اختر النتيجة الأصلية من الكتالوج.':
    'Search by song or artist, then pick the original result from the catalog.',
  'مثال: Fairuz Nassam Alayna El Hawa': 'Example: Fairuz Nassam Alayna El Hawa',
  'بحث عن أغنية': 'Search for a song',
  'جارِ البحث في الكتالوج…': 'Searching the catalog…',
  'نتائج الأغاني': 'Song results',
  'مضافة': 'Added',
  'أغانيك المفضلة': 'Your favourite songs',
  'لم تختر أي أغنية بعد.': 'You haven’t picked a song yet.',
  'التصنيفات': 'Genres',
  'تصنيفات الموسيقى': 'Music genres',
  'الفنانون': 'Artists',
  'الفنانون:': 'Artists:',
  'مثال: فيروز أو Radiohead': 'Example: Fairuz or Radiohead',
  'بحث عن فنان': 'Search for an artist',
  'جارِ البحث…': 'Searching…',
  'نتائج البحث': 'Search results',
  'فنانوك المفضلون': 'Your favourite artists',
  'لم تضف أي فنان بعد.': 'You haven’t added an artist yet.',
  'حذف البيانات': 'Delete data',
  'يحذف أغانيك وتصنيفاتك وفنانيك وإعدادات الاكتشاف من حسابك نهائيًا.':
    'Permanently deletes your songs, genres, artists and discovery settings from your account.',
  'حذف كل بيانات الموسيقى': 'Delete all music data',
  'اذهب إلى المطابقة بالموسيقى': 'Go to music matching',
  'الذوق الموسيقي': 'Music taste',

  // Music matching.
  'تعذر تحميل الماتشات': 'Could not load your connections',
  'تعذر حفظ اختيارك': 'Could not save your choice',
  'تعذر إلغاء التطابق': 'Could not undo that connection',
  'تطابق متبادل': 'Mutual connection',
  'لا توجد ماتشات متبادلة بعد.': 'No mutual connections yet.',

  // Private direct messages.
  'الرسائل': 'Messages',
  'الرسائل الخاصة': 'Private messages',
  'تعذر تحميل الرسائل': 'Could not load messages',
  'سجّل الدخول لرؤية رسائلك.': 'Sign in to see your messages.',
  'محادثاتك الخاصة بين هويات Openly. لا يظهر بريدك أو اسمك الحقيقي.':
    'Private conversations between Openly identities. Your email and real name stay hidden.',
  'أنت:': 'You:',
  'لا توجد رسائل في هذه المحادثة بعد.': 'There are no messages in this conversation yet.',
  'لا توجد رسائل بعد.': 'No messages yet.',
  'ابدأ من صفحة أي هوية واضغط «رسالة خاصة».':
    'Open any identity page and choose “Private message” to start.',
  'المحادثة غير متاحة': 'This conversation is unavailable',
  'تعذر إرسال الرسالة': 'Could not send the message',
  'العودة إلى الرسائل': 'Back to messages',
  'عرض رسائل أقدم': 'Show older messages',
  'لا يمكن إرسال رسائل جديدة في هذه المحادثة.':
    'New messages cannot be sent in this conversation.',
  'اكتب رسالة خاصة…': 'Write a private message…',
  'تعذر بدء المحادثة': 'Could not start the conversation',
  'جارِ فتح المحادثة…': 'Opening conversation…',
  'رسالة خاصة': 'Private message',
  'متصل الآن': 'Online now',
  'يكتب…': 'Typing…',
  'غير متصل': 'Offline',
  'تعذر تحميل الإشعارات': 'Could not load notifications',

  // Shell and small labels.
  'open — الرئيسية': 'Openly — Home',
  'التنقل الرئيسي': 'Main navigation',
  'جارِ تحميل الحساب': 'Loading account',
  'وضع الإضاءة': 'Appearance mode',
  'اقتراحات الأكواد': 'Code suggestions',
  '،': ','
}

// The bridge walks every text node of every DOM mutation, so the cheapest
// possible answer for "this string needs nothing done to it" is what keeps a
// scrolling feed off the main thread. Almost no string carries either term.
const TERMINOLOGY_PATTERN = /ماتش|تطابق/

function normalizeTerminology(value) {
  if (!TERMINOLOGY_PATTERN.test(value)) return value
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
  // A post's counters are built from a number and a word, so they can only be
  // translated here. The like button used to show the bare number and slipped
  // past this; the comment count never had an entry at all.
  match = value.match(/^(\d+) إعجاب$/)
  if (match) return `${match[1]} like${match[1] === '1' ? '' : 's'}`
  match = value.match(/^(\d+) تعليق$/)
  if (match) return `${match[1]} comment${match[1] === '1' ? '' : 's'}`
  match = value.match(/^تطابق (.+)$/)
  if (match) return `Connected ${match[1]}`
  match = value.match(/^حدث تطابق بينك وبين (.+)\. الاختيار كان متبادلًا\.$/)
  if (match) return `You and ${match[1]} chose each other.`

  // Interest and music copy that carries a count or a user-typed label.
  match = value.match(/^نسبة التوافق (\d+) بالمئة$/)
  if (match) return `${match[1]} percent compatible`
  match = value.match(/^نسبة التشابه (\d+) بالمئة$/)
  if (match) return `${match[1]} percent similar`
  match = value.match(/^(\d+) اختيار$/)
  if (match) return `Chosen by ${match[1]}`
  match = value.match(/^أضف موضوع «(.+)»$/)
  if (match) return `Add the topic “${match[1]}”`
  match = value.match(/^الحد الأقصى (\d+) اهتمامًا\.$/)
  if (match) return `At most ${match[1]} interests.`
  match = value.match(/^الحد الأقصى (\d+) من فئة (.+)\.$/)
  if (match) return `At most ${match[1]} in ${EN[match[2]] || match[2]}.`
  match = value.match(/^إلغاء التطابق مع (.+)؟$/)
  if (match) return `Disconnect from ${match[1]}?`
  return null
}

function translateValue(raw, language) {
  if (typeof raw !== 'string' || !raw.trim()) return raw
  // Arabic is the default, and Arabic copy is only rewritten when it carries
  // one of the two terms above. Answering that with a single regex test beats
  // trimming, rewriting and re-joining every label on the page.
  if (language === 'ar' && !TERMINOLOGY_PATTERN.test(raw)) return raw
  const leading = raw.match(/^\s*/)?.[0] || ''
  const trailing = raw.match(/\s*$/)?.[0] || ''
  const core = normalizeTerminology(raw.trim())
  if (language === 'ar') return `${leading}${core}${trailing}`
  const dynamic = englishDynamic(core)
  const translated = dynamic || EN[core] || core
  return `${leading}${translated}${trailing}`
}

const SKIP_SELECTOR = 'script, style, code, pre, .post-body, .comment-body, [data-user-content]'

function shouldSkip(node) {
  const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
  return !!element?.closest(SKIP_SELECTOR)
}

function translateElement(element, language) {
  if (!(element instanceof Element) || element.matches(SKIP_SELECTOR)) return
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

  // Rejecting a shielded element skips its whole subtree in one step. Asking
  // every node for its own `closest()` instead re-walked the ancestor chain
  // per node, which made the cost of a post body grow with its depth.
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.nodeType === Node.ELEMENT_NODE && node.matches(SKIP_SELECTOR)
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT
    }
  })
  let node = walker.nextNode()
  while (node) {
    if (node.nodeType === Node.TEXT_NODE) {
      const current = node.nodeValue
      const next = translateValue(current, language)
      if (next !== current) node.nodeValue = next
    } else {
      translateElement(node, language)
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
