# Client notes — round 2 (الملاحظات.pdf, received 2026-10-16)

Source: `~/Downloads/الملاحظات.pdf` (20 pages). Every point in that PDF is listed below, in PDF order,
numbered. We go ONE AT A TIME: fix → verify in the real app/dashboard → screenshot to owner →
owner says "ok go next" → next point. Each finished point gets its "How it was fixed" filled in.

Rules carried over from round 1 (see `CLIENT_MEETING_HANDOFF.md`): OPOS task first (office 19,
account momen 1758), never write to production through the dashboard dev server, report with
**Found:** / **Fixed:**.

Type: **F** = fix/change to something that already exists (do now, in order) · **A** = ADDITION / new
feature (owner rule 2026-10-16: do LAST, and ONLY if it is in the original proposal — if it isn't, we don't do it) ·
**Q** = question about an existing feature (answer by showing where it is; if it turns out missing → becomes A).
Type is noted in brackets at the start of each point.

Status key: 🅰 deferred (addition) · ⬜ todo · 🔧 in progress · ✅ done (owner approved) · ❓ question answered / needs owner decision · ↪ merged into another point

---

## Page 1 — general notes

| # | Point (client's words, condensed) | Status |
|---|---|---|
| 1 | [F] **Simplify & de-clutter UI.** Repeated details, long explanations across sections; donation takes up to 6 screens. Shorten everything, make donation fast/easy with many payment options. (Umbrella — concrete work is #47–#55.) | ⬜ |
| 2 | [A] **Where are attendance / activity details in app + dashboard?** (a) daily attendance/leave log for staff & volunteers; (b) participant registration form per activity/campaign; (c) aid-delivery documentation — volunteer/staff uploads report + proof (photo or signature). | 🅰 |
| 3 | [Q] **Group chats management:** how does the supervisor create custom group rooms from the dashboard: staff-only, volunteers-only, staff + donor + some beneficiaries, staff + suitor + fiancée (+ maybe her guardian). | ✅ |
| 4 | [Q] **Room control buttons for supervisor:** temporary pause, archive, delete, kick a member, add a new member. | ❓ answered — awaiting owner OK |
| 5 | [A] **Calling feature:** voice/video calls in all private + group chats for all roles (staff, volunteer, donor, beneficiary, general user, events/khotba), supervisor can switch calling on/off entirely. | 🅰 |
| 6 | [F] **Simplify staff/volunteer messaging:** remove friction; once an account is activated + approved in the dashboard, enable direct instant messaging; pause/archive/delete stays with admin. | ⬜ |
| 7 | [F] **In-app logo** looks like a question mark — add effect/shadow so it reads as a logo. | ⬜ |
| 8 | [F] **App font is bad:** letters overlap, esp. words with «لا» and joined letters → words read wrong. | ⬜ |
| 9 | [F] (Info only) Images: some have red markers; some notes are explained in text without a picture. | ℹ️ |
| 10 | [A] **In-App Admin Panel** (staff manage from the phone, isolated permissions): Khotba staff → khotba files, approvals, their chats only; Volunteers staff → volunteers, activities, chats, attendance; Store staff → products + purchase requests; Beneficiaries staff → beneficiary data, approvals, forms, their messages. | 🅰 |

## Page 2 — saved accounts & verification

| # | Point | Status |
|---|---|---|
| 11 | [A] **Saved accounts + switching:** on logout keep accounts in secure local storage; login screen lists previously-used accounts (photo, name, phone); one tap switches without password/OTP; button «تسجيل دخول بحساب آخر» under the list. (Same as page 3 intro.) | 🅰 |
| 12 | [A] **Verification architecture:** first account creation → Step 1 phone OTP, Step 2 email verification (link/code). After both, email is the default confirmation method for later operations (new-device login, recovery) — free. Settings option to switch back to phone. | 🅰 |
| 13 | [F] Image resize/crop enabled in ALL sections, not only the identity section. | ⬜ |
| 14 | [A] Extra-files field (attach files, documents, other photos) in registration for all roles (donor, volunteer, khotba, beneficiary, general user) — exists? With image resize. | 🅰 |
| 15 | [F] Fix slowness during registration. | ⬜ |
| 16 | [F] Fix bug that stops a VISITOR from messaging support and viewing sections (humanitarian, store, city guide, khotba posts). | ⬜ |
| 17 | [F] Visitor «ترقية الحساب»: error when filling data, English message "Failed to send verification code". | ⬜ |
| 18 | [F] Upgrade screen bottom send button is black, its text invisible. | ⬜ |
| 19 | [F] Shorten long hint («سنرسل لك رمزاً لمرة واحدة...») → «يرجى تأكيد رقم هاتفك لترقية الحساب». | ⬜ |

## Page 3 — welcome screen

| # | Point | Status |
|---|---|---|
| 20 | [F] Logo vs dark olive circle out of proportion → shrink the circle so the logo stands out; add shadow / light 3D. | ⬜ |
| 21 | [F] Tagline «توازن واستقرار من أجل حياة أفضل!» (2 lines) → «توازن لمستقبل أفضل», centered, one line. | ⬜ |
| 22 | [F] Bottom text «سجل الدخول أو أنشئ حساباً برقم هاتفك» is at the very bottom, right-aligned → centered, raised a bit, font slightly bigger. | ⬜ |
| 23 | [F] Welcome screen scrolls → disable scroll, elements fixed. | ⬜ |

## Page 4 — splash logo icon

| # | Point | Status |
|---|---|---|
| 24 | [F] Circular logo overlaps inside the dark square: remove the thin green circular lines around the square; enlarge inner logo slightly (not to square size); add light shadow / 3D. | ⬜ |

## Page 5 — login screen

| # | Point | Status |
|---|---|---|
| 25 | [F] Login screen scrolls → disable scroll, elements fixed (screenshots show «جديد هنا؟ أنشئ حساباً» moving). | ⬜ |
| 26 | [F] Phone field accepts up to 15 digits → per-country rules; Iraq (+964): auto-trim a leading 0, keep the 10 digits; max length per country. | ⬜ |

## Page 6 — set password screen

| # | Point | Status |
|---|---|---|
| 27 | [F] Three long repetitive texts at the top (circled) → delete all, replace with ONE short centered phrase. | ⬜ |
| 28 | [F] Hint «8 أحرف على الأقل» → «الحد الأدنى 8 خانات تشمل أحرفاً وأرقاماً», centered. | ⬜ |

## Page 7 — OTP verification screen

| # | Point | Status |
|---|---|---|
| 29 | [F] «أدخل الرمز المكون من 6 ارقام المرسل الى 0770*******» → «أدخل رمز التحقق المرسل إلى», phone number on the line below, centered. | ⬜ |
| 30 | [F] Red hint long, typos, side-aligned → centered: «الرقم مسجل بالفعل، يرجى العودة لتسجيل الدخول». | ⬜ |
| 31 | [F] OTP input → 6 separate small boxes, one digit each, auto-advance; SMS auto-fill; paste support (code copied from WhatsApp/SMS). | ⬜ |
| 32 | [F] Keep main green button, rename to «متابعة تسجيل الدخول»; delete the duplicate «العودة إلى تسجيل الدخول» link. | ⬜ |
| 33 | [F] Resend countdown «إعادة إرسال الرمز خلال 00:59»; escalating cooldown on repeated requests (e.g. ½ h, 1 h, 1 day) against spam. | ⬜ |

## Page 8 — complete registration

| # | Point | Status |
|---|---|---|
| 34 | [F] Top hint «اخبرنا عن نفسك ليتمكن المشرف من مراجعة حسابك» → «يرجى إكمال البيانات التالية لإنشاء حسابك», centered. | ⬜ |
| 35 | [F] Data duplication: role picker = dropdown, **general user** is the default; picking volunteer/beneficiary/donor shows that role's fields; data already typed is reused (no re-entry); add photo + email to general registration (and dashboard); same required/optional rule system. | ⬜ |
| 36 | [F] Remove every «(اختياري)»; one sentence at the top: «الحقول المصحوبة بعلامة حمراء إجبارية». | ⬜ |
| 37 | [F] General user rights: browse everything (humanitarian, store, city guide, khotba), message support. Blocked: commenting in khotba, applying to khotba requests, requesting aid, joining volunteering; no volunteer notifications — until «تطوير حسابه» (upgrade + choose role). | ⬜ |
| 38 | [F] Dashboard: separate section «المستخدم العام» (or better name) with admin controls (edit data, add user) matching the registration fields. | ⬜ |

## Page 9 — notifications screen

| # | Point | Status |
|---|---|---|
| 39 | [F] Filter tiles (الكل / غير مقروء / مقروء) unequal; «غير مقروء» wraps badly → equal size, one line or two stacked centered words. | ⬜ |
| 40 | [F] «مسح 2 مقروءة» button tiny and off to the side → bigger icon + text, centered. | ⬜ |
| 41 | [F] Category/Type dropdowns change look when a value is picked; no linkage → stable design; Type list filtered by chosen Category. | ⬜ |
| 42 | [F] Notifications in random order → newest first by date+time. | ⬜ |
| 43 | [F] Where is "mark all as read"? | ⬜ |

## Page 10 — incentive activities (wheel + scratch)

| # | Point | Status |
|---|---|---|
| 44 | [A] App: result → action link (e.g. «اكفل عائلة هذا الشهر» → opens donation section); share result instantly; real finger-scratch effect instead of tap-to-reveal video. | 🅰 |
| 45 | [A] Dashboard: manage wheel slot texts, scratch prizes/texts, and link each text to an app section (destination). | 🅰 |
| 46 | [F] Visual quality: wheel/scratch graphics look amateur → modern UI matching brand + smooth animations. | ⬜ |

## Pages 11–12 — donation flow restructure

| # | Point | Status |
|---|---|---|
| 47 | [F] Donation in 2 steps max. Step 1: «قدم مساهمة» → short clean screen with 4 options: الدفع الإلكتروني / تحويل رصيد / التسليم النقدي المباشر / المساهمات العينية. | ⬜ |
| 48 | [F] Step 2 — e-payment: amount, card type (Visa, Master, FIB) → straight to gateway; IQD default, other currencies manual; notes. | ⬜ |
| 49 | [F] Step 2 — balance transfer, ONE fixed page, two toggles at top «تعبئة / تحويل مباشر» vs «إرسال كرت». Transfer: network (Asia, Zain, Korek), amount, org phone with copy button, screenshot attach, notes. Card: network, photograph card with camera, serial field, value, notes. Fixed bottom: attach + notes + «تأكيد المساهمة». Toggle switches fields in place. Phone/address auto-filled, editable. | ⬜ |
| 50 | [F] Step 2 — direct cash: amount, address, phone, optional visit-time note; phone/address auto-filled, editable. | ⬜ |
| 51 | [F] Step 2 — in-kind: material type, phone, address (auto-filled, editable), optional photo of the items. | ⬜ |
| 52 | [F] Every path ends with one clear bottom button «تأكيد المساهمة» that sends straight to the dashboard. | ⬜ |
| 53 | [F] General: unclear labels (تبرع الان / عرض الكل); repeated confirmation screens; long explanation text under every option → remove, short labels (1–2 words per button). | ⬜ |
| 54 | [F] After sending a contribution it says "sent & pending" but NO donation/support shows up → final submission mechanism broken, fix. | ⬜ |
| 55 | [F] Remove donation type (عام / زكاة / صدقة) and «التبرع لمؤسسة»; replace with one fixed line: «تنويه: يتم استقطاع نسبة بسيطة من التبرعات لتغطية التكاليف التشغيلية وضمان استمرار عمل المشروع.» | ⬜ |

## Page 13 — messaging & support

| # | Point | Status |
|---|---|---|
| 56 | [F] Remove explanation screens/popups (مساعد الدعم / التواصل مع الدعم / إرسال تذكرة) → section becomes fast live chat. | ⬜ |
| 57 | [F] Arabize system texts (e.g. "Event service request: Hall booking") → Modern Standard Arabic. | ⬜ |
| 58 | [F] Staff & volunteers: direct instant messaging, no friction. (↪ with #6) | ⬜ |
| 59 | [F] Beneficiaries / khotba / general user / visitor: start with a support ticket; staff replies; staff can convert the ticket into a chat with specific people; can close it; ticket feature stays. | ⬜ |
| 60 | [Q] Encrypted group chats: aid section (staff + donor(s)/beneficiary); khotba (staff + suitor + girl + guardian). Opens only with staff approval; no personal data shown (numbers, real names); files/photos only by staff; staff can pause / archive / delete. (Related #3, #4) | ⬜ |
| 61 | [Q] Staff chat controls: **temporary pause** (client can still send, staff sees it, no read receipt until reply); **full stop** (lock, client can't send); admin buttons Archive / Block / Delete. (Related #4) | ⬜ |

## Page 14 — city guide, profile, أثرنا, store

| # | Point | Status |
|---|---|---|
| 62 | [F] City guide «إضافة نشاط»: no photo option; why lat/long fields (just attach GPS); submit button sits under the phone nav buttons → move it up. | ⬜ |
| 63 | [F] Profile: logout button at the very bottom collides with phone nav buttons → move up. | ⬜ |
| 64 | [F] «أثرنا» section doesn't work — where are its data/photos/details edited? | ⬜ |
| 65 | [F] Store: selecting a product froze the page, cancel didn't respond, logout/login didn't fix; cart only appeared after several tries. | ⬜ |
| 66 | [A] Store: no payment options, only cash? (needs e-payment). | 🅰 |

## Page 15 — wallet, home, events section

| # | Point | Status |
|---|---|---|
| 67 | [F] **CRITICAL wallet hole:** app tops up the wallet with no real payment and no staff approval → block auto top-up; real gateway OR pending until dashboard approval; fix balance reading (shows 0) across wallet screens. | ⬜ |
| 68 | [F] Home → browse by category: campaign details cut off → give the details more space. | ⬜ |
| 69 | [F] Home: «مشاركتي» opens a page titled «سجلي» — naming mistake?; shorten the circled phrases to one line, remove extra details; «استعلام بالرمز التعريفي» long unclear explanation — is this lookup approach right at all? | ⬜ |
| 70 | [F] Rename «قسم الفعاليات» → «إدارة ملف التوافق الأسري». | ⬜ |
| 71 | [F] Inside it, rename «ملفي الشخصي» → «بيانات الملف الأسري». | ⬜ |
| 72 | [A] «خدمات الفعاليات» → real store: subcategories (halls, photographers, decor), each with providers, photos (e.g. 6 per hall), price; cart; e-payment; booking/direct purchase. | 🅰 |
| 73 | [A] Public posting: today only targeted posts to one person → allow public posts (e.g. "looking for specs X") others can view, comment on, and contact the owner. | 🅰 |

## Pages 16–20 — dashboard

| # | Point | Status |
|---|---|---|
| 74 | [F] Export button + date/time column in EVERY section/table (screenshots: الشركاء has no date/time; إيصالات المساعدات has no export and no date/time). | ⬜ |
| 75 | [F] Sticky table header in every section. (Round-1 #49021 did this — re-verify all pages.) | ⬜ |
| 76 | [F] Unify the top bar design across all sections. | ⬜ |
| 77 | [F] «حذف الحساب» moves INTO the user edit page, not the outside dropdown. | ⬜ |
| 78 | [F] Account data parity: same fields/options when creating an account in the app, in the dashboard, or editing. | ⬜ |
| 79 | [F] Change-password in dashboard (edit user modal, «كلمة مرور جديدة») doesn't work → fix. | ⬜ |
| 80 | [Q] Supervisor permissions: where to assign roles to dashboard staff with per-section permissions? | ⬜ |
| 81 | [F] Full separation of account lists: Volunteers / Donors / Beneficiaries / General users / Visitors / Khotba & marriage (family files) / Staff — each section shows only its roles. | ⬜ |
| 82 | [F] «تحديد الكل» (Select All) checkbox at the top of every table → bulk delete old test data. | ⬜ |
| 83 | [A] Store (dashboard + app) judged weak by someone who runs a real store app → needs clear, easy, complete sections. | 🅰 |
| 84 | [F] Align all toolbar input fields on ONE horizontal row in every section (screenshots: لوحة التحكم, المستحقون, اشتراكات الفعاليات, المتطوعون, طلبات التواصل, التعليقات, دليل المدينة, الموظفون). | ⬜ |
| 85 | [F] Create-notification language tabs (EN / عربي / سوراني / باديني) don't translate anything; plus a language switch at the top — what are these for? | ⬜ |
| 86 | [F] Dashboard font is bad too (e.g. «المدن والأقضية والنواحي», «الأقضية») — letters hard to read. | ⬜ |
| 87 | [F] Change password not working in edit account (↪ #79). | ↪ |
| 88 | [F] City guide: clicking the warning banner («...لا تظهر على خريطة التطبيق») doesn't jump to the offending entries. | ⬜ |
| 89 | [F] Zoom / tablet / phone: list layout breaks — «إجراءات» column header disappears, columns shift. | ⬜ |
| 90 | [F] Sidebar notification counts: open the section and there's no badge/marker showing WHICH sub-item has the notifications. | ⬜ |
| 91 | [F] Sidebar bug: two items look selected at once (المجموعات الحوارية + طلبات التواصل) while only one is open. | ⬜ |

---

## How each point was fixed

(Filled in as each point is approved. Format: `### #N — title` → Found / Fixed / Files / OPOS id / verified how.)

### #3 — How the supervisor creates group chats (OPOS 96169) — ANSWERED, no code change
**Found:** it already exists. Dashboard → التواصل والدعم → **المجموعات الحوارية** (`/chat-groups`) → «مجموعة جديدة».
Two room types: **مجموعة فريق** (real names, staff + volunteers only) and **مجموعة بأسماء مستعارة**
(donors/beneficiaries/volunteers/staff, members see aliases like «مانح 1», contact details hidden).
- staff-only room → مجموعة فريق with staff ✅
- volunteers room → مجموعة فريق with volunteers ✅
- staff + donor + beneficiaries → مجموعة بأسماء مستعارة ✅
- khotba (suitor + girl + staff) → not created by hand: the suitor's request appears in الفعاليات → **طلبات الفعاليات**,
  staff press «موافقة» → a staff-supervised chat opens in **محادثات الفعاليات** (starts closed; فتح/أرشفة/حذف buttons) ✅
- adding the girl's **guardian** to that khotba chat → ❌ no button for it → part of #4 / addition.
**Verified:** local scratch backend (DB `r2scratch`, port 8095, seeded with `cmd/seed-test-users`) + dashboard on :5196;
created 3 example rooms + approved a khotba request. Screenshots: `round2_screens/03/`.

### #4 — Room control buttons (OPOS 96172) — ANSWERED, no code change yet
**Found:** all 5 exist on every group room (المجموعات الحوارية → open a room) and all 5 work (tested on local scratch):
إغلاق المحادثة = temporary pause (members read-only, «فتح المحادثة» re-opens) ✅ · أرشفة / إلغاء الأرشفة ✅ ·
حذف المحادثة (→ trash, password-confirmed) ✅ · إزالة beside each member ✅ · «إضافة عضو» form under the members ✅.
**Gap:** the khotba chat (محادثات الفعاليات) has open/archive/delete but NO add/remove member → the girl's guardian
can't be added. New capability → treated as addition (deferred, proposal-gated).
**Clutter seen on this screen (proposed small fixes, waiting owner):** (a) pause state is written twice (line under the
buttons + green banner); (b) member aliases show in English inside the Arabic UI ("Donor 1", "Member 1");
(c) removing a member asks twice (confirm dialog, then password dialog).
Screenshots: `round2_screens/04/`.

