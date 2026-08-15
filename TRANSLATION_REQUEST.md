# TRANSLATION REQUEST — Kurdish Sorani (ckb) and Badini (kmr)

**For a native speaker. Nothing in this file is machine-translated, and
nothing in the codebase was guessed.**

Generated 2026-08-15 by measuring the committed tree, not by estimating.

## Why these are empty rather than wrong

This project's standing decision (recorded in `app_translations.dart` and in
`TERMINOLOGY.md`, issue **#21431**) is that **invented Kurdish is worse than a
visible English fallback**. Both Kurdish locales are written in ARABIC SCRIPT,
so "it looks Arabic" is not evidence a string is correct — that mistake was
made on this project once and had to be reverted.

Every key below currently renders its **English** string to a Kurdish user.
That is deliberate and safe. It is not a crash, and it is not Arabic text.

## Count: 111 keys need Kurdish

| Client | Sorani (ckb) | Badini (kmr) | Distinct keys |
|---|---|---|---|
| Flutter app | 87 | 91 | 91 |
| Admin dashboard | 20 | 20 | 20 |
| **Total** | | | **111** |

Each row below gives the English and the Arabic. Supply **ckb** and **kmr**.
Where a row is marked `REMOVED (was Arabic)`, a value existed but was
untranslated Arabic pasted into the Kurdish map; it was deleted so the key
falls back to English instead of showing the wrong language.

---

# Part 1 — Flutter app

Source map: `humanitarian/lib/localization/app_translations.dart`.
Add entries to `_sorani` and `_badini`. **Grep BOTH `'key':` and `"key":`
before adding — `_badini` mixes quote styles and a duplicate is a silent bug.**

## auth  (9 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Continue with phone` | Continue with phone | المتابعة برقم الهاتف | ckb + kmr |
| `Could not load your display-name choice.` | Could not load your display-name choice. | تعذّر تحميل اختيارك لاسم العرض. | ckb + kmr |
| `Could not load your privacy settings.` | Could not load your privacy settings. | تعذّر تحميل إعدادات الخصوصية. | ckb + kmr |
| `Could not load your tasks.` | Could not load your tasks. | تعذّر تحميل مهامك. | ckb + kmr |
| `Could not load your wallet and payment methods.` | Could not load your wallet and payment methods. | تعذّر تحميل محفظتك وطرق الدفع. | ckb + kmr |
| `Could not refresh the list of fields you can hide.` | Could not refresh the list of fields you can hide. | تعذّر تحديث قائمة الحقول التي يمكنك إخفاؤها. | ckb + kmr |
| `Registration` | Registration | التسجيل | ckb + kmr |
| `Sign in or create an account with your phone number.` | Sign in or create an account with your phone number. | سجّل الدخول أو أنشئ حساباً برقم هاتفك. | ckb + kmr |
| `Your registration was saved, but your documents did not upload. You can add them from your profile.` | Your registration was saved, but your documents did not upload. You can add them from your profile. | تم حفظ تسجيلك، لكن لم يتم رفع مستنداتك. يمكنك إضافتها من ملفك الشخصي. | ckb + kmr |

## bot, localization, notifications, proposal, widgets  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `news` | News | أخبار | ckb + kmr |

## chat  (3 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Ask me anything — I\'ll guide you through the app` | Ask me anything — I\'ll guide you through the app | اسألني عن أي شيء — سأرشدك خلال التطبيق | kmr |
| `Could not decline this chat request.` | Could not decline this chat request. | تعذّر رفض طلب المحادثة. | ckb + kmr |
| `Could not load your case chats.` | Could not load your case chats. | تعذّر تحميل محادثات حالتك. | ckb + kmr |

## chat, marriage  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Could not load this conversation.` | Could not load this conversation. | تعذّر تحميل هذه المحادثة. | ckb + kmr |

## community  (4 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `No places in this sector` | No places in this sector | لا توجد أماكن في هذا القطاع | ckb + kmr |
| `No places on the map yet` | No places on the map yet | لا توجد أماكن على الخريطة بعد | ckb + kmr |
| `Show all places` | Show all places | عرض كل الأماكن | ckb + kmr |
| `These places have no map location yet.\nBrowse them in the row below.` | These places have no map location yet.\nBrowse them in the row below. | هذه الأماكن ليس لها موقع على الخريطة بعد.\nتصفّحها في الصف أدناه. | ckb + kmr |

## core  (4 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Dark` | Dark | داكن | ckb + kmr |
| `Light` | Light | فاتح | ckb + kmr |
| `error_title` | Something went wrong | حدث خطأ ما | ckb + kmr |
| `retry` | Try again | إعادة المحاولة | ckb + kmr |

## dashboard  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Could not load your dashboard.` | Could not load your dashboard. | تعذّر تحميل لوحتك. | ckb + kmr |

## donations  (2 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Beneficiary community` | Eligible community | مجتمع المستحق | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `We couldn't load the latest payment options, so these are the default ones.` | We couldn't load the latest payment options, so these are the default ones. | تعذّر تحميل أحدث خيارات الدفع، لذا هذه هي الخيارات الافتراضية. | ckb + kmr |

## donations, marketplace  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Balance unavailable right now` | Balance unavailable right now | الرصيد غير متاح حالياً | ckb + kmr |

## history  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Beneficiary history` | Eligible history | سجل المستحق | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |

## localization  (4 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `article` | Article | مقال | ckb + kmr |
| `event` | Event | فعالية | ckb + kmr |
| `food_pantry` | Food pantry | المواد الغذائية | ckb + kmr |
| `home_textiles` | Home textiles | مفروشات منزلية | ckb + kmr |

## localization, marketplace  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `beauty_care` | Beauty care | العناية بالجمال | ckb + kmr |

## localization, notifications  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `activity` | Activity | نشاط | ckb + kmr |

## marriage  (6 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Could not load subscription packages.` | Could not load subscription packages. | تعذّر تحميل باقات الاشتراك. | ckb + kmr |
| `Create my profile` | Create my profile | إنشاء ملفي | ckb + kmr |
| `Need to change something?` | Need to change something? | هل تحتاج إلى تعديل شيء؟ | ckb + kmr |
| `Submit a new profile` | Submit a new profile | إرسال ملف جديد | ckb + kmr |
| `View your profile and its status, or create one` | View your profile and its status, or create one | اطّلع على ملفك وحالته، أو أنشئ ملفاً | ckb + kmr |
| `Your balance could not be refreshed. Retry the load before subscribing.` | Your balance could not be refreshed. Retry the load before subscribing. | تعذّر تحديث رصيدك. أعد المحاولة قبل الاشتراك. | ckb + kmr |

## notifications  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `We could not check for new notifications.` | We could not check for new notifications. | تعذّر التحقق من وجود إشعارات جديدة. | ckb + kmr |

## proposal  (12 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `All partners` | All partners | كل الشركاء | ckb + kmr |
| `Beneficiary case saved for review.` | Eligible case saved for review. | تم حفظ حالة المستحق للمراجعة. | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Community and support` | Community and support | المجتمع والدعم | ckb + kmr |
| `Could not load the comments.` | Could not load the comments. | تعذّر تحميل التعليقات. | ckb + kmr |
| `Could not load this partner's joint activities.` | Could not load this partner's joint activities. | تعذّر تحميل الأنشطة المشتركة لهذا الشريك. | ckb + kmr |
| `Could not load your saved items.` | Could not load your saved items. | تعذّر تحميل العناصر المحفوظة. | ckb + kmr |
| `Could not play this video.` | Could not play this video. | تعذّر تشغيل هذا الفيديو. | ckb + kmr |
| `Giving tools` | Giving tools | أدوات العطاء | ckb + kmr |
| `Submitted beneficiary cases will appear here.` | Submitted eligible cases will appear here. | ستظهر حالات المستحق المرسلة هنا. | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Unable to load beneficiary cases from the server.` | Unable to load eligible cases from the server. | تعذر تحميل حالات المستحقين من الخادم. | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Unable to load your beneficiary cases.` | Unable to load your eligible cases. | تعذر تحميل حالات المستحق الخاصة بك. | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Volunteer tools` | Volunteer tools | أدوات التطوع | ckb + kmr |

## proposal, sponsorship  (3 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Beneficiary cases` | Eligible cases | حالات المستحقين | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `My beneficiary cases` | My eligible cases | حالات المستحق الخاصة بي | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Submit beneficiary case` | Submit eligible case | إرسال حالة مستحق | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |

## receipts  (1 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `receipts_load_failed` | Could not load your receipts. | تعذّر تحميل إيصالاتك. | ckb + kmr |

## sponsorship  (12 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `All requests` | All requests | كل الطلبات | ckb + kmr |
| `Beneficiary or community name` | Eligible or community name | اسم المستحق أو المجتمع | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Could not load your sponsorship schedule.` | Could not load your sponsorship schedule. | تعذّر تحميل جدول الكفالة. | ckb + kmr |
| `Enter beneficiary or community` | Enter eligible or community | أدخل المستحق أو المجتمع | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Example: “Clean water for Al-Mafraq village” — state the goal, who benefits, and the total budget you need.` | Example: “Clean water for Al-Mafraq village” — state the goal, who benefits, and the total budget you need. | مثال: "مياه نظيفة لقرية المفرق" — اذكر الهدف ومن يستفيد والميزانية الإجمالية المطلوبة. | kmr *REMOVED (was Arabic)* |
| `No approved requests` | No approved requests | لا توجد طلبات موافق عليها | ckb + kmr |
| `No pending requests` | No pending requests | لا توجد طلبات قيد الانتظار | ckb + kmr |
| `No rejected requests` | No rejected requests | لا توجد طلبات مرفوضة | ckb + kmr |
| `Requests the admins approve will appear here.` | Requests the admins approve will appear here. | ستظهر هنا الطلبات التي يوافق عليها المشرفون. | ckb + kmr |
| `Requests the admins turn down will appear here.` | Requests the admins turn down will appear here. | ستظهر هنا الطلبات التي يرفضها المشرفون. | ckb + kmr |
| `Requests waiting for review, changes, or sponsor matching will appear here.` | Requests waiting for review, changes, or sponsor matching will appear here. | ستظهر هنا الطلبات التي تنتظر المراجعة أو التعديل أو مطابقة الكفيل. | ckb + kmr |
| `Your beneficiary workspace` | Your eligible workspace | مساحة المستحق الخاصة بك | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |

## support  (3 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Could not load volunteer missions.` | Could not load volunteer missions. | تعذّر تحميل المهام التطوعية. | ckb + kmr |
| `Could not load your support requests.` | Could not load your support requests. | تعذّر تحميل طلبات الدعم الخاصة بك. | ckb + kmr |
| `status_open` | Open | مفتوح | ckb + kmr |

## widgets  (4 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Balance unavailable — tap to retry` | Balance unavailable — tap to retry | الرصيد غير متاح — اضغط لإعادة المحاولة | ckb + kmr |
| `Could not save that preference. Please try again.` | Could not save that preference. Please try again. | تعذّر حفظ هذا الإعداد. يرجى المحاولة مرة أخرى. | ckb + kmr |
| `No beneficiary cases yet.` | No eligible cases yet. | لا توجد حالات مستحق بعد. | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Your contributions will appear here once you give.` | Your contributions will appear here once you give. | ستظهر مساهماتك هنا بعد أول تبرع. | ckb + kmr |

## (shared / not directly referenced)  (16 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Approved places in the city guide will appear here. You can suggest one with Add an Activity.` | Approved places in the city guide will appear here. You can suggest one with Add an Activity. | ستظهر هنا الأماكن المعتمدة في دليل المدينة. يمكنك اقتراح مكان عبر «إضافة نشاط». | ckb + kmr |
| `Ask the staff team to update an existing profile, or submit a new one for review.` | Ask the staff team to update an existing profile, or submit a new one for review. | اطلب من فريق العمل تحديث ملف قائم، أو أرسل ملفاً جديداً للمراجعة. | ckb + kmr |
| `Beneficiary or community name (Arabic)` | Eligible or community name (Arabic) | اسم المستحق أو المجتمع (بالعربية) | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Beneficiary pending projects` | Eligible pending projects | مشاريع المستحقين المعلقة | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Don\'t have an account?` | Don\'t have an account? | ليس لديك حساب؟ | kmr |
| `Eligibles` | Eligibles | المستحقون | ckb *REMOVED (was Arabic)* + kmr *REMOVED (was Arabic)* |
| `Name and phone come from your verified account. Change them in Profile > Edit profile.` | Name and phone come from your verified account. Change them in Profile > Edit profile. | الاسم ورقم الهاتف يأتيان من حسابك المُوثّق. يمكنك تغييرهما من «الملف الشخصي > تعديل الملف». | ckb + kmr |
| `Nothing in the guide matches this sector yet. Clear the filter to see every place.` | Nothing in the guide matches this sector yet. Clear the filter to see every place. | لا يوجد في الدليل ما يطابق هذا القطاع بعد. امسح المرشّح لعرض كل الأماكن. | ckb + kmr |
| `Projects are funded in Iraqi dinar (IQD), so the currency is fixed.` | Projects are funded in Iraqi dinar (IQD), so the currency is fixed. | تموّل المشاريع بالدينار العراقي (IQD)، لذا فإن العملة ثابتة. | ckb + kmr |
| `This is the verified number you sign in with, so it cannot be edited here.` | This is the verified number you sign in with, so it cannot be edited here. | هذا هو الرقم المُوثّق الذي تسجّل الدخول به، لذا لا يمكن تعديله هنا. | ckb + kmr |
| `You are getting close to this month\'s impact milestone with a strong donor retention trend.` | You are getting close to this month\'s impact milestone with a strong grantor retention trend. | أنت تقترب من إنجاز أثر هذا الشهر مع اتجاه قوي للحفاظ على المانحين. | kmr |
| `status_closed` | Closed | مغلق | ckb + kmr |
| `status_done` | Done | منجز | ckb + kmr |
| `status_in_progress` | In progress | قيد المعالجة | ckb + kmr |
| `status_pending` | Pending | قيد الانتظار | ckb + kmr |
| `status_resolved` | Resolved | تم الحل | ckb + kmr |

---

# Part 2 — Admin dashboard

Source: `admin-web/src/lib/locales/`. Add the same nested key path to
`ckb.ts` and `kmr.ts`. Key names are **identical across all four files** —
there are no `_ckb`/`_kmr` suffixes on locale keys (those exist only on
database columns). Missing keys are type-legal and fall back to English.

## `status.*`  (20 keys)

| Key | English | Arabic | Needs |
|---|---|---|---|
| `status.bank` | Bank | بنك | ckb + kmr |
| `status.cash` | Cash | نقد | ckb + kmr |
| `status.divorced` | Divorced | مطلّق | ckb + kmr |
| `status.employed` | Employed | موظف | ckb + kmr |
| `status.female` | Female | أنثى | ckb + kmr |
| `status.incomplete` | Incomplete | غير مكتمل | ckb + kmr |
| `status.male` | Male | ذكر | ckb + kmr |
| `status.married` | Married | متزوج | ckb + kmr |
| `status.optional` | Optional | اختياري | ckb + kmr |
| `status.other` | Other | أخرى | ckb + kmr |
| `status.owner` | Owner | المالك | ckb + kmr |
| `status.requester` | Requester | مقدّم الطلب | ckb + kmr |
| `status.required` | Required | مطلوب | ckb + kmr |
| `status.self_employed` | Self-employed | يعمل لحسابه الخاص | ckb + kmr |
| `status.single` | Single | أعزب | ckb + kmr |
| `status.staff` | Staff | موظف | ckb + kmr |
| `status.student` | Student | طالب | ckb + kmr |
| `status.unemployed` | Unemployed | عاطل عن العمل | ckb + kmr |
| `status.wallet` | Wallet | محفظة | ckb + kmr |
| `status.widowed` | Widowed | أرمل | ckb + kmr |

---

# Part 3 — Housekeeping for whoever applies the translations

**Stale Kurdish keys that no longer exist in English.** They are dead
weight and can be deleted; they are listed so the finding is not lost.

| Map | Key |
|---|---|
| `_badini` | `Ask me anything — I'll guide you through the app` |
| `_badini` | `Don't have an account?` |
| `_badini` | `You are getting close to this month's impact milestone with a strong donor retention trend.` |

**Do not translate these** — they are protected vocabulary (`TERMINOLOGY.md` T18):

| Word | Language | Actually means |
|---|---|---|
| `سوودمەند` | Kurdish | **useful** — NOT "beneficiary". A previous pass nearly renamed it. |
| `وەرگرتن` | Kurdish | to receive (the ordinary verb) |
| `مستلمة` | Arabic | received (a delivered item) |

