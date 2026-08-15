# Client notes — verification checklist

Captured 2026-08-15 from the owner's written list, 11 annotated screenshots, and
two PDFs (`ملاحظات - منصة توازن - الداشبورد.pdf`, `ملاحظات وتعديلات تطبيق توازن.pdf`, 35pp).

**Status key:** ⬜ not yet verified · 🔎 verified, defect confirmed · ✅ verified, already correct · ❌ could not verify

Every item must be TESTED against the running app/dashboard, not assumed from code.
Several notes say "still not fixed", so a previous pass may have missed or only
partially addressed them — check the actual behaviour.

---

## A. SEVERE — blocks a working flow

| # | Item | Where | Status |
|---|---|---|---|
| A1 | **`Database error.` on the contributions page**, and in-kind contributions sent to a user never arrive. Screenshot shows the red error banner with an empty table beneath. | Dashboard → المساعدات والحملات → المساهمات | ⬜ |
| A2 | **Force logout (تسجيل خروج قسري) does not work** | Dashboard → المستخدمون → row actions | ⬜ |
| A3 | **Contact-support chat does not work** (التواصل مع الدعم لا يعمل) | App → الرسائل | ⬜ |
| A4 | **City Guide: the last slide cannot be displayed** — technical fault | App → دليل المدينة | ⬜ |

## B. English leaking into the Arabic UI (hard project rule)

| # | Item | Where | Status |
|---|---|---|---|
| B1 | Notification **type filter options are raw English enums** — `beneficiary_case_submitted`, `marriage_approved`, `new_campaign`, `support_ticket_resolved`, `system_test`, `volunteer_application_*` … | App → الإشعارات → التصفية حسب النوع | ⬜ |
| B2 | **"Support Assistant / Ask me anything — I'll guide you through the app"** is in English | App → الرسائل, top card | ⬜ |
| B3 | Place detail shows a **raw JSON array** `["commercial","government","education","health"]` instead of readable sector names | Dashboard → دليل المدينة → عرض | ⬜ |
| B4 | Login screen is in English (`Secure sign in`, `Phone number`, `Send OTP`, `Continue as guest`, `Don't have an account?`) | App → login | ⬜ |
| B5 | Place list shows status `approved` in English | Dashboard → دليل المدينة table, الحالة column | ⬜ |
| B6 | General: "انكليزي لم يتم الترجمه" — untranslated English remains in places | App + Dashboard | ⬜ |

## C. Duplication / information architecture

| # | Item | Where | Status |
|---|---|---|---|
| C1 | **"شركاؤنا" (Our Partners) appears 3–4 times**: profile menu, خدماتنا, bottom of home. Owner wants it in ONE place only. NOTE: a previous pass removed a duplicate drawer row — verify what remains and remove the rest. | App | ⬜ |
| C2 | "هنالك قوائم لا تظهر ما هي؟" — lists on the City Guide screen that do not appear / are unexplained | App → دليل المدينة | ⬜ |

## D. Dropdowns / labels

| # | Item | Where | Status |
|---|---|---|---|
| D1 | User-type dropdown contains **"بلا"** and **"—"**. Rename: one → **زائر** (guest), the other → **خاطب** or another term for a user registered for marriage. | Dashboard → المستخدمون → نوع المستخدم | ⬜ |
| D2 | Marriage applicant details are missing entirely — "اين بيانات او تفاصيل الشخص الذي يقوم بتسجيل بياناته كطالب للزواج" | Dashboard → الزواج | ⬜ |

## E. Forms / validation / display

| # | Item | Where | Status |
|---|---|---|---|
| E1 | **Phone number still displays incorrectly** — explicitly "لم يتم تصحيح العرض" (was reported before and not fixed) | App + Dashboard, wherever phone is shown | ⬜ |
| E2 | Phone should be **editable**, and the identifier (المعرّف) should be a **code**, not a raw row id | Dashboard → المستخدمون | ⬜ |
| E3 | **Image size must be constrained** when a user picks a profile photo | App → تعديل الملف الشخصي | ⬜ |
| E4 | Login **error text is red on a background that does not suit it** — contrast/legibility | App → login | ⬜ |
| E5 | **No countdown timer** showing how long until the OTP can be re-requested ("Please wait before requesting another code" with no timer) | App → login | ⬜ |
| E6 | City Guide: "كيفية اضافة رابط" — how to add a link is unclear | Dashboard → دليل المدينة | ⬜ |

## F. Missing dashboard features

| # | Item | Where | Status |
|---|---|---|---|
| F1 | **No dark/light mode toggle** — "لم نجد خيار تفعيل الوضع الليلي والعادي في الداشبورد". NOTE: a theme button exists in the header (`Switch to light mode`) — verify whether it works and is discoverable, since the client could not find it. | Dashboard | ⬜ |
| F2 | **No manual setting for browser auto-logout time** | Dashboard → إعدادات النظام | ⬜ |

---

## Not yet extracted

The two PDFs have **not** been fully read into this checklist — only the owner's
written list and the screenshots are captured above. The app PDF alone is 35
pages. Anything in them beyond the items above still needs extracting and adding.

## Already known, separate from this batch

- `0IQD` vs `0 د.ع` — inconsistent currency formatting on the dashboard KPI card
- 4 marketplace products have `category_slug = NULL`, so they fall back to the
  legacy free-text category (patched in the app; the data fix is admin work)
- Events tab shows an orphaned back chevron with an empty title
