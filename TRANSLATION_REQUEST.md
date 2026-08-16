# TRANSLATION REQUEST — Kurdish Sorani (ckb) and Badini (kmr)

**For a native speaker. Nothing in this file is machine-translated, and
nothing in the codebase was guessed.**

Generated 2026-08-15 by measuring the committed tree, not by estimating.
Updated 2026-08-15 with the 25 strings the A16 password sign-in flow added.
Updated 2026-08-15 again with the 100 keys the group-B English-leak sweep added
(81 notification types, shared by both clients, plus 19 widget literals).
Updated 2026-08-16 with the 2 keys the J1 guest sign-up name box added.
Updated 2026-08-16 again with the 8 keys the K7 alert-categories screen added.
Updated 2026-08-16 once more with the 2 keys the L19 engagement-profile field
privacy picker added.
Updated 2026-08-16 again with the 6 keys the K12 content sub-section editor
added, and the 9 keys the K13 contact-details editor added.
Updated 2026-08-16 once more with the 94 keys that gave every field-rule row on
قواعد الحقول an Arabic label (NEW FINDING 9).

## Why these are empty rather than wrong

This project's standing decision (recorded in `app_translations.dart` and in
`TERMINOLOGY.md`, issue **#21431**) is that **invented Kurdish is worse than a
visible English fallback**. Both Kurdish locales are written in ARABIC SCRIPT,
so "it looks Arabic" is not evidence a string is correct — that mistake was
made on this project once and had to be reverted.

Every key below currently renders its **English** string to a Kurdish user.
That is deliberate and safe. It is not a crash, and it is not Arabic text.

## Count: 373 keys need Kurdish

| Client | Sorani (ckb) | Badini (kmr) | Distinct keys |
|---|---|---|---|
| Flutter app | 112 | 116 | 116 |
| Flutter app — B1 notification types (new) | 81 | 81 | 81 |
| Flutter app — B21 widget literals (new) | 19 | 19 | 19 |
| Flutter app — J1 guest sign-up name (new) | 2 | 2 | 2 |
| Flutter app — K7 alert categories (new) | 8 | 8 | 8 |
| Flutter app — L19 engagement field privacy (new) | 2 | 2 | 2 |
| Flutter app — K12 content page states (new) | 1 | 1 | 1 |
| Flutter app — K13 contact details (new) | 0 | 1 | 1 |
| Flutter app — K21 identity-code lookup (new) | 5 | 5 | 5 |
| Admin dashboard — audited `status.*` | 20 | 20 | 20 |
| Admin dashboard — B1 notification types (new) | 81 | 81 | *same 81 words as above* |
| Admin dashboard — K12 content sub-sections (new) | 6 | 6 | 6 |
| Admin dashboard — K13 contact details (new) | 9 | 9 | 9 |
| Admin dashboard — Field Rules form labels (new) | 94 | 94 | 94 |
| Admin dashboard — content page save confirmation | 2 | 2 | 2 |
| Admin dashboard — delete confirmation bodies (were FALSE in Kurdish) | 5 | 5 | 5 |
| App — City Guide map chip (place count) | 2 | 2 | 2 |
| **Total distinct words to translate** | | | **373** |

> **The dashboard figure above is a floor, not a ceiling — and it is the one
> number in this file that was never fully measured.** Counting key paths in
> `en.ts` against `ckb.ts`/`kmr.ts` today gives **297** missing on each, of
> which 177 are `page.*` and 105 are `status.*`. The "20" row was an audit of
> part of `status.*`, not of the whole file. Nothing here is wrong — every one
> of those 297 falls back to English, which is the intended behaviour — but a
> translator should know the dashboard job is larger than the table suggests.
> Measuring the rest properly is outstanding work, not a defect.

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

## auth · J1 guest sign-up name  (2 keys)

Added 2026-08-16. The guest sign-up sheet now collects a name (the client's
"الاسم" box), which the backend stores on the guest's `user_profiles` row. Only
two strings are new: the field's example and its length rule. The LABEL is
`pf_full_name`, which already has Sorani **and** Badini, so nothing about the
box is untranslated except these two.

`guest_full_name_hint` is an EXAMPLE NAME, not a sentence — replace "زيد أحمد"
with a name that reads naturally in Kurdish rather than transliterating it.
The `٢٠٠` in the second row is the database column limit and must stay 200.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `guest_full_name_hint` | e.g. Zaid Ahmed | مثال: زيد أحمد | ckb + kmr |
| `guest_full_name_too_long` | That name is too long. Use 200 characters or fewer. | الاسم طويل جدًا. استخدم ٢٠٠ حرف أو أقل. | ckb + kmr |

## notifications · K7 alert categories  (8 keys)

Added 2026-08-16. The Settings menu gained a screen with one switch per
CATEGORY of alert, replacing an all-or-nothing switch. The six category NAMES
are **not** in this list: they are `Urgent`, `Payment`, `Campaign`, `System`,
`Reminder` and `Normal` — the same keys the Alerts tab's filter chips already
use, already present in Sorani. Only the screen's own furniture is new.

`notif_cat_on` / `notif_cat_off` are the line under each switch saying what its
position means, so they must read as a consequence ("you receive these"), not
as a state word ("on"/"off") — the switch itself already shows the state.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Alert categories` | Alert categories | فئات التنبيهات | ckb + kmr |
| `Could not load your notification settings.` | Could not load your notification settings. | تعذّر تحميل إعدادات الإشعارات. | ckb + kmr |
| `notif_cat_desc` | Choose which kinds of alert you receive. Switching one off stops it being sent to you, not just hidden after it arrives. | اختر أنواع التنبيهات التي تصلك. إيقاف أي نوع يمنع إرساله إليك، وليس مجرد إخفائه بعد وصوله. | ckb + kmr |
| `notif_cat_empty` | No alert categories yet | لا توجد فئات تنبيهات بعد | ckb + kmr |
| `notif_cat_empty_desc` | There is nothing to switch on or off right now. Your notifications still arrive as usual. | لا يوجد شيء لتشغيله أو إيقافه الآن. لا تزال إشعاراتك تصلك كالمعتاد. | ckb + kmr |
| `notif_cat_master_off` | All notifications are switched off, so none of these will reach you until you turn the switch above back on. | جميع الإشعارات متوقّفة، لذا لن يصلك أي منها حتى تعيد تشغيل المفتاح أعلاه. | ckb + kmr |
| `notif_cat_off` | You will not receive these | لن تصلك هذه التنبيهات | ckb + kmr |
| `notif_cat_on` | You receive these | تصلك هذه التنبيهات | ckb + kmr |

## marriage · L19 engagement field privacy  (2 keys)

Added 2026-08-16. The خطوبتي profile gained a per-field picker: the owner
chooses which details other people can see, and the server now actually masks
them. The screen reuses everything it could — `Field privacy`, `privacy_desc`,
`privacy_visible`, `privacy_hidden`, and the ten `marriage_*` field labels the
engagement FORM already prints, all of which already have Sorani and Badini.
Only the empty state, shown when staff have retired every option, is new.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `marriage_privacy_empty` | Nothing to hide yet | لا يوجد ما يمكن إخفاؤه بعد | ckb + kmr |
| `marriage_privacy_empty_desc` | There are no details you can hide on this profile right now. It shows what it shows today. | لا توجد تفاصيل يمكنك إخفاؤها في هذا الملف حالياً. سيظهر كما هو الآن. | ckb + kmr |

## history · K21 identity-code lookup  (5 keys)

Added 2026-08-16. The history screen gained a box that looks a donation /
support history up by identity code, and the profile card now shows the account
its own code. **The label for the code itself is not in this list**:
`reg_volunteer_code` ("Identification code") already carries Sorani and Badini
and is the same words, so it is reused rather than duplicated under a new name.
`Copied` is reused for the copy confirmation.

Two of these carry a rule and must keep it in translation:

* `history_code_not_found` is deliberately VAGUE and must stay so. The server
  answers "no such code" and "that code belongs to somebody else" with the same
  words on purpose — the codes are sequential (ER-000123, GR-000124), so an
  answer that told them apart would let anyone confirm which codes are real. Do
  not translate it into something more helpful.
* `history_code_help` states who may look up what. It is the only thing telling
  a user why a code they typed was refused, so the two halves ("your own" /
  "staff can look up others") both have to survive.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `history_code_title` | Look up by identity code | استعلام بالرمز التعريفي | ckb + kmr |
| `history_code_help` | Enter an identity code to see its donation and support history. You can look up your own code; staff can look up others. Clear the box to return to your own history. | أدخل الرمز التعريفي لعرض سجل التبرعات وحالة الدعم الخاص به. يمكنك الاستعلام برمزك الخاص، ويستطيع الموظفون الاستعلام برموز الآخرين. امسح الحقل للعودة إلى سجلك. | ckb + kmr |
| `history_code_not_found` | No history is available for that code. | لا يوجد سجل متاح لهذا الرمز. | ckb + kmr |
| `history_code_not_permitted` | Your account is not allowed to look up other people's records. | حسابك غير مخوّل بالاستعلام عن سجلات الآخرين. | ckb + kmr |
| `history_code_failed` | Could not look that code up. Check your connection and try again. | تعذّر الاستعلام عن هذا الرمز. تحقّق من اتصالك وحاول مرة أخرى. | ckb + kmr |

## legal · K12 content page states  (1 key)

Added 2026-08-16. `من نحن` and `اتصل بنا` now draw their NAMED sub-sections as
separate titled blocks rather than one blob, and a page carrying no text at all
shows a designed empty state instead of a blank sheet — which is what every one
of these pages will be until the owner writes them. The rest of the screen
reuses keys that already carry Sorani and Badini (`About Us`, `Contact Us`,
`content_load_failed`); only the empty state is new.

It must not read as a failure — `content_load_failed` already covers that, and
the whole point of the pair is that a page nobody has written yet is not a
broken app.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `content_page_empty` | There is nothing on this page yet. Please check back soon. | لا يوجد محتوى في هذه الصفحة بعد. يرجى العودة قريباً. | ckb + kmr |

## legal · K13 contact details  (1 key, Badini only)

Added 2026-08-16. `اتصل بنا` now draws the phone, WhatsApp, email, address,
social accounts and logo the dashboard has been able to store since migration
112. **No new key was written for it** — every label reuses one that already
exists: `Contact information`, `Phone`, `whatsapp_open`, `Address` and
`Social media accounts` all already carry Sorani and Badini.

One gap surfaced rather than being created: `Email` has Sorani but no Badini, so
a Badini reader sees the English word on this screen. It is listed here because
K13 is what put it in front of them.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Email` | Email | البريد الإلكتروني | kmr only (ckb already present) |

## community, widgets · C2 filter-row error states  (2 keys)

Added 2026-08-15. Two filter rows used to vanish without a word when their
fetch failed. They now say what is missing and offer a retry.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Could not load the browse categories.` | Could not load the browse categories. | تعذّر تحميل فئات التصفح. | ckb + kmr |
| `Could not load the sector filters.` | Could not load the sector filters. | تعذّر تحميل مرشحات القطاعات. | ckb + kmr |

## auth · E5 OTP resend countdown  (2 keys)

Added 2026-08-15. The OTP screen now says how long until another code can be
requested, instead of offering a button the server will refuse. `@time` is a
pre-formatted `m:ss` duration already wrapped in LTR isolate marks by the app —
**keep `@time` exactly as written and do not reorder it**, or the digits mirror
inside the RTL sentence.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Resend in @time` | Resend in @time | إعادة الإرسال خلال @time | ckb + kmr |
| `A code was just sent. You can ask for another shortly.` | A code was just sent. You can ask for another shortly. | تم إرسال رمز للتو. يمكنك طلب رمز آخر بعد قليل. | ckb + kmr |

## auth · A16 password sign-in  (25 keys)

The sign-in design changed on 2026-08-15: a code now only CREATES an account
(and rescues one that never had a password), and every sign-in after that uses
a password. These are the strings that flow carries. Two of them interpolate —
`@n` is the minimum password length and `@phone` is the user's own number, and
both must survive the translation, in place.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `At least @n characters.` | At least @n characters. | @n أحرف على الأقل. | ckb + kmr |
| `Back to sign in` | Back to sign in | العودة إلى تسجيل الدخول | ckb + kmr |
| `Choose a password` | Choose a password | اختر كلمة مرور | ckb + kmr |
| `Could not save your password. Please try again.` | Could not save your password. Please try again. | تعذّر حفظ كلمة المرور. يرجى المحاولة مرة أخرى. | ckb + kmr |
| `Could not sign you in. Please try again.` | Could not sign you in. Please try again. | تعذّر تسجيل دخولك. يرجى المحاولة مرة أخرى. | ckb + kmr |
| `Go to sign in` | Go to sign in | اذهب إلى تسجيل الدخول | ckb + kmr |
| `Hide password` | Hide password | إخفاء كلمة المرور | ckb + kmr |
| `Incorrect phone number or password.` | Incorrect phone number or password. | رقم الهاتف أو كلمة المرور غير صحيحة. | ckb + kmr |
| `New here? Create an account` | New here? Create an account | جديد هنا؟ أنشئ حساباً | ckb + kmr |
| `New password` | New password | كلمة المرور الجديدة | ckb + kmr |
| `Save and continue` | Save and continue | حفظ ومتابعة | ckb + kmr |
| `Setting the password for @phone` | Setting the password for @phone | تعيين كلمة المرور للرقم @phone | ckb + kmr |
| `Show password` | Show password | إظهار كلمة المرور | ckb + kmr |
| `Sign in with your phone number and password.` | Sign in with your phone number and password. | سجّل الدخول برقم هاتفك وكلمة المرور. | ckb + kmr |
| `Sign-in endpoint returned an invalid response.` | Sign-in endpoint returned an invalid response. | أعادت خدمة تسجيل الدخول استجابة غير صالحة. | ckb + kmr |
| `That password is too long. Use 72 characters or fewer.` | That password is too long. Use 72 characters or fewer. | كلمة المرور طويلة جداً. استخدم 72 حرفاً أو أقل. | ckb + kmr |
| `That verification expired. Request a new code and try again.` | That verification expired. Request a new code and try again. | انتهت صلاحية التحقق. اطلب رمزاً جديداً وحاول مرة أخرى. | ckb + kmr |
| `The two passwords do not match.` | The two passwords do not match. | كلمتا المرور غير متطابقتين. | ckb + kmr |
| `This number already has a password. Sign in with it instead.` | This number already has a password. Sign in with it instead. | لهذا الرقم كلمة مرور بالفعل. سجّل الدخول بها بدلاً من ذلك. | ckb + kmr |
| `This number has no password yet. Verify it to choose one.` | This number has no password yet. Verify it to choose one. | لا توجد كلمة مرور لهذا الرقم بعد. تحقق منه لاختيار واحدة. | ckb + kmr |
| `Too many failed attempts. Try again later.` | Too many failed attempts. Try again later. | محاولات فاشلة كثيرة. حاول مرة أخرى لاحقاً. | ckb + kmr |
| `Use at least @n characters.` | Use at least @n characters. | استخدم @n أحرف على الأقل. | ckb + kmr |
| `Verify my number` | Verify my number | تحقق من رقمي | ckb + kmr |
| `Verify your number again to continue.` | Verify your number again to continue. | تحقق من رقمك مرة أخرى للمتابعة. | ckb + kmr |
| `Your number is verified. This password is how you will sign in from now on.` | Your number is verified. This password is how you will sign in from now on. | تم التحقق من رقمك. ستسجّل الدخول بكلمة المرور هذه من الآن فصاعداً. | ckb + kmr |

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

## notifications · B1 notification_type vocabulary  (81 keys)

Added 2026-08-15 by `d498453` (app) and by the dashboard commit that followed
(`status.*` in `en.ts`/`ar.ts`). **These 81 rows serve BOTH clients** — the
Flutter map keys the raw token directly (`'marketplace_order_approved'`) and the
dashboard keys the same token under `status.` — so one Kurdish word per row
fills four files.

These are the values the notification `type` filter and the dashboard's النوع
column display. Before this vocabulary existed an Arabic reader picked between
`marketplace_order_approved` and `system_test`; a Kurdish reader still sees the
English column below, which is the intended fallback, not a bug.

Source of truth for the list: the `Type:` field of every `LocalizedMessage` in
`backend/internal/notify/templates.go`.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `admin_announcement` | Admin announcement | إعلان إداري | ckb + kmr |
| `admin_new_beneficiary_case` | New beneficiary case | حالة مستفيد جديدة | ckb + kmr |
| `admin_new_guest_account` | New guest account | حساب زائر جديد | ckb + kmr |
| `admin_new_marriage_profile` | New marriage profile | ملف زواج جديد | ckb + kmr |
| `admin_new_project_request` | New project request | طلب مشروع جديد | ckb + kmr |
| `beneficiary_case_approved` | Beneficiary case approved | قبول حالة مستفيد | ckb + kmr |
| `beneficiary_case_rejected` | Beneficiary case rejected | رفض حالة مستفيد | ckb + kmr |
| `beneficiary_case_submitted` | Beneficiary case submitted | تقديم حالة مستفيد | ckb + kmr |
| `case_volunteer_chat_message` | Case chat message | رسالة محادثة الحالة | ckb + kmr |
| `case_volunteer_chat_opened` | Case chat opened | فتح محادثة الحالة | ckb + kmr |
| `chat_accepted` | Chat accepted | قبول المحادثة | ckb + kmr |
| `chat_message` | Chat message | رسالة محادثة | ckb + kmr |
| `chat_request` | Chat request | طلب محادثة | ckb + kmr |
| `donation_approved` | Donation approved | قبول التبرع | ckb + kmr |
| `donation_cancelled_by_donor` | Donation cancelled | إلغاء التبرع | ckb + kmr |
| `donation_payment_confirmed` | Donation payment confirmed | تأكيد دفع التبرع | ckb + kmr |
| `donation_payment_failed` | Donation payment failed | فشل دفع التبرع | ckb + kmr |
| `donation_received_on_project` | Donation received on project | تبرع وارد على مشروع | ckb + kmr |
| `donation_rejected` | Donation rejected | رفض التبرع | ckb + kmr |
| `donation_submitted` | Donation submitted | تقديم تبرع | ckb + kmr |
| `in_kind_donation_cancelled` | In-kind donation cancelled | إلغاء مساهمة عينية | ckb + kmr |
| `in_kind_donation_delivered` | In-kind donation delivered | تسليم مساهمة عينية | ckb + kmr |
| `in_kind_donation_received` | In-kind donation received | استلام مساهمة عينية | ckb + kmr |
| `in_kind_donation_scheduled` | In-kind donation scheduled | جدولة مساهمة عينية | ckb + kmr |
| `in_kind_donation_submitted` | In-kind donation submitted | تقديم مساهمة عينية | ckb + kmr |
| `marketplace_order_approved` | Order approved | قبول طلب من المتجر | ckb + kmr |
| `marketplace_order_cancelled` | Order cancelled | إلغاء طلب من المتجر | ckb + kmr |
| `marketplace_order_completed` | Order completed | إكمال طلب من المتجر | ckb + kmr |
| `marketplace_order_submitted` | Order submitted | تقديم طلب من المتجر | ckb + kmr |
| `marriage_approved` | Marriage profile approved | قبول ملف الزواج | ckb + kmr |
| `marriage_chat_accepted` | Marriage chat accepted | قبول محادثة الزواج | ckb + kmr |
| `marriage_chat_message` | Marriage chat message | رسالة محادثة الزواج | ckb + kmr |
| `marriage_chat_request` | Marriage chat request | طلب محادثة الزواج | ckb + kmr |
| `marriage_meeting_declined` | Meeting request declined | رفض طلب اللقاء | ckb + kmr |
| `marriage_profile_submitted` | Marriage profile submitted | تقديم ملف زواج | ckb + kmr |
| `marriage_rejected` | Marriage profile rejected | رفض ملف الزواج | ckb + kmr |
| `marriage_status_changed` | Marriage status changed | تغيير حالة ملف الزواج | ckb + kmr |
| `marriage_subscription_activated` | Subscription activated | تفعيل الاشتراك | ckb + kmr |
| `marriage_subscription_pending` | Subscription pending | اشتراك قيد المراجعة | ckb + kmr |
| `marriage_subscription_pending_admin` | Subscription awaiting review | اشتراك بانتظار الإدارة | ckb + kmr |
| `marriage_subscription_rejected` | Subscription rejected | رفض الاشتراك | ckb + kmr |
| `new_campaign` | New campaign | حملة جديدة | ckb + kmr |
| `new_media_post` | New post | منشور جديد | ckb + kmr |
| `new_partner` | New partner | شريك جديد | ckb + kmr |
| `new_volunteer_mission` | New volunteer mission | مهمة تطوع جديدة | ckb + kmr |
| `post_comment_received` | New comment | تعليق جديد | ckb + kmr |
| `project_request_approved` | Project request approved | قبول طلب مشروع | ckb + kmr |
| `project_request_rejected` | Project request rejected | رفض طلب مشروع | ckb + kmr |
| `project_request_status_changed` | Project request updated | تغيير حالة طلب المشروع | ckb + kmr |
| `project_request_submitted` | Project request submitted | تقديم طلب مشروع | ckb + kmr |
| `registration_approved` | Registration approved | قبول التسجيل | ckb + kmr |
| `registration_rejected` | Registration rejected | رفض التسجيل | ckb + kmr |
| `sponsorship_accepted` | Sponsorship accepted | قبول الكفالة | ckb + kmr |
| `sponsorship_cancelled` | Sponsorship cancelled | إلغاء الكفالة | ckb + kmr |
| `sponsorship_due_grantor` | Sponsorship payment due | استحقاق دفعة الكفالة | ckb + kmr |
| `sponsorship_due_recipient` | Sponsorship payment on the way | دفعة كفالة في الطريق | ckb + kmr |
| `sponsorship_payment_due_reminder` | Sponsorship payment reminder | تذكير بدفعة الكفالة | ckb + kmr |
| `sponsorship_status_changed` | Sponsorship status changed | تغيير حالة الكفالة | ckb + kmr |
| `sponsorship_submitted` | Sponsorship submitted | تقديم كفالة | ckb + kmr |
| `staff_chat_message` | Staff chat message | رسالة محادثة الموظفين | ckb + kmr |
| `support_request_submitted` | Support request submitted | تقديم طلب دعم | ckb + kmr |
| `support_ticket_closed` | Support request closed | إغلاق طلب الدعم | ckb + kmr |
| `support_ticket_in_progress` | Support request in progress | طلب دعم قيد المعالجة | ckb + kmr |
| `support_ticket_replied` | Support request replied | رد على طلب الدعم | ckb + kmr |
| `support_ticket_resolved` | Support request resolved | حل طلب الدعم | ckb + kmr |
| `system_test` | System test | اختبار النظام | ckb + kmr |
| `task_assigned` | Task assigned | إسناد مهمة | ckb + kmr |
| `volunteer_application_approved` | Volunteer application approved | قبول طلب التطوع | ckb + kmr |
| `volunteer_application_inactive` | Volunteer application deactivated | تعطيل طلب التطوع | ckb + kmr |
| `volunteer_application_rejected` | Volunteer application rejected | رفض طلب التطوع | ckb + kmr |
| `volunteer_application_submitted` | Volunteer application submitted | تقديم طلب تطوع | ckb + kmr |
| `volunteer_mission_absent` | Marked absent | تسجيل غياب في مهمة | ckb + kmr |
| `volunteer_mission_approved` | Mission join approved | قبول الانضمام لمهمة | ckb + kmr |
| `volunteer_mission_cancelled` | Mission join cancelled | إلغاء الانضمام لمهمة | ckb + kmr |
| `volunteer_mission_completed` | Mission completed | إكمال مهمة | ckb + kmr |
| `volunteer_mission_completion_requested` | Mission completion under review | إكمال مهمة قيد المراجعة | ckb + kmr |
| `volunteer_mission_join_submitted` | Mission join submitted | تقديم طلب انضمام لمهمة | ckb + kmr |
| `volunteer_mission_joined` | Attendance recorded | تسجيل حضور في مهمة | ckb + kmr |
| `volunteer_mission_no_show` | Marked absent | تسجيل غياب في مهمة | ckb + kmr |
| `volunteer_mission_rejected` | Mission join rejected | رفض الانضمام لمهمة | ckb + kmr |
| `wallet_topup` | Wallet top-up | شحن المحفظة | ckb + kmr |

## widgets · B21 literals that widgets translate internally  (19 keys)

Added 2026-08-15 by `d498453`. `AppEmpty`, `AppScreen`, `SectionScaffold`,
`SectionTile`, `AppFigure` and `InfoChip` apply `.tr` to a String FIELD, so a
call site passing a bare English literal looks correct and compiles. These 19
had no map entry and rendered verbatim in Arabic; they now have `_en` and `_ar`.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Eligible support` | Eligible support | الدعم المتاح | ckb + kmr |
| `Kafala Support` | Kafala Support | دعم الكفالة | ckb + kmr |
| `Submit help requests and track admin review in one place.` | Submit help requests and track admin review in one place. | قدّم طلبات المساعدة وتابع مراجعة الإدارة في مكان واحد. | ckb + kmr |
| `Monitor sponsorship plans, your submitted projects, and stories.` | Monitor sponsorship plans, your submitted projects, and stories. | تابع خطط الكفالة ومشاريعك المقدَّمة والقصص. | ckb + kmr |
| `gifts` | gifts | مساهمة | ckb + kmr |
| `contributions` | contributions | مساهمة | ckb + kmr |
| `Delivered` | Delivered | تم التسليم | ckb + kmr |
| `Awaiting confirmation` | Awaiting confirmation | بانتظار التأكيد | ckb + kmr |
| `No gifts yet` | No gifts yet | لا توجد مساهمات بعد | ckb + kmr |
| `Every gift you make appears here with its reference code and delivery status, so you always know where it went.` | Every gift you make appears here with its reference code and delivery status, so you always know where it went. | كل مساهمة تقدّمها تظهر هنا مع رمزها المرجعي وحالة تسليمها، لتعرف دائمًا أين وصلت. | ckb + kmr |
| `Send the first message to start the conversation.` | Send the first message to start the conversation. | أرسل أول رسالة لبدء المحادثة. | ckb + kmr |
| `Send a support request and track the reply.` | Send a support request and track the reply. | أرسل طلب دعم وتابع الرد عليه. | ckb + kmr |
| `Flexible` | Flexible | مرن | ckb + kmr |
| `My volunteer application` | My volunteer application | طلب التطوع الخاص بي | ckb + kmr |
| `Submit your skills and availability to the institution.` | Submit your skills and availability to the institution. | قدّم مهاراتك وأوقات توفّرك إلى المؤسسة. | ckb + kmr |
| `Sending...` | Sending... | جارٍ الإرسال... | ckb + kmr |
| `Featured campaigns will appear here once published.` | Featured campaigns will appear here once published. | ستظهر الحملات المميزة هنا بمجرد نشرها. | ckb + kmr |
| `new one for review.` | new one for review. | نسخة جديدة للمراجعة. | ckb + kmr |
| `edited here.` | edited here. | تُعدَّل هنا. | ckb + kmr |

## donations · K5 operation-status vocabulary  (13 keys)

Added 2026-08-15 by the K5 fix. Two separate additions, both in
`app_translations.dart`:

1. **`donations.delivery_status`**, the eight values of the CHECK constraint in
   migration 050. The app had never rendered any of them — it parsed
   `payment_status` and labelled it "Status" — so a donor could not tell a
   cleared payment from delivered aid. `under_review`, `archived` and
   `cancelled` already had entries and are NOT repeated here.
2. **Funding wording.** The coloured status badge said "Delivered in full"
   while being fed money raised ÷ goal. The delivery wording stays for delivery
   data; these three are what a funding number now says instead.

All 13 currently fall back to English for a Kurdish reader.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `registered` | Registered | مُسجّل | ckb + kmr |
| `received` | Received | تم الاستلام | ckb + kmr |
| `delivered` | Delivered | تم التسليم | ckb + kmr |
| `paused` | Paused | موقوف مؤقتاً | ckb + kmr |
| `suspended` | Suspended | معلّق | ckb + kmr |
| `Delivery status` | Delivery status | حالة التسليم | ckb + kmr |
| `Payment status` | Payment status | حالة الدفع | ckb + kmr |
| `Confirmed` | Confirmed | مؤكَّد | ckb + kmr |
| `Fully funded` | Fully funded | تم التمويل بالكامل | ckb + kmr |
| `Partially funded` | Partially funded | مموّل جزئياً | ckb + kmr |
| `Not funded yet` | Not funded yet | لم يبدأ التمويل بعد | ckb + kmr |
| `mute_all` | Mute sounds & vibration | كتم الأصوات والاهتزاز | **already translated — listed for completeness (K26 reused it)** |
| `mute_all_desc` | Silence chimes, vibrations, and spoken summaries. | أوقف النغمات والاهتزاز والملخصات المنطوقة. | **already translated — K26 needed no new words** |

> The Arabic for the five delivery tokens is taken from the admin dashboard's
> own `ar.ts`, where staff have been reading these exact statuses since the
> Donations page shipped — so the app and the dashboard now say the same word
> for the same state rather than two translators' versions of it.

## community · K16 City Guide sub-categories  (2 keys)

Added 2026-08-15 by the K16 fix. The "التصنيف" field on إضافة نشاط stopped
being a typing box and became a picker over the 27 curated sub-categories,
scoped to the sectors the user ticked above it.

**The 27 sub-category names themselves need nothing** — migration 101 seeded
`name_ckb` and `name_kmr` for every row, so the chips already read correctly in
both Kurdish variants. Only these two UI strings are outstanding.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `activity_pick_sector_first` | Choose a sector above to see its sub-categories. | اختر قطاعًا في الأعلى لعرض فئاته الفرعية. | ckb + kmr |
| `activity_need_fields` | Please enter a name and choose a sub-category. | يرجى إدخال الاسم واختيار فئة فرعية. | **ckb + kmr — REWORDED**, the existing Kurdish says "enter a name and a category" and now describes a control that no longer exists |

## auth · L2 donor social links  (1 key)

Added 2026-08-15 by the L2 fix. The three field labels needed nothing — the
donor panel reuses `reg_recipient_social_accounts_section` and the three
`reg_recipient_social_*` labels, whose key names say "recipient" but whose
values are role-neutral and already present in ckb and kmr. Only the failure
snackbar is new.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Your registration was saved, but your social links did not. You can add them from Privacy settings.` | Your registration was saved, but your social links did not. You can add them from Privacy settings. | تم حفظ تسجيلك، لكن لم يتم حفظ روابط التواصل. يمكنك إضافتها من إعدادات الخصوصية. | ckb + kmr |

## core · J7 the main-menu button  (1 key)

Added 2026-08-15 by the J7 fix. The ☰ control that now sits beside Back on every
pushed page needs one word — its tooltip and screen-reader label. It names the
destination rather than the glyph, because this app's main menu is a screen (the
five-tab dashboard), not a drawer that slides out.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Main menu` | Main menu | القائمة الرئيسية | ckb + kmr |

## dashboard · J6 the اللعبة menu entry  (1 key)

Added 2026-08-15 by the J6 fix. The wheel and the coupon already read correctly
in both Kurdish variants — `Wheel of Fortune`, `Lucky Coupon` and both of their
one-line descriptions are present in all four locales, so the new hub screen
reuses them verbatim. One word is outstanding: the name of the menu entry and
of the hub itself.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Game` | Game | اللعبة | ckb + kmr |

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

## `common.*` · E15 recoverable-delete wording  (1 key)

Added by the E15 fix (حذف on المتطوعين → تسجيلات المهام). English and Arabic
are written; `ckb.ts` / `kmr.ts` deliberately have no entry, so both Kurdish
locales fall back to English until a native speaker fills this in.

**Why it is a new string rather than a reuse.** The three `confirm_delete_body*`
keys that already exist all promise the record will be removed *permanently*.
That is no longer true of the deletes H15 made recoverable, and it is not true
of this one — the row goes to المهملات and can be restored. Reusing one of them
would have made the dialog lie about what the button does.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `common.confirm_delete_body_recoverable` | "{name}" will be moved to the Trash. You can restore it from there. | سيُنقل «{name}» إلى المهملات، ويمكنك استرجاعه من هناك. | ckb + kmr |

> `{name}` is a placeholder — keep it exactly as written, braces included. It is
> substituted at runtime with the record's own label (for a mission signup: the
> volunteer's name and the mission title).

## `field.*` · K15 product discount  (1 key)

Added by the K15 fix (العروض والخصومات needed an amount, not just the existing
`sale` badge — a badge can say "on offer" and cannot say what the price now is).
English and Arabic are written; `ckb.ts` / `kmr.ts` deliberately have no entry,
so both Kurdish locales fall back to English until a native speaker fills this
in.

**Why it is a new string rather than a reuse.** Every existing `field.*` key in
the four locale files was checked for something that already means "percentage
off"; `field.brand` (the other half of the same fix) was reused exactly because
it already existed in all four. There is no percent/discount key of any kind in
`en.ts`, so this one had to be added.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `field.discount_percent` | Discount % | نسبة الخصم ٪ | ckb + kmr |

> A whole number, 1–99. Empty or 0 means no offer, and the server stores that as
> NULL — so the label must not imply a value is required.

## `status.*` · notification types  (81 keys — same words as Part 1)

Do **not** translate these twice. They are the identical 81 values listed under
*Part 1 → notifications · B1 notification_type vocabulary*, keyed here as
`status.<token>` instead of `<token>`. Fill them once and copy the same word
into `ckb.ts` / `kmr.ts` under `status:`.

Deliberate: the dashboard reads one vocabulary and the app another, so a type
that reads "قبول حالة مستحق" on the phone must read the same in the النوع
column. Splitting the Kurdish wording between the two files is the failure mode
to avoid.

## `donationTypes.*` · M7 donation-type CMS  (6 keys)

New screen (`admin-web/src/pages/DonationTypesPage.tsx`, nav **أنواع المساهمة**)
added for M7, where the donor-facing giving types became dashboard-managed rows.

Six of the block's eleven keys were filled in `ckb.ts`/`kmr.ts` **without
inventing anything**: `add_new`, `added`, `saved`, `deleted`, `need_en` and
`active` were copied verbatim from the existing `sponsorshipTypes.*` block,
whose Kurdish text is already generic ("Add type", "Type saved", …) with no
sponsorship wording in it. The rows below are the remaining ones, left absent so
they fall back to English rather than be guessed.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `donationTypes.title` | Donation types | أنواع المساهمة | ckb + kmr |
| `donationTypes.subtitle` | The giving types a donor picks from on the donate screen. Add or edit them here — no code change needed. | الأنواع التي يختار منها المانح في شاشة المساهمة. أضفها أو عدّلها هنا دون الحاجة إلى تعديل برمجي. | ckb + kmr |
| `donationTypes.confirm_delete` | Delete this type? Past donations keep the type they were recorded with. | حذف هذا النوع؟ تحتفظ المساهمات السابقة بالنوع المسجّل معها. | ckb + kmr |
| `donationTypes.slug_hint` | The internal key is derived from the English name and cannot be changed afterwards, because past donations are already stored under it. You can rename the displayed labels at any time. | يُشتق المفتاح الداخلي من الاسم الإنجليزي ولا يمكن تغييره لاحقًا، لأن المساهمات السابقة مسجّلة به. أما الأسماء المعروضة فيمكن تعديلها في أي وقت. | ckb + kmr |
| `donationTypes.empty` | No donation types yet. Add the first one above. | لا توجد أنواع مساهمة بعد. أضف أول نوع من الأعلى. | ckb + kmr |
| `nav.donation_types` | Donation types | أنواع المساهمة | ckb + kmr |

> `donationTypes.title` and `nav.donation_types` are the same words and must get
> the same Kurdish. Note the noun follows `nav.donations` (**المساهمات**, per
> `TERMINOLOGY.md` T1), not "التبرعات".

> The three seeded types themselves — General / Zakat / Sadaqah — needed **no**
> new translation: migration 103 seeds their Kurdish from strings already
> shipped in `app_translations.dart` and the dashboard `status.*` block. Types
> staff add later are typed in by staff in all four languages on the screen
> itself, which is the point of the row.

## `field.section` · `col.sort_order` · `hint.eg_section` · F7 mission sections  (3 keys)

Added for F7, which gave قائمة المهام a section per mission and an order
column. `common.move_up` / `common.move_down` already exist in all four
locales and are reused for the arrows, so only these three are missing.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `field.section` | Section | القسم | ckb + kmr |
| `col.sort_order` | Order | الترتيب | ckb + kmr |
| `hint.eg_section` | e.g. Field work | مثال: العمل الميداني | ckb + kmr |

> `col.sort_order` is a NEW key rather than a reuse of the existing
> `noun.order`, because that one means a **purchase order** (`طلب` in Arabic)
> and would have mislabelled the column. Translate it as *sort position*, not
> as *a request*.

> `hint.eg_section` is a placeholder, and placeholders in this file already
> fall back to English for Kurdish (`hint.eg_city` has no ckb/kmr either), so
> it is the lowest priority of the three.

## donations · M3 the five kinds of donation  (14 keys)

Added 2026-08-16 by the M3 fix, which put one step between the Contribute tab
and checkout asking what kind of donation this is. Source map:
`humanitarian/lib/localization/app_translations.dart`.

**Two of the five titles needed nothing** and are deliberately not listed
below: `In-kind donation` and `Support the organization` already exist in
`_en`, `_ar` and `_sorani` (`Support the organization` has `_badini` too), and
`DonationChannel` reuses those exact keys rather than minting synonyms. Same
for the organization channel's one-line explanation, `Covers running costs:
servers, subscriptions and administration.`, which is present in all four.

The Arabic below is the **client's own wording** from his donation note,
verbatim where he supplied it — these are the five labels he asked to see.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `What kind of donation is this?` | What kind of donation is this? | ما نوع هذا التبرع؟ | ckb + kmr |
| `Choose how you would like to give.` | Choose how you would like to give. | اختر الطريقة التي تريد التبرع بها. | ckb + kmr |
| `Cash donation (direct handover)` | Cash donation (direct handover) | تبرع نقدي (تسليم مباشر) | ckb + kmr |
| `Hand your gift to a representative or leave it at a collection point.` | Hand your gift to a representative or leave it at a collection point. | سلّم تبرعك إلى مندوب أو اتركه في نقطة تجميع. | ckb + kmr |
| `Donation by electronic payment` | Donation by electronic payment | التبرع عبر وسائل الدفع الإلكتروني | ckb + kmr |
| `Cards, electronic wallets and bank transfer.` | Cards, electronic wallets and bank transfer. | البطاقات والمحافظ الإلكترونية والتحويل المصرفي. | ckb + kmr |
| `Donation by balance transfer` | Donation by balance transfer | التبرع عبر تحويل الرصيد | ckb + kmr |
| `Recharge cards, or transfer to the numbers set aside for donations.` | Recharge cards, or transfer to the numbers set aside for donations. | بطاقات تعبئة الرصيد، أو التحويل إلى الأرقام المخصصة للتبرعات. | ckb + kmr |
| `Food, clothing, stationery, furniture or home appliances.` | Food, clothing, stationery, furniture or home appliances. | مواد غذائية، ملابس، قرطاسية، أثاث، أجهزة منزلية. | ckb + kmr |
| `We could not load the ways you can give.` | We could not load the ways you can give. | تعذّر تحميل طرق التبرع المتاحة. | ckb + kmr |
| `No ways to pay yet` | No ways to pay yet | لا توجد وسائل دفع بعد | ckb + kmr |
| `The organization has not published a payment method yet. You can still donate goods below.` | The organization has not published a payment method yet. You can still donate goods below. | لم تنشر المنظمة أي وسيلة دفع بعد. لا يزال بإمكانك التبرع بالمواد العينية أدناه. | ckb + kmr |
| `Kind of donation` | Kind of donation | نوع التبرع المختار | ckb + kmr |
| `this option is not available right now, so every method the organization accepts is shown below.` | this option is not available right now, so every method the organization accepts is shown below. | هذا الخيار غير متاح حالياً، لذلك تظهر أدناه جميع الوسائل التي تقبلها المنظمة. | ckb + kmr |

> `Kind of donation` and the existing `Donation type` are **different
> questions** and must not be given the same Kurdish word. `Donation type` is
> the giving type — Zakat / Sadaqah / General. `Kind of donation` labels the
> row reporting which of the five ways to give the donor picked, so the Arabic
> adds المختار (*the chosen one*) to keep them apart; do the same in Kurdish.

> `Change` was added in the same pass and is listed under the M3 fix here for
> completeness, but it is a single common verb — check `_sorani`/`_badini` for
> an existing word before adding a new one.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Change` | Change | تغيير | ckb + kmr |

## donations · M3 the giving-type field  (2 keys)

The `Donation type` chips stopped being three `const` entries in the checkout
widget and now come from `GET /api/donation-types` (M7, migration 103). That
gave the field its own loading, error and empty states, and two new strings
with them.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `We could not load the donation types.` | We could not load the donation types. | تعذّر تحميل أنواع التبرع. | ckb + kmr |
| `No donation type has been published yet, so this gift will be recorded as a general donation.` | No donation type has been published yet, so this gift will be recorded as a general donation. | لم يُنشر أي نوع تبرع بعد، لذلك سيُسجَّل هذا التبرع كتبرع عام. | ckb + kmr |

> The type NAMES need nothing here — they are server content, typed in by
> staff in all four languages on the dashboard screen, and the app renders
> `name_ckb` / `name_kmr` straight from the row (falling back to `name_en`
> when staff leave a language blank).

## donations · M4 general aid vs a specific project  (9 keys)

Added 2026-08-16 by the M4 fix, which replaced checkout's bare project dropdown
with the two named paths the client asked for. `Select a project` already exists
in all four locales and is reused for the picker's hint, so it is not listed.

The Arabic for the two path names is the client's own wording.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `Who should this help?` | Who should this help? | من تريد أن يستفيد من تبرعك؟ | ckb + kmr |
| `General aid` | General aid | مساعدات عامة | ckb + kmr |
| `Our team distributes it by priority and real need.` | Our team distributes it by priority and real need. | يوزّعه فريقنا حسب الأولوية والحاجة الفعلية. | ckb + kmr |
| `Donate to a specific project` | Donate to a specific project | التبرع حسب مشروع محدد | ckb + kmr |
| `Choose one of the organization's open projects.` | Choose one of the organization's open projects. | اختر أحد مشاريع المنظمة المفتوحة. | ckb + kmr |
| `We could not load the projects.` | We could not load the projects. | تعذّر تحميل المشاريع. | ckb + kmr |
| `Choose a project, or go back to general aid.` | Choose a project, or go back to general aid. | اختر مشروعًا، أو ارجع إلى المساعدات العامة. | ckb + kmr |
| `No project is open for donation right now, so your gift goes to general aid.` | No project is open for donation right now, so your gift goes to general aid. | لا يوجد مشروع مفتوح للتبرع حالياً، لذلك سيذهب تبرعك إلى المساعدات العامة. | ckb + kmr |
| `Project donations are switched off right now, so your gift goes to general aid.` | Project donations are switched off right now, so your gift goes to general aid. | التبرع حسب مشروع موقوف حالياً، لذلك سيذهب تبرعك إلى المساعدات العامة. | ckb + kmr |

> The last two are **different states and must stay distinguishable**. One means
> the organization turned project donations off; the other means it left them on
> and has nothing open today. A donor reading them should be able to tell which.

> The 22 PROJECT NAMES need nothing — migration 085 seeds `name_ckb` and
> `name_kmr` for every row, so the picker already reads correctly in both
> Kurdish variants.

## `content.*` — K12 content sub-sections (6 keys)

New vocabulary added by the "من نحن: three named sub-sections, extendable"
editor (`admin-web/src/components/ContentSectionsEditor.tsx`). English and
Arabic are written; ckb/kmr fall back to English until these are filled in.

`{n}` is a number substituted at runtime — keep it exactly as written.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `content.sections_title` | Sub-sections | الأقسام الفرعية | ckb + kmr |
| `content.sections_desc` | Split this page into named parts. They appear in the app in this order. Add as many as you need — changes apply when you press Save. | قسّم هذه الصفحة إلى أجزاء مسمّاة تظهر في التطبيق بهذا الترتيب. أضف ما تحتاجه منها — تُطبَّق التغييرات عند الضغط على حفظ. | ckb + kmr |
| `content.sections_empty` | No sub-sections yet — this page is one block of text. | لا توجد أقسام فرعية بعد — هذه الصفحة كتلة نص واحدة. | ckb + kmr |
| `content.section_n` | Sub-section {n} | القسم الفرعي {n} | ckb + kmr |
| `content.add_section` | Add sub-section | إضافة قسم فرعي | ckb + kmr |
| `content.body_from_sections` | The body is built from the sub-sections below, so edit the text there. | يُبنى النص من الأقسام الفرعية أدناه، لذا حرّره هناك. | ckb + kmr |

> "Sub-section" here means a NAMED PART OF ONE PAGE (About Us → the app / the
> organization / its goals), not a section of the dashboard and not the
> `section` field on a volunteer mission. Pick a word that reads as "part of
> this page".

## K13 contact details (9 keys)

New vocabulary added by the "تواصل معنا: logo, phone, WhatsApp, email, socials,
address" editor (`admin-web/src/components/ContentContactEditor.tsx`). English
and Arabic are written; ckb/kmr fall back to English until these are filled in.

The five `error.*` rows are shown UNDER the field as the operator types, and are
the same codes the server sends back if a save gets past the form — so one
translation covers both. They must say what to type, not just that something is
wrong.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `content.contact_title` | Contact details | بيانات التواصل | ckb + kmr |
| `content.contact_desc` | Shown on this page in the app, so people can call, message or find you. Leave a field empty to hide it. | تظهر في هذه الصفحة داخل التطبيق ليتمكّن الناس من الاتصال بك أو مراسلتك أو الوصول إليك. اترك الحقل فارغاً لإخفائه. | ckb + kmr |
| `content.fix_fields_first` | Fix the highlighted fields before saving. | صحّح الحقول المميّزة قبل الحفظ. | ckb + kmr |
| `field.whatsapp` | WhatsApp | واتساب | ckb + kmr |
| `error.invalid_phone` | Enter a phone number — at least 5 digits. Spaces, +, brackets and an extension are fine. | أدخل رقم هاتف — خمسة أرقام على الأقل. المسافات وعلامة + والأقواس ورقم التحويلة مقبولة. | ckb + kmr |
| `error.invalid_email` | Enter a full email address, like info@example.com. | أدخل بريداً إلكترونياً كاملاً، مثل info@example.com. | ckb + kmr |
| `error.invalid_social_links` | One link per line, each with a website address — for example facebook.com/yourpage. | رابط واحد في كل سطر، وكل رابط يتضمّن عنوان موقع — مثل facebook.com/yourpage. | ckb + kmr |
| `error.invalid_logo_path` | That logo could not be used. Upload the image again. | تعذّر استخدام هذا الشعار. أعد رفع الصورة. | ckb + kmr |
| `error.value_too_long` | This is too long. Please shorten it. | النص طويل جداً. يرجى اختصاره. | ckb + kmr |

> `info@example.com` and `facebook.com/yourpage` are EXAMPLES the reader copies
> the shape of — leave them in Latin script exactly as they are.

## Field Rules — registration form labels (94 keys)

New vocabulary added while closing **NEW FINDING 9** in `VERIFICATION_REPORT.md`:
179 of the 233 rows on **قواعد الحقول** (`admin-web/src/pages/FieldRulesPage.tsx`)
printed a title-cased English column name — "Grantor National Id", "Recipient
Tribe Clan" — because the `grantor_`/`recipient_`/`volunteer_` families had no
label map at all, and the `marriage_` one covered 11 of its 67 keys. Every row
is labelled now. English and Arabic are written; ckb/kmr fall back to English
until these are filled in.

**94 keys, 151 rows.** Most of these labels are shared by two or more of the
five forms — `field.phone1` alone labels four rows — so the payoff per
translated word is high.

> **The Flutter app almost certainly already has these words in Kurdish.** Every
> label here was copied from the wording the app shows the applicant for the same
> field — the matching `reg_*` key in
> `humanitarian/lib/localization/app_translations.dart` — and most of those keys
> already carry `_sorani`/`_badini` values. **Check the app's value first and
> copy it if it is right**, rather than translating from scratch. They were not
> copied automatically here: both Kurdish locales are written in Arabic script,
> so a wrong value cannot be spotted by eye, and this project has already had to
> revert Arabic text pasted into a Kurdish map.

The seven `fieldRules.section_*` rows are the section headings that now split
that page into one block per form. المانح / المستحق / المتطوّع are the role
words the dashboard already uses elsewhere (`registrations.role_*`).

| Key | English | Arabic | Needs |
|---|---|---|---|
| `fieldRules.section_registration_desc` | Fields the app’s sign-up form asks every role for. | الحقول التي يطلبها نموذج التسجيل في التطبيق من جميع الأدوار. | ckb + kmr |
| `fieldRules.section_grantor` | Grantor registration fields | حقول تسجيل المانح | ckb + kmr |
| `fieldRules.section_grantor_desc` | Extra fields the app’s sign-up form asks a grantor for. | حقول إضافية يطلبها نموذج التسجيل في التطبيق من المانح. | ckb + kmr |
| `fieldRules.section_recipient` | Eligible Recipient registration fields | حقول تسجيل المستحق | ckb + kmr |
| `fieldRules.section_recipient_desc` | Extra fields the app’s sign-up form asks an eligible recipient for. | حقول إضافية يطلبها نموذج التسجيل في التطبيق من المستحق. | ckb + kmr |
| `fieldRules.section_volunteer` | Volunteer registration fields | حقول تسجيل المتطوّع | ckb + kmr |
| `fieldRules.section_volunteer_desc` | Extra fields the app’s sign-up form asks a volunteer for. | حقول إضافية يطلبها نموذج التسجيل في التطبيق من المتطوّع. | ckb + kmr |
| `field.name_parts` | Full name (four parts) | الاسم الكامل (رباعي) | ckb + kmr |
| `field.title_surname` | Surname / title | اللقب / الكنية | ckb + kmr |
| `field.phone1` | Primary phone number | رقم الهاتف الأساسي | ckb + kmr |
| `field.phone2` | Second phone number | رقم الهاتف الثاني | ckb + kmr |
| `field.emergency_phone` | Emergency phone (family member) | هاتف الطوارئ (أحد أفراد العائلة) | ckb + kmr |
| `field.gps_location` | GPS location | الموقع الجغرافي (GPS) | ckb + kmr |
| `field.education_level` | Educational attainment | التحصيل الدراسي | ckb + kmr |
| `field.id_photo` | National Card photo | صورة البطاقة الوطنية | ckb + kmr |
| `field.tribe_clan` | Tribe / clan | العشيرة / القبيلة | ckb + kmr |
| `field.nationality` | Nationality | الجنسية | ckb + kmr |
| `field.residency_status` | Legal / residency status | الوضع القانوني / الإقامة | ckb + kmr |
| `field.housing_side` | Side of the city | جانب المدينة | ckb + kmr |
| `field.neighborhood` | Neighborhood / residential area | الحي / المنطقة السكنية | ckb + kmr |
| `field.nearest_landmark` | Nearest landmark | أقرب معلم | ckb + kmr |
| `field.housing_type` | Housing type | نوع السكن | ckb + kmr |
| `field.rental_amount` | Rental amount | مبلغ الإيجار | ckb + kmr |
| `field.housing_area` | Housing area / size | مساحة السكن | ckb + kmr |
| `field.floors_count` | Number of floors | عدد الطوابق | ckb + kmr |
| `field.rooms_count` | Number of rooms | عدد الغرف | ckb + kmr |
| `field.families_count` | Number of families living in the house | عدد العائلات التي تسكن المنزل | ckb + kmr |
| `field.other_certificate` | Other certificate / qualification | شهادة / مؤهل آخر | ckb + kmr |
| `field.certificates_count` | Number of certificates | عدد الشهادات | ckb + kmr |
| `field.previous_occupation` | Previous occupation | المهنة السابقة | ckb + kmr |
| `field.job_description` | Job description | وصف العمل | ckb + kmr |
| `field.working_hours` | Number of working hours | عدد ساعات العمل | ckb + kmr |
| `field.is_employed` | Currently employed? | هل يعمل حالياً؟ | ckb + kmr |
| `field.workplace` | Workplace | مكان العمل | ckb + kmr |
| `field.wage_amount` | Wage amount | مبلغ الأجر | ckb + kmr |
| `field.registered_social_welfare` | Registered with social welfare | مسجل في الرعاية الاجتماعية | ckb + kmr |
| `field.registered_unemployed` | Registered as unemployed | مسجل كعاطل عن العمل | ckb + kmr |
| `field.household_employees` | Number of employees in the household | عدد الموظفين في الأسرة | ckb + kmr |
| `field.working_members` | Number of working household members | عدد أفراد الأسرة العاملين | ckb + kmr |
| `field.men_count` | Number of men | عدد الرجال | ckb + kmr |
| `field.women_count` | Number of women | عدد النساء | ckb + kmr |
| `field.male_children_count` | Number of male children | عدد الأطفال الذكور | ckb + kmr |
| `field.female_children_count` | Number of female children | عدد الأطفال الإناث | ckb + kmr |
| `field.age_0_5_count` | Ages 0–5 years | الأعمار 0–5 سنوات | ckb + kmr |
| `field.age_5_10_count` | Ages 5–10 years | الأعمار 5–10 سنوات | ckb + kmr |
| `field.age_10_15_count` | Ages 10–15 years | الأعمار 10–15 سنة | ckb + kmr |
| `field.age_15_25_count` | Ages 15–25 years | الأعمار 15–25 سنة | ckb + kmr |
| `field.age_25_40_count` | Ages 25–40 years | الأعمار 25–40 سنة | ckb + kmr |
| `field.age_40_plus_count` | Ages 40 years and above | 40 سنة فأكثر | ckb + kmr |
| `field.students_count` | Number of students | عدد الطلاب | ckb + kmr |
| `field.orphans_count` | Number of orphans | عدد الأيتام | ckb + kmr |
| `field.widows_count` | Number of widows | عدد الأرامل | ckb + kmr |
| `field.divorced_count` | Number of divorced persons | عدد المطلقين | ckb + kmr |
| `field.smoking_status` | Smoking status | حالة التدخين | ckb + kmr |
| `field.eyesight_condition` | Eyesight condition | حالة النظر | ckb + kmr |
| `field.has_disability` | Person with special needs / disability? | من ذوي الاحتياجات الخاصة / إعاقة؟ | ckb + kmr |
| `field.disability_type` | Type of disability | نوع الإعاقة | ckb + kmr |
| `field.household_disabled` | Persons with disabilities in the household | عدد ذوي الإعاقة في الأسرة | ckb + kmr |
| `field.chronic_illnesses` | Chronic illnesses | الأمراض المزمنة | ckb + kmr |
| `field.medical_conditions_count` | Number of medical conditions | عدد الحالات المرضية | ckb + kmr |
| `field.medical_conditions_desc` | Description of each medical condition | وصف كل حالة مرضية | ckb + kmr |
| `field.ration_card_photo` | Ration Card | البطاقة التموينية | ckb + kmr |
| `field.property_proof_photo` | Proof of property ownership or rental agreement | إثبات ملكية العقار أو عقد الإيجار | ckb + kmr |
| `field.medical_report_photo` | Medical reports | التقارير الطبية | ckb + kmr |
| `field.house_facade_photo` | House photo — exterior façade | صورة المنزل — الواجهة الخارجية | ckb + kmr |
| `field.house_inside_photo` | House photo — inside the house | صورة المنزل — من الداخل | ckb + kmr |
| `field.house_outside_photo` | House photo — outside the house | صورة المنزل — من الخارج | ckb + kmr |
| `field.available_furniture` | Available furniture | الأثاث المتوفر | ckb + kmr |
| `field.owns_car` | Owns a car? | يمتلك سيارة؟ | ckb + kmr |
| `field.needs_description` | Situation, needs, or requested support | الوضع أو الاحتياجات أو الدعم المطلوب | ckb + kmr |
| `field.social_facebook` | Facebook link | رابط فيسبوك | ckb + kmr |
| `field.social_instagram` | Instagram link | رابط إنستغرام | ckb + kmr |
| `field.social_telegram` | Telegram link | رابط تيليغرام | ckb + kmr |
| `field.social_other` | Other social media links | روابط تواصل اجتماعي أخرى | ckb + kmr |
| `field.consent_show_real_name` | Allow my real name to be shown to the grantor | السماح بعرض اسمي الحقيقي للمانح | ckb + kmr |
| `field.consent_share_info` | Allow some of my information to be shown to the grantor | السماح بعرض بعض معلوماتي للمانح | ckb + kmr |
| `field.languages` | Languages | اللغات | ckb + kmr |
| `field.golden_square_photo` | Golden Square document | وثيقة المربع الذهبي | ckb + kmr |
| `field.residence_card_photo` | Residence Card | بطاقة السكن | ckb + kmr |
| `field.passport_photo` | Passport | جواز السفر | ckb + kmr |
| `field.graduation_cert_photo` | Graduation certificate | شهادة التخرج | ckb + kmr |
| `field.cv_photo` | Curriculum vitae (CV) | السيرة الذاتية | ckb + kmr |

The last twelve rows are the fields only the Marriage/Engagement form asks
about; their wording comes from `marriage_form_screen.dart`.

| Key | English | Arabic | Needs |
|---|---|---|---|
| `field.years_current_residence` | Years at current residence | عدد سنوات السكن الحالي | ckb + kmr |
| `field.previous_residence` | Previous residence | السكن السابق | ckb + kmr |
| `field.years_previous_residence` | Years at previous residence | عدد سنوات السكن السابق | ckb + kmr |
| `field.skin_tone` | Skin tone | لون البشرة | ckb + kmr |
| `field.children_count` | Number of children | عدد الأطفال | ckb + kmr |
| `field.ethnicity` | Ethnicity / national identity | القومية / الهوية الوطنية | ckb + kmr |
| `field.owns_house` | Owns a house | يمتلك منزلاً | ckb + kmr |
| `field.owns_shop` | Owns a shop | يمتلك محلاً | ckb + kmr |
| `field.owns_company` | Owns a company | يمتلك شركة | ckb + kmr |
| `field.owns_land` | Owns land | يمتلك أرضاً | ckb + kmr |
| `field.other_assets` | Other available assets | ممتلكات أخرى متوفرة | ckb + kmr |
| `field.partner_requirements` | Requirements sought in a partner | المواصفات المطلوبة في شريك الحياة | ckb + kmr |

> `GPS` and `(CV)` are shown in Latin script on purpose — leave them as they are.
> "Golden Square document" (`وثيقة المربع الذهبي`) is an Iraqi residence
> document; keep whatever name it is known by locally.

---

# Part 2b — Backend push / in-app notification templates

Source: `backend/internal/notify/templates.go`. Each builder returns a
`LocalText{En, Ar, Ckb, Kmr}` per title and body. An empty slot is stored NULL
and every client renders the English one, so these are safe as they stand.

Most builders in that file already carry Kurdish — first-pass drafts flagged in
the file header as needing a native-speaker review. The rows below are the ones
deliberately left EMPTY rather than guessed, and they are the ones to fill first.

| Builder | Slot | English | Arabic | Needs |
|---|---|---|---|---|
| `SupportRepliedMsg` | title | Support replied | رد فريق الدعم | ckb + kmr |
| `SupportRepliedMsg` | body | The support team answered your request "%s". Open it to read the reply. | أجاب فريق الدعم على طلبك "%s". افتحه لقراءة الرد. | ckb + kmr |

`%s` is the ticket subject and must survive in the translation, in that
position — it is the only thing telling a user with several open tickets which
one was answered.

---

# Part 3 — Housekeeping for whoever applies the translations

**Stale Kurdish keys that no longer exist in English.** They are dead
weight and can be deleted; they are listed so the finding is not lost. The last
two went stale on 2026-08-15: the login screen's footer became a real "New here?
Create an account" action when sign-up stopped being the same thing as sign-in,
and the sentence it replaced was removed from `_en` and `_ar`.

| Map | Key |
|---|---|
| `_badini` | `Ask me anything — I'll guide you through the app` |
| `_badini` | `Don't have an account?` |
| `_badini` | `You are getting close to this month's impact milestone with a strong donor retention trend.` |
| `_sorani` | `New here? Entering your number creates your account.` |
| `_badini` | `New here? Entering your number creates your account.` |

**Do not translate these** — they are protected vocabulary (`TERMINOLOGY.md` T18):

| Word | Language | Actually means |
|---|---|---|
| `سوودمەند` | Kurdish | **useful** — NOT "beneficiary". A previous pass nearly renamed it. |
| `وەرگرتن` | Kurdish | to receive (the ordinary verb) |
| `مستلمة` | Arabic | received (a delivered item) |


## Content page save confirmation (2 keys, added with the CMS toast fix)

One component backs eight content pages, so its save confirmation must name the
page it saved. `{page}` is substituted with that page's own title in the
reader's language — do not translate the placeholder itself.

| Key | English | Arabic | Note for the translator |
|---|---|---|---|
| `content.saved` | Saved {page}. | تم حفظ {page}. | **Do not derive this from the old Terms & Conditions message.** The Sorani wording there was `پاشەکەوتکران`, whose verb is PLURAL because it agreed with "terms and rules". `{page}` is a single page title, so the number agreement changes. Please supply a form that reads correctly with any single page name. |
| `content.saved_untitled` | Page saved. | تم حفظ الصفحة. | Shown only when the page has no title in any language. |

Arabic needed no such care and is already written: «تم حفظ» is built on the
verbal noun «حفظ», not on `{page}`, so it does not shift with the gender of the
page name — which is why substituting the object alone was safe there.

## Delete confirmation bodies (3 keys) — URGENT, these were WRONG in Kurdish

`common.confirm_delete_body`, `confirm_delete_body_noun` and
`confirm_delete_body_code` told the reader the record would be **deleted
permanently**. That is not what the button does: all 16 delete dialogs in the
dashboard act on tables listed in the backend's `restorableTables`, so the row
goes to المهملات and a Super-Admin can restore it.

English and Arabic are corrected. The **Sorani and Badini strings were deleted
rather than rewritten** — they said `بە تەواوی` / `ب تەمامی` ("completely"), and
a mistranslated promise about whether data can be recovered is worse than an
English sentence that is true. Until these are translated, Kurdish readers see
the correct English.

| Key | English (corrected) |
|---|---|
| `common.confirm_delete_body` | "{name}" will be moved to the Trash. You can restore it from there. |
| `common.confirm_delete_body_noun` | {noun} will be moved to the Trash. You can restore it from there. |
| `common.confirm_delete_body_code` | {noun} {code} will be moved to the Trash. You can restore it from there. |
| `page.users.delete_body` | {name} will be moved to the Trash. You can restore it from there. Contributions and other records linked to this user will block the delete (a clear error message will appear if so). |
| `bulk.confirm_body` | The rows will be moved to the Trash. You can restore them from there. Records referenced by other tables will be skipped. |

Note for the translator: "Trash" is the المهملات screen in the dashboard sidebar
— please use whatever word that screen already uses in Kurdish, so the dialog
and the destination match.

## City Guide map chip (2 keys)

The chip on the City Guide map was raw English — "8 places · Mosul" — on a
screen whose own header already reads «الموصل · العراق». English and Arabic are
written; ckb/kmr fall back to English.

| Key | English | Arabic |
|---|---|---|
| `@count place · Mosul` | @count place · Mosul | @count مكان · الموصل |
| `@count places · Mosul` | @count places · Mosul | @count مكانا · الموصل |

Two keys rather than one so English stays correct at a single pin. Arabic uses
the تمييز form after the numeral, following the existing `@count شخصا متأثرا`.
The city name is part of the key because this guide is Mosul-specific — the
sibling key `Mosul · Iraq` is already built the same way in all four locales.
