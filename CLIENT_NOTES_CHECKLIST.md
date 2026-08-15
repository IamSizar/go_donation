# Client notes — verification checklist

Captured 2026-08-15 from the owner's written list, 11 annotated screenshots, and
two PDFs (`ملاحظات - منصة توازن - الداشبورد.pdf` 10pp, `ملاحظات وتعديلات تطبيق توازن.pdf` 35pp).

**Status key:** ⬜ not yet verified · 🔎 verified, defect confirmed · ✅ verified, already correct · ❌ could not verify

**Page reference key:** `[D pN]` = dashboard PDF page N · `[A pN]` = app PDF page N.

Every item must be TESTED against the running app/dashboard, not assumed from code.
Several notes say "still not fixed", so a previous pass may have missed or only
partially addressed them — check the actual behaviour.

Groups A–F are the original written list + screenshots (page refs appended where a
PDF repeats the same complaint). Groups G–N are new material extracted from the PDFs.

---

## A. SEVERE — blocks a working flow

| # | Item | Where | Status |
|---|---|---|---|
| A1 | **`Database error.` on the contributions page**, and in-kind contributions sent to a user never arrive. Screenshot shows the red error banner with an empty table beneath. | Dashboard → المساعدات والحملات → المساهمات | 🔎 **fixed, not deployed** — see A1 notes below |
| A2 | **Force logout (تسجيل خروج قسري) does not work** | Dashboard → المستخدمون → row actions | ⬜ |
| A3 | **Contact-support chat does not work** (التواصل مع الدعم لا يعمل). PDFs additionally spec the support section it should be: direct message to the support team + follow request status/replies, and after >3 messages on different dates about the same unresolved issue, offer direct WhatsApp escalation. `[A p27, p34]` | App → الرسائل | 🔎 **confirmed, fixed, not deployed** — see A3 notes below |
| A4 | **City Guide: the last slide cannot be displayed** — technical fault | App → دليل المدينة | ⬜ |
| A5 | Dashboard shows a **wrong phone number for a real user**: `07701111111` appears on the accounts page for user **نور كاظم** although he is registered successfully through the phone app — "ظهور رقم الهاتف ٠٧٧٠١١١١١١١ في صفحة الحسابات داخل لوحة التحكم ... رغم كونه مسجلاً بنجاح عبر تطبيق الهاتف" `[D p9]` | Dashboard → المستخدمون | ⬜ |
| A6 | **Some app screens stop working when signed in with that same account** — "توقف بعض واجهات تطبيق الهاتف عن العمل بصورة صحيحة عند الدخول بهذا الحساب". Reproduce by logging in as نور كاظم. `[D p9]` | App | ⬜ |
| A7 | Pressing **back from the app's main screen pops a logout message** — "ظهور رسالة تسجيل الخروج للمستخدم عند الضغط على زر الرجوع من داخل الواجهة الرئيسية للتطبيق". Back should navigate, not offer to sign out. `[D p9]` | App → home, hardware/UI back | ⬜ |
| A8 | **Confirming that logout turns the whole screen black and freezes the app** — "تحول شاشة التطبيق بالكامل إلى اللون الأسود وتجمد النظام عند الضغط على خيار موافقة الخروج من الرسالة السابقة" `[D p10]` | App → the A7 dialog → confirm | ⬜ |
| A9 | **Logout does not actually log out** — "فشل عملية تسجيل الخروج الفعلي حيث يتم الدخول بشكل مباشر إلى الحساب عند إغلاق التطبيق كاملاً وإعادة فتحه بدلاً من توجيه المستخدم لصفحة تسجيل الدخول". Session survives a full app kill. `[D p10]` | App → تسجيل الخروج, then force-quit and reopen | ⬜ |
| A10 | **A submitted help request / beneficiary case produced NO dashboard notification** — "قمنا بتجربة إرسال طلب مساعدة (مشروع)، وإرسال حالة المستفيد، ولم يصل أي إشعار في شاشة الداش" `[A p34]` | App → send request → Dashboard notifications | ⬜ |
| A11 | **Selecting `needs_changes` crashes the page layout** — "إصلاح الخلل البرمجي والتصميمي الشامل (UI Crash / Layout Bug) الذي يحدث في ترتيب وعرض كافة تفاصيل الصفحة بمجرد اختيار خيار (needs_changes) من القائمة المنسدلة" `[D p4]` | Dashboard → المستفيدون → الحالة dropdown | ⬜ |
| A12 | **Volunteer request action buttons disappear after final approval/submission**, so a request can never be closed or reversed — "إصلاح مشكلة اختفاء أزرار الإجراءات بعد الموافقة النهائية أو تقديم الطلب، لضمان عدم قفل الطلب تماماً" `[D p6]` | Dashboard → المتطوعين → تسجيلات المهام | ⬜ |
| A13 | **The `mark completed` button disappears when clicked** — "عند اختيار هذا الزر المجاور للعرض والتعديل يختفي عند الضغط عليه" `[D p6]` | Dashboard → المهام | ⬜ |
| A14 | **المهام → عرض has no detail page at all** — shows "مورد غير معروف" (unknown resource); no details page exists for `volunteer_missions`. And **there is no back button or route out** — "لايوجد زر او طريقة رجوع عند الدخول لصفحة العرض" `[D p6]` | Dashboard → المهام → عرض | ⬜ |
| A15 | **SECURITY: ordinary app users can reach the dashboard.** Client asks to close "الثغرة الحالية التي تسمح لهم باستعراض وتعديل الأقسام كالأخبار والحملات والدليل" — block any app user from logging into and browsing/editing dashboard pages; restrict to admin and approved employees only. `[D p9]` | Dashboard auth | 🔎 **confirmed, fixed, not deployed** — see A15 notes below |
| A16 | **SECURITY: a phone number alone bought a session — including a Super-Admin's.** Found while fixing A15 and raised there as needing its own item. `POST /api/auth/login` issued a 30-day token for any number with no `password_hash`, and no OTP was enforced anywhere on the server. Production id **34** is a `super_admin` with no password. | App + Dashboard auth (shared token store) | 🔎 **confirmed, fixed, not deployed** — see A16 notes below. **Final design 2026-08-15, as decided by the owner: a code CREATES an account, a password signs you in.** A verified code can now do exactly one thing — give a first password to an account that has none — so it can never open one that already has a password (that hole was live until today), and each of the 36 passwordless accounts can be claimed **once**. Staff still need `OTP_STAFF_DEMO_CODE` to claim theirs (**must be set, or ids 1 and 34 stay locked out**), and `OTPIQ_API_KEY` still switches the platform to real OTP with no app release. **Residual risk while demo OTP is on: whoever knows the number of a passwordless account can claim it first — narrower than today, where that same person gets a session on it repeatedly and forever. ⚠️ A safe self-service "forgot password" needs `OTPIQ_API_KEY` first; until then staff reset passwords from the dashboard.** |

### A3 — diagnosis and fix (2026-08-15)

**The support round trip was open at the far end: staff could not reply.**

The pieces all existed and none of them met. `POST /api/admin/support_tickets/:id/reply`
was routed (`main.go:808`) and wrote `admin_reply` (`extras.go`), and the app's
support screen already renders a reply inside the ticket card
(`technical_support_screen.dart:427-461`). But **no dashboard control ever
called that endpoint** — `SupportPage.tsx` offered view / edit / delete only,
and its edit modal carried subject, status and message, no reply field. So the
user-visible reply panel could never be populated by anyone using the product.

Two further gaps behind it:

- `support.Store.Reply` fired **no notification**, so even a reply sent
  straight to the API was silent. A user has no reason to reopen a ticket they
  already sent, so an answer would have sat unread. Every other support event
  (submit, status change) already notifies.
- The admin list query never selected `admin_reply` / `replied_at`, so the
  dashboard could not tell an answered ticket from an unanswered one — and a
  reply box would have overwritten an existing answer blind.

**Changed:** `backend/internal/support/support.go` (`Reply` now returns the
ticket owner + subject via `RETURNING`, one round trip, and exports
`ErrEmptyReply` / `ErrTicketNotFound`) · `backend/internal/notify/templates.go`
(new `SupportRepliedMsg`) · `backend/internal/handlers/extras.go` (`AdminReply`
notifies the owner and maps each failure to a stable `code` instead of
forwarding the store's raw English) · `backend/internal/handlers/admin_lists.go`
(`admin_reply` + `replied_at` on the admin list) · admin-web `SupportPage.tsx`
(Reply row action + reply modal + "Replied:" preview in the row),
`api-types.ts`, and `en`/`ar` locale keys.

**A dashboard-raised ticket can have no user attached** (`user_id` is nullable —
the create form's "User ID (optional)"). Those get no notification, by design;
`Replied.OwnerID` is a pointer so that case is distinguishable from user 0.

**Kurdish left to a translator, deliberately.** `SupportRepliedMsg` supplies
En + Ar and leaves Ckb/Kmr empty, which `Send` stores as NULL and every client
falls back to English for. Both Kurdish locales use Arabic script, so pasted
Arabic would look plausible and be wrong. Listed in `TRANSLATION_REQUEST.md`.

**Test:** `backend/internal/notify/templates_support_test.go` — pins the
related-entity link (so tapping the alert can open the ticket) and pins the
empty-Kurdish decision so a later silent paste has to be deliberate. Verified
it fails without the fix (`undefined: SupportRepliedMsg`).

**Gates:** `go build ./...`, `go vet ./...`, `go test ./...`, `npx tsc -b`,
`npm run build` all pass.

**Not deployed.**

---

**The other half of A3 — users were being sent to the WRONG support screen.**

Two support screens existed. `TechnicalSupportScreen` is the real one: compose
box, ticket history, staff reply, WhatsApp escalation, four states with the
error branch checked before the empty branch. It was reachable from **one**
place, the profile drawer.

`SupportTicketFormScreen` (inside `proposal_services_section.dart`) was a bare
compose form and it owned the other **three** entry points:

| Entry point | Was | Now |
|---|---|---|
| Services hub → الدعم الفني | bare form | TechnicalSupportScreen |
| Bot `support` route | bare form | TechnicalSupportScreen |
| Tapped support notification | bare form, and unreachable (below) | TechnicalSupportScreen |

The bare form had no ticket history, no staff reply, no validation, no submit
gating — an empty submit was a silent no-op — and
`catch (e) { Get.snackbar('Error', e.toString()) }`, i.e. a **raw exception in
front of the user**.

**Deleted, not kept as the compose step.** It was checked for a state the good
screen does not serve, because "duplicate" screens on this project have more
than once turned out to serve different ones. This one served none: it POSTs
the same two fields to the same endpoint, and the good screen's compose panel
*is* that form. Keeping it would have preserved the worse copy of a box that
already exists inside the good screen.

**A second, separate defect found on the notification path.** `destinationFor`
matched the exact string `'support_ticket'`, which the backend **never emits**
— it emits `support_request_submitted`, `support_ticket_<status>` and (new
above) `support_ticket_replied`. So every support notification fell through to
`null` and tapping it did nothing. Matching the support family by prefix makes
the reply notification actionable, which is the whole point of it.

**Also brought up to rule 5.6** on the screen that is now the only support
surface: inline per-field errors that name what is missing and sit at the field
(not a snackbar covering the form), a send button disabled while the form is
incomplete or in flight, keyboard dismissal on scroll and before submit.

**Changed:** `proposal_services_section.dart` (route + delete) ·
`bot_navigation.dart` · `notifications_controller.dart` ·
`technical_support_screen.dart` · `app_translations.dart`
(`support_subject_required` / `support_message_required`, en + ar).

**Test:** `humanitarian/test/notifications/support_destination_test.dart`.
Verified it fails before the fix — **7 of 9 failing**, every real support type
returning `null` — and passes after.

**Gates:** `flutter analyze` 6 issues (the 6 pre-existing deprecation infos,
none new), `flutter test` 158 passing.

### A1 — diagnosis and fix (2026-08-15)

**These are two unrelated faults that the owner reported as one.**

**Fault 1 — the `Database error.` banner.** `GET /api/admin/donations` returned
HTTP 500 for every request. Root cause: `donations.AdminList` selected a bare
`u.phone` from a `LEFT JOIN users` into `AdminListRow.DonorPhone`, which is a
plain `string`, not a pointer like every other join-sourced field in that
struct. `users.phone` became nullable in migration 017, and **guest accounts are
created with no phone at all** — in production all 3 guests have `phone IS NULL`
and all 43 real users have one. Donation `id 16` belongs to guest `user_id 32`,
so pgx failed the scan on that single row and took the entire list down with it.

Proof, running the exact query against production data read-only:

```
before:  SCAN FAILED after 1 good rows:
         can't scan into dest[3] (col: phone): cannot scan NULL into *string
after:   OK: scanned 14 rows with no error
```

The endpoint also bisected cleanly against the live API: `page=2&per_page=1`
(which isolates row 16) returned 500, while every page and every search filter
that excluded row 16 returned 200. The 14 contributions were never lost — only
unreadable.

Fixed with `COALESCE(u.phone, '')`, the convention this repo already uses in
`users.go`, `auth/token.go`, `profilechanges.go` and `sponsorshipschedule.go`.
**The same latent fault was found and closed in two more places** that were not
yet firing only because no phoneless account had reached them: the staff
directory (`staffchat.go` — would break on any phoneless account promoted to a
staff tier) and the registrations list (`users/registration.go` — a Google
sign-in with no phone attached is exactly a pending registration).

The fault was undiagnosable because the handler discarded the driver error and
answered with a fixed `"Database error."` and **no log line at all** (rule 1.5).
It now logs the technical detail server-side and returns a translatable `code`.

**Fault 2 — "in-kind contributions sent to a user never arrive."** Not a bug in
the same sense: **the feature does not exist.** `in_kind_donations` has only a
`donor_user_id` column — the person who *gives* an item. There is no recipient
column anywhere in the schema, so an in-kind contribution cannot be addressed to
a user. When an admin fills in "معرّف المستخدم" on the dashboard's create form
they are recording who *donated* the item, not who receives it.

It also arrives nowhere else: `POST /api/admin/in_kind_donations` writes the row
and **sends no notification**, unlike the app-side submit path which does. The
data confirms it — of 9 in-kind rows, only the 2 submitted from the app (ids 4
and 5) ever produced a notification; the 4 created from the dashboard on
2026-07-26/28 (ids 6, 7, 8, 10) produced none. And the Flutter app only ever
POSTs to `in_kind_donations` — it has no screen that lists them, so even a
correctly linked record would be invisible to the user.

So: the records **are** written and **are** linked to the user id typed in — but
linked in the wrong direction (as donor, not recipient), never announced, and
not displayable in the app. Delivering what the owner expects needs a product
decision and new work: a recipient concept on the record, a notification on the
admin create path, and a screen in the app. **Flagged, not silently invented.**

**Also fixed on the dashboard**, since a failed load rendered as three
contradictory states at once (header "جارٍ التحميل…", red banner, and
"لا توجد مساهمات بعد" over 14 real records):
- `Table` gained mutually exclusive error / loading / empty states, so a failed
  load can no longer claim the list is empty, and offers a Retry.
- `describeError` no longer dumps the backend's raw English at the operator; it
  translates a handler's `code` and falls back to a generic localized line for
  any 5xx. New `error.*` keys added in all four locales.
- A successful background poll now clears a previous error, which it did not do
  before — a recovered list kept showing a stale failure banner.

**Gates:** `go build ./...`, `go vet ./...`, `npx tsc -b`, `npm run build` all
pass. Verified end-to-end in the real dashboard UI against a local backend with
the production failure shape reproduced (a NULL-phone guest donation): the list
loads, and with the fix reverted the page shows the translated Arabic error plus
Retry instead of the false "no contributions yet".

**Not deployed.** Production still 500s until the backend is released.

### A15 — diagnosis and fix (2026-08-15)

**The client is right. The hole is real, and it is wider than reported.**

**Root cause — two fields, one of them lying.** `users` carries both
`is_admin` (a legacy SMALLINT) and `staff_tier` (the tier the whole permission
system is built on). Migration 015 backfilled `staff_tier` from `is_admin` and
`is_admin` was supposed to retire — but every gate kept honouring it as an
*independent* grant, written as `if user.IsAdmin != 1 && <tier check>`. So the
legacy flag alone opened the door, tier be damned. The two fields then drifted
apart in production, in both directions.

**Why an app user could walk in.** The mobile app and the dashboard share one
token store: `POST /api/auth/login` (phone) and `POST /api/auth/admin/login`
(username + password) mint the same kind of Bearer token, and nothing marks a
token as "app" or "dashboard". So an ordinary app user whose row carried
`is_admin = 1` did not need the dashboard login form at all — their **normal app
login token** passed `RequireAdmin`. Production user **23** is exactly that
shape (`is_admin = 1`, `staff_tier = 'user'`, no username, has a password).

**Reproduced end-to-end** against a local backend on the real schema, with a
row seeded in user 23's shape: `POST /api/auth/login` → token →
`GET /api/admin/campaigns` → **HTTP 200 with the campaign list**. Same token
also reached `/api/admin/community` (the الدليل / City Guide queue) and
`/api/admin/users`. After the fix all return **403 `dashboard_access_required`**.

**Wider than reported — two more consequences of the same flag:**

1. `RequireAdminTier` had the identical short-circuit, so `is_admin = 1` also
   conferred *admin-level* authority: trash restore, catalogue CRUD, payment
   methods, global settings.
2. `POST /api/admin/users/:id/admin` (which writes `is_admin`) was gated on
   `perm("users","edit")` — an **employee**-default permission. Any employee
   could stamp `is_admin = 1` on any row, including their own, and self-promote
   past every tier check. That is the most likely origin of user 23's shape.

**The decision: `staff_tier` is authoritative; `is_admin` no longer authorises
anything.** It survives as a display column only. Every gate now routes through
one predicate pair (`auth.IsDashboardStaff` / `auth.IsAdminLevel`), so "who is
staff" has a single answer in a single place.

**Changed:** `backend/internal/auth/middleware.go` (both predicates, all four
gates, plus a `denyAuthz` helper that logs every refusal with user id / tier /
IP and returns a translatable `code`) · `backend/internal/handlers/auth.go`
(`AdminLogin` gates on `staff_tier`, fails closed on lookup error, brute-force
lockout semantics unchanged) · `backend/cmd/server/main.go`
(`/admin/users/:id/admin` → Super-Admin only) ·
`backend/internal/notify/notify.go` (staff broadcast by tier) · admin-web
`lib/api.ts`, `LoginPage.tsx`, `UsersPage.tsx` + 5 `error.*` locale keys × 4
languages.

**Test:** `backend/internal/auth/dashboard_access_test.go`. Verified it FAILS
before the fix (`status = 200, want 403` on the user-23 shape, for both
`RequireAdmin` and `RequireAdminTier`) and passes after.

**Production rows that look misconfigured — NOT modified, for the owner to
decide:**

| id | is_admin | staff_tier | what it means |
|----|----------|-----------|----------------|
| 23 | 1 | `user` | An **app user** who held dashboard + admin-level access. The reported hole. Now blocked. Someone should establish whether this account was meant to be staff — and if not, why it was flagged. |
| 34 | 0 | `super_admin` | The inverse: a genuine Super-Admin the **dashboard login refused**, because the login checked `is_admin`. Now admitted. Has no username/password, so it can only sign in through the app. |

Also worth the owner's attention: of five staff accounts only **id 18** has both
a username and a password, i.e. only one can use the dashboard login form at
all. Ids 1, 15, 19 and 34 are staff who must sign in through the app — which is
how app tokens ended up being the dashboard's de-facto credential in the first
place.

**Out of scope, found on the way — now tracked as A16 and fixed there:**
`POST /api/auth/login` issued a token for a phone with **no password_hash**
without verifying an OTP; the OTP endpoint is separate and the server never
required it. Any account with no password (production id 34 — a `super_admin`)
could therefore be signed in as by anyone who knew the phone number. This is a
bigger blast radius than A15 and was not touched here.

**Not deployed.**

### A16 — diagnosis and fix (2026-08-15)

**Confirmed, and wider than reported: there were TWO doors, not one.**

**Door 1 — `POST /api/auth/login` traded a phone number for a session.** The
handler looked the number up, and *only if* the row had a `password_hash` did it
ask for a password. No hash meant no question asked: it minted a 30-day Bearer
token. For an *unknown* number it created the account first, then minted the
token. Nothing consulted the OTP tables — `/auth/otp/request` and
`/auth/otp/verify` are separate public endpoints the app merely *chose* to call,
and a verified code leaves no durable trace (the record is deleted on success),
so this handler could not have checked one even if it had wanted to. Combined
with A15's finding that the app and dashboard **share one token store with no
marker**, the token issued here was a dashboard token.

**Door 2 — the OTP path never checked a password, and demo mode is on in
production.** `/auth/otp/verify` issues a token for whatever phone verifies a
code, with no password and no tier check — so it reached *every* staff account,
including the ones that do have passwords. And on the production backend
`OTP_DEMO_ENABLED` is **on** while `OTPIQ_API_KEY` is **unset**, so demo is the
only OTP mode that works there — and demo mode **returns the code to the caller
in the `/auth/otp/request` response body** (a fixed value besides). A factor that
hands you the factor is not a factor.

**Production exposure (read-only query, nothing modified):** 36 of 46 accounts
have a phone and no password. Among them:

| id | staff_tier | password | username | exposure before this fix |
|----|-----------|----------|----------|--------------------------|
| 34 | `super_admin` | **none** | none | **The reported hole.** Phone number alone → super-admin session. |
| 1 | `admin` | **none** | none | Same shape, not previously reported. |
| 15, 19 | `admin`, `super_admin` | yes | none | Password bypassable via the demo-OTP door. |
| 18 | `super_admin` | yes | `admin` | Same demo-OTP bypass. The only account that can use the dashboard login form. |

**The decision — a token requires a verified factor, and demo is not one.**

1. **`/auth/login` no longer accepts a phone on its own.** A password account
   verifies its password (unchanged, including the brute-force lockout, which is
   deliberately *not* incremented when no password was submitted — otherwise
   anyone could lock a victim out by replaying their number). A passwordless
   account gets `401 {code: "otp_required"}` and is sent to the OTP flow, which
   is what the app already uses to sign in. The endpoint also no longer creates
   accounts.
2. **A demo OTP can never sign in a staff account** — refused at
   `/auth/otp/request` (so no such code is ever stored) and again at
   `/auth/otp/verify` (so codes stored before this shipped can't be spent),
   `403 {code: "staff_demo_otp_blocked"}`. ⚠️ **Superseded — see the revision
   below.** This left staff with no way in at all under an OTP-only design, and
   the refusal code is now `staff_otp_unavailable`.

**Why not simply bar all staff from the phone path?** Because it would have
locked four of the five staff accounts out of the platform entirely: only id 18
has the username *and* password the dashboard door requires, and A15 already
noted that ids 1, 15, 19 and 34 must sign in through the app. The rule shipped
instead — staff may not authenticate with a factor that proves nothing — closes
the reported hole under the *current* production configuration while leaving
every genuine factor (a password; a real out-of-band OTP once OTPIQ is
configured) working.

**Why not turn demo mode off?** Because ordinary users sign in with it today —
the app's login screen defaults to `mode: 'demo'` precisely because
`OTPIQ_API_KEY` is unset. Turning it off with no SMS provider configured would
lock out every user on the platform. It is an env flag and therefore the owner's
call (§2 rule 1). Ordinary users are unaffected by this fix.

**Effect on the production accounts above:** ids 15, 18 and 19 keep access
(phone + password). **Ids 1 and 34 can no longer sign in** — they have no
password, no username, and real OTP delivery is not configured, so nothing they
hold proves who they are. That is the fail-closed outcome, and those two rows
*are* the vulnerability. Recovery needs no data surgery: id 18 can set a password
for them from the dashboard (`POST /api/admin/users/:id/password`, Users →
edit). **No production data was modified.**

**Changed:** `backend/internal/handlers/auth.go` (`Login` verified-factor gate;
`blockStaffDemoOTP` + its two call sites in `OTPRequest`/`OTPVerify`; every
refusal carries a translatable `code` and is logged with user id, tier and IP;
all lookups fail **closed**) · `backend/internal/users/users.go`
(`StaffTierByPhone`) · app `api/auth_session.dart` (deleted `ensureApiSession`,
the silent re-mint that POSTed the remembered phone number to `/auth/login` —
the same hole seen from the client, and it *cleared the working token before*
the request, so a plain 403 used to sign a working user out) ·
`api/module_api.dart` (drops the retry that called it) ·
`modules/splash/screens/splash_screen.dart` (no token now means sign in again) ·
`api/links.dart` (doc + the orphaned `insertUserWithPhoneUrl`).

**Test:** `backend/internal/handlers/auth_verified_factor_test.go`. Verified it
**FAILS before** the fix — `status = 200, want 401` for a passwordless
`super_admin`, an account created by an unknown number, and a demo code minting
a staff session at all four staff tiers — and **passes after**, while the
legitimate paths (correct password; ordinary user completing request → verify;
real out-of-band OTP for staff) pass both before and after.

**Still open for the owner — this fix does not remove these:**

1. **`OTP_DEMO_ENABLED` is on in production with `OTPIQ_API_KEY` unset.** For
   *ordinary* accounts the demo code is still a free pass, because it is printed
   in the response body. Set `OTPIQ_API_KEY` (and `OTPIQ_SENDER_ID`), confirm
   real delivery, then turn demo off — in that order, or sign-in breaks.
2. **Ids 1 and 34 are privileged rows with no credentials.** Give them a password
   (and ideally a username), or decide they should not be staff.

**Not deployed.**

### A16 — revised to the owner's OTP-only design (2026-08-15)

**The instruction.** "We don't want passwords, it's all going to be with OTP. A
user only enters his phone number and receives an OTP to sign in. For now make
demo OTP until we implement the real OTPIQ API key."

The verified-factor gate above matches that. Its second rule did not: barring
staff from demo OTP was survivable only while "sign in with your password"
remained an answer, and under an OTP-only design it is not one. Ids 1 and 34
hold no password and no username, so they could not sign in at all.

**Checked before changing anything — one claim in the brief was wrong.** It was
put to us that the demo code is already shown on the app's login screen, so the
server could stop returning it in the `/auth/otp/request` body at no cost. It is
not. `_OtpModeRow` at the foot of the sign-in screen offers only a delivery
choice ("WhatsApp / SMS · Demo code"); the string `Code: 123456` survives in the
translation files but no widget renders it. **The response echo is the app's only
source for the code**, so removing it would have ended sign-in for every user on
the platform. It stays for ordinary users, and is the one thing staff never get.

**What changed.**

1. **Delivery is decided by the server, not the caller.** A request for
   `mode: "demo"` is served as a real out-of-band code whenever `OTPIQ_API_KEY`
   is configured. This is what makes the switchover a pure environment change:
   the shipped app hard-codes `mode: "demo"` (it was defaulted that way because
   real delivery 502s with no gateway) and a build already on people's phones
   cannot be told otherwise — so *without* this, setting the key would have
   changed nothing for the users who are actually out there. The same rule now
   governs the dashboard's optional login second factor and the permission-change
   OTP, so no demo code survives anywhere once the gateway is live.
2. **Staff sign in with a code the server never prints.** `OTP_STAFF_DEMO_CODE`
   — six digits, and refused if it equals `OTP_DEMO_CODE` — is stored for a staff
   phone in place of the public code and is left out of the response. The owner
   sets it once and passes it to the five staff members out of band. The flow
   they see is unchanged: phone number, then a code. Unset, malformed, or equal
   to the public code ⇒ `403 {code: "staff_otp_unavailable"}`, which is where
   production stands today, so **ids 1 and 34 remain locked out until this
   variable is set.**
3. **The public code still cannot open a staff account**, including a demo record
   written before any of this shipped: at verify, a demo record standing against
   a staff phone is only spendable by the staff code. A wrong code there answers
   byte-for-byte as any other wrong code (`401 invalid_otp` with the same
   `attempts_left`), so the endpoint cannot be used to ask "is this number staff?"

**The exposure this buys, stated plainly.** While `OTP_STAFF_DEMO_CODE` is set,
**anyone who holds that one code and a staff phone number can sign in as that
staff member — Super-Admin included, dashboard included.** It is a shared
password, not a second factor. It is strictly narrower than the alternative the
instruction implies (letting staff spend the public code, which would need no
secret at all), and strictly wider than today's total block. Treat it as
temporary: set it to a random six digits, give it to staff directly rather than
in a group chat, and **delete it the day `OTPIQ_API_KEY` goes in** — from that
moment it is ignored anyway.

**Rate limiting is unchanged and still applies to all of this:** 10 requests per
IP per hour, a 60-second resend cooldown, an escalating per-phone lock (5 genuine
requests in 15 minutes ⇒ 2h, then 6h, then 24h), and 5 wrong codes per issued
code. Guessing a six-digit staff code is therefore capped at five attempts before
a fresh code is needed and lockout follows. `/auth/login` still does **not** count
a failed attempt when no password was submitted, so nobody can lock a victim out
by replaying their number.

**Real OTP works on an environment change alone — verified, not assumed.**
`TestRealDeliveryTakesOverFromDemo` points the OTPIQ client at a stub gateway,
sends the request the shipped app sends (`mode: "demo"`), and asserts the
response carries no code, the gateway received a generated one, and that code
signs in. `OTPIQ_BASE_URL` was added to make that possible without touching the
network; unset, it is the live API exactly as before.

**Order of operations for the owner:** set `OTP_STAFF_DEMO_CODE` now to get ids 1
and 34 working → set `OTPIQ_API_KEY` (+ `OTPIQ_SENDER_ID`) when the account is
funded → confirm a real code arrives on one number → remove
`OTP_STAFF_DEMO_CODE` and `OTP_DEMO_ENABLED`. The server logs which state it is
in at boot.

**Changed:** `backend/internal/handlers/auth_staff_otp.go` (new — the whole rule,
kept out of `auth.go`, which is already over the size limit) ·
`backend/internal/handlers/auth.go` (`OTPRequest` mode upgrade + demo branch;
`OTPVerify` staff gate; `consumeOTPCode` refusals carry a `code`;
`sendAdminLoginOTP`) · `backend/internal/handlers/admin_permissions.go` (demo
only as fallback) · `backend/internal/auth/otp.go` (`StaffDemoCode`) ·
`backend/internal/auth/otpiq.go` (`OTPIQ_BASE_URL`) · `backend/cmd/server/main.go`
(boot log says which OTP state the server is in) · `backend/.env.example` ·
app `modules/auth/screens/login.dart` (comment only — the default no longer needs
changing by hand).

**Test:** `auth_verified_factor_test.go` gains `TestStaffDemoOTPSignIn`,
`TestStaffDemoCodeMisconfiguration` and `TestRealDeliveryTakesOverFromDemo`. All
were run against the shipped code first and **failed** there (staff request
`403 staff_demo_otp_blocked` where 200 was wanted; a demo request not upgraded to
real), and pass after. The pre-existing cases — phone alone buys nothing, an
unknown number creates no account, a correct password still works, an ordinary
user completes request → verify, the public code cannot open any of the four
staff tiers — pass both before and after.

**Known gap, not introduced here:** the app renders the server's English `error`
string because it has no `code` → message mapping yet (tracked under B4), so the
new staff refusal reads in English on the app. The stable `code` is on every
refusal and every refusal is logged server-side with user id, tier and IP.

**No production data was read or modified in this revision.** Ids 1 and 34 are
still misconfigured rows — privileged, with no credentials of their own — and
setting `OTP_STAFF_DEMO_CODE` is a workaround for that, not a fix.

**Not deployed.**

### A16 — final design: OTP creates the account, a password signs you in (2026-08-15)

**The instruction, verbatim.** "OTP for account creation only, password will be
used for sign in to the app later." This supersedes the OTP-only revision above.

**The problem it creates, and the whole of the answer.** Read-only production
count, re-checked today: **46 accounts, 36 with no `password_hash`.**

| staff_tier | accounts | no password | no username |
|---|---|---|---|
| `super_admin` | 3 | 1 (id 34) | 2 |
| `admin` | 2 | 1 (id 1) | 2 |
| `user` | 41 | 34 | 38 (3 are guests) |

Under "sign in with your password" all 36 are locked out, and ids 1 and 34 cannot
fall back to the dashboard door either — **only id 18 has a username**. So the
design needs a bridge, and the bridge is one sentence:

> **A verified code can do exactly one thing: give a password to an account that
> has NONE.**

Everything else follows from it, and every part is enforced server-side:

1. `/auth/otp/verify` **no longer issues a session.** It returns a single-use
   setup ticket (10 minutes, 5 guesses, bound to that phone) — new table
   `password_setup_tickets`, migration 102. Until now a verified code left *no
   durable trace* at all, which is why nothing could ever check one.
2. `/auth/password/set` spends the ticket and writes the FIRST password. The
   write is `UPDATE … WHERE password_hash IS NULL OR is empty`, so two racing
   claims cannot both win and an existing password can never be overwritten.
3. A code therefore **cannot open an account that already has a password** —
   refused `409 password_required` before anything is issued. That closes a hole
   nobody had reported: until today the public demo code signed in *any* account,
   password or not, so the ten accounts that do have one (ids 15, 18, 19 among
   them) were protected by nothing.
4. The claim is **once per account, for good.** The window shuts the moment the
   legitimate owner uses it.
5. **Staff are not claimable on the public code.** A staff phone still needs
   `OTP_STAFF_DEMO_CODE` (never printed by the server) while demo delivery is all
   there is — the gate from the previous revision, now guarding a one-time claim
   rather than an unlimited session.

**The exposure, stated plainly.** While demo OTP is on, anyone who knows the
phone number of one of the 34 non-staff passwordless accounts can claim it once
by setting a password — and after that the account has a real credential no code
can touch. That is **narrower than what production does today**, where the same
person gets a full 30-day session on that number, repeatedly, forever. For the
two staff accounts the claim additionally needs `OTP_STAFF_DEMO_CODE`, and it is
spent on first use. The exposure shrinks every time a user signs up, and ends
entirely when `OTPIQ_API_KEY` is configured.

**There is deliberately NO self-service forgot-password, and this is the finding
the owner should act on.** A reset flow is this same flow with the bound removed:
under demo delivery it would make *every* account on the platform permanently
seizable by phone number, which is worse than what we started with. **A safe
forgot-password requires real OTP delivery — i.e. `OTPIQ_API_KEY` configured.**
Until then a forgotten password is reset by staff through the existing
`POST /api/admin/users/:id/password`, which is already rank-guarded (H13).

**Order of operations for the owner (revised).** Set `OTP_STAFF_DEMO_CODE` so
ids 1 and 34 can claim their accounts → tell those two staff members to sign in
once and choose a password → **remove `OTP_STAFF_DEMO_CODE`** (it is spent; they
now have real passwords) → set `OTPIQ_API_KEY` when funded → confirm a real code
arrives → remove `OTP_DEMO_ENABLED` → self-service password reset becomes safe to
build. Migration 102 applies itself on the next deploy (`RUN_MIGRATIONS=1` is
already set on the backend service).

**App.** The login screen now has two modes: **Sign in** (phone + password) and
**Create an account** (phone → code → choose a password). A `401 otp_required`
is answered with an action, not a scolding — a card offering "Verify my number",
which leads to the same code screen and then to the new create-password screen.
Inline per-field validation, `visiblePassword` keyboards, show/hide toggles, the
return key moving through the form, in-button loading, and one shared post-sign-in
finish for all three routes in (`completeSignInAndRoute`). en + ar only; the 25
new strings are listed for a Kurdish translator in `TRANSLATION_REQUEST.md`.

**Changed:** `backend/migrations/102_password_setup_tickets.sql` (new) ·
`backend/internal/auth/password_setup.go` (new — ticket store + the password
rules) · `backend/internal/handlers/auth_password_setup.go` (new —
`POST /auth/password/set`) · `backend/internal/handlers/auth.go` (`OTPVerify`
issues a ticket instead of a session and refuses accounts that have a password;
`Login` comments/messages) · `backend/internal/users/users.go`
(`SetPasswordIfUnset`) · `backend/cmd/server/main.go` (route) · app
`controllers/login.dart`, `core/auth_navigation.dart`, `api/links.dart`,
`modules/auth/screens/{login,verification,create_password}.dart`,
`routes/app_routes.dart`, `main.dart`, `localization/app_translations.dart`.

**Test:** `auth_verified_factor_test.go` gains `TestOTPCannotOpenAnAccountThatHasAPassword`,
`TestPasswordSetupBridge` (11 cases) and `TestOTPRequestRateLimitBoundsEnumeration`,
and the existing OTP cases were rewritten to the new rule. All were run against
the shipped code first and **failed** there — a demo code returned `200` with an
`access_token` for an account that has a password — and pass after. The file is
written so it still COMPILES at the previous commit, so anyone can reproduce that.

**Not deployed. No production data was modified; the counts above come from
SELECT-only queries.**

## B. English leaking into the Arabic UI (hard project rule)

| # | Item | Where | Status |
|---|---|---|---|
| B1 | Notification **type filter options are raw English enums** — `beneficiary_case_submitted`, `marriage_approved`, `new_campaign`, `support_ticket_resolved`, `system_test`, `volunteer_application_*` … | App → الإشعارات → التصفية حسب النوع | ⬜ |
| B2 | **"Support Assistant / Ask me anything — I'll guide you through the app"** is in English | App → الرسائل, top card | ⬜ |
| B3 | Place detail shows a **raw JSON array** `["commercial","government","education","health"]` instead of readable sector names | Dashboard → دليل المدينة → عرض | ⬜ |
| B4 | Login screen is in English (`Secure sign in`, `Phone number`, `Send OTP`, `Continue as guest`, `Don't have an account?`) | App → login | ⬜ |
| B5 | Place list shows status `approved` in English | Dashboard → دليل المدينة table, الحالة column | ⬜ |
| B6 | General: "انكليزي لم يتم الترجمه" — untranslated English remains in places. PDF restates it as a global requirement: "إلزام النظام بتعريب وترجمة كافة الكلمات والعبارات التي ما زالت تظهر باللغة الإنجليزية في جميع قوائم لوحة التحكم عند اختيار اللغة العربية أو اللغة الكردية" — client wants it fixed once as a Global Function. `[D p2, p3]` | App + Dashboard | ⬜ |
| B7 | User read-only detail page renders **raw DB column names**: `active`, `created_at`, `id`, `is_admin`, `password_hash`, `phone`, `registration_reject_reason`, `registration_reviewed_at`, `registration_reviewed_by`, `registration_status`, `registration_submitted_at`, `role_id` — plus the header **"Read-only view."** and the value `approved`. Screenshot annotated "Need to be Translated". `[D p1]` | Dashboard → المستخدمون → عرض (مستخدم #10) | ⬜ |
| B8 | Same page shows **numeric ids where names belong**: `registration_reviewed_by: 8` and `role_id: 2`. Client: "يذكر اسم المشرف" (show the supervisor's name) and "يذكر اسم الدور المعرف" (show the role name). `[D p1]` | Dashboard → المستخدمون → عرض | ⬜ |
| B9 | Same page shows **raw ISO timestamps** `2026-06-14T11:13:32.50385Z` instead of a localized Arabic date/time. `[D p1]` | Dashboard → المستخدمون → عرض | ⬜ |
| B10 | **Edit-campaign modal is 100% English**: "Edit Campaign #4", `LIFECYCLE STATUS`, "Active — accepting donations", `TITLE (EN)/(AR)/(SORANI)/(BADINI)`, `ADDRESS`, `BENEFICIARIES`, `GOAL AMOUNT`, `RAISED AMOUNT`, `DESCRIPTION (EN)/(AR)/(SORANI)`, `Cancel`, `Save changes`. Client: "ترجم حسب اللغة / Translated based on web language". `[D p2]` | Dashboard → الحملات → تعديل | ⬜ |
| B11 | Status dropdown shows the raw term `needs_changes`. `[D p4]` | Dashboard → المستفيدون → الحالة | ⬜ |
| B12 | Status dropdown shows the raw term `matched` — client suggests "مُتطابق" or "تم التوفيق". `[D p5]` | Dashboard → زواج → الحالة | ⬜ |
| B13 | Status dropdown shows the raw term `published`; and the "متخفي" (hidden) option needs renaming — "تعديل التسمية في القائمة المنسدلة كلمة (متخفي)". `[D p5]` | Dashboard → الاخبار والاعلام → الحالة | ⬜ |
| B14 | The **"Add place"** button at the top of the list is in English. `[D p5]` | Dashboard → دليل المدينة | ⬜ |
| B15 | The action button is labelled **"mark completed"** in English. `[D p6]` | Dashboard → المهام | ⬜ |
| B16 | Per-section Arabization sweep still outstanding when Arabic is selected, section by section: **الحملات** `[D p4]`, **زواج** (الوجهة والتفاصيل) `[D p5]`, **الرسائل** `[D p5]`, **لوحة المتطوعين** `[D p6]`, **الكفالات** (page data + details) `[D p6]`, **الدعم** (dropdown) `[D p7]`, **الاشعارات** (top-left "كل الملفات" dropdown + category field/data) `[D p7]`, **الاشعارات الفورية** (whole interface + dropdown) `[D p7]`, **التقارير** (all interface words) `[D p7]`, **سجلات التدقيق** (dropdowns) `[D p7]`, **المستخدمون → عرض** `[D p3]`, **دليل المدينة → عرض** `[D p5]`. Test each separately. | Dashboard, per section | ⬜ |
| B17 | Words and options under the **الأولوية** (priority) column are still English. `[D p4]` | Dashboard → المستفيدون → الأولوية | ⬜ |
| B18 | **Gender dropdown options not Arabized** — "تعريب خيارات القائمة المنسدلة الخاصة بالجنس في الواجهة العربية". `[D p3]` | Dashboard → المستخدمون → تعديل → الجنس | ⬜ |
| B19 | The Arabic wording **"حالة دورة الحياة"** (lifecycle status) is wrong and must be corrected — "تصحيح كلمة حالة دورة الحياة في اللغة العربي". `[D p4]` | Dashboard → الحملات → حملة جديدة | ⬜ |
| B20 | Top dropdown headers (**الكل، المهام، أي يوم**) are unnamed/English, and all option words inside those dropdowns are untranslated. `[D p6]` | Dashboard → المتطوعين → الطلبات | ⬜ |
| B21 | **Choosing a language must translate ALL app text** — "عند اختيار لغة معينة يجب أن يكون جميع الكلام الموجود داخل التطبيق باللغة التي تم اختيارها". Test by switching each of the four languages and sweeping every screen. `[A p34]` | App | 🔎 **marketplace orders fixed, not deployed** — see B21 notes below. The sweep itself is still outstanding |

### B21 — marketplace order card (2026-08-15)

**Two machine values were printed onto one card in the Arabic UI.**

`marketplace_orders_screen.dart` passed the **raw order status** to
`AppStatusTag`, which renders `label.tr.toUpperCase()`. GetX returns the key
unchanged when it has no entry, and there were **no entries for any of the five
statuses** — so `approved` / `pending` / `processing` / `completed` /
`cancelled` rendered as Latin capitals, right-to-left, directly beside money
that `_formatMoney` was already localizing correctly.

The same card interpolated `created_at` as-is, so it read
**`Submitted: 2026-08-15T12:15:35.660229Z`** — Go's RFC 3339 marshalling,
shown to a person.

**Fixed with the app's existing mechanisms, not new ones.** The status goes
through `localizedTag`, which is already the single mechanism for backend tags,
and the five statuses gained `en` + `ar` entries. The date goes through a new
`localizedDate` in the **same file as `localizedTag`** — the eight screens that
format a date each carry their own private copy of the same five lines, and
adding a ninth was the wrong answer. `AppLocaleService.syncDateFormatLocale`
already pins `Intl.defaultLocale` on every language switch, so it takes no
locale argument.

`_statusTone` still switches on the RAW status — the tone is a mapping from a
machine value and must not depend on a translation.

The screen's four states were already correct (`AppAsync`, error checked before
empty) and were left alone.

**Test:** `humanitarian/test/localization/marketplace_order_labels_test.dart`.
Verified 2 of its 8 fail without the translation keys — the Arabic assertion
and the one proving `AppStatusTag`'s second `.tr` + `toUpperCase()` cannot
resurrect the token. The date tests pin `localizedDate`'s contract; that helper
landed one commit earlier (with E8), so they pass on either side of this change
rather than failing first.

**Left deliberately:** the other six copies of the private date formatter are
untouched — migrating them is a labelled refactor of its own, not a drive-by.
And B21 as a whole is a four-language sweep of every screen; this closes one
card, not the row.

## C. Duplication / information architecture

| # | Item | Where | Status |
|---|---|---|---|
| C1 | **"شركاؤنا" (Our Partners) appears 3–4 times**: profile menu, خدماتنا, bottom of home. Owner wants it in ONE place only. NOTE: a previous pass removed a duplicate drawer row — verify what remains and remove the rest. PDF separately specs a single dedicated الشركاء section (see K6). `[A p23]` | App | ⬜ |
| C2 | "هنالك قوائم لا تظهر ما هي؟" — lists on the City Guide screen that do not appear / are unexplained | App → دليل المدينة | ⬜ |
| C3 | **Notification icon is duplicated top AND bottom of the app** — "يوجد حالياً تكرار لأيقونة التنبيهات في أعلى وأسفل التطبيق". Keep ONE place only; merge into the profile area or the top bar. `[A p20]` | App | ⬜ |
| C4 | **"من نحن" and "اتصل بنا" repeat inside خطوبتي and دليل الموصل الشامل** — and with *different* details, addresses and phone numbers than the aid numbers: "لكن بتفاصيل ومواقع وأرقام تواصل مختلفة عن أرقام المساعدات". Decide whether that divergence is intentional. `[A p28]` | App → خطوبتي, دليل الموصل | ⬜ |
| C5 | **"Send a request" is duplicated three times on the beneficiary side**: الواجهة الرئيسية (خيار إرسال طلب), الإجراءات السريعة (إرسال), الكفالة (إرسال مشروع مساعدة). Client: "تم تكرار هذا الخيار في جميع ما ذكر، نرجو توضيح ذلك" *(needs owner clarification — he is asking us to explain it)*. `[A p34]` | App → لوحة المستفيد | ⬜ |
| C6 | Move **الخدمات off the home screen into الملف الشخصي** — "نقل قسم الخدمات من الصفحة الرئيسية إلى داخل صفحة الملف الشخصي". `[A p20]` | App | ⬜ |
| C7 | Move **خدمات المجتمع entirely into الملف الشخصي**. `[A p34]` | App | ⬜ |
| C8 | For beneficiary accounts, **move الرسائل out of the bottom bar into the profile icon** — "عند التسجيل كمستفيد، نقل الرسائل في الشريط السفلي إلى أيقونة الملف الشخصي". `[A p34]` | App → beneficiary bottom bar | ⬜ |
| C9 | **دليل المجتمع** and **تبرعات عينية** need the same repeated fixes listed at the top of the document — "نفس إجراءات التعديل المكرر والمذكور في البداية (تنسيق العرض - تسمية اخر حقل الخ)". Verify both sections against G1/D6. `[D p5, p7]` | Dashboard | ⬜ |
| C10 | **Split دليل المدينة/الموصل and الزواج/خطوبتي into their own standalone tab/interface**, away from the humanitarian sections — "لضمان سرعة الوصول والتمييز البصري، بعيداً عن أقسام العمل الإنساني". `[A p33]` | App navigation | ⬜ |

## D. Dropdowns / labels

| # | Item | Where | Status |
|---|---|---|---|
| D1 | User-type dropdown contains **"بلا"** and **"—"**. Rename: one → **زائر** (guest), the other → **خاطب** or another term for a user registered for marriage. PDF confirms the current list is (متبرع — مستفيد — متطوع — بلا). `[D p3]` | Dashboard → المستخدمون → نوع المستخدم | ⬜ |
| D2 | Marriage applicant details are missing entirely — "اين بيانات او تفاصيل الشخص الذي يقوم بتسجيل بياناته كطالب للزواج". The field set the client expects is fully specified in the app PDF — see L15–L19. `[A p9–p13]` | Dashboard → الزواج | ⬜ |
| D3 | **مشرف dropdown: add a "موظف" (employee) option** alongside the current (ادمن — مشرف — المستخدم). `[D p3]` | Dashboard → المستخدمون → مشرف | ⬜ |
| D4 | **الدور dropdown: add "موظف"** to the roles list, currently (متبرع — مستفيد — متطوع — بلا). `[D p3]` | Dashboard → المستخدمون → الدور | ⬜ |
| D5 | Rename the **"أي يوم"** option to something linguistically accurate — "استبداله بتسمية أدق لغوياً مثل (الأيام أو أيام الأسبوع)". `[D p6]` | Dashboard → المتطوعين → قائمة المهام الأيام | ⬜ |
| D6 | **Every dashboard table's last column has an empty header** (the one holding عرض/تعديل/حذف). Name it **"الإجراءات"** or **"خيارات"** in ALL tables, to unify table appearance. `[D p2]` | Dashboard, all tables | ⬜ |
| D7 | In the profile, **replace the long expanded language list with an arrow/dropdown selector** — "تبديل العرض المطول للغات بسهم ويتم الاختيار، وبقائمة منسدلة أو بطريقة أخرى". `[A p34]` | App → الملف الشخصي → اللغة | ⬜ |

## E. Forms / validation / display

| # | Item | Where | Status |
|---|---|---|---|
| E1 | **Phone number still displays incorrectly** — explicitly "لم يتم تصحيح العرض" (was reported before and not fixed). PDF adds the suspected cause: untrimmed whitespace, and digits fragmenting when the interface flips to Arabic. `[D p9, p10]` | App + Dashboard, wherever phone is shown | ⬜ |
| E2 | Phone should be **editable**, and the identifier (المعرّف) should be a **code**, not a raw row id | Dashboard → المستخدمون | ⬜ |
| E3 | **Image size must be constrained** when a user picks a profile photo. PDF adds the carve-out: auto-compress and resize account images, **except** medical case documents, important documents, house photos and medical reports, which keep original size and quality "لضمان وضوح تفاصيلها عند الفحص". `[D p10]` | App → تعديل الملف الشخصي | ⬜ |
| E4 | Login **error text is red on a background that does not suit it** — contrast/legibility | App → login | ⬜ |
| E5 | **No countdown timer** showing how long until the OTP can be re-requested ("Please wait before requesting another code" with no timer). Related backend requirement: H22 (progressive rate limiting). | App → login | ⬜ |
| E6 | City Guide: "كيفية اضافة رابط" — how to add a link is unclear | Dashboard → دليل المدينة | ⬜ |
| E7 | **Trim spaces in phone number fields programmatically** — "إلغاء الفراغات والمساحات الزائدة (Trim Spaces) داخل حقول أرقام الهواتف برمجياً، لمنع تشتت الأرقام وظهورها بشكل غير نظامي عند تحويل الواجهة للغة العربية". `[D p10]` | App + Dashboard, phone inputs | ⬜ |
| E8 | **Rejection reason never appears in the dashboard** — "إصلاح مشكلة عدم ظهور سبب الرفض في لوحة التحكم، وإلزام النظام بعرض نص وسبب الرفض المكتوب بوضوح". Client also asks that reasons be written in Arabic, and asks **"ماهي الحالات التي تضهر فيها اسباب الرفض"** *(needs owner clarification — which states surface a reason)*. `[D p1, p4]` | Dashboard → المستخدمون / registrations | 🔎 **beneficiary cases fixed, not deployed** — see E8 notes below |
| E9 | **No "تعديل الباسوورد" option inside the user edit page** — "إضافة خيار (تعديل الباسوورد) داخل صفحة تعديل اليوزر". `[D p3]` | Dashboard → المستخدمون → تعديل | ⬜ |
| E10 | **التسجيلات has no details and no export** — "لا يوجد فيها تفاصيل وأيضا لا يوجد فيها خيار التصدير". `[D p4]` | Dashboard → التسجيلات | ⬜ |
| E11 | Delivery needs an optional **"إيقاف أو أرشفة"** — "إضافة خياري (إيقاف أو أرشفة) لعملية التسليم". `[D p4]` | Dashboard → التبرعات → التسليم | ⬜ |
| E12 | **Partner images do not appear in the table** — and should show the actual company image, not the fixed default icon: "تغييرها لتُعرض الصورة الفعلية للشركة بدلاً من أيقونة الصورة الافتراضية الثابتة". `[D p5]` | Dashboard → الشركاء | ⬜ |
| E13 | **Last actions column has no "عرض" button** — the user cannot open an entry's details, nor see the id of the user who added it: "لكي يتمكن المستخدم من الدخول واستعراض تفاصيل البيانات ومعرفة اليوزر الذي قام بعملية الإضافة". `[D p5]` | Dashboard → دليل المدينة → الإجراءات | ⬜ |
| E14 | **حقل التقديم layout breaks when the dropdown options change** — "الذي يحدث عند تغيير خيارات القائمة المنسدلة، مما يؤدي إلى تغير أبعاد الحقول وزحف البيانات وعدم تنسيقها". `[D p6]` | Dashboard → المتطوعين → تسجيلات المهام | ⬜ |
| E15 | Add a **fixed field/list that always shows the action commands** (موافق، قبول، رفض، تراجع، حذف) so edit and rollback are possible at any time. `[D p6]` | Dashboard → المتطوعين → تسجيلات المهام | ⬜ |
| E16 | **Login phone input must accept international numbers** — "عند تسجيل الدخول يجب أن يكون رقم الهاتف مويد يدعم جميع دول العالم" (country-code support for every country). `[A p34]` | App → login | ⬜ |
| E17 | **Profile edits must not save until an employee approves** — request goes to the dashboard; "لا تُعتمد التغييرات إلا بعد مراجعتها والموافقة عليها من قبل موظف التطبيق"; employee can accept or reject with a stated reason. `[A p26, p34]` | App → تعديل الملف الشخصي + Dashboard | ⬜ |
| E18 | **All registration and profile-edit requests go through a review workflow** for donors, volunteers and beneficiaries — "ولا يتم تفعيل الحساب أو عرض بياناته إلا بعد الموافقة النهائية" by the follow-up/evaluation employee. `[A p33]` | App + Dashboard | ⬜ |

### E8 — diagnosis and fix, beneficiary cases (2026-08-15)

**Answering the client's own question — "ماهي الحالات التي تضهر فيها اسباب
الرفض" — for this resource: `rejected` and `needs_changes` now REQUIRE a
reason, `approved` clears any earlier one, and every other transition leaves
the note alone.** Registrations already had a reason flow (`RegistrationsPage`);
beneficiary cases had none, which is the gap closed here.

**Approving or rejecting an aid case recorded nothing but the word.**
`POST /admin/beneficiary_cases/:id/status` ran through the generic
`updateStringStatus`, which writes exactly one column. `beneficiary_cases` has
carried `review_notes`, `reviewed_by_user_id` and `reviewed_at` since migration
001 — with an FK on the reviewer — and **nothing ever wrote them**, so:

- the reviewer's reason went nowhere (the only way to record one was to abandon
  the status control and open the edit modal, which notifies nobody);
- no query returned the reviewer or the decision date, to the app or the
  dashboard, so nobody could see who decided;
- `BeneficiaryCaseRejectedMsg` took no reason and its copy said *"Please
  contact support for details"* — sending the applicant to ask for an answer a
  member of staff had already typed.

HANDOFF's acceptance criterion ("reviewer name + rejection reason shown in the
app") was therefore unreachable by any code path.

**Changed, backend:** `admin_status.go` — `updateStringStatus` now delegates to
`updateReviewedStringStatus`, which takes an OPT-IN `reviewStamp`. The other
eleven status resources pass nil and behave byte-for-byte as before; only
beneficiary cases stamp reviewer + timestamp and record the reason.
`statusReq.ReviewNotes` is a `*string` so three cases stay apart — absent
(leave the note), empty (clear it), present (record it). The reviewer is
written NULL rather than 0 when the actor cannot be resolved, because the
column carries an FK. · `admin_status_notify.go` passes the reason on. ·
`templates.go` — `reasonTail` extracted from `RegistrationRejectedMsg` so
`BeneficiaryCaseRejectedMsg` reuses **those exact four strings** instead of
composing new Kurdish. · `beneficiary.go` — one shared `caseColumns` projection
across all three case queries, adding `reviewed_by_name` and `reviewed_at`. The
name comes from a scalar SUBQUERY, not a join: joining `users` would put a
second `phone`, `full_name` and `city` in scope and `AdminListCases`' search
filter matches on exactly those unqualified names.

**Changed, app:** `beneficiary_case_detail_screen.dart` — a Review-decision
panel directly under the summary (reason, reviewer, date); an applicant who has
been refused should not read past nine rows of their own data to find out why.
`_DetailLine` gained `translateValue: false` so a person's name is never
swapped for a translation it happens to collide with. `verification_status` and
`priority_level` now route through `localizedTag` — they were printed raw, so
an Arabic reader saw "needs_changes". Same for the list subtitle, whose
`replaceAll('_', ' ')` only made the English prettier.

**Changed, dashboard:** `StatusCell` gained an opt-in `reasonRequiredFor`,
which opens a required reason box (reusing `EditModal`, so validation, Esc,
click-outside and error display come for free) and does NOT flip the visible
value until the operator confirms. `BeneficiaryPage` passes
`['rejected', 'needs_changes']`, sends `review_notes: ''` on approve, and shows
the reason plus "Reviewed by {name} · {date}" under the status cell — the E8
complaint itself, since the reason previously lived only inside the edit modal.

**Bulk status changes deliberately collect no reason.** One sentence cannot
honestly stand for a decision on twenty different cases. They still stamp the
reviewer and the date, and a bulk approve still clears a stale reason.

**Verified against a real database and the real HTTP endpoint**, on a scratch
DB migrated from `backend/migrations`:

| Check | Result |
|---|---|
| reject with a reason | `review_notes` + `reviewed_by_user_id=8` + `reviewed_at` all persisted |
| the applicant's notification | *"…was rejected. Reason: Missing the tenancy contract…"* / *"…السبب: …"* |
| status change with no `review_notes` key | note untouched, reviewer + date still stamped |
| approve with `review_notes: ""` | stale rejection reason cleared to NULL |
| app + admin case payloads | `reviewed_by_name: "Sara Al-Rawi"`, `reviewed_at` present |

**Tests:** `backend/internal/notify/templates_review_test.go` and
`humanitarian/test/localization/case_review_labels_test.dart`. The Flutter one
was verified to FAIL before the fix — 5 of 7 failing, the case statuses and the
panel labels having no Arabic at all.

**Not deployed. No production data touched** — all verification ran against a
scratch database.

**Left deliberately:** `beneficiary_project_requests` uses the same generic
endpoint and has no review columns, so it is unchanged; giving it the same
treatment needs a migration and is its own item. The `PATCH` edit form can
still set `review_notes` without notifying anyone — a second way in that
predates this and is worth closing separately.

## F. Missing dashboard features

| # | Item | Where | Status |
|---|---|---|---|
| F1 | **No dark/light mode toggle** — "لم نجد خيار تفعيل الوضع الليلي والعادي في الداشبورد". NOTE: a theme button exists in the header (`Switch to light mode`) — verify whether it works and is discoverable, since the client could not find it. | Dashboard | ⬜ |
| F2 | **No manual setting for browser auto-logout time.** PDF specs it precisely: "تحديد جلسة العمل (Session Timeout): تسجيل خروج تلقائي وقفل قسم الصلاحيات فوراً في حال ترك المدير لوحة التحكم مفتوحة وبدون حركة لمدة دقيقتين او يحدد الوقت من قبل المدير، ويطلب منه الرقم السري مجدداً للدخول." `[D p8]` | Dashboard → إعدادات النظام | ⬜ |
| F3 | **Unified fixed top action bar in every dashboard section**: رجوع (back), التالي (next), تحديث/Refresh, حفظ البيانات/خزن. `[D p3]` | Dashboard, all sections | ⬜ |
| F4 | **Admin notification on every user operation** (change user, edit, add user), stored permanently in reports and deletable only by the admin — "مع تخزين العملية في التقارير بشكل دائم ولا تُحذف إلا من قبل الادمن". `[D p4]` | Dashboard → المستخدمون | ⬜ |
| F5 | **Export option missing entirely** in: التسجيلات `[D p4]`, الرسائل `[D p5]`, لوحة المتطوعين `[D p6]`, الاشعارات `[D p7]`, الاشعارات الفورية `[D p7]`, التقارير `[D p7]`. Gating rules for export are in H16. | Dashboard, per section | ⬜ |
| F6 | **No way to add a user manually** — "إضافة خيار (يوزر جديد) لكي يتمكن المشرف أو الادمن من إضافة يوزر يدوياً". `[D p3]` | Dashboard → المستخدمون | ⬜ |
| F7 | **قائمة المهام is not editable**: add the ability to insert a new mission manually into the dropdown, edit existing missions, change their sections, and reorder them. `[D p6]` | Dashboard → المتطوعين → قائمة المهام | ⬜ |
| F8 | **Dashboard-side project management**: show/hide, temporarily disable, re-enable, add, delete and edit each donation project. Client's own examples: disable النفط الأبيض in summer, disable المستلزمات الدراسية after the school season, stop accepting donations for a medical case once the amount is met or the case is cancelled. `[A p17]` | Dashboard → المشاريع | ⬜ |
| F9 | **Dynamic CMS admin panel** — add, edit or hide sections, menus and fields with no code change; a responsive web dashboard working on browsers, desktop and phones. `[A p34]` | Dashboard | ⬜ |
| F10 | Authorized employees can **search and instantly verify beneficiary data (by name or national id) against دائرة الرعاية والشؤون الاجتماعية** databases. `[A p34]` *(needs owner clarification — external integration, legal and feasibility unconfirmed)* | Dashboard | ⬜ |
| F11 | **Reports pulling beneficiary/donor/activity/operation data, exportable as Excel and Word.** `[A p34]` | Dashboard → التقارير | ⬜ |
| F12 | **Comment moderation**: delete abusive comments, auto-filter against a pre-set banned-words list, and update that list from the dashboard. `[A p22]` | Dashboard → أعمالنا comments | ⬜ |

---

## G. Dashboard — RTL direction & table/column alignment

The client flags this as one repeated global defect and asks for one global fix:
"هناك مشاكل عامة ومشتركة تتكرر في أغلب الواجهات والقوائم، وبمجرد حلها برمجياً كدالة عامة (Global Function) … سيتم حلها تلقائياً في كافة صفحات الملف دفعة واحدة" `[D p2]`.

| # | Item | Where | Status |
|---|---|---|---|
| G1 | **Detail/view pages put labels at the far right and data at the far left** in Arabic and Kurdish — "حيث تظهر التسميات أقصى اليمين والبيانات أقصى اليسار، والمطلوب تعديل محاذاة النصوص لتصبح متقاربة ومتجانسة جهة اليمين". `[D p3]` | Dashboard, all عرض/تفاصيل pages | ⬜ |
| G2 | **Data breaks when the dashboard direction flips fully RTL** — "مع مراعاة عدم حدوث مشكلة في البيانات اذا تغير اتجاه لوحة التحكم بالكامل من اليمين إلى اليسار (RTL Direction)". `[D p3]` | Dashboard, global | ⬜ |
| G3 | **التبرعات table: Arabic column headers do not line up with the data beneath** — "إزاحة بين عنوان العمود والبيانات مثل المعرف، المجموع، والمتبرع". `[D p4]` | Dashboard → التبرعات | ⬜ |
| G4 | **المستفيدون table misalignment**: the المعرف column renders empty, its data shifts under "رمز الحالة", and the المتبرع data lands under "العنوان". `[D p4]` | Dashboard → المستفيدون | ⬜ |
| G5 | **السوق table misalignment**: the selection checkbox appears under a heading, images appear under the name, details appear under the category. `[D p4]` | Dashboard → السوق | ⬜ |
| G6 | **الكفالات top column header row is irregular** — "تعديل العمود الأعلى لأنه غير نظامي (البيانات مُزاحة عن العناوين)". `[D p6]` | Dashboard → الكفالات | ⬜ |
| G7 | The same RTL fix is required on **المستخدمون → عرض** `[D p3]` and **دليل المدينة → عرض** `[D p5]` — "لتكون التسمية والتفاصيل متقابلة ومظهرها متناسق (ليست أقصى اليمين وأقصى اليسار)". | Dashboard | ⬜ |
| G8 | **User detail page field order follows the English layout** — "تحتاج الى اعادة ترتيب حسب الواجهة الانكليزي … الواجهه يجب تتحول RTL وتترجم". Screenshot shows two red boxes, labels and values split across the screen. `[D p1]` | Dashboard → المستخدمون → عرض | ⬜ |

## H. Dashboard — permissions, sessions, audit & security (new subsystem)

`[D p8–p9]` describes a whole new admin-only section: **"الضبط او إدارة الصلاحيات (إضافة جديدة) القسم الرئيسي للمدير الأساسي حصراً"**. Session timeout is tracked as F2.

| # | Item | Where | Status |
|---|---|---|---|
| H1 | **New "إدارة الصلاحيات" section, main admin exclusively**, with 2FA: password then a temporary OTP (رمز تأكيد مؤقت) sent to phone or email — on login *and* when confirming any change to permissions. `[D p8]` | Dashboard → new section | ⬜ |
| H2 | Main admin can **choose which menus each user may enter** (e.g. قائمة المستفيدين، قائمة المنتجات) and **hide the rest entirely**. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H3 | **Per-section operational precision**: الاطلاع فقط / التعديل / الأرشفة / الحذف / إضافة جديد. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H4 | **Full show/hide control of sections, side menus and interfaces per role** (مشرف، ادمن، موظف، مستخدم). `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H5 | **Grant or block export/download permission (Excel and PDF)** for every interface and table in the application. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H6 | **Detailed per-section, per-table control of add / edit / delete / archive**, each section handled separately. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H7 | **Grant or block viewing financial reports, statistics, and Audit Logs.** `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H8 | **Control activating/deactivating accounts, products or stores** and temporarily disabling them from the dashboard. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H9 | **Control who may change product status** (مقبول، مسودة، مرفوض) based on the products table. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H10 | **Control who may see sensitive contact data** (رقم الهاتف والإيميل) — otherwise hidden/encrypted "لحماية البيانات وتشفيرها". `[D p8]` | Dashboard → الصلاحيات | 🔎 partly — see the H10/B7 note below |
| H11 | **Force logout the instant an account is disabled or its permissions are reduced** — "يتم إنهاء جلسة ذلك اليوزر فوراً وعمل تسجيل خروج تلقائي له (Force Logout) لتطبيق التعديل في نفس اللحظة". `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H12 | **Audit Log**: a dedicated DB record of the time, date and IP of every change the admin makes in this section (example given: "المدير قام بتعديل صلاحية الموظف أحمد"); read-only, cannot be finally deleted. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H13 | **Super Admin protection**: no other user — even "ادمن" or "مشرف" — may edit, disable, or change the permissions of the "المدير الأساسي / Super Admin" account from inside the dashboard. `[D p8]` | Dashboard → الصلاحيات | 🔎 **confirmed, fixed, not deployed** — see H13 notes below |
| H14 | **Temporary block + immediate auto-logout with SMS confirmation to lift**, triggered when repeated and rapid change/delete operations are detected in this section. `[D p8]` | Dashboard → الصلاحيات | ⬜ |
| H15 | **Global trash**: every delete anywhere moves to سلة المهملات automatically; final delete only from inside the trash, by the main admin, with mandatory password, item-by-item or select-all. Employees get **archive** instead of delete — "مع إضافة الأرشفة كبديل للموظفين". `[D p3, p9]` | Dashboard, global | 🔎 **confirmed, fixed (29 of 31), not deployed** — see H15 notes below |
| H16 | **CSV export gated**: enabled only for the main admin or users he authorizes, "مع فرض إدخال الرقم السري كشرط أساسي مسبق لإتمام عملية تصدير البيانات". `[D p3]` | Dashboard, all export buttons | ⬜ |
| H17 | **JSON database export restricted to the main super admin exclusively**, or whoever he grants that permission from the permissions section. `[D p7]` | Dashboard → تصدير قاعدة البيانات | ⬜ |
| H18 | **Force Logout (إنهاء الجلسات النشطة)**: end any user's session immediately, or revoke login from the phone and from the dashboard entry points. Note this overlaps A2 — the existing button reportedly does not work. `[D p9]` | Dashboard | ⬜ |
| H19 | **Force Actions (الإدارة الفورية لليوزرات)**: force logout, temporary/permanent block, or move to trash immediately for **any** rank of user — عادي، متطوع، مشرف، مساهم. `[D p9]` | Dashboard | ⬜ |
| H20 | **Main-admin account protection**: password + extra protection protocol; change only via a confirmation code sent through **both** phone and email. `[D p3]` | Dashboard → المستخدمون | ⬜ |
| H21 | **Require password entry as a condition when changing user roles** — "تفعيل حماية طلب إدخال رقم سري كشرط عند تغيير الأدوار لليوزرات". `[D p3]` | Dashboard → المستخدمون | ⬜ |
| H22 | **Rate limiting on OTP/login abuse**: on detecting repeated, continuous login/logout that burns OTP SMS, lock attempts progressively — **2 hours, then 6 hours, then a full day** if attempts continue. `[D p10]` | Backend / App login | ⬜ |
| H23 | **Auto-generated identity codes instead of real names** for donors and beneficiaries at registration, "مع حظر عرض أي بيانات خاصة إلا بموافقة صاحب العلاقة". `[A p33]` | App + Dashboard | ⬜ |

### H13 — diagnosis and fix (2026-08-15)

**Reproduced, as a working takeover.** Eight of the nine write endpoints on the
users resource asked "is the target protected?" before touching the row. The
ninth — `PATCH /api/admin/users/:id`, the only route that can rewrite
`users.phone` — asked nothing; its only gate was the `(users, edit)` permission,
which **supervisor and employee hold by default** and which no production
override narrows. A test driving the real request chain confirmed it: an `admin`,
an `employee` and a `supervisor` each rewrote a higher-ranked account's phone
number and the row changed in the database.

That matters more than it used to, because the phone is no longer only a contact
field — it is where a sign-in code is delivered, so whoever holds the number
clears at least one factor of that person's login. How much that alone buys an
attacker depends on the login design, which is currently being revised, so this
fix does not rest on it. It rests on what production says today:

| tier | accounts | with **no password at all** |
|---|---|---|
| `super_admin` | 3 | 1 |
| `admin` | 2 | 1 |
| `user` | 41 | 34 |

For those two staff accounts there is no second factor to fall back on, so the
phone number is currently sufficient on its own — set it to a handset you own and
sign in as them.

**Two rules now guard every write on the resource, from one shared place**
(`backend/internal/handlers/admin_user_guard.go`):

1. **Tier floor** — you may not write to an account that outranks you, on any
   field. This generalises the old check, which only shielded the Super-Admin, so
   a supervisor can no longer reset an *admin's* password either.
2. **Credential rule** — changing the phone of any account that holds dashboard
   access is **Super-Admin-only**. Rule 1 permits a peer edit, and a peer edit of
   a credential is still a takeover, only sideways.

Correcting an ordinary user's mistyped number stays available to every rank that
holds تعديل — that is the everyday task, and it is covered by a test.
Two behaviours also changed for the better on the way: a failed tier lookup used
to wave the write through (it now refuses), and refusals now carry a translatable
`code` and a server-side log line instead of a raw English sentence.

**Not covered by this fix:** H13 also asks that no one may change the
Super-Admin's *permissions*. That half was already correct — the permissions
matrix is `RequireSuperAdmin`-gated, and `super_admin` is never stored as
overridable (`internal/permissions/permissions.go`).

### H15 — diagnosis and fix (2026-08-15)

**Counted, not estimated: 31 admin delete routes, 16 recoverable, 15 permanent.**
Among the permanent ones were the two you named — **فئات المشاريع** and
**طرق الدفع**.

The cause was structural rather than an oversight anywhere. The trash helper was
a *private method* on one handler, so the catalogue, task and comment handlers —
which live in their own files with their own stores — could not call it even if
someone had wanted to. It is a shared function now, and "delete" means the same
thing wherever it is written.

**13 of the 15 now go to المهملات:** project categories · payment methods ·
assistance types · in-kind categories · city sectors · guide sub-categories ·
Our Work categories · case categories · product categories · professions ·
marriage subscription packages · tasks · post comments. Each can also be
restored — the restore allow-list was extended in the same change, because a row
that reaches the Trash and then refuses to come back out is worse than one that
was never trashed.

**2 stay permanent, deliberately:**

| Route | Why it stays permanent |
|---|---|
| `DELETE /admin/events/:id` (Notification Centre feed) | `app_events` is an append-only activity/analytics log. A log line is not an authored record; its delete is already Super-Admin-only by your own rule; and filling المهملات with feed rows would bury the records staff actually need to recover. |
| `DELETE /admin/banned-words/:id` (blocked words) | The blocklist is held in memory with no expiry, and only its own code refreshes that copy. Routing the delete around it would leave a word you removed **still being blocked** until the server restarts — and the restore path could not refresh it either. Re-typing a word takes seconds; silently enforcing one you deleted is the worse failure. |

**Also fixed in the Trash page:** the new rows would have shown a bare id (their
display text lives in `name_ar` / `label_ar` / `body`, which the preview did not
look at) and their module column would have printed the raw English table name
into the Arabic UI. Both corrected.

**Still not built:** the "employees get أرشفة instead of حذف" half of H15.
Archive exists only for user accounts, not for the other resources.

### H10 / B7 — the detail page was sending password hashes (2026-08-15)

Found while working on H10's "who may see sensitive data" question, and worse
than H10 itself. `GET /api/admin/detail/:resource/:id` ran `SELECT *` and then
hid the columns whose **name** looked like contact information. Everything else
went to the browser as-is, including **`users.password_hash`** — the bcrypt hash
the account signs in with. Ten of the 46 production accounts carry one, two of
them `super_admin`.

Two things made it worse than it reads:

- The route has **no per-module permission at all** (it is one of the few
  main.go leaves "ungated beyond RequireAdmin"), so the hash reached *any* staff
  account — an `employee` who was never granted `sensitive_data` included.
  Reproduced at all four tiers.
- The mechanism could never have caught it. A redaction list has to be told
  about each new secret, and this one only ever knew about phone/email-shaped
  names, so a credential column was outside its scope by construction.

**Fixed by inverting it:** each resource now declares the columns it may return
(`detailColumns` in `backend/internal/handlers/admin_detail.go`) and the query
asks for exactly those. Nothing visible today was lost — the lists were
generated from the migrated schema and verified column-for-column against
production — but `password_hash` and `google_sub` are withheld, and any column a
future migration adds is invisible until someone lists it deliberately.

**Checked and clean:** the users **list** endpoint never had this shape (it
selects explicit columns and returns only a `has_password` boolean); a test now
keeps it that way. The dashboard's CSV export builds its file in the browser
from data the API already returned, so it inherits the fix.

**Still open, reported not changed:** the JSON database export
(`POST /api/admin/export/all`) does `SELECT *` over 40-odd tables including
`users`, so it *does* contain the hashes. That one is Super-Admin-only, requires
the caller to re-enter their own password, and is a **backup** — an export with
the auth columns stripped could not be restored. Left as designed; flagged here
so the owner knows the backup file is as sensitive as the database.

## I. Global terminology & naming changes

`[D p9]` frames these as required for **payment-gateway and international-organization compliance**, and says they must be unified across the dashboard, the mobile app, **and the API code**.

| # | Item | Where | Status |
|---|---|---|---|
| I1 | **Donations "التبرعات" → "Back Us"**, with the internationally accepted alternative **Contributions: المساهمات**. `[D p9]` | Dashboard + App + API | ⬜ |
| I2 | **Beneficiary "المستفيد" → "Recipients / المستحقين"**, alternative **Target Groups: الفئات المستهدفة**. `[D p9]` | Dashboard + App + API | ⬜ |
| I3 | **Sponsorships "الكفالات" → "Assistance / المعونات"**. `[D p9]` | Dashboard + App + API | ⬜ |
| I4 | **Volunteers "المتطوعين" stays unchanged** in both Arabic and English — "لكونها مقبولة محلياً ودولياً". Verify nothing renamed it. `[D p9]` | Dashboard + App + API | ⬜ |
| I5 | **"حساب المتبرع" → "مانح"** in all parts of the app. `[A p1]` | App | ⬜ |
| I6 | **"متعفف" → "مستحق"** (singular) / **"مستحقين"** (plural) in all parts of the app. `[A p1]` | App | ⬜ |

> ⚠️ I1–I3 (dashboard PDF) and I5–I6 (app PDF) are two overlapping rename passes written at different times. Reconcile into one vocabulary before any rename lands — see N7.
>
> **Reconciled in [`TERMINOLOGY.md`](TERMINOLOGY.md)** (repo root): 20 concepts, each
> grounded in what the locale files actually say today, with blast radius and a
> `SETTLED` / `CONFLICT` / `NEEDS OWNER` status per row. Headline findings — **I1
> (Donations → Contributions / المساهمات), I5 (المتبرع → المانح), I6 (متعفف → مستحق,
> now zero occurrences) and the English half of I2 and I3 are ALREADY DONE**; the
> live conflict is the *English* word for المستحق (`Recipient` vs `Eligible`, one
> shipped in each client); the dashboard's *Arabic* still says المستفيدون. Do not
> start any rename from this group before reading that file.

## J. App — home screen & navigation restructure

| # | Item | Where | Status |
|---|---|---|---|
| J1 | **Guest-login button was never added** — "لم يتم إضافة زر الدخول كزائر". Guest entry asks only for الاسم، اسم المستخدم (Username) فقط، رمز سري, and "حفظ بيانات التسجيل في النظام والتقارير". `[A p1]` | App → home / login | ⬜ |
| J2 | **Guest scope**: may browse الأعمال والإنجازات, see الحملات والتبرعات, follow الإحصائيات, view some الخدمات, and المنح والتبرعات وإمكانية الدعم — but must NOT create requests, edit data, or reach sensitive info/user data; all of it controlled from the dashboard. `[A p13–14]` | App → guest mode | ⬜ |
| J3 | **Animated slider banner on home** carrying عدد المتبرعين، عدد المستفيدين، عدد الأعمال المنجزة. `[A p1]` | App → home | ⬜ |
| J4 | **Welcome card fix**: username on the same level as "أهلاً بعودتك" with the name after it; and **delete the "ابق مستعد ..." line** from the card. `[A p1]` | App → home | ⬜ |
| J5 | **The three home cards (منتجاتنا، خطوبتي، دليل المدينة) should sit together** in one rectangle with an even division, at the top or in the middle — "لكن لا تؤثر على التطبيق وهذه". `[A p1]` | App → home | ⬜ |
| J6 | **Move the profile icon to the top-right as a circular avatar**; tapping it opens the profile page with: الملف الشخصي، الاعدادات، الاشعارات، خدمات المجتمع، اللعبة، الوضع الداكن، الدعم الفني، من نحن، اتصل بنا، الشروط والأحكام، تسجيل الخروج. `[A p20]` | App | ⬜ |
| J7 | **A Menu button on every app page and a Back button on every page and section** — "بحيث يمكن للمستخدم الوصول إلى القائمة الرئيسية في أي وقت". `[A p25]` | App, global | ⬜ |
| J8 | **In-app search** available in the main menu, all sub-sections, and every page holding data or lists. `[A p25]` | App, global | ⬜ |
| J9 | **Add a support button at the top of the app** — "إضافة زر الدعم في أعلى التطبيق". `[A p34]` | App | ⬜ |
| J10 | **Add الشروط والأحكام** (terms & conditions). `[A p34]` | App | ⬜ |
| J11 | "في الواجهة الرئيسية للمستخدم، عند الضغط على **'سجلني'** يظهر طلب المستفيد" — pressing سجلني surfaces the beneficiary request. `[A p34]` *(needs owner clarification — unclear whether reported as a defect or as expected behaviour)* | App → home | ⬜ |

## K. App — missing sections & features

| # | Item | Where | Status |
|---|---|---|---|
| K1 | **"أعمالنا" section was never added** — "لم يتم إضافة قسم أعمالنا": an independent interface showing all the organization's works and achievements, placed at the bottom of the app or in/next to the profile field. `[A p1, p20–21]` | App | ⬜ |
| K2 | **أعمالنا content model**: a main activities list, with **المساعدات الإنسانية** as its own section or dropdown (كفالة يتيم، كفالة أرملة، توزيع السلال الغذائية، توزيع الملابس، المساعدات الطبية، المشاريع الموسمية) plus **برامج أخرى** (برامج الطفولة، برامج المرأة، سبل العيش، البيئة والمناخ، التراث والثقافة، بناء السلام، المعارض والمهرجانات، التعليم والتدريب، الأنشطة المجتمعية), extendable later. `[A p21]` | App → أعمالنا | ⬜ |
| K3 | **Per-post model in أعمالنا**: اسم النشاط، تاريخ النشاط، مكان الإقامة، وصف مختصر، صور، فيديوهات (عند توفرها); interactions زر مشاركة خارج التطبيق، زر الإعجاب، زر التعليق; and an **Activity Code** identifying the post's category, with the ability to add a new field that auto-creates its code "دون الحاجة لعمل كود برمجي جديد". `[A p22]` | App → أعمالنا | ⬜ |
| K4 | **عجلة الحظ / امسح كوبون الحظ was never added** to الإجراءات السريعة. Mechanism: spinning or scratching gives the donor a motivational task or challenge. Client asks to ship it in the current version **even hidden or disabled** — "حتى وإن كانت مخفية أو غير مفعلة" — ready for later launch, with editable task names. `[A p2]` | App → الإجراءات السريعة | ⬜ |
| K5 | **Colour-coded operation status was never added** — "لم يتم إضافة نظام واضح لعرض حالة العمليات باستخدام ألوان توضيحية وبيانات رقمية بداخل الألوان": 🟢 green = donations fully delivered, operation complete · 🔴 red = beneficiary has received nothing yet · 🟠 orange = part received / started but still in progress. `[A p1]` | App → operations & donations | ⬜ |
| K6 | **Dedicated "الشركاء" section**: per-partner profile (اسم الجهة، شعار/Logo، رابط الموقع أو الصفحة الرسمية، نبذة تعريفية، فئة الجهة، الموقع، أرقام التواصل، البريد الإلكتروني، مواقع التواصل), a **1–5 star or numeric rating** computed from criteria the organization sets (عدد الأنشطة المنفذة، حجم التبرعات، مستوى التعاون، استمرارية الدعم), and a per-partner page listing joint activities and the rating level. `[A p23–24]` | App | ⬜ |
| K7 | **Settings page**: language selection across **العربية، الإنجليزية، الكردية البادينية، الكردي الصوراني**; notifications on/off plus per-type control of what the user receives. `[A p24]` | App → الإعدادات | ⬜ |
| K8 | **Privacy settings page**: user chooses which fields are visible to others (الاسم، رقم الهاتف، المحافظة أو السكن، الصورة الشخصية، البريد الإلكتروني، وأي بيانات أخرى) per account type. `[A p26]` | App → الإعدادات → الخصوصية | ⬜ |
| K9 | **سجل النشاط page** listing everything the user has done since the account was created — سجل الدعم، طلبات المساعدة، المعونات، طلبات الانضمام للتطوع، المشاركات في الأنشطة — with per-operation detail. `[A p27]` | App → الملف الشخصي | ⬜ |
| K10 | **Technical support section**: send a direct message to the support team and follow the request status and replies. Escalation: after more than three messages on different dates about the same unresolved problem, offer **direct WhatsApp contact**. `[A p27]` | App → الدعم الفني | ⬜ |
| K11 | **"تفريغ المساحة" option in settings** clearing local data only — المنشورات المحفوظة، نتائج البحث السابقة، الملفات المؤقتة (Cache)، بيانات التصفح المحلية — with an explicit assurance it does not touch account or server data. `[A p27]` | App → الإعدادات | ⬜ |
| K12 | **من نحن details**: نبذة مختصرة عن التطبيق، عن المنظمة، عن أهداف المنظمة، plus the ability to add more fields later without code. `[A p28]` | App → من نحن | ⬜ |
| K13 | **تواصل معنا details**: لوكو المنظمة، رقم هاتف المنظمة، رقم الواتساب، الإيميل، مواقع التواصل، عنوان وموقع المنظمة, extendable fields. `[A p28]` | App → اتصل بنا | ⬜ |
| K14 | **خطوبتي/الزواج feature set**: account creation per the L15–L19 spec, login, guest registration, a profile with edit/activate/delete-account, **filtered search**, **save-a-person during search**, and a contact request routed either as an interview, through a mediating employee, or as a visit request — plus subscription and the documented payment methods. `[A p28]` | App → خطوبتي | ⬜ |
| K15 | **Products list structure**: 10 main categories (الإلكترونيات والأجهزة المنزلية، الأزياء والملابس، الصحة والجمال، المنزل والحديقة، المواد الغذائية والمشروبات، الرياضة واللياقة البدنية، ألعاب الأطفال والمواليد، مستلزمات السيارات، الكتب والمكتبة والقرطاسية، العدد والأدوات الصناعية); functional labels الأكثر مبيعاً، وصل حديثاً، العروض والخصومات، التصفية، الفئات، العلامات التجارية; per-product fields اسم المنتج، الوصف، رمز التخزين التعريفي، السعر، الحالة/التوفر، المواصفات التقنية. `[A p29]` | App → منتجاتنا | ⬜ |
| K16 | **دليل المدينة category tree — 6 sectors**: الأمن والخدمات السيادية · الصحة والخدمات الطبية · التجارة والأعمال (دليل المحال والمهن) · الصناعة والإنتاج · السياحة والتراث والترفيه · التعليم والخدمات العامة, each with the sub-categories listed in the PDF. `[A p30; repeated verbatim p31–32]` | App → دليل المدينة | ⬜ |
| K17 | **Per-place data fields in the city guide**: اسم الجهة، التصنيف الرئيسي والفرعي، إحداثيات GPS مرتبطة بخرائط جوجل، العنوان النصي (الحي، الشارع، أقرب نقطة دالة)، أرقام الهواتف مع ميزة الاتصال المباشر من التطبيق، البريد الإلكتروني، ساعات العمل (مفتوح الآن/مغلق)، وصف الخدمات، معرض الصور، روابط التواصل الاجتماعي. `[A p31]` | App → دليل المدينة | ⬜ |
| K18 | **"إضافة نشاط" for shop/factory owners** — the owner submits a request to add his business and the admin approves or rejects it. `[A p31]` | App + Dashboard | ⬜ |
| K19 | **Supervised donor↔beneficiary chat**: opened only on the donor's request and with the assigned employee's approval, the employee acting as mediator and monitor, with **full personal-data blocking "منعاً للابتزاز"**. `[A p33]` | App | ⬜ |
| K20 | **General chat platform** reaching all user types (مستفيدين، متبرعين، وزوار), plus a **confidential employee-only space** for exchanging notes and receiving smart task alerts from management. `[A p33]` | App | ⬜ |
| K21 | **Smart search engine**: query by identity code to review the donation/support history — "استعلام بالكود التعريفي لاستعراض سجل (التبرعات وحالة الدعم)" — plus fast activity search. `[A p33]` | App | ⬜ |
| K22 | **Interactive map** showing activities and events with custom pins, and beneficiary locations shown only as an **approximate location (e.g. a 500 m radius)** so the exact home address is never revealed. `[A p33]` | App | ⬜ |
| K23 | **Share the app, or any in-app post, to social media.** `[A p33]` | App | ⬜ |
| K24 | **1–5 star interactive rating as an app-wide trait** across all options, with interactive icons (القلب، الإعجاب، وغيرها). `[A p33]` | App, global | ⬜ |
| K25 | **Dark mode / "التصفح الليلي"** in the app, "لتقليل إجهاد العين وتحسين تجربة المستخدم في الإضاءة المنخفضة". Distinct from F1, which is the dashboard. `[A p20, p33]` | App | ⬜ |
| K26 | **Full user control over sounds and vibration** from a قائمة "إعدادات التطبيق" — enable or mute. Client also asks for quiet official sounds and haptic feedback throughout. `[A p33]` | App → الإعدادات | ⬜ |
| K27 | **Push notifications about activities happening in the app**, which the user can turn off. `[A p33]` | App | ⬜ |
| K28 | **AI chatbot** giving instant answers, plus an **AI icon beside each menu** offering a short explanation of that section and answering FAQs. `[A p34]` | App | ⬜ |
| K29 | **Digital delivery confirmation**: confirm receipt in-app and attach field photos to each distribution operation, "لضمان تحديث سجل المستفيدين وإثبات نجاح التنفيذ". `[A p34]` | App + Dashboard | ⬜ |
| K30 | **Save/bookmark any post** into a saved box, retrievable quickly and deletable from it. `[A p34]` | App | ⬜ |
| K31 | **Scope & delivery (contract item, not a UI test)**: the app ships on **both Android and iOS**; the complete database, source code, website and dashboard are handed to the organization on completion; and the whole visual identity (لوكو، خلفيات، صور، أيقونات) for both the website and the app is the developer's responsibility. `[A p33, p34]` | Project scope | ⬜ |

## L. App — registration & profile data specifications

The client's framing is that these forms exist but the specified fields **were never
put in** — "لم يتم ادراج التفاصيل في استمارة تسجيل المانح" `[A p2]`. Verify each form
field-by-field against the spec.

| # | Item | Where | Status |
|---|---|---|---|
| L1 | **Donor (المانح) — البيانات الأساسية**: رقم البطاقة الوطنية أو الهوية (اختياري)، الاسم الرباعي، اللقب، رقم الهاتف (اختياري)، رقم هاتف ثانٍ (اختياري)، البريد الإلكتروني (اختياري)، الجنس، الموقع GPS (اختياري)، تاريخ الميلاد (يوم/شهر/سنة)، المحافظة (dropdown of all governorates)، السكن (اختياري)، التحصيل الدراسي، الوظيفة (اختياري). `[A p2]` | App → تسجيل المانح | ⬜ |
| L2 | **Donor — المرفقات والخصوصية**: صورة شخصية (اختياري)، صورة البطاقة الوطنية أو الهوية (اختياري); privacy option letting the donor choose to **display his real name or a pseudonym (كنية)**; optional Facebook / Instagram / Telegram links. `[A p2–3]` | App → تسجيل المانح | ⬜ |
| L3 | **Beneficiary (مستحق) — البيانات التعريفية**: كود تعريفي يُنشأ تلقائياً، رقم البطاقة الوطنية، الاسم الرباعي، العشيرة، اللقب، تاريخ التولد، البريد الإلكتروني، رقم الهاتف، رقم هاتف ثانٍ (اختياري)، رقم هاتف للطوارئ (أحد أفراد العائلة). `[A p3]` | App → تسجيل مستحق | ⬜ |
| L4 | **Beneficiary — البيانات الشخصية**: الجنس; **الجنسية** dropdown (عراقي، سوري، مصري، خليجي، أخرى); **الحالة الزوجية** dropdown (أعزب، خاطب، متزوج، منفصل، ارمل، مطلق، اخرى); **الحالة القانونية** dropdown (مجتمع محلي، عائد، نازح، لاجئ، أخرى). `[A p3–4]` | App → تسجيل مستحق | ⬜ |
| L5 | **Beneficiary — بيانات السكن with cascading dropdowns**: المحافظة covering all Iraqi governorates; choosing **نينوى** opens **الجانب** (الأيمن/الأيسر/أخرى) and then shows **only that side's neighbourhoods** — "عند اختيار الجانب الأيمن تظهر أحياء الجانب الأيمن فقط"; other governorates open a free-text الحي field, then أقرب نقطة دالة, then the location. Plus الحي/السكن، أقرب نقطة دالة، الموقع الجغرافي (GPS). `[A p4]` | App → تسجيل مستحق | ⬜ |
| L6 | **Beneficiary — نوع السكن** dropdown (ملك، إيجار، ورث، مشترك، استحدام، أخرى); choosing **"إيجار" reveals an extra rent-amount field**. Then مساحة السكن (رقم)، عدد الطوابق dropdown (طابق / طابق ونصف / طابقين / ثلاثة أو أكثر)، عدد الغرف، عدد العوائل المقيمة في المنزل. `[A p4]` | App → تسجيل مستحق | ⬜ |
| L7 | **Beneficiary — البيانات التعليمية والوظيفية**: تاريخ الميلاد، التحصيل الدراسي، شهادة أخرى، عدد الشهادات، الوظيفة الحالية، الوظيفة السابقة، الوصف الوظيفي، عدد ساعات العمل، الدخل الشهري. **حالة التوظيف**: "هل يعمل حالياً؟ (نعم/لا)" — choosing نعم reveals مكان العمل then الأجور رقماً. `[A p5]` | App → تسجيل مستحق | ⬜ |
| L8 | **Beneficiary — البيانات الاجتماعية**: مسجل في الرعاية الاجتماعية، مسجل ضمن العاطلين عن العمل، عدد الموظفين في المنزل، عدد العاملين في المنزل، عدد أفراد الأسرة، عدد الرجال، عدد النساء، عدد الأطفال الذكور، عدد الأطفال الإناث، **age brackets** (0–5، 5–10، 10–15، 15–25، 25–40، 40 فما فوق)، عدد الطلاب، عدد الأيتام، عدد الأرامل، عدد المطلقين. `[A p5]` | App → تسجيل مستحق | ⬜ |
| L9 | **Beneficiary — البيانات الصحية**: الطول، الوزن، التدخين، صحة النظر، من ذوي الاحتياجات الخاصة؟، نوع الإعاقة، عدد الأشخاص ذوي الإعاقة في المنزل، الأمراض المزمنة، عدد الحالات المرضية، شرح كل حالة مرضية. `[A p5–6]` | App → تسجيل مستحق | ⬜ |
| L10 | **Beneficiary — المرفقات والممتلكات والاحتياجات**: صورة شخصية، صورة البطاقة الوطنية، البطاقة التموينية / بطاقة السكن / الجواز (اختياري)، مستند التملك أو عقد الإيجار، التقارير الطبية لكل حالة مرضية، **صور للمنزل** (الواجهة الخارجية، داخل المنزل، خارج المنزل); الممتلكات (الأثاث المتوفر، هل يمتلك سيارة؟); a free-text الاحتياجات field. `[A p6]` | App → تسجيل مستحق | ⬜ |
| L11 | **Beneficiary — الخصوصية**: a consent option determining whether the beneficiary permits showing the **donor's real name**, or showing some of his own data to the donor "حسب سياسة التطبيق وما يتم تحديده من الداش بورد". `[A p6–7]` | App → تسجيل مستحق | ⬜ |
| L12 | **Volunteer/employee — all option fields must be dropdowns** "لتسهيل عملية الإدخال وتوحيد البيانات". البيانات التعريفية (كود تلقائي، رقم البطاقة الوطنية، الاسم الرباعي، العشيرة، اللقب); بيانات التواصل (هاتف أساسي، ثانٍ اختياري، طوارئ، بريد); البيانات الشخصية (تاريخ الميلاد، الجنس، الجنسية — all dropdowns) plus **اللغات as multi-select** (عربي، إنكليزي، كردي، تركي، الماني، فرنسي، صيني/ياباني، اخرى). `[A p7–8]` | App → تسجيل المتطوع | ⬜ |
| L13 | **Volunteer — بيانات السكن والاجتماعية**: المحافظة (dropdown; نينوى opens a further dropdown)، القضاء، الجانب with side-filtered neighbourhoods، المنطقة/الحي، أقرب نقطة دالة، نوع السكن (ملك، إيجار، مشترك، ورث، أخرى)، مساحة السكن، عدد أفراد الأسرة (dropdown)، تحديد موقع المنزل (GPS); الحالة الاجتماعية dropdown (أعزب، خاطب، متزوج، منفصل، ارمل، مطلق، أخرى); البيانات التعليمية والمهنية (التحصيل الدراسي، شهادات أخرى، الوظيفة الحالية، السابقة، المهارات والخبرات). `[A p8–9]` | App → تسجيل المتطوع | ⬜ |
| L14 | **Volunteer — المرفقات**: المربع الذهبي، بطاقة موحدة أو الهوية، بطاقة تموينية، بطاقة السكن، الجواز (اختياري)، صورة شخصية رسمية، شهادة التخرج، السيرة الذاتية (CV); plus Facebook / Instagram / Telegram and other optional social links. `[A p9]` | App → تسجيل المتطوع | ⬜ |
| L15 | **خطوبتي/الزواج — البيانات التعريفية والشخصية**: كود تعريفي تلقائي، رقم البطاقة الوطنية، الاسم الرباعي، العشيرة، اللقب، تاريخ التولد، البريد الإلكتروني، رقم الهاتف، رقم هاتف ثانٍ (اختياري); الجنس، الجنسية dropdown، الحالة الزوجية dropdown **with an added "منفصل / باكر" option**، الحالة القانونية dropdown (مجتمع محلي، عائد، نازح، لاجئ، أخرى). `[A p9–10]` | App → خطوبتي registration | ⬜ |
| L16 | **خطوبتي — بيانات السكن**: same cascading المحافظة → الجانب → الحي rules as L5, plus **عدد سنوات السكن الحالي، السكن السابق، عدد سنوات السكن السابق**; نوع السكن dropdown with the rent-amount reveal; مساحة السكن، عدد الطوابق، عدد الغرف، عدد العوائل المقيمة. `[A p11]` | App → خطوبتي registration | ⬜ |
| L17 | **خطوبتي — التعليمية/الوظيفية والصحية**: تاريخ الميلاد، التحصيل الدراسي، شهادة أخرى، عدد الشهادات، الوظيفة الحالية، السابقة، الوصف الوظيفي، عدد ساعات العمل، الدخل الشهري; الطول، الوزن، لون البشرة، عدد أفراد الأسرة، عدد الأطفال، التدخين، صحة النظر، الإعاقة، الأمراض المزمنة، **الديانة، القومية**، هل الشخص من ذوي الاحتياجات الخاصة؟، المهارات والخبرات. `[A p11–12]` | App → خطوبتي registration | ⬜ |
| L18 | **خطوبتي — الممتلكات والاحتياجات والمرفقات**: yes/no ownership flags for سيارة، منزل، محل، شركة، ارض, plus free-text other possessions; an الاحتياجات field describing what he asks for in a partner; attachments صورة شخصية، المربع الذهبي، شهادة التخرج، السيرة الذاتية (اختياري) and social links. `[A p12–13]` | App → خطوبتي registration | ⬜ |
| L19 | **خطوبتي — إعدادات الخصوصية**: the user picks which data others may see — الاسم، العمر، الشهادة الدراسية، الوظيفة، المحافظة، الصورة الشخصية، أو أي بيانات أخرى يحددها المستخدم. `[A p13]` | App → خطوبتي profile | ⬜ |
| L20 | **Every field's optional/mandatory flag must be switchable from the admin panel** (client highlighted this in red): "جميع الحقول الاختيارية والإجبارية يجب أن تكون قابلة للتحكم من لوحة الإدارة، بحيث يمكن للإدارة تغيير أي حقل من 'إجباري' إلى 'اختياري' أو العكس دون الحاجة لتعديل برمجي" — and the registration model must accept **new fields later without rebuilding the system**. `[A p7, p13]` | Dashboard + App forms | ⬜ |

## M. Donations, payments & sponsorship scheduling

| # | Item | Where | Status |
|---|---|---|---|
| M1 | **Transaction Code on every payment operation**, with **independent code ranges per section** — التبرعات العامة، منجزاتنا، خطوبتي او الزواج، المشاريع، and any future section — "لتسهيل تتبع العمليات المالية والتمييز بينها في التقارير ولوحة التحكم". `[A p14–15]` | App + Backend + Dashboard | ⬜ |
| M2 | **Payment notification system** on every completed donation: instant in-app notification, a notification **to the phone number dedicated to that section**, showing the amount paid, the Transaction Code, and which section the payment came through, and auto-recording the operation in the dashboard. `[A p14–15]` | App + Dashboard | ⬜ |
| M3 | **Donation types offered at selection**: تبرع نقدي (تسليم مباشر) · تبرع عبر وسائل الدفع الإلكتروني (MasterCard, Visa Card, المحافظ الإلكترونية, future methods) · التبرع عبر تحويل الرصيد (بطاقات تعبئة الرصيد, التحويل المباشر إلى أرقام الهواتف المخصصة) · التبرعات العينية (مواد غذائية، ملابس، قرطاسية، أثاث، أجهزة منزلية) · التبرع لدعم المنظمة (تكاليف تشغيل التطبيق، الاشتراكات والخوادم، إدارة البيانات، المصاريف الإدارية، الاحتياجات اللوجستية). `[A p15–16]` | App → التبرعات | ⬜ |
| M4 | **Electronic-transfer donation branches into two paths**: **مساعدات عامة** (donor picks no category; staff distribute by priority and need) or **التبرع حسب مشروع محدد**, with projects hideable from the dashboard while the general donation stays available. `[A p16]` | App → التبرعات | ⬜ |
| M5 | **Project list for targeted donation — 22 named projects**: الأنشطة العامة، كفالة يتيم، كفالة أرملة، كفالة مستفيد، كفالة طالب، إطفاء الديون، كسوة الأطفال للعيد، الملابس العامة، المستلزمات الدراسية، دفع إيجار منزل، دفع إيجار مولد، توفير النفط الأبيض خلال فصل الشتاء، السلال الغذائية، موائد الإفطار، الزواج الخيري، الأثاث المنزلي، الأجهزة الكهربائية، المشاريع الصغيرة، الحرف اليدوية، حفر الآبار، ترميم المنازل، الحالات المرضية — plus an option to add and auto-name a new field "دون الحاجة لعمل كود مستقلا". `[A p17]` | App → التبرعات | ⬜ |
| M6 | **"امنح الآن" / "منح شامل"** — a standalone option collecting donations into a general fund with no project chosen, distributed by staff per real priorities. Client frames it as the fallback for when project-by-project donation underperforms, donors feel overwhelmed by choice (شعر المتبرعون بالحيرة بسبب كثرة الخيارات), or projects miss their financial targets. `[A p18]` | App → التبرعات | ⬜ |
| M7 | **Donations system must be extensible from the dashboard**: new donation types, new projects, edit/delete existing projects, new payment methods — "التحكم الكامل بجميع الخيارات من لوحة الإدارة دون الحاجة إلى تحديث برمجي". `[A p18]` | Dashboard | ⬜ |
| M8 | **Sponsorship calendar**: link المعونات/الكفالات to a calendar with recurring due dates (معونة يتيم شهرياً، معونة أرملة، دفع إيجار منزل، any other recurring aid); the system builds the timetable per case automatically. `[A p18–19]` | App + Dashboard | ⬜ |
| M9 | **Reminders**: automatic alerts to the **donor** for his next donation date and to the **beneficiary** for his aid collection date, via in-app notification, SMS, and an in-app voice alert when available. `[A p19]` | App + Backend | ⬜ |
| M10 | **Entitlement tracking screen**: مواعيد المساهمات والمنح القادمة، المساعدات المستحقة، المساعدات المتأخرة، سجل المعونات السابقة — "لضمان استمرارية المعونات وعدم نسيان مواعيدها". `[A p19]` | App + Dashboard | ⬜ |

## N. Open questions — need owner clarification before implementing

| # | Item | Where | Status |
|---|---|---|---|
| N1 | **"أين الدردشة بين المتطوع و المتعفف و المانح؟"** — where is the chat between volunteer, beneficiary and donor? Overlaps K19/K20; confirm which of the three chat surfaces is actually expected in this release. `[A p34]` | App | ⬜ |
| N2 | **"أين الدردشة بين المتطوع و الفريق التقني للتطبيق؟"** — where is the volunteer ↔ technical-team chat? `[A p34]` | App | ⬜ |
| N3 | **"أين الدردشة في خاصية الزواج / خطوبتي بين المسجل والفريق التقني؟"** — where is the registrant ↔ technical-team chat inside خطوبتي? `[A p34]` | App → خطوبتي | ⬜ |
| N4 | **"أين خاصية البحث في قسم الزواج / خطوبتي؟"** — where is search in the marriage section? Overlaps K14 (filtered search). `[A p34]` | App → خطوبتي | ⬜ |
| N5 | **"عند الضغط على الاشعارات في احد الأقسام الخاصة بالاشعارات تختفي فورا؟"** — tapping a notification inside one of the notification sections makes it vanish immediately. Written as a question; unclear whether reported as a bug or asking whether it is intended. `[A p34]` | App → الإشعارات | ⬜ |
| N6 | **"عند التسجيل كمستحق يجب إلغاء عرض ظهور تفاصيل الكفالة وتحويلها إلى المتطوع"** — when registering as a beneficiary, stop displaying sponsorship details and route them to the volunteer instead. Scope and destination unclear. `[A p34]` | App → beneficiary registration | ⬜ |
| N7 | **Terminology conflict**: `[D p9]` renames التبرعات → المساهمات / Back Us and المستفيد → المستحقين / Recipients, while `[A p1]` renames حساب المتبرع → مانح and متعفف → مستحق. Confirm one final vocabulary before any rename touches the app, dashboard or API. See group I. | Global | ⬜ |
| N8 | **"نظام لوحة تحكم للمستخدم في العقد"** `[A p31]` — the phrase "في العقد" is ambiguous. Confirm what dashboard a shop/factory owner is meant to receive under K18. | App + Dashboard | ⬜ |
| N9 | **External integration with دائرة الرعاية والشؤون الاجتماعية** `[A p34]` (see F10) — needs legal authorization and technical feasibility confirmed before it can be planned at all. | Backend | ⬜ |
| N10 | The client's closing note says **they could not review some dashboard sections** — "ونود التنويه إلى وجود بعض الأقسام التي لم نتمكن من مراجعتها نظراً لعدم توفر تفاصيل أو بيانات داخلها حالياً" `[D p10]`. More findings should be expected once those sections hold data. Ask which sections they were. | Dashboard | ⬜ |
| N11 | **Duplicated "send request" action** — the client explicitly asks us to explain it: "تم تكرار هذا الخيار في جميع ما ذكر، نرجو توضيح ذلك" `[A p34]`. Tracked as C5; answer it rather than silently changing the IA. | App → لوحة المستفيد | ⬜ |

---

## Extraction summary — what came from the PDFs

**Both PDFs were read in full. Nothing was sampled.**

| Source | Pages | Read | New rows added |
|---|---|---|---|
| `ملاحظات - منصة توازن - الداشبورد.pdf` | 10 | 1–10, all | **78** — A5–A9, A11–A15 · B7–B20 · C9 · D3–D6 · E7–E15 · F3–F7 · all of G (8) · H1–H22 · I1–I4 · N10 |
| `ملاحظات وتعديلات تطبيق توازن.pdf` | 35 | 1–35, all | **102** — A10 · B21 · C3–C8, C10 · D7 · E16–E18 · F8–F12 · H23 · I5–I6 · all of J (11), K (31), L (20), M (10) · N1–N6, N8, N9, N11 |
| both (conflict between the two) | — | — | **1** — N7, the terminology clash |

Total new rows: **181** (checklist now holds 203 rows across A–N), plus **8 page
references appended** to existing rows (A3, B6, C1, D1, D2, E1, E3, F2) where a PDF
repeated a complaint already captured rather than adding a new one.

---

## Gaps and unknowns

What the extraction pass could **not** resolve. Two kinds of gap live here: defects
in the source documents themselves (which only the owner can close), and the fact
that these notes are **not full product coverage**. Read this before treating the
checklist as a complete scope.

### Source-document defects

- **App PDF page 35 is blank** — no content lost, it is a trailing empty page.
- **App PDF pp. 31–32 duplicate pp. 29–31 verbatim** (the whole دليل المدينة /
  الموصل الشامل category tree and Data Fields list is printed twice in the source
  document). Likewise **pp. 14–15 repeat the payment-management section twice**
  (headed سادساً then سابعاً, the second copy slightly expanded). No unique content
  was dropped; K16/K17 and M1/M2 cover both copies.
- **Dashboard PDF p. 10 ends with an EMPTY BULLET** — a `•` with nothing after it,
  sitting directly below the ضغط وحجم الصور المرفوعة bullet and immediately before the
  closing thank-you note. **A note is missing from the client's own document.**
  Verified by re-reading p10 while writing `TERMINOLOGY.md`; it is not a rendering
  artefact of our extraction. **This is question 1 for the owner** — it is the last
  bullet of the last technical section, so whatever was meant to go there was
  probably the client's final and possibly most recent thought.
- **Dashboard PDF p. 1, first screenshot is LOW-RESOLUTION**: the dark mirrored
  screenshot is small and cannot be read directly. Its field names were recovered
  from the **second, larger screenshot on the same page**, which shows the same
  read-only user page legibly — so B7/B8/B9/G8 are safe. But a small
  partially-visible corner overlay (reading roughly `…a. pr…`) **could not be read**.
  It looks like a browser or screen-recording widget — a capture artefact, not
  client content. Recorded in case it later turns out to be an annotation we lost.
- Nothing in either PDF was scanned-image-only or otherwise unreadable; both are
  text-rendered documents.

### These notes are NOT full product coverage

- **The client could not review parts of the dashboard at all**, because those
  sections had no data in them — "ونود التنويه إلى وجود بعض الأقسام التي لم نتمكن من
  مراجعتها نظراً لعدم توفر تفاصيل أو بيانات داخلها حالياً" `[D p10]`, tracked as **N10**.
  Everything in groups A–M therefore describes what the client *could reach*, not
  the whole product. **Expect a second wave of findings** once those sections hold
  data — do not treat a green checklist as a signed-off dashboard, and seed the
  empty sections with test data before the next review round rather than after it.
- **Group I is a specification, not a verified list.** The two PDFs contain two
  overlapping rename passes written at different times, and a third pass has
  already shipped. Reconciled against the actual locale files in
  [`TERMINOLOGY.md`](TERMINOLOGY.md) — several of the requested renames turned out
  to be **already done**, and the live conflict is narrower than N7 suggests.

### Open questions for the owner — answerable in one pass

Every group-N row plus the two document defects above, phrased so they can be
answered in a single sitting. Numbers are stable; N-refs point back to the row.

1. **Dashboard PDF p10 ends with an empty bullet** — what was meant to go there?
   (Document defect, see above. No N-row: the note never made it into the file.)
2. **Where is the chat between volunteer, beneficiary (متعفف/مستحق) and donor?**
   Which of the three chat surfaces is expected in *this* release? (**N1**, overlaps
   K19/K20 — supervised donor↔beneficiary chat and the general chat platform.)
3. **Where is the volunteer ↔ technical-team chat?** (**N2**)
4. **Where is the registrant ↔ technical-team chat inside خطوبتي?** (**N3**)
5. **Where is search in the marriage section?** Is this the same thing as K14's
   filtered search, or a second requirement? (**N4**)
6. **Tapping a notification makes it vanish immediately** — is that a bug report or
   a question about intended behaviour? (**N5**)
7. **"عند التسجيل كمستحق يجب إلغاء عرض ظهور تفاصيل الكفالة وتحويلها إلى المتطوع"** —
   which sponsorship details should be hidden from the beneficiary, and what does
   "routed to the volunteer" mean: visible to the assigned volunteer only, or
   actioned by them? (**N6**)
8. **Terminology: confirm one final vocabulary before any rename lands.** (**N7**)
   The six decisions are laid out in [`TERMINOLOGY.md`](TERMINOLOGY.md) — the ones
   that block everything else are: (a) the English word for المستحق, `Recipient` or
   `Eligible`; (b) whether the payment-gateway compliance claim really extends to
   API field and database names or only to visible labels; (c) whether `الكفالات`
   becomes `المعونات` given that four products are literally named `كفالة …`.
9. **"نظام لوحة تحكم للمستخدم في العقد"** — what does "في العقد" mean, and what
   dashboard is a shop or factory owner meant to receive under K18? (**N8**)
10. **External lookup against دائرة الرعاية والشؤون الاجتماعية** (F10) — is there
    written legal authorization and a technical channel? Until both exist this
    cannot be estimated, let alone built. (**N9**)
11. **Which dashboard sections could you not review** for lack of data, so we can
    populate them and get a real review of those too? (**N10**)
12. **The duplicated "send request" action** — the client asked *us* to explain it
    (C5). Confirm which of the three entry points should survive before we change
    the information architecture. (**N11**)

Questions 2–5 and 9–10 are scope questions: they decide whether features get built
at all. Questions 1, 6, 7, 11 and 12 are clarifications on work already in the
checklist. Question 8 blocks every rename in group I.

---

## Already known, separate from this batch

- `0IQD` vs `0 د.ع` — inconsistent currency formatting on the dashboard KPI card
- 4 marketplace products have `category_slug = NULL`, so they fall back to the
  legacy free-text category (patched in the app; the data fix is admin work)
- Events tab shows an orphaned back chevron with an empty title
