# Tawazzn — Round 2 client notes: fix report

Source: client PDF «الملاحظات» (20 pages, 2026-10-16). Every point in PDF order.
Legend: ✅ fixed & verified · ⏳ waiting (new feature — needs the original scope) · ❌ not fixed (reason given) · ℹ️ info only

All testing on a local copy (local server + test database + iPhone simulator). Nothing was changed on the live system.
Code: branch `round2-fixes` (not pushed / not deployed yet).

## 1. **Simplify & de-clutter UI.** Repeated details, long explanations across sections; donation takes up to 6 screens. Shorten everything, make donation fast/easy with many payment options. (Umbrella — concrete work is #47–#55.)

**Status:** ⬜ not done yet


## 2. **Where are attendance / activity details in app + dashboard?** (a) daily attendance/leave log for staff & volunteers; (b) participant registration form per activity/campaign; (c) aid-delivery documentation — volunteer/staff uploads report + proof (photo or signature).

**Status:** ⏳ Waiting — new feature, needs scope

What exists today (partial):
- Attendance: volunteers check in / check out per mission (time + GPS + photo) → dashboard **لوحة المتطوعين**. No daily attendance table; nothing for staff.
- Participants: only volunteer sign-ups per mission (**تسجيلات المهام**). No beneficiary/participant list per activity or campaign.
- Aid proof: **إيصالات المساعدات** (dashboard only). No photo/signature upload from the app.

The missing parts are new features → waiting for the scope.

![](round2_screens/02/1_volunteer_checkin_checkout.jpg)
![](round2_screens/02/2_aid_receipts.jpg)

## 3. **Group chats management:** how does the supervisor create custom group rooms from the dashboard: staff-only, volunteers-only, staff + donor + some beneficiaries, staff + suitor + fiancée (+ maybe her guardian).

**Status:** ✅ Already exists — no change needed

Dashboard → التواصل والدعم → **المجموعات الحوارية** → «مجموعة جديدة». Two room types:
- **مجموعة فريق** (real names) — staff-only room ✅, volunteers room ✅
- **مجموعة بأسماء مستعارة** (aliases, contact details hidden) — staff + donor + beneficiaries ✅
- Khotba (suitor + girl + staff): request arrives in الفعاليات → **طلبات الفعاليات** → «موافقة» → supervised chat opens in **محادثات الفعاليات** ✅
- Adding the girl's guardian to the khotba chat: not possible today → ⏳ new feature (see #4).

![](round2_screens/03/1_create_dialog_team.jpg)
![](round2_screens/03/2_groups_list.jpg)
![](round2_screens/03/3_event_request_approve.jpg)
![](round2_screens/03/4_event_chat_opened.jpg)

## 4. **Room control buttons for supervisor:** temporary pause, archive, delete, kick a member, add a new member.

**Status:** ✅ Already existed — tested — plus 3 clean-ups

All 5 buttons are on every room (المجموعات الحوارية → open a room) and all 5 work:
إغلاق المحادثة = temporary pause (members read only; «فتح المحادثة» reopens) · أرشفة · حذف المحادثة · إزالة (per member) · «إضافة عضو».

![](round2_screens/04/1_room_controls.jpg)
![](round2_screens/04/2_paused.jpg)
![](round2_screens/04/3_member_added.jpg)
![](round2_screens/04/5_archived.jpg)
![](round2_screens/04/6_deleted.jpg)

**Clean-ups done on this page (simpler, less repetition):**
1. The "paused" state was written twice (line under the buttons + a green box above the message field) → now shown once.
2. Member nicknames showed in English inside the Arabic dashboard ("Donor 1", "Member 1") → now «مانح 1»، «مستحق 1»، «عضو 1».
3. Removing a member asked twice (a confirm box, then a password box) → one box with a short sentence + the password.

![](round2_screens/04/8_after_status_once_arabic_aliases.png)
![](round2_screens/04/9_after_single_remove_dialog.jpg)
![](round2_screens/04/10_after_member_removed.jpg)

**Note:** the khotba chat (محادثات الفعاليات) has open / archive / delete but no add / remove member, so the girl's guardian can't be added → ⏳ new feature, waiting for scope.

Files: `admin-web/src/lib/groupAlias.ts` (new), `components/chatGroups/GroupRoster.tsx`, `GroupMessages.tsx`, `GroupComposer.tsx`, `components/AskDialog.tsx`, `lib/dialogs.tsx`, `lib/chatGroupsApi.ts`, locales ar/en; tests updated (40/40 pass).

## 5. **Calling feature:** voice/video calls in all private + group chats for all roles (staff, volunteer, donor, beneficiary, general user, events/khotba), supervisor can switch calling on/off entirely.

**Status:** ⏳ Waiting — new feature, needs scope


## 6. **Simplify staff/volunteer messaging:** remove friction; once an account is activated + approved in the dashboard, enable direct instant messaging; pause/archive/delete stays with admin.

**Status:** ✅ Already possible — made simpler

- A volunteer (once approved) messages the team instantly: Messages → «التواصل مع الدعم» now opens the volunteers' support chat in **one tap** (no popup, no explanation screens — see #56).
- Staff talk to each other in the dashboard under «محادثة الموظفين».
- Staff can put volunteers and staff in a team room (المجموعات الحوارية → «مجموعة فريق», see #3), and pause / archive / delete stay with the admin (see #4).

**Note:** volunteers messaging *each other* directly (without staff) is not open — that was a deliberate earlier decision (members only talk through supervised rooms). If the client wants that, it is a new feature → ask first.

![](round2_screens/56-57/after_volunteer_one_tap_chat.png)

## 7. **In-app logo** looks like a question mark — add effect/shadow so it reads as a logo.

**Status:** ✅ Fixed

The logo next to the page title («لوحة التحكم», «لوحة المتطوع», المتجر, …) was the bare mark on the dark bar — it read like a question mark. It now sits on a small **white disc with a soft shadow**, the same look as the launch/welcome logo, so it clearly reads as the Tawazzn logo. It lines up with the edge of the cards below it.

Before → After:

![](round2_screens/07/before.png)
![](round2_screens/07/after.png)

## 8. **App font is bad:** letters overlap, esp. words with «لا» and joined letters → words read wrong.

**Status:** ✅ Fixed

**Found — two causes:**
1. The app used **Noto Kufi Arabic**, a geometric "Kufi" style; in bold, «لا» and some joined letters look like other letters.
2. Many texts had **letter-spacing** (designed for English). Negative spacing pushes Arabic letters into each other (the overlap the client saw); positive spacing pulls joined letters apart.

**Fix:**
- Switched the app's Arabic/Kurdish font to **Noto Sans Arabic** — the clean, highly readable member of the same font family, with all Kurdish letters (ڕ ڵ ۆ ێ ڤ گ) and real bold weights.
- Arabic text now never gets letter-spacing anywhere in the app (theme + 20 hard-coded places removed).

Before (left) → After (right):

![](round2_screens/08/before_after_font.png)

## 9. (Info only) Images: some have red markers; some notes are explained in text without a picture.

**Status:** ℹ️ info only


## 10. **In-App Admin Panel** (staff manage from the phone, isolated permissions): Khotba staff → khotba files, approvals, their chats only; Volunteers staff → volunteers, activities, chats, attendance; Store staff → products + purchase requests; Beneficiaries staff → beneficiary data, approvals, forms, their messages.

**Status:** ⏳ Waiting — new feature, needs scope


## 11. **Saved accounts + switching:** on logout keep accounts in secure local storage; login screen lists previously-used accounts (photo, name, phone); one tap switches without password/OTP; button «تسجيل دخول بحساب آخر» under the list. (Same as page 3 intro.)

**Status:** ⏳ Waiting — new feature, needs scope


## 12. **Verification architecture:** first account creation → Step 1 phone OTP, Step 2 email verification (link/code). After both, email is the default confirmation method for later operations (new-device login, recovery) — free. Settings option to switch back to phone.

**Status:** ⏳ Waiting — new feature, needs scope


## 13. Image resize/crop enabled in ALL sections, not only the identity section.

**Status:** ✅ Already in place (checked in the code)

Every photo the app asks for — personal photo, ID card front/back, residence card, ration card, extra documents, events/khotba profile photos — goes through the same picker that first asks «التقاط صورة / اختيار من المعرض» and then opens the **crop / resize** screen (done in the previous round). There is no upload left that skips it.
The one deliberate exception is the volunteer's **check-in photo** at a mission: it is proof of presence taken live with the camera, so it must not be edited.

## 14. Extra-files field (attach files, documents, other photos) in registration for all roles (donor, volunteer, khotba, beneficiary, general user) — exists? With image resize.

**Status:** ⏳ Waiting — new feature, needs scope


## 15. Fix slowness during registration.

**Status:** ❌ Not reproduced on the local test copy — needs a timing on the live system

On the local copy every registration request answers in a few milliseconds and the form opens instantly, so the slowness is not in the app's own code path. Likely causes on the live system: the live server's response time / region, or large photos on a slow connection (photos are already resized to 1600px before upload).
Next step: time the registration screens against the live server (read-only) or with the client's phone to find which step is slow.

## 16. Fix bug that stops a VISITOR from messaging support and viewing sections (humanitarian, store, city guide, khotba posts).

**Status:** ✅ Fixed (app + server)

**Problem found:** a visitor (الدخول كزائر) was blocked in two layers:
- Home showed only a "sign in" card — no campaigns, no categories, no our-work.
- City guide was blocked («يتطلب عرض دليل المدينة إكمال التسجيل») by the app **and** the server.
- Support chat and support tickets were refused by the server and the app asked to sign in first.

**Fix:**
- Visitor home now shows the real public content: browse by category, featured campaigns, latest news / our work (the store and the khotba posts were already open).
- City guide opens for visitors (viewing only — adding a place still needs an account).
- Visitors can open a support chat and send support tickets.
- Safety kept: a visitor can only talk in a **support** chat with **staff** — every other chat stays closed to visitors (new server check + tests).
- Small clean-ups seen on the way: the visitor's name shows as «زائر» (was "Guest" in English); the 👋 emoji was removed from the empty chat text.

Before → After:

![](round2_screens/16-19/before_guest_home.png)
![](round2_screens/16-19/after_guest_home.png)
![](round2_screens/16-19/before_city_guide_blocked.png)
![](round2_screens/16-19/after_city_guide_open.png)
![](round2_screens/16-19/after_guest_support_chat.png)

**Note:** on the local test copy the city-guide map shows an «API KEY REQUIRED» watermark from the map provider (CartoDB). To check on the live app; if it shows there too, the map needs a provider key.

## 17. Visitor «ترقية الحساب»: error when filling data, English message "Failed to send verification code".

**Status:** ✅ Fixed

**Problem found:** the «ترقية الحساب» screen forced a *real* SMS request on its own (sign-up doesn't), so when SMS sending wasn't available it failed and showed the server's raw English text "Failed to send verification code".
**Fix:** the upgrade screen now asks for the code the same way as sign-up, so the server chooses how to deliver it. If sending ever fails, the user sees one Arabic sentence («تعذّر إرسال رمز التحقق.») — never server English. The code step now uses the same 6 boxes as sign-up. Tested: code sent → verified → the account continues to the registration form (the placeholder name "Guest" is no longer pre-filled).

![](round2_screens/16-19/after_upgrade_code_sent.png)
![](round2_screens/16-19/after_upgrade_code_boxes.png)

## 18. Upgrade screen bottom send button is black, its text invisible.

**Status:** ✅ Fixed

The send button used the text colour as its fill with a dark-navy label (black button, unreadable text). It now uses the app's green button with dark text — readable in light and dark mode. Same for the «تحقّق وتابع» button.

![](round2_screens/16-19/after_upgrade_phone.png)

## 19. Shorten long hint («سنرسل لك رمزاً لمرة واحدة...») → «يرجى تأكيد رقم هاتفك لترقية الحساب».

**Status:** ✅ Fixed

Long hint («سنرسل لك رمزاً لمرة واحدة…») → **«يرجى تأكيد رقم هاتفك لترقية الحساب»**.

![](round2_screens/16-19/after_upgrade_phone.png)

## 20. Logo vs dark olive circle out of proportion → shrink the circle so the logo stands out; add shadow / light 3D.

**Status:** ✅ Fixed

The dark ring around the logo was too big. Ring 168 → 136, logo 116 → 120 on a white disc with a soft shadow, so the logo stands out. The same logo is now used on the launch screen too (see #24).

Before → After:

![](round2_screens/20-24/before_welcome.png)
![](round2_screens/20-24/after_welcome.png)

## 21. Tagline «توازن واستقرار من أجل حياة أفضل!» (2 lines) → «توازن لمستقبل أفضل», centered, one line.

**Status:** ✅ Fixed

«توازن واستقرار من أجل حياة أفضل!» (two lines, start-aligned) → «توازن لمستقبل أفضل», centred, always one line.
Also removed the small «توازن» badge that sat right above it (the name was written twice in a row).
Kurdish texts were left as they are (no Kurdish written by us — waiting for the client's translator).

![](round2_screens/20-24/after_welcome.png)

## 22. Bottom text «سجل الدخول أو أنشئ حساباً برقم هاتفك» is at the very bottom, right-aligned → centered, raised a bit, font slightly bigger.

**Status:** ✅ Fixed

«سجّل الدخول أو أنشئ حساباً برقم هاتفك» is now centred, raised off the bottom edge, and one size larger.

![](round2_screens/20-24/after_welcome.png)

## 23. Welcome screen scrolls → disable scroll, elements fixed.

**Status:** ✅ Fixed

The welcome screen no longer scrolls — every element is fixed in place (tested by swiping up/down).

## 24. Circular logo overlaps inside the dark square: remove the thin green circular lines around the square; enlarge inner logo slightly (not to square size); add light shadow / 3D.

**Status:** ✅ Fixed

**Problem found:** at app start the logo appeared **three times in three different styles**: the phone's white launch screen, then an animated splash (logo inside a dark square with thin green arcs — the one in the client's picture), then the welcome screen.

**Fix:**
- The animated splash (square, green arcs, loading bar, 2.4 s wait) is removed. The app now shows **one** launch screen and goes straight on.
- The phone's own launch screen (iOS + Android, light + dark) now draws the **same** logo as the welcome screen, on the app's own background colour.
- The logo is at **exactly the same spot** on the launch screen and the welcome screen (measured: same pixels), so only the text and button fade in around it — the logo itself never moves.

Launch screen → welcome screen:

![](round2_screens/20-24/after_launch.png)
![](round2_screens/20-24/after_welcome.png)

Video of the hand-over: `round2_screens/20-24/launch.mp4`

**Note:** the iPhone simulator kept an old cached launch picture for the first frame; on a fresh install on a real phone the new one shows.

## 25. Login screen scrolls → disable scroll, elements fixed (screenshots show «جديد هنا؟ أنشئ حساباً» moving).

**Status:** ✅ Fixed

The sign-in screens (login, set password, upgrade account) no longer scroll or bounce when the form fits on screen — everything stays in place (tested: swiping does nothing). They only move if the keyboard actually covers a field, so no field can get hidden.

![](round2_screens/25-26/login.png)

## 26. Phone field accepts up to 15 digits → per-country rules; Iraq (+964): auto-trim a leading 0, keep the 10 digits; max length per country.

**Status:** ✅ Fixed

The phone field now follows the selected country:
- Iraq (+964): a leading 0 is removed automatically and only 10 digits are accepted. Typing «0770123456789…» gives «770 123 4567».
- Every other country has its own maximum length.
- The error message is now «أدخل 10 أرقام».
Same rule on the login screen and the «ترقية الحساب» screen.

![](round2_screens/25-26/after_phone_0_removed_10_digits.png)

## 27. Three long repetitive texts at the top (circled) → delete all, replace with ONE short centered phrase.

**Status:** ✅ Fixed

The three lines at the top («اختر كلمة مرور» + «تم التحقق من رقمك. ستسجّل الدخول بكلمة المرور هذه من الآن فصاعداً.» + «تعيين كلمة المرور للرقم …») are gone. One short centred line instead: **«أنشئ كلمة مرور لحسابك»**.
Also removed the «العودة إلى تسجيل الدخول» link at the bottom (the back arrow at the top already does that), and the form now starts at the top of the screen instead of floating in the middle.

Before → After:

![](round2_screens/27-28/before.png)
![](round2_screens/27-28/after.png)

## 28. Hint «8 أحرف على الأقل» → «الحد الأدنى 8 خانات تشمل أحرفاً وأرقاماً», centered.

**Status:** ✅ Fixed

Hint under the password: «8 أحرف على الأقل» → **«الحد الأدنى 8 خانات تشمل أحرفاً وأرقاماً»**, centred.
Because the hint now says "letters and numbers", the app also checks it: a password with only letters (or only numbers) is refused with «استخدم أحرفاً وأرقاماً معاً.»

![](round2_screens/27-28/after.png)
![](round2_screens/27-28/after_rule_enforced.png)

## 29. «أدخل الرمز المكون من 6 ارقام المرسل الى 0770*******» → «أدخل رمز التحقق المرسل إلى», phone number on the line below, centered.

**Status:** ✅ Fixed

«أدخل الرمز المكون من 6 أرقام المرسل إلى 0770…» → **«أدخل رمز التحقق المرسل إلى»**, with the phone number on its own line underneath, both centred.

![](round2_screens/29-33/after_otp_boxes_timer.png)

## 30. Red hint long, typos, side-aligned → centered: «الرقم مسجل بالفعل، يرجى العودة لتسجيل الدخول».

**Status:** ✅ Fixed

The red message for a number that already has an account is now **«الرقم مسجل بالفعل، يرجى العودة لتسجيل الدخول»**, centred.

![](round2_screens/29-33/after_already_registered.png)

## 31. OTP input → 6 separate small boxes, one digit each, auto-advance; SMS auto-fill; paste support (code copied from WhatsApp/SMS).

**Status:** ✅ Fixed

- The code field is now **6 separate boxes**, one digit each.
- **SMS auto-fill**: the phone offers the code from the incoming SMS above the keyboard.
- **Paste**: a code copied from WhatsApp/SMS can be pasted (long-press → Paste).
- The code is checked **automatically** as soon as the 6th digit is entered — no button press needed.

![](round2_screens/29-33/after_otp_boxes_timer.png)

## 32. Keep main green button, rename to «متابعة تسجيل الدخول»; delete the duplicate «العودة إلى تسجيل الدخول» link.

**Status:** ✅ Fixed

When the number is already registered there is now **one** green button, renamed **«متابعة تسجيل الدخول»**. The second link «العودة إلى تسجيل الدخول» underneath it (same action) was removed.

![](round2_screens/29-33/after_already_registered.png)

## 33. Resend countdown «إعادة إرسال الرمز خلال 00:59»; escalating cooldown on repeated requests (e.g. ½ h, 1 h, 1 day) against spam.

**Status:** ✅ Fixed

- Resend now counts down as **«إعادة إرسال الرمز خلال 00:59»** (and the extra sentence under it was removed).
- Repeated requests are already blocked by the server with growing waits: after too many requests the number is locked for **2 hours**, then **6 hours**, then **24 hours** (the app shows the wait).

![](round2_screens/29-33/after_otp_boxes_timer.png)

**Also removed:** a developer switch at the bottom of the sign-up screen («طريقة الإرسال واتساب / رسالة نصية · رمز تجريبي») was visible to users — it now only appears in developer builds.

## 34. Top hint «اخبرنا عن نفسك ليتمكن المشرف من مراجعة حسابك» → «يرجى إكمال البيانات التالية لإنشاء حسابك», centered.

**Status:** ✅ Fixed

«أخبرنا عن نفسك ليتمكن المشرف من مراجعة حسابك.» → **«يرجى إكمال البيانات التالية لإنشاء حسابك»**, centred.

Before → After:

![](round2_screens/34-38/before_top.png)
![](round2_screens/34-38/after_top.png)

## 35. Data duplication: role picker = dropdown, **general user** is the default; picking volunteer/beneficiary/donor shows that role's fields; data already typed is reused (no re-entry); add photo + email to general registration (and dashboard); same required/optional rule system.

**Status:** ✅ Partly fixed · ⏳ "general user" part waiting for scope

**Done:**
- The three big role cards (مانح / مستحق / متطوع) are now **one dropdown** «نوع الحساب».
- Choosing a role only opens that role's extra section underneath. Everything already typed (name, date of birth, address, gender, city, job) **stays filled** — nothing has to be typed again when the role is changed.

![](round2_screens/34-38/after_role_dropdown.png)
![](round2_screens/34-38/after_volunteer_selected.png)

**Waiting (new feature):** a fourth account type **«مستخدم عام»** as the default does not exist in the system today — the server only accepts donor / beneficiary / volunteer. Adding it means a new account type in the app, the server and the dashboard (this is also #37 and #38). Waiting for the original scope before building it.

## 36. Remove every «(اختياري)»; one sentence at the top: «الحقول المصحوبة بعلامة حمراء إجبارية».

**Status:** ✅ Fixed

The word «(اختياري)» was removed from every registration field (91 texts, in all four languages).
One line at the top instead: **«\* الحقول المصحوبة بعلامة حمراء إجبارية»** — the red \* next to a field already marks what must be filled.

![](round2_screens/34-38/after_top.png)

## 37. General user rights: browse everything (humanitarian, store, city guide, khotba), message support. Blocked: commenting in khotba, applying to khotba requests, requesting aid, joining volunteering; no volunteer notifications — until «تطوير حسابه» (upgrade + choose role).

**Status:** ⏳ Waiting — needs the new «مستخدم عام» account type (see #35)

The rights the client describes (browse everything, message support, but no khotba comments / aid requests / volunteering until the account is upgraded) belong to a "general user" account type that does not exist yet. Waiting for the scope.

## 38. Dashboard: separate section «المستخدم العام» (or better name) with admin controls (edit data, add user) matching the registration fields.

**Status:** ⏳ Waiting — needs the new «مستخدم عام» account type (see #35)

A dashboard section for general users only makes sense once that account type exists. (The general list of all accounts is already under المستخدمون; #81 covers separating the lists per role.)

## 39. Filter tiles (الكل / غير مقروء / مقروء) unequal; «غير مقروء» wraps badly → equal size, one line or two stacked centered words.

**Status:** ✅ Fixed

The three tiles (الكل / غير مقروء / مقروء) are now the same size, with the count on top and a one-line label below, both centred.
They are also the filter itself: tap a tile to show that list (the selected tile is outlined). The duplicate row of All / Unread / Read buttons under them was removed.

![](round2_screens/39-43/after-all-newest-first.png)

## 40. «مسح 2 مقروءة» button tiny and off to the side → bigger icon + text, centered.

**Status:** ✅ Fixed

«مسح N مقروءة» is now a full button in the centre, with a larger icon and text (see the screenshot under #39).

## 41. Category/Type dropdowns change look when a value is picked; no linkage → stable design; Type list filtered by chosen Category.

**Status:** ✅ Fixed

- Both dropdowns keep the same look before and after a value is picked: the label always sits above the field.
- The Type list now depends on the chosen Category: it only offers types that exist in that category. If the category changes, a type that no longer fits is reset to «كل الأنواع».

Example: Category «دفع» → the Type list shows only «شحن المحفظة».

![](round2_screens/39-43/after-linked-dropdowns.png)

## 42. Notifications in random order → newest first by date+time.

**Status:** ✅ Fixed

The list is sorted strictly by date and time, newest first. Before, urgent and payment notifications were pinned to the top, which made the order look random.
Screenshot under #39: 5 minutes → 2 hours → 1 day.

## 43. Where is "mark all as read"?

**Status:** ✅ Fixed

The button already existed in the green box at the top, but its label was just «تحديد الكل». It now reads **«تحديد الكل كمقروء»**. It only appears when there are unread notifications (screenshot under #39).

## 44. App: result → action link (e.g. «اكفل عائلة هذا الشهر» → opens donation section); share result instantly; real finger-scratch effect instead of tap-to-reveal video.

**Status:** ⏳ Waiting — new feature, needs scope


## 45. Dashboard: manage wheel slot texts, scratch prizes/texts, and link each text to an app section (destination).

**Status:** ⏳ Waiting — new feature, needs scope


## 46. Visual quality: wheel/scratch graphics look amateur → modern UI matching brand + smooth animations.

**Status:** ⬜ not done yet


## 47. Donation in 2 steps max. Step 1: «قدم مساهمة» → short clean screen with 4 options: الدفع الإلكتروني / تحويل رصيد / التسليم النقدي المباشر / المساهمات العينية.

**Status:** ⬜ not done yet


## 48. Step 2 — e-payment: amount, card type (Visa, Master, FIB) → straight to gateway; IQD default, other currencies manual; notes.

**Status:** ⬜ not done yet


## 49. Step 2 — balance transfer, ONE fixed page, two toggles at top «تعبئة / تحويل مباشر» vs «إرسال كرت». Transfer: network (Asia, Zain, Korek), amount, org phone with copy button, screenshot attach, notes. Card: network, photograph card with camera, serial field, value, notes. Fixed bottom: attach + notes + «تأكيد المساهمة». Toggle switches fields in place. Phone/address auto-filled, editable.

**Status:** ⬜ not done yet


## 50. Step 2 — direct cash: amount, address, phone, optional visit-time note; phone/address auto-filled, editable.

**Status:** ⬜ not done yet


## 51. Step 2 — in-kind: material type, phone, address (auto-filled, editable), optional photo of the items.

**Status:** ⬜ not done yet


## 52. Every path ends with one clear bottom button «تأكيد المساهمة» that sends straight to the dashboard.

**Status:** ⬜ not done yet


## 53. General: unclear labels (تبرع الان / عرض الكل); repeated confirmation screens; long explanation text under every option → remove, short labels (1–2 words per button).

**Status:** ⬜ not done yet


## 54. After sending a contribution it says "sent & pending" but NO donation/support shows up → final submission mechanism broken, fix.

**Status:** ⬜ not done yet


## 55. Remove donation type (عام / زكاة / صدقة) and «التبرع لمؤسسة»; replace with one fixed line: «تنويه: يتم استقطاع نسبة بسيطة من التبرعات لتغطية التكاليف التشغيلية وضمان استمرار عمل المشروع.»

**Status:** ⬜ not done yet


## 56. Remove explanation screens/popups (مساعد الدعم / التواصل مع الدعم / إرسال تذكرة) → section becomes fast live chat.

**Status:** ✅ Fixed

Removed the explanation text everywhere in Messages / support:
- Page line «الدردشة مع أصحاب الحملات والمانحين. الدعم متضمن.» — removed.
- The description under «مساعد الدعم», «التواصل مع الدعم», «إرسال طلب دعم», «طلبات التواصل الخاصة بي» — removed (titles only).
- The long empty-state paragraph → «تظهر محادثاتك هنا.»
- The «أي قسم دعم؟» popup: explanation line and the description under each section removed.
- A **volunteer** is no longer asked which section at all — «التواصل مع الدعم» opens the volunteers' support chat **directly in one tap**, and the support form has the section already chosen.
- The 👋 emoji was removed from the empty chat («لا توجد رسائل بعد»).

Before → After:

![](round2_screens/56-57/before_messages.png)
![](round2_screens/56-57/after_messages.png)
![](round2_screens/56-57/before_section_popup.png)
![](round2_screens/56-57/after_volunteer_one_tap_chat.png)

## 57. Arabize system texts (e.g. "Event service request: Hall booking") → Modern Standard Arabic.

**Status:** ✅ Fixed

The English ticket text came from the app itself: the events-services request built "Event service request: Hall booking / Name: … / Phone: …". It now writes Arabic: **«طلب خدمة فعالية: …»**, «الاسم:», «الهاتف:», and the ticket is routed to the events support desk. (Old tickets already saved keep their old text.)
Also: chat sender "Guest" now shows as «زائر»; upgrade-screen errors are Arabic (see #17).

## 58. Staff & volunteers: direct instant messaging, no friction. (↪ with #6)

**Status:** ✅ Same as #6 (merged)

See #6: volunteers reach staff in one tap; staff ↔ staff via «محادثة الموظفين»; team rooms for staff + volunteers.

## 59. Beneficiaries / khotba / general user / visitor: start with a support ticket; staff replies; staff can convert the ticket into a chat with specific people; can close it; ticket feature stays.

**Status:** ✅ Partly exists · ⏳ "turn a ticket into a chat" waiting for scope

What works today:
- Beneficiaries / visitors / anyone can open a support **ticket** (and visitors now too — #16), and staff answer it in the dashboard (الدعم → Reply). Staff can mark it open / in progress / resolved / **closed**.
- Staff can open a supervised room with specific people (المجموعات الحوارية, #3).

Missing (new feature): a button on the ticket that converts it directly into a chat with chosen people. Waiting for scope.

## 60. Encrypted group chats: aid section (staff + donor(s)/beneficiary); khotba (staff + suitor + girl + guardian). Opens only with staff approval; no personal data shown (numbers, real names); files/photos only by staff; staff can pause / archive / delete. (Related #3, #4)

**Status:** ✅ Mostly exists · ⏳ 3 parts waiting for scope

Exists and checked in the code:
- Rooms between donor / beneficiary are opened **only by staff** (connect request → staff approval, or staff creates the room).
- Members see only a nickname («مانح 1», «مستحق 1») — **no real names, no phone numbers**; a message containing a phone number or email is **blocked** automatically and logged.
- Staff can pause / archive / delete (#4).

Not in the system yet (new features → waiting for scope):
1. Message **encryption** at rest (messages are stored as normal text today).
2. Sending **files / photos** in chats (today nobody can — text only; the client wants staff only).
3. Adding the girl's **guardian** to the khotba chat (see #3/#4).

## 61. Staff chat controls: **temporary pause** (client can still send, staff sees it, no read receipt until reply); **full stop** (lock, client can't send); admin buttons Archive / Block / Delete. (Related #4)

**Status:** ✅ Exists (tested in #4) · ⏳ "Block" waiting for scope

- **Full stop**: «إغلاق المحادثة» — members can only read until staff reopen it. ✅
- **Temporary pause where the client can still write**: simply leave the chat open — members never see "read" marks (the app has no read receipts for members), so staff can read without the client knowing. ✅
- **Archive** ✅ · **Delete** ✅ (moves to trash, password-confirmed).
- **Block** a person from a chat: not as a separate button today (staff can remove the member — «إزالة», #4 — or suspend the account). A dedicated "block" is a new feature → waiting for scope.

## 62. City guide «إضافة نشاط»: no photo option; why lat/long fields (just attach GPS); submit button sits under the phone nav buttons → move it up.

**Status:** ⬜ not done yet


## 63. Profile: logout button at the very bottom collides with phone nav buttons → move up.

**Status:** ⬜ not done yet


## 64. «أثرنا» section doesn't work — where are its data/photos/details edited?

**Status:** ⬜ not done yet


## 65. Store: selecting a product froze the page, cancel didn't respond, logout/login didn't fix; cart only appeared after several tries.

**Status:** ⬜ not done yet


## 66. Store: no payment options, only cash? (needs e-payment).

**Status:** ⏳ Waiting — new feature, needs scope


## 67. **CRITICAL wallet hole:** app tops up the wallet with no real payment and no staff approval → block auto top-up; real gateway OR pending until dashboard approval; fix balance reading (shows 0) across wallet screens.

**Status:** ⬜ not done yet


## 68. Home → browse by category: campaign details cut off → give the details more space.

**Status:** ⬜ not done yet


## 69. Home: «مشاركتي» opens a page titled «سجلي» — naming mistake?; shorten the circled phrases to one line, remove extra details; «استعلام بالرمز التعريفي» long unclear explanation — is this lookup approach right at all?

**Status:** ⬜ not done yet


## 70. Rename «قسم الفعاليات» → «إدارة ملف التوافق الأسري».

**Status:** ⬜ not done yet


## 71. Inside it, rename «ملفي الشخصي» → «بيانات الملف الأسري».

**Status:** ⬜ not done yet


## 72. «خدمات الفعاليات» → real store: subcategories (halls, photographers, decor), each with providers, photos (e.g. 6 per hall), price; cart; e-payment; booking/direct purchase.

**Status:** ⏳ Waiting — new feature, needs scope


## 73. Public posting: today only targeted posts to one person → allow public posts (e.g. "looking for specs X") others can view, comment on, and contact the owner.

**Status:** ⏳ Waiting — new feature, needs scope


## 74. Export button + date/time column in EVERY section/table (screenshots: الشركاء has no date/time; إيصالات المساعدات has no export and no date/time).

**Status:** ⬜ not done yet


## 75. Sticky table header in every section. (Round-1 #49021 did this — re-verify all pages.)

**Status:** ⬜ not done yet


## 76. Unify the top bar design across all sections.

**Status:** ⬜ not done yet


## 77. «حذف الحساب» moves INTO the user edit page, not the outside dropdown.

**Status:** ⬜ not done yet


## 78. Account data parity: same fields/options when creating an account in the app, in the dashboard, or editing.

**Status:** ⬜ not done yet


## 79. Change-password in dashboard (edit user modal, «كلمة مرور جديدة») doesn't work → fix.

**Status:** ⬜ not done yet


## 80. Supervisor permissions: where to assign roles to dashboard staff with per-section permissions?

**Status:** ⬜ not done yet


## 81. Full separation of account lists: Volunteers / Donors / Beneficiaries / General users / Visitors / Khotba & marriage (family files) / Staff — each section shows only its roles.

**Status:** ⬜ not done yet


## 82. «تحديد الكل» (Select All) checkbox at the top of every table → bulk delete old test data.

**Status:** ⬜ not done yet


## 83. Store (dashboard + app) judged weak by someone who runs a real store app → needs clear, easy, complete sections.

**Status:** ⏳ Waiting — new feature, needs scope


## 84. Align all toolbar input fields on ONE horizontal row in every section (screenshots: لوحة التحكم, المستحقون, اشتراكات الفعاليات, المتطوعون, طلبات التواصل, التعليقات, دليل المدينة, الموظفون).

**Status:** ⬜ not done yet


## 85. Create-notification language tabs (EN / عربي / سوراني / باديني) don't translate anything; plus a language switch at the top — what are these for?

**Status:** ⬜ not done yet


## 86. Dashboard font is bad too (e.g. «المدن والأقضية والنواحي», «الأقضية») — letters hard to read.

**Status:** ✅ Fixed

The dashboard used «Kurdfont» — a single-weight font, so every bold heading was a fake bold that smudged the letters («المدن والأقضية والنواحي», «الأقضية»). It now uses the same **Noto Sans Arabic** as the app (real weights), and letter-spacing is forced to zero for all Arabic text in the dashboard.

![](round2_screens/08/after_dashboard_font.jpg)

## 87. Change password not working in edit account (↪ #79).

**Status:** ⬜ not done yet


## 88. City guide: clicking the warning banner («...لا تظهر على خريطة التطبيق») doesn't jump to the offending entries.

**Status:** ⬜ not done yet


## 89. Zoom / tablet / phone: list layout breaks — «إجراءات» column header disappears, columns shift.

**Status:** ⬜ not done yet


## 90. Sidebar notification counts: open the section and there's no badge/marker showing WHICH sub-item has the notifications.

**Status:** ⬜ not done yet


## 91. Sidebar bug: two items look selected at once (المجموعات الحوارية + طلبات التواصل) while only one is open.

**Status:** ⬜ not done yet

