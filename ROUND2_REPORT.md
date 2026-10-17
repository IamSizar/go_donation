# Tawazzn — Round 2 client notes: fix report

Source: client PDF «الملاحظات» (20 pages, 2026-10-16). Every point in PDF order.
Legend: ✅ fixed · ➕ addition outside the original scope (postponed) · ℹ️ information

We tested all changes on a separate test copy. Nothing was changed on the live system.

## 1. **Simplify & de-clutter UI.** Repeated details, long explanations across sections; donation takes up to 6 screens. Shorten everything, make donation fast/easy with many payment options.

**Status:** ✅ Fixed (general summary)

**Fixed:** this is the general point. The de-cluttering was done screen by screen in the other points of this document: shorter titles, duplicate and long explanatory sentences removed, cleaner cards and sheets, a tidier profile menu and dashboard, plus a pass over every screen touched for cut-off words and misaligned text. The donation flow is now a single organized screen with all its fields kept.

## 2. **Where are attendance / activity details in app + dashboard?** (a) daily attendance/leave log for staff & volunteers; (b) participant registration form per activity/campaign; (c) aid-delivery documentation — volunteer/staff uploads report + proof (photo or signature).

**Status:** ✅ Already available — where to find it

**Attendance (volunteers):** a volunteer assigned to a mission checks in and out from the app; each check records the time, the location (GPS) and a live photo. Staff see it in the dashboard under **لوحة المتطوعين** (check-in / check-out proof on each sign-up).

**Participants:** volunteers register for each mission from the app; the list per mission is in the dashboard under **تسجيلات المهام**.

**Aid delivery documentation:** the dashboard has **إيصالات المساعدات**, where each aid receipt is recorded and kept.

**Not available yet:** an attendance log for staff members, and uploading the delivery proof (photo or signature) from the app by a volunteer or staff member.

![](round2_screens/02/hi_volunteer_board.png)
![](round2_screens/02/hi_receipts.png)

## 3. **Group chats management:** how does the supervisor create custom group rooms from the dashboard: staff-only, volunteers-only, staff + donor + some beneficiaries, staff + suitor + fiancée (+ maybe her guardian).

**Status:** ✅ Already exists — no change needed

Dashboard → التواصل والدعم → **المجموعات الحوارية** → «مجموعة جديدة». Two room types:
- **مجموعة فريق** (real names) — staff-only room ✅, volunteers room ✅
- **مجموعة بأسماء مستعارة** (aliases, contact details hidden) — staff + donor + beneficiaries ✅
- Khotba (suitor + girl + staff): request arrives in الفعاليات → **طلبات الفعاليات** → «موافقة» → supervised chat opens in **محادثات الفعاليات** ✅
- Adding the girl's guardian to the khotba chat: not possible today → a new feature, postponed.

![](round2_screens/03/1_create_dialog_team.jpg)
![](round2_screens/03/hi_groups_list.png)
![](round2_screens/03/3_event_request_approve.jpg)
![](round2_screens/03/4_event_chat_opened.jpg)

## 4. **Room control buttons for supervisor:** temporary pause, archive, delete, kick a member, add a new member.

**Status:** ✅ Already existed — we tested it — plus 3 clean-ups

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

**Note:** the khotba chat (محادثات الفعاليات) has open / archive / delete but no add / remove member, so the girl's guardian can't be added → a new feature, postponed.

## 5. **Calling feature:** voice/video calls in all private + group chats for all roles (staff, volunteer, donor, beneficiary, general user, events/khotba), supervisor can switch calling on/off entirely.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: no voice or video calls.

## 6. **Simplify staff/volunteer messaging:** remove friction; once an account is activated + approved in the dashboard, enable direct instant messaging; pause/archive/delete stays with admin.

**Status:** ✅ Already possible — made simpler

- A volunteer (once approved) messages the team instantly: Messages → «التواصل مع الدعم» now opens the volunteers' support chat in **one tap** (no popup, no explanation screens).
- Staff talk to each other in the dashboard under «محادثة الموظفين».
- Staff can put volunteers and staff in a team room (المجموعات الحوارية → «مجموعة فريق»), and pause / archive / delete stay with the admin.

**Note:** volunteers messaging *each other* directly (without staff) is not open, on purpose, to protect privacy (members only talk through supervised rooms). If you want it, it can be added as a new feature.

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
2. Many texts had **letter spacing** (designed for English). Negative spacing pushes Arabic letters into each other (the overlap you noticed); positive spacing pulls joined letters apart.

**Fix:**
- Switched the app's Arabic/Kurdish font to **Noto Sans Arabic** — the clean, highly readable member of the same font family, with all Kurdish letters (ڕ ڵ ۆ ێ ڤ گ) and real bold weights.
- Arabic text no longer gets any letter spacing anywhere in the app.

Before (left) → After (right):

![](round2_screens/08/before_after_font.png)

## 9. (Info only) Images: some have red markers; some notes are explained in text without a picture.

**Status:** ℹ️ For information

We used the markings you placed inside the images to find the screen each note refers to; for the notes explained in text only, we identified the screen from your description. No action is needed from you.

## 10. **In-App Admin Panel** (staff manage from the phone, isolated permissions): Khotba staff → khotba files, approvals, their chats only; Volunteers staff → volunteers, activities, chats, attendance; Store staff → products + purchase requests; Beneficiaries staff → beneficiary data, approvals, forms, their messages.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: the admin side is a web dashboard (§4, §19), not a panel inside the phone app.

## 11. **Saved accounts + switching:** on logout keep accounts in secure local storage; login screen lists previously-used accounts (photo, name, phone); one tap switches without password/OTP; button «تسجيل دخول بحساب آخر» under the list. (Same as page 3 intro.)

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: no saved accounts or account switching.

## 12. **Verification architecture:** first account creation → Step 1 phone OTP, Step 2 email verification (link/code). After both, email is the default confirmation method for later operations (new-device login, recovery) — free. Settings option to switch back to phone.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: no email-verification architecture.

## 13. Image resize/crop enabled in ALL sections, not only the identity section.

**Status:** ✅ Already in place (we checked)

Every photo the app asks for — personal photo, ID card front/back, residence card, ration card, extra documents, events/khotba profile photos — goes through the same picker that first asks «التقاط صورة / اختيار من المعرض» and then opens the **crop / resize** screen. We checked that no upload skips this step.
The one deliberate exception is the volunteer's **check-in photo** at a mission: it is proof of presence taken live with the camera, so it must not be edited.

## 14. Extra-files field (attach files, documents, other photos) in registration for all roles (donor, volunteer, khotba, beneficiary, general user) — exists? With image resize.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal for all roles (§7 covers supporting documents for beneficiaries only).

## 15. Fix slowness during registration.

**Status:** ✅ Improved

**Found:** on the local copy every registration request answers in a few ms, so the slowness can't be reproduced here. We found two real weak spots on a slow connection: the form opened with every field visible and then re-arranged itself when the field-rules answer arrived, and that request had no time limit (a stalled connection left the form in the wrong state forever). Photos are already uploaded in the background after the registration is saved, and resized before upload.

**Fixed:** the form now remembers the last field-rules answer on the device so it opens already correct, and the request gives up after 8 seconds instead of hanging.

## 16. Fix bug that stops a VISITOR from messaging support and viewing sections (humanitarian, store, city guide, khotba posts).

**Status:** ✅ Fixed (app + server)

**What we found:** the limited account (general user, formerly labelled "visitor / guest") was blocked in several places:
- Home showed only a «سجّل الدخول» card — no campaigns, no categories, no our-work.
- The city guide was blocked («يتطلب عرض دليل المدينة إكمال التسجيل») by the app **and** the server.
- Support chat and support tickets were refused by the server, and the app asked to sign in first.

**Fixed:**
- The general user's home now shows the real public content: browse by category, featured campaigns, latest news / our work (the store and the khotba posts were already open).
- The city guide opens for them (view only — adding a place needs a full account).
- They can open a support chat and send support tickets.
- Safety kept: they can only talk in a **support** chat with **staff**; every other chat stays closed to them.
- Small clean-ups: the name shows as «مستخدم عام», and the 👋 emoji was removed from the empty chat text.

Before / After:

![](round2_screens/16-19/before_guest_home.png)
![](round2_screens/16-19/after_guest_home.png)
![](round2_screens/16-19/before_city_guide_blocked.png)
![](round2_screens/16-19/after_city_guide_open.png)
![](round2_screens/16-19/after_guest_support_chat.png)

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

The dark ring around the logo was too big. Ring 168 → 136, logo 116 → 120 on a white disc with a soft shadow, so the logo stands out. The same logo is now used on the launch screen too.

Before → After:

![](round2_screens/20-24/before_welcome.png)
![](round2_screens/20-24/after_welcome.png)

## 21. Tagline «توازن واستقرار من أجل حياة أفضل!» (2 lines) → «توازن لمستقبل أفضل», centered, one line.

**Status:** ✅ Fixed

«توازن واستقرار من أجل حياة أفضل!» (two lines, start-aligned) → «توازن لمستقبل أفضل», centred, always one line.
Also removed the small «توازن» badge that sat right above it (the name was written twice in a row).
Kurdish texts were left as they are, pending your approved translation.

![](round2_screens/20-24/after_welcome.png)

## 22. Bottom text «سجل الدخول أو أنشئ حساباً برقم هاتفك» is at the very bottom, right-aligned → centered, raised a bit, font slightly bigger.

**Status:** ✅ Fixed

«سجّل الدخول أو أنشئ حساباً برقم هاتفك» is now centred, raised off the bottom edge, and one size larger.

![](round2_screens/20-24/after_welcome.png)

## 23. Welcome screen scrolls → disable scroll, elements fixed.

**Status:** ✅ Fixed

The welcome screen no longer scrolls — every element is fixed in place (we tested this by swiping up and down).

## 24. Circular logo overlaps inside the dark square: remove the thin green circular lines around the square; enlarge inner logo slightly (not to square size); add light shadow / 3D.

**Status:** ✅ Fixed

**Problem found:** at app start the logo appeared **three times in three different styles**: the phone's white launch screen, then an animated splash (logo inside a dark square with thin green arcs — the one in your picture), then the welcome screen.

**Fix:**
- The animated splash (square, green arcs, loading bar, 2.4 s wait) is removed. The app now shows **one** launch screen and goes straight on.
- The phone's own launch screen (iOS + Android, light + dark) now draws the **same** logo as the welcome screen, on the app's own background colour.
- The logo is at **exactly the same spot** on the launch screen and the welcome screen (we checked that the position is identical), so only the text and button fade in around it — the logo itself never moves.

Launch screen → welcome screen:

![](round2_screens/20-24/after_launch.png)
![](round2_screens/20-24/after_welcome.png)

**Note:** the iPhone simulator kept an old cached launch picture for the first frame; on a fresh install on a real phone the new one shows.

## 25. Login screen scrolls → disable scroll, elements fixed (screenshots show «جديد هنا؟ أنشئ حساباً» moving).

**Status:** ✅ Fixed

The sign-in screens (login, set password, upgrade account) no longer scroll or bounce when the form fits on screen — everything stays in place (we tested: swiping does nothing). They only move if the keyboard actually covers a field, so no field can get hidden.

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

**Status:** ✅ Fixed

**Done:**
- The three big role cards (donor / beneficiary / volunteer) became **one dropdown** called «نوع الحساب».
- Choosing a role opens only that role's extra section below. Everything already typed (name, date of birth, address, gender, city, occupation) **stays filled in**, so nothing is typed twice when the role changes.
- The **general user** is the account everyone can start with («المتابعة كمستخدم عام»): it has limited rights and is upgraded later from the same form by choosing a role (see the rights listed under the general-user point).

![](round2_screens/34-38/after_role_dropdown.png)
![](round2_screens/34-38/after_volunteer_selected.png)

## 36. Remove every «(اختياري)»; one sentence at the top: «الحقول المصحوبة بعلامة حمراء إجبارية».

**Status:** ✅ Fixed

The word «(اختياري)» was removed from every registration field (91 texts, in all four languages).
One line at the top instead: **«\* الحقول المصحوبة بعلامة حمراء إجبارية»** — the red \* next to a field already marks what must be filled.

![](round2_screens/34-38/after_top.png)

## 37. General user rights: browse everything (humanitarian, store, city guide, khotba), message support. Blocked: commenting in khotba, applying to khotba requests, requesting aid, joining volunteering; no volunteer notifications — until «تطوير حسابه» (upgrade + choose role).

**Status:** ✅ Fixed

**General user** (the account created by «المتابعة كمستخدم عام», previously labelled "visitor / guest") now matches the described rights:
- **Can:** browse everything — humanitarian work, the store, the city guide and the khotba section — and message support (chat and tickets).
- **Cannot, until the account is upgraded:** comment in the khotba section, send khotba requests, request humanitarian aid, join volunteer work, donate or buy. Each of these shows the «ترقية الحساب» prompt, and the server refuses it as well.
- Volunteer notifications reach volunteer accounts only, so a general user does not receive them until upgraded to a volunteer.
- **Upgrading:** «ترقية الحساب» → phone verification → the registration form with the role dropdown.

The name «زائر» is now «مستخدم عام» everywhere in the app and the dashboard.

## 38. Dashboard: separate section «المستخدم العام» (or better name) with admin controls (edit data, add user) matching the registration fields.

**Status:** ✅ Fixed

General users are now a named group in the dashboard: the Users page has the filter «المستخدمون العامون» and a «مستخدم عام» badge, they can be hidden from the list, a new general user is announced as «حساب مستخدم عام جديد», and their data can be edited and archived like any other account. The «General User Access» page controls which app screens they can browse. Users create their own accounts in the app, either by registering or by entering as a general user, so no manual creation is needed from the dashboard.

## 39. Filter tiles (الكل / غير مقروء / مقروء) unequal; «غير مقروء» wraps badly → equal size, one line or two stacked centered words.

**Status:** ✅ Fixed

The three tiles (الكل / غير مقروء / مقروء) are now the same size, with the count on top and a one-line label below, both centred.
They are also the filter itself: tap a tile to show that list (the selected tile is outlined). The duplicate row of All / Unread / Read buttons under them was removed.

![](round2_screens/39-43/after-all-newest-first.png)

## 40. «مسح 2 مقروءة» button tiny and off to the side → bigger icon + text, centered.

**Status:** ✅ Fixed

«مسح N مقروءة» is now a full button in the centre, with a larger icon and text (see the screenshot).

## 41. Category/Type dropdowns change look when a value is picked; no linkage → stable design; Type list filtered by chosen Category.

**Status:** ✅ Fixed

- Both dropdowns keep the same look before and after a value is picked: the label always sits above the field.
- The Type list now depends on the chosen Category: it only offers types that exist in that category. If the category changes, a type that no longer fits is reset to «كل الأنواع».

Example: Category «دفع» → the Type list shows only «شحن المحفظة».

![](round2_screens/39-43/after-linked-dropdowns.png)

## 42. Notifications in random order → newest first by date+time.

**Status:** ✅ Fixed

The list is sorted strictly by date and time, newest first. Before, urgent and payment notifications were pinned to the top, which made the order look random.
Screenshot: 5 minutes → 2 hours → 1 day.

## 43. Where is "mark all as read"?

**Status:** ✅ Fixed

The button already existed in the green box at the top, but its label was just «تحديد الكل». It now reads **«تحديد الكل كمقروء»**. It only appears when there are unread notifications.

## 44. App: result → action link (e.g. «اكفل عائلة هذا الشهر» → opens donation section); share result instantly; real finger-scratch effect instead of tap-to-reveal video.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: the wheel / scratch games are not listed (§13 lists stars, badges and motivational elements).

## 45. Dashboard: manage wheel slot texts, scratch prizes/texts, and link each text to an app section (destination).

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: managing the wheel / scratch games from the dashboard.

## 46. Visual quality: wheel/scratch graphics look amateur → modern UI matching brand + smooth animations.

**Status:** ✅ Fixed

**Wheel of Fortune**
- The 8-colour rainbow was replaced by the app's own colours (dark green, ivory, the logo's teal, mint), with white lines between slices, a dark rim with studs, and the logo in the centre.
- Each slice now has an icon and a clear label. The labels always read the right way up: the old Arabic labels were drawn left-to-right, which broke their letters.
- The pointer is a pin in the app colour that flicks as each slice passes it. A light vibration ticks per slice (it follows the app's mute setting).
- The spin slows down smoothly over 5 seconds and stops on the slice whose challenge is then shown.
- The result card was redone: the slice icon in a soft circle, «تحديك», the challenge, and one button.

**Lucky Coupon**
- The grey box became a ticket in the brand green (side notches, fine dot texture, logo, «اضغط للكشط»).
- Tapping it turns the ticket over in 3D to an ivory back with the challenge. «جرّب كوبوناً آخر» turns it back.

The explanation line under each title was removed (style rule).

Note: a real finger-scratch effect is part of the same addition (a postponed addition).

| Before | After |
|---|---|
| ![](round2_screens/46/before-wheel.png) | ![](round2_screens/46/after-wheel.png) |
| ![](round2_screens/46/before-coupon.png) | ![](round2_screens/46/after-coupon.png) |
| ![](round2_screens/46/before-coupon-revealed.png) | ![](round2_screens/46/after-coupon-revealed.png) |

Wheel result, and the coupon mid-turn:

![](round2_screens/46/after-wheel-result.png) ![](round2_screens/46/after-coupon-flipping.png)

## 47. Donation in 2 steps max. Step 1: «قدم مساهمة» → short clean screen with 4 options: الدفع الإلكتروني / تحويل رصيد / التسليم النقدي المباشر / المساهمات العينية.

**Status:** ✅ Fixed — one screen (same old payment system)

**Found:** donating went Contribute → "what kind of donation" step → a long checkout with a big header card, two locked boxes plus a note, and a summary that repeated the amount twice.

**Fixed:** the separate step is gone. After choosing the amount, ONE checkout screen holds everything, in this order: donor (name + phone on one line), amount, optional message, kind of donation (one row — tap to pick cash / electronic / balance transfer / support the organization / in-kind), who it helps, donation type, payment method, and one confirm button at the bottom. Nothing about how a donation is saved, approved or credited to the wallet was touched; every field is still there. Removed only the repeated parts: the header card, the locked-fields note and the duplicate summary panel.

| Top | Bottom | Kind picker |
|---|---|---|
| ![](round2_screens/47-55/after_one_screen_top.png) | ![](round2_screens/47-55/after_one_screen_bottom.png) | ![](round2_screens/47-55/after_kind_picker.png) |

## 48. Step 2 — e-payment: amount, card type (Visa, Master, FIB) → straight to gateway; IQD default, other currencies manual; notes.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: no payment-gateway integration is listed, and §24 puts bank transfer outside phase 1. §9 only says electronic donation «through the approved payment methods» (the dashboard-managed list).

The app has no payment gateway, so "straight to the gateway" cannot be built. A gateway means a provider account and keys, a redirect, and a confirmation callback. The old flow records a pending contribution and staff confirm it. Left unchanged.

## 49. Step 2 — balance transfer, ONE fixed page, two toggles at top «تعبئة / تحويل مباشر» vs «إرسال كرت». Transfer: network (Asia, Zain, Korek), amount, org phone with copy button, screenshot attach, notes. Card: network, photograph card with camera, serial field, value, notes. Fixed bottom: attach + notes + «تأكيد المساهمة». Toggle switches fields in place. Phone/address auto-filled, editable.

**Status:** ✅ Partly — inside the one screen

**Done:** «balance transfer» is now one of the kinds picked from the single row in the unified donation screen. Choosing it shows only the payment methods that belong to it (recharge cards and the transfer numbers set by the organization), with the organization's number and a «copy» button. The notes field and the confirm button stay fixed at the bottom.

**Not added yet:** choosing the network (Asiacell, Zain, Korek), attaching a transfer screenshot, photographing the recharge card and the serial field, and the top switch between «direct transfer» and «send a card»; they add new fields to the current payment flow.

![](round2_screens/47-55/after_electronic_methods.png)

## 50. Step 2 — direct cash: amount, address, phone, optional visit-time note; phone/address auto-filled, editable.

**Status:** ✅ Partly — inside the one screen

**Done:** «direct cash» is now one of the kinds picked from the single row in the unified donation screen; choosing it shows only the cash payment method. The donor's name and phone appear automatically from the account on one line, with the amount, the optional note and the confirm button at the bottom.

**Not added yet:** a home-address field and a preferred-visit-time note for the representative, and editing the phone by hand on this screen; they add new fields to the current payment flow.

## 51. Step 2 — in-kind: material type, phone, address (auto-filled, editable), optional photo of the items.

**Status:** ✅ Partly — inside the one screen

**Done:** «in-kind» is now one of the options in the same kind-of-donation row of the unified donation screen; choosing it opens its form with: category, item name, quantity and pickup address.

**Not added yet:** a phone number field and an option to attach a photo of the items; they are new fields in the current form.

## 52. Every path ends with one clear bottom button «تأكيد المساهمة» that sends straight to the dashboard.

**Status:** ✅ Fixed

**Fixed:** every kind now ends with one clear button at the bottom of the screen showing the amount («تأكيد مساهمة 20,000 د.ع»). The amount is formatted with thousands separators. The old duplicate summary above it is removed.

## 53. General: unclear labels (تبرع الان / عرض الكل); repeated confirmation screens; long explanation text under every option → remove, short labels (1–2 words per button).

**Status:** ✅ Fixed (checkout) — first step left as is

**Fixed:** on the checkout the repeated confirmation (hero card + summary + total) and the long explanatory note are gone, the amount icon is now a payments icon instead of a dollar sign, and the message box is shorter. The Contribute tab before it (amounts + the selected-option card) was not redesigned.

## 54. After sending a contribution it says "sent & pending" but NO donation/support shows up → final submission mechanism broken, fix.

**Status:** ✅ Fixed

**Found:** «sent and pending» is correct by design (an admin confirms the payment and approves it). The real bug was different: any gift of 1,000,000 IQD or more was saved with an EMPTY amount and still answered "success", so it showed as 0 for the donor and in the dashboard.

**Fixed:** the limit is now 1,000,000,000 IQD, and an amount that is not usable is refused with a clear message instead of saving an empty row. The pending / approval / wallet logic is unchanged.

## 55. Remove donation type (عام / زكاة / صدقة) and «التبرع لمؤسسة»; replace with one fixed line: «تنويه: يتم استقطاع نسبة بسيطة من التبرعات لتغطية التكاليف التشغيلية وضمان استمرار عمل المشروع.»

**Status:** ✅ Partly

**Done:** the donation-type and «Support the organization» choices stay, now compact (the organization option is one of the kinds in the single row; the type is one short row of chips). **Not done yet:** replacing them with the fixed line «تنويه: …».

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
Also: chat sender "Guest" now shows as «زائر»; upgrade-screen errors are Arabic.

## 58. Staff & volunteers: direct instant messaging, no friction.

**Status:** ✅ Fixed — covered by the same change as the staff and volunteer messaging

Volunteers reach staff — volunteers reach staff in one tap; staff ↔ staff via «محادثة الموظفين»; team rooms for staff + volunteers.

## 59. Beneficiaries / khotba / general user / visitor: start with a support ticket; staff replies; staff can convert the ticket into a chat with specific people; can close it; ticket feature stays.

**Status:** ✅ Partly exists · ➕ the rest is an addition — not in the original scope (put aside)

**Scope:** Part exists (see below). Turning a ticket into a chat is an addition: §18 only lists contacting support from inside the app.

What works today:
- Beneficiaries / visitors / anyone can open a support **ticket** (and visitors now too), and staff answer it in the dashboard (الدعم → Reply). Staff can mark it open / in progress / resolved / **closed**.
- Staff can open a supervised room with specific people (المجموعات الحوارية).

Missing (new feature): a button on the ticket that converts it directly into a chat with chosen people. Postponed until it is approved within the scope.

## 60. Encrypted group chats: aid section (staff + donor(s)/beneficiary); khotba (staff + suitor + girl + guardian). Opens only with staff approval; no personal data shown (numbers, real names); files/photos only by staff; staff can pause / archive / delete.

**Status:** ✅ Mostly exists · ➕ the rest is an addition — not in the original scope (put aside)

**Scope:** Mostly exists (see below). The extra parts (encryption, staff file sending, block button) are additions: not in the proposal.

Exists, and we checked it:
- Rooms between donor / beneficiary are opened **only by staff** (connect request → staff approval, or staff creates the room).
- Members see only a nickname («مانح 1», «مستحق 1») — **no real names, no phone numbers**; a message containing a phone number or email is **blocked** automatically and logged.
- Staff can pause / archive / delete.

Not in the system yet (new features, postponed):
1. Message **encryption** at rest (messages are stored as normal text today).
2. Sending **files / photos** in chats (today nobody can — text only; you asked for staff only).
3. Adding the girl's **guardian** to the khotba chat.

## 61. Staff chat controls: **temporary pause** (client can still send, staff sees it, no read receipt until reply); **full stop** (lock, client can't send); admin buttons Archive / Block / Delete.

**Status:** ✅ Exists · ➕ the rest is an addition — not in the original scope (put aside)

**Scope:** Pause / stop modes and Block are additions: not in the proposal.

- **Full stop**: «إغلاق المحادثة» — members can only read until staff reopen it. ✅
- **Temporary pause where the user can still write**: simply leave the chat open — members never see "read" marks (the app has no read receipts for members), so staff can read without the user knowing. ✅
- **Archive** ✅ · **Delete** ✅ (moves to trash, password-confirmed).
- **Block** a person from a chat: not as a separate button today (staff can remove the member — «إزالة» — or suspend the account). A dedicated "block" is a new feature, postponed.

## 62. City guide «إضافة نشاط»: no photo option; why lat/long fields (just attach GPS); submit button sits under the phone nav buttons → move it up.

**Status:** ✅ Fixed

**Found:** the add-activity form had no way to add a photo, asked the user to type a latitude and longitude by hand, and its submit button was the last item of the scrolling list, so it sat under the phone's navigation buttons.

**Fixed:**
- **Photos:** a «الصور» row where the user adds up to 6 photos (camera or gallery, with the resize / crop step). They upload only when the form is sent. Staff see them in the dashboard city-guide review.
- **GPS:** the two number boxes are gone. One button, «تحديد موقعي», takes the phone's GPS (it says «تم تحديد الموقع» when done, with «إزالة الموقع» to undo). If location is off or refused, it says why in words.
- **Submit button:** «إرسال للمراجعة» is now pinned at the bottom of the screen, clear of the phone's buttons, and always visible while the form scrolls.
- **Server:** it now accepts the photos and keeps only photos uploaded through the app itself (anything else is dropped), at most 6.

We checked this end to end on a test copy: the suggestion arrived as «قيد المراجعة» with the GPS coordinates and the uploaded photo.

| Before (top) | Before (bottom: button at the edge) |
|---|---|
| ![](round2_screens/62/before-1-top.png) | ![](round2_screens/62/before-2-bottom.png) |

| After | With GPS + photo | Sent |
|---|---|---|
| ![](round2_screens/62/after-1-form.png) | ![](round2_screens/62/after-2-gps-photo-submit.png) | ![](round2_screens/62/after-3-submitted.png) |

## 63. Profile: logout button at the very bottom collides with phone nav buttons → move up.

**Status:** ✅ Fixed (it could not be reproduced on screen)

**Found:** the profile page ended with a flat 24 points of space and ignored the phone's system navigation bar. On Android phones that draw the app edge to edge, the bar overlaps the bottom of the screen, so the last row, «تسجيل الخروج», stopped underneath the buttons. The overlap does not show on every test device (some keep the navigation bar outside the app window), so the fix was checked by simulating a 56-point bar.

**Fixed:** the page now clears the system inset plus a margin, so the logout row scrolls fully above the buttons. On phones with no inset nothing changes.

![](round2_screens/63/android-profile-bottom.png)

## 64. «أثرنا» section doesn't work — where are its data/photos/details edited?

**Status:** ✅ Fixed (the card); the question answered below

**Answer — where is «أثرنا» edited?** Nowhere, by design. It is the "Our impact" banner on Home and its three numbers are counted live from the real data: **donors** (active donor accounts), **beneficiaries** (active beneficiary accounts) and **completed activities** (completed volunteer missions plus approved project requests). That matches the proposal's «banner showing the general statistics», which are automatic. It has no photos or text to edit. The statistics boxes below it («المساهمات المؤكدة» etc.) work the same way.

**Found:** the card looked broken: a wide empty dark rectangle with the icon at one corner and the number at the opposite one, so it read as an unfinished or non-working section.

**Fixed:** the card is now compact: the icon beside a large number and its label, vertically centred, at a sensible height. The data, the automatic rotation and the dots are unchanged. We checked on iPhone and Android.

If you want the section editable (photos, custom text), that is a new feature, not in the proposal.

| Before (Android) | After (iPhone) | After (Android) |
|---|---|---|
| ![](round2_screens/64/before-android.png) | ![](round2_screens/64/after-ios.png) | ![](round2_screens/64/after-android.png) |

## 65. Store: selecting a product froze the page, cancel didn't respond, logout/login didn't fix; cart only appeared after several tries.

**Status:** ✅ Fixed (the cause that could be reproduced); the "froze for good" case could not be reproduced

**Found:** tapping a product opens a sheet that covered most of the screen and could only be dismissed by swiping it down or tapping the dim strip above it. Nothing on it said so: no close button. After «إضافة» the sheet stayed open, and it hid the cart bar behind it, so the cart only showed up once the sheet was finally dismissed. That matches «selecting a product froze the page, cancel didn't respond, the cart only appeared after several tries». Logging out and back in doesn't help because it is not a stuck state, just a sheet with no visible exit.

**Fixed:**
- A visible **✕** in the sheet's header (we checked on iPhone and Android).
- Once the product is in the cart the sheet shows **«عرض السلة · N عنصر»**, which closes it and opens the cart.
- After closing, the cart bar («1 عنصر · 15,000 د.ع») is visible immediately.

**Could not reproduce:** a page that stays frozen with no way out at all. If it still happens on your phone, please send the phone model and what was on screen.

Payment was not touched.

| Before | After |
|---|---|
| ![](round2_screens/65/before-sheet-no-exit.png) | ![](round2_screens/65/after-sheet-close-and-cart.png) |

Android: ![](round2_screens/65/after-android-sheet.png) ![](round2_screens/65/after-android-closed-cart-bar.png)

## 66. Store: no payment options, only cash? (needs e-payment).

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: store payment (§14 lists orders and status only).

## 67. **CRITICAL wallet hole:** app tops up the wallet with no real payment and no staff approval → block auto top-up; real gateway OR pending until dashboard approval; fix balance reading (shows 0) across wallet screens.

**Status:** ℹ️ By design

The wallet top-up works through the admin confirming the proof of transfer.

## 68. Home → browse by category: campaign details cut off → give the details more space.

**Status:** ✅ Fixed

**Found:** «تصفح حسب الفئة» opens the family-profiles screen. Its cards cut the title to one line («أرملة تعيل ثلاثة أطفال وتحتاج إلى دعم عاجل لتأمين الغذاء وال…») because the priority tag beside it took a third of the row. A big «دليل الملفات» explanation card above the list repeated the subtitle in a paragraph and pushed the profiles down. The tags read «Urgent need» / «High priority» in English.

**Fixed:**
- The title now shows in full (up to as many lines as it needs); the tag moved under the family line.
- The explanation card was removed, so the filter chips and the profiles start straight after the title.
- The three tags now read «حاجة عاجلة», «أولوية عالية», «دعم مستمر» (the existing «دعم مستقر» stays).

Note: the grey line under each tag («Monthly food basket…») is the case's own text typed in English by whoever created the case; it is data, not something the app translates.

| Before | After |
|---|---|
| ![](round2_screens/68/before-cut-title-and-intro-card.png) | ![](round2_screens/68/after-full-title-arabic-tags.png) |

## 69. Home: «مشاركتي» opens a page titled «سجلي» — naming mistake?; shorten the circled phrases to one line, remove extra details; «استعلام بالرمز التعريفي» long unclear explanation — is this lookup approach right at all?

**Status:** ✅ Fixed

**Found:** the Home tile is «مشاركتي» but the page it opened was titled «سجلي» (and the list heading under it said it again by role). A two-line subtitle under the title and a long sentence inside the green card both described the page the user was already on. The lookup box carried a three-line explanation.

**Fixed:**
- Same name at both ends: the page is now titled «مشاركتي».
- The two-line subtitle and the sentence in the green card were removed.
- «استعلام بالرمز التعريفي» is now «البحث بالرمز التعريفي», and its explanation is one short line: «أدخل الرمز التعريفي. امسح الحقل للعودة إلى سجلك.»

**Is the lookup the right approach?** It is kept, but it is only really useful for staff: an ordinary user can only ever look up their own code (the server refuses other people's, by design, to protect privacy), and that code is already shown under the box. If you prefer, it can be hidden from non-staff accounts: say so.

![](round2_screens/69-71/69-after-my-participation.png)

## 70. Rename «قسم الفعاليات» → «إدارة ملف التوافق الأسري».

**Status:** ✅ Fixed

«قسم الفعاليات» is now **«إدارة ملف التوافق الأسري»** on the Events screen tile and on the page title (the bottom tab itself stays «الفعاليات»: it is the whole Events area, which also holds «خدمات الفعاليات»).

![](round2_screens/69-71/70-after-section-name.png)

## 71. Inside it, rename «ملفي الشخصي» → «بيانات الملف الأسري».

**Status:** ✅ Fixed

Inside it, «ملفي الشخصي» is now **«بيانات الملف الأسري»** (the tile, the page it opens, and the «create / edit» label became «إنشاء / تعديل بيانات الملف الأسري»).

![](round2_screens/69-71/71-after-family-file-data.png)

## 72. «خدمات الفعاليات» → real store: subcategories (halls, photographers, decor), each with providers, photos (e.g. 6 per hall), price; cart; e-payment; booking/direct purchase.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: an events-services store with providers, prices, cart and payment.

## 73. Public posting: today only targeted posts to one person → allow public posts (e.g. "looking for specs X") others can view, comment on, and contact the owner.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** Not in the proposal: public posts in the marriage section (§16 says contact only through staff).

## 74. Export button + date/time column in EVERY section/table (screenshots: الشركاء has no date/time; إيصالات المساعدات has no export and no date/time).

**Status:** ✅ Fixed

**Found:** Receipts, City Guide, Marriage meeting requests, Profile changes and Trash had no export; Partners, Campaigns, Community, Missions, Receipts and Trash had no date/time column.

**Fixed:** every table now has an Export button and a stacked date + time column. The system now returns the creation time for receipts, partners and campaigns (older campaigns show «—»). Community now reads the admin list so it has the date too.

![](round2_screens/74/hi_city_guide.png)

## 75. Sticky table header in every section. 

**Status:** ✅ Already works everywhere (we verified)

**Found:** the header is made sticky by one shared mechanism that every table uses; no table has its own markup. Nothing overrides it, so no change was needed.

## 76. Unify the top bar design across all sections.

**Status:** ✅ Fixed

**Fixed:** one shared page header on every section: title + count at the start, then search, filters, Export and «New» on the same row, one control height. Works in Arabic (mirrored) and light/dark.

![](round2_screens/76/hi_users_head.png)

## 77. «حذف الحساب» moves INTO the user edit page, not the outside dropdown.

**Status:** ✅ Fixed

**Fixed:** «حذف الحساب» moved out of the row menu into a red Danger zone at the bottom of the account Edit window (Super-Admin only). The password confirmation is still required, and asked once.

![](round2_screens/77/hi_row_menu.png)
![](round2_screens/77/hi_edit_modal_bottom.png)

## 78. Account data parity: same fields/options when creating an account in the app, in the dashboard, or editing.

**Status:** ✅ Fixed (with notes)

**Found:** Edit showed every profile column, while New User showed only the fields of the chosen role.

**Fixed:** both screens now use one shared rule for which fields are shown per role.

**Notes:** a few fields exist only in the app form (grantor social links, some passport/residence photos) and have no setting in the dashboard, so they can't be made required/hidden from there. Marriage and employee roles have no registration form, so New User shows no profile boxes for them.

## 79. Change-password in dashboard (edit user modal, «كلمة مرور جديدة») doesn't work → fix.

**Status:** ✅ Fixed

**Found:** saving the password worked, but dashboard sign-in uses a username and the Edit window had no username box, so staff accounts without one could never sign in.

**Fixed:** Edit now has Username + New password in an Account section; saving a password on a staff account with no username is refused with a clear message. Username must be valid and unique.

![](round2_screens/77/hi_edit_modal_bottom.png)

## 80. Supervisor permissions: where to assign roles to dashboard staff with per-section permissions?

**Status:** ❓ Answered

**Answer:** menu الصلاحيات والموظفون → «الصلاحيات» (matrix: tier × section × view/add/edit/archive/delete/export, password-confirmed and audit-logged, plus per-employee overrides) and «الموظفون» (staff accounts, support department). To make a new staff member: create the account in المستخدمين, then «ترقية إلى موظف» on the Staff page and pick the tier. Super-Admin only.

## 81. Full separation of account lists: Volunteers / Donors / Beneficiaries / General users / Visitors / Khotba & marriage (family files) / Staff — each section shows only its roles.

**Status:** ✅ Fixed

**Found:** the Donors list could include guest accounts.

**Fixed:** role-scoped lists never contain guests; a type filter in Users (donors, beneficiaries, volunteers, employees, family files, visitors) separates the lists.

## 82. «تحديد الكل» (Select All) checkbox at the top of every table → bulk delete old test data.

**Status:** ✅ Fixed

**Fixed:** a select-all checkbox + bulk delete bar (with confirmation) on Donations, Community, City Guide, Missions, Trash, Campaigns, Users and Staff. Not added to Registrations, Receipts, Meeting requests, Profile changes and Audit logs because the system has no delete for those.

## 83. Store (dashboard + app) judged weak by someone who runs a real store app → needs clear, easy, complete sections.

**Status:** ➕ Addition — not in the original scope (put aside, to come back to later)

**Scope:** A full store redesign goes beyond §14 (display, link to beneficiary, review/approve, orders + status).

## 84. Align all toolbar input fields on ONE horizontal row in every section (screenshots: لوحة التحكم, المستحقون, اشتراكات الفعاليات, المتطوعون, طلبات التواصل, التعليقات, دليل المدينة, الموظفون).

**Status:** ✅ Fixed

**Fixed:** search, filters, dates, Export and «New» sit on one row on desktop. On mid-size screens the controls wrap to a second line instead of being squeezed or cut; phones keep the stacked layout.

![](round2_screens/76/hi_users_head.png)

## 85. Create-notification language tabs (EN / عربي / سوراني / باديني) don't translate anything; plus a language switch at the top — what are these for?

**Status:** ✅ Clarified + fixed

**Answer:** each language tab edits the title/text users get in that language (in-app sends all four; each user sees their own app language; a blank language falls back to English). The top language switch only changes the dashboard's own language. There is no auto-translation.

**Fixed:** the page now says this, marks empty tabs, shows the English fallback, and warns that a push banner goes in one language only.

![](round2_screens/85/hi_push.png)

## 86. Dashboard font is bad too (e.g. «المدن والأقضية والنواحي», «الأقضية») — letters hard to read.

**Status:** ✅ Fixed

The dashboard used «Kurdfont» — a single-weight font, so every bold heading was a fake bold that smudged the letters («المدن والأقضية والنواحي», «الأقضية»). It now uses the same **Noto Sans Arabic** as the app (real weights), and letter-spacing is forced to zero for all Arabic text in the dashboard.

![](round2_screens/08/hi_dashboard.png)

## 87. Change password not working in edit account.

**Status:** ✅ Fixed

**Fixed:** the Edit window now has the username the sign-in needs.

![](round2_screens/77/hi_edit_modal_bottom.png)

## 88. City guide: clicking the warning banner («...لا تظهر على خريطة التطبيق») doesn't jump to the offending entries.

**Status:** ✅ Fixed

**Fixed:** the warning banner is now clickable: it filters the table to places without valid coordinates and scrolls to it, with a «Show all» button. One shared coordinate rule drives the count, the cell and the filter.

## 89. Zoom / tablet / phone: list layout breaks — «إجراءات» column header disappears, columns shift.

**Status:** ✅ Fixed

**Found:** other header cells sat above the pinned «إجراءات» header and slid over it when the table scrolled sideways; a leftover rule also un-pinned it on phones.

**Fixed:** the Actions header is pinned above the others and the leftover rule is removed.

![](round2_screens/74/hi_city_guide.png)

## 90. Sidebar notification counts: open the section and there's no badge/marker showing WHICH sub-item has the notifications.

**Status:** ✅ Fixed (sidebar) / ➕ per-tab counts inside pages not done

**Fixed:** each open sidebar section now shows a count badge on the exact sub-item that has pending items (e.g. Recipient 1, Volunteers 2, Notifications, Support).

**Not done:** counts on the tabs inside a page (e.g. Beneficiaries status tabs) need new per-tab counts — put aside as an addition.

## 91. Sidebar bug: two items look selected at once (المجموعات الحوارية + طلبات التواصل) while only one is open.

**Status:** ✅ Fixed

**Fixed:** only the open page's sidebar item is highlighted; the parent group no longer looks selected together with a child (we checked on Push and Users).

