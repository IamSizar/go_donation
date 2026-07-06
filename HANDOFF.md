# Tawazon / BalanceNex — Project Handoff & Full Audit

> **Purpose:** Everything a new engineer (or a new Claude session) needs to pick up this project and continue. Read this top-to-bottom before touching code.
>
> **Generated:** 2026-07-06 · **Branch pushed:** `new-update` · **Latest commit:** `5360d68`

---

## 0. TL;DR

- **App:** "Tawazon" (توازن) / **BalanceNex** — a multi-language humanitarian **donations & community platform**.
- **Three apps in one monorepo** (`IamSizar/go_donation`):
  - `humanitarian/` — **Flutter** mobile app (GetX), package name `flutter_application_1`.
  - `backend/` — **Go / Gin** API, Postgres (pgx), Go module `github.com/karam-flutter/humanitarian-backend`.
  - `admin-web/` — **React + Vite + TypeScript** admin dashboard.
- **Work model:** a **54-task backlog across 8 phases**, done **one task at a time**.
- **Progress:** **28 / 54 tasks complete** (+ one sub-task #16b). **Phases 1–4 fully done, Phase 5 is 7/9 done.**
- **This branch (`new-update`)** contains tasks **#10–#28** (plus earlier #1–#9 already on `main`). `main` is untouched.
- **NOTHING IS DEPLOYED.** All changes are code-only, awaiting an explicit deploy go-ahead. New DB migrations must be applied on deploy.
- **Next up:** **#29 and #30** (City Guide) to finish Phase 5, then Phases 6–8.

---

## 1. Repository, branches & how to continue

- **Repo:** https://github.com/IamSizar/go_donation
- **Local path (owner's machine):** `/Users/obaidaaljarjary/Desktop/untitled folder/go_donation`
- **`main`** — production line. Last commit `f8b008b` (phases 1–10 batch, 6c security, BalanceNex branding). **Do NOT commit here without explicit permission.**
- **`new-update`** — THIS handoff's branch. Commit `5360d68` = "feat: Tawazon backlog tasks #10–#28 (Phases 2–5)". 117 files, migrations 025–036, all new packages/pages/screens.

**To continue from another machine / session:**
```bash
git clone https://github.com/IamSizar/go_donation.git
cd go_donation
git checkout new-update
```

**Build / verify commands (run these after every change — the standard quality gate):**
```bash
# Backend (Go)
cd backend && go build ./... && go vet ./...

# Admin (React/Vite)
cd admin-web && npm install && npx tsc -b && npm run build

# Flutter app
cd humanitarian && flutter pub get && flutter analyze
```
All three must be clean before a task is considered done. (No test suite exists; these are the gates used all session.)

---

## 2. ⚠️ STANDING RULES & CONSTRAINTS (do not violate)

These are hard rules the owner set. They override defaults.

1. **NEVER deploy without an explicit "go".** "Deploy" = push to Railway / run migrations in prod / flip env flags. Pushing to a feature branch is fine when asked; deploying is not — always confirm first.
2. **Arabic = NO English.** In the Arabic UI, everything must be Arabic — **except charts/data values**. This applies to the app AND the admin dashboard. Same spirit for Kurdish.
3. **"Kurdish" = Kurdish Badini (kmr) by default.** The app supports 4 languages: **en, ar, ckb (Sorani), kmr (Badini)**. When the owner says "translate to Kurdish", they mean **Badini** unless they say Sorani.
4. **Every user-facing string must be translated in all 4 languages.** Never ship an English string that shows to ar/ckb/kmr users.
5. **OPOS task tracking** (their project-management tool): every change should be logged as OPOS tasks in office **"-129- Charity App"** (officeId **19**, workspaceId **3**, assignedUserId **16**, act as accountId **16** = user *sizarr*). Two-phase workflow: a "review" task first, then granular "build" sub-tasks, then mark done. **⚠️ The OPOS connector has been DOWN all session — tasks #14–#28 are NOT logged and need BACKFILL when it recovers (see §9).**
6. **Do work "my way" / polished** — the owner repeatedly says "make by ur way, client love it, no mistakes." Bias toward complete, polished, verified features.
7. **Login:** admin credentials belong to the owner; never enter passwords/tokens on their behalf.

---

## 3. Architecture & conventions (READ before coding — these patterns are used everywhere)

### 3.1 Backend (Go / Gin)
- **Entry point:** `backend/cmd/server/main.go`. Wires config → DB pool → stores → handlers → routes.
- **Route groups in `main.go`:**
  - `api := router.Group("/api")` — **public**, no auth (public GETs live here).
  - `authed := api.Group("/")` + `authed.Use(auth.RequireBearer(tokenStore), auth.RequireApproved())` — **logged-in app users**. App write actions (donate, comment, rate, etc.) live here.
  - `admin := api.Group("/")` + `admin.Use(auth.RequireAdmin(tokenStore))` — **admin dashboard**. Gated per-route by either `perm("module","action")` (permission system) or `auth.RequireAdminTier()`.
- **Acting user in a handler:** `user, _ := auth.UserFromGin(c)` → `user.UserID`, `user.RoleID`. In the `authed` group it's always non-null. Body helpers: `collectBody(c)`, `asStr(m["k"])`, `asInt(m["k"])`.
- **Store pattern:** `type Store struct { Pool *pgxpool.Pool }` + `New(pool)`. SQL via `s.Pool.Query/QueryRow/Exec`.
- **Migrations:** `backend/migrations/NNN_name.sql`, applied in filename order when `RUN_MIGRATIONS=1` on boot (tracked in `schema_migrations`, each runs once). **Always write idempotent SQL** (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `INSERT ... ON CONFLICT DO NOTHING`). **The repo convention is NO foreign-key constraints** — handlers validate existence explicitly.
- **Notifications:** `internal/notify` — `notifier.Send(ctx, userID, LocalizedMessage)` (4-language title/body, deduped) + `Broadcast` / `BroadcastToStaff`. Copy lives in `internal/notify/templates.go` (one builder func per trigger, all 4 languages). FCM push is delivered best-effort (see §7).

### 3.2 The "CMS clone" pattern (used 5× — clone it for any admin-managed 4-language list)
A reusable recipe for admin-editable, ordered, 4-language taxonomies. Reference implementations:
`internal/projectcategories`, `internal/mediacategories`, `internal/marketplacecategories`, `internal/paymentmethods`.
Each has:
- **Table:** `id, slug UNIQUE, name_en, name_ar, name_ckb, name_kmr, display_order, active SMALLINT, created_by, created_at`.
- **Store:** `List(activeOnly)`, `Add` (slugify from EN name, 23505→friendly dup error), `Update` (names+active, slug immutable), `Reorder` (tx), `Delete`.
- **Handler:** `PublicList` (active only) + `AdminList` + `Add/Update/Reorder/Delete`.
- **Routes:** public `GET /api/<x>` + admin CRUD (writes gated `auth.RequireAdminTier()` or `perm(...)`).
- **Admin page:** a React CMS page (clone `MediaCategoriesPage.tsx`) + lazy route in `App.tsx` + nav entry in `components/AppShell.tsx` + i18n block in all 4 locale files.
- **App:** a `links.dart` URL + `ModuleApi` fetch method + a controller that maps `slug → localized name` via `AppLocaleService.assistantLang()`.

### 3.3 Admin dashboard (React/Vite)
- **`EditModal` + `FieldSpec`** (`admin-web/src/components/EditModal.tsx`) is the generic edit form. Field types: `text | textarea | number | select | file | gallery | multiselect`.
  - `file` → `FileInput` (uploads to `POST /api/admin/upload`, stores returned path).
  - `gallery` (added #23) → `GalleryInput` (repeatable image list; value carried as a JSON-array string).
  - `multiselect` (added #28) → checkbox group (value carried as a JSON-array string; used for product labels).
- **Pages** are lazy-loaded in `App.tsx`; nav items in `components/AppShell.tsx` (`{to, tKey, module, superAdminOnly}` — hidden if the tier lacks `view` on `module`).
- **Tables:** `components/Table.tsx` + `StatusCell` (renders a status dropdown, POSTs to `/api/admin/<x>/:id/status`).
- **i18n:** 4 locale files `src/lib/locales/{en,ar,ckb,kmr}.ts`. **`en.ts` is the source of truth.** Admin uses `_ckb`/`_kmr` suffixes for Kurdish keys. Access via `useI18n().t('key')`. `useStatusLabel()` localizes status/enum strings.

### 3.4 Flutter app
- **GetX** for state/routing. Translations: `humanitarian/lib/localization/app_translations.dart` with **4 maps**: `_en`/`_ar` are `static const` (a **duplicate key = COMPILE ERROR**), `_sorani`/`_badini` are `static final` (dup = warning).
  - **GOTCHA:** the `_badini` map uses BOTH `'key':` (single-quote) and `"key":` (double-quote) styles. **Always grep BOTH quote styles before adding a Badini key** or you'll create silent duplicates.
- `.tr` translates a string via those maps (returns the key unchanged if missing → that's why untranslated English leaks to ar/ckb/kmr; always add keys). `.trParams({'x':'y'})` fills `@x` placeholders.
- **Canonical language codes:** `AppLocaleService.assistantLang()` returns `en | ar | ckb | kmr` (`lib/localization/locale_service.dart`).
- **Localized content from an API map:** `localizedContentFromMap(item, 'name')` reads `name` / `name_ar` / `name_sorani` / `name_badini`.
- **Current logged-in user id:** `sharedPreferences.getString('id_user')` (global `sharedPreferences` from `lib/core/app_state.dart`). Role: `sharedPreferences.getString('role_id')` (`'1'`=grantor/donor, `'2'`=beneficiary/eligible).
- **Shared UI:** `lib/shared/widgets/glass_ui.dart` (`SectionScaffold`, `GlassPanel`, `SectionTile`, `InfoChip` — these auto-`.tr` their title/subtitle/label).
- **Feedback helpers:** `lib/core/app_sound.dart` (`AppSound.notification()` chime), `lib/core/app_haptics.dart` (`AppHaptics.gentle()`), `lib/core/app_voice.dart` (`AppVoice.speak()` TTS — added #21).
- **API layer:** `lib/api/links.dart` (URL constants/builders), `lib/api/module_api.dart` (`getItems`/`getObject`/`postJson`/`postJsonNoTrack`; auth is attached automatically via `withApiAuth*`).

### 3.5 Terminology renames already shipped (use the NEW words — never revert)
- **Donor → Grantor** (المانح / بەخشەر). Do NOT rename the act of donating, "volunteer", or "partner" words.
- **Recipient/Beneficiary → Eligible** (مستحق). Do NOT rename "receive", "useful", or generic receiving words (مستلمة, وەرگرتن, سوودمەند=useful).
- App renamed **AutoShow → BalanceNex / توازن**.

---

## 4. Status snapshot — the 54-task backlog

Legend: ✅ done · ⬜ not started · **App**=Flutter · **API**=backend · **Admin**=dashboard

### Phase 1 — Quick wins ✅ (done in earlier sessions, already on `main`)
| # | Task | Status |
|---|---|---|
| 1 | Fix bug B1: notify admins/staff on submit | ✅ |
| 2 | Rename Donor → Grantor | ✅ |
| 3 | Rename Recipient/Beneficiary → Eligible | ✅ |
| 4 | Welcome card cleanup | ✅ |
| 5 | Notifications de-duplication | ✅ |
| 6 | Move Services into Profile | ✅ |
| 7 | Remove duplicate "Submit project" (bug B3) | ✅ |
| 8 | Support button at top | ✅ |
| 9 | Terms & Conditions screen + link (admin-editable) | ✅ |

### Phase 2 — Home & navigation ✅
| # | Task | Status |
|---|---|---|
| 10 | Home stats slider (grantors/eligibles/completed works) | ✅ |
| 11 | Group the stat cards in one rectangle | ✅ |
| 12 | Profile icon top-right → profile menu | ✅ |
| 13 | Beneficiary: messages + community services → profile | ✅ |

### Phase 3 — Donations & finance ✅
| # | Task | Status |
|---|---|---|
| 14 | Per-section transaction-code namespaces | ✅ |
| 15 | Donation-arrived notification: per-section phone + SMS | ✅ |
| 16 | Donation-type UI (+ #16b admin visibility) | ✅ |
| 17 | Project-category CMS | ✅ |
| 18 | "Give Now / Comprehensive Giving" | ✅ |
| 19 | Payment-method scalability (CMS) | ✅ |

### Phase 4 — Sponsorship calendar ✅
| # | Task | Status |
|---|---|---|
| 20 | Reminder scheduler (cron) | ✅ |
| 21 | Entitlement tracking screen + voice alert | ✅ |

### Phase 5 — Content sections 🔨 (7/9)
| # | Task | Status |
|---|---|---|
| 22 | "Our Work": 10 categories + add-category | ✅ |
| 23 | Post fields: add location + media | ✅ |
| 24 | Posts: like / comment / share | ✅ |
| 25 | Comment moderation + banned-words | ✅ |
| 26 | Partners: email / social / location | ✅ |
| 27 | Partners: rating | ✅ |
| 28 | Marketplace: categories + SKU + specs + labels | ✅ |
| 29 | City Guide: 6 sectors + hours + gallery + maps + call | ⬜ **NEXT** |
| 30 | City Guide: "Add an Activity" submission | ⬜ |

### Phase 6 — Settings, profile, privacy ⬜
| # | Task | Status |
|---|---|---|
| 31 | Notifications enable/disable toggle | ⬜ |
| 32 | Privacy per-field show/hide | ⬜ |
| 33 | In-app global search | ⬜ |
| 34 | Clear-cache / storage | ⬜ |
| 35 | About Us + Contact Us page (admin-editable — extend `app_content`) | ⬜ |
| 36 | WhatsApp escalation after 3 messages | ⬜ |
| 37 | Sounds + haptics mute toggle | ⬜ |
| 38 | Language selector dropdown | ⬜ |

### Phase 7 — Registration forms ⬜
| # | Task | Status |
|---|---|---|
| 39 | Grantor registration — full field set | ⬜ |
| 40 | Eligible/Beneficiary registration — full set | ⬜ |
| 41 | Volunteer/Employee registration | ⬜ |
| 42 | Marriage/My-Engagement form + privacy | ⬜ |
| 43 | Field-schema CMS (mandatory/optional per field) | ⬜ |
| 44 | Guest-mode action gating | ⬜ |

### Phase 8 — Cross-cutting / advanced ⬜
| # | Task | Status |
|---|---|---|
| 45 | Chat wiring (grantor↔eligible + volunteer↔tech + marriage↔tech) | ⬜ |
| 46 | Marriage: search + save + meeting request | ⬜ |
| 47 | Login: world phone codes | ⬜ |
| 48 | Approximate-location map (~500m) | ⬜ |
| 49 | Share app / post | ⬜ (share_plus already added in #24) |
| 50 | Digital aid-delivery receipt + photos | ⬜ |
| 51 | Reports export in Word | ⬜ |
| 52 | AI chatbot per-section icon | ⬜ |
| 53 | Hide sponsorship details for eligible | ⬜ |
| 54 | ID-code privacy everywhere | ⬜ |

---

## 4b. Plain-language feature guide — what every task means IN THE APP

> For each of the 54 tasks: what the user actually gets. The app itself ships in **4 languages (English, Arabic, Kurdish Sorani, Kurdish Badini)** and every feature below is fully translated in all four.

### Phase 1 — Quick wins ✅
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 1 | Submit alerts | When someone submits a case/request, admins & staff get an instant alert so nothing is missed | ✅ |
| 2 | "Grantor" wording | The person who gives is now called **Grantor** everywhere (was "Donor") | ✅ |
| 3 | "Eligible" wording | The person who receives help is now called **Eligible** everywhere (was "Recipient/Beneficiary") | ✅ |
| 4 | Cleaner welcome | The home welcome card was tidied up | ✅ |
| 5 | No double alerts | The same notification never shows twice | ✅ |
| 6 | Services in Profile | The Services section moved under Profile to declutter the home | ✅ |
| 7 | No duplicate button | Removed a duplicated "Submit project" button | ✅ |
| 8 | Support up top | The help/Support button now sits at the top, easy to reach | ✅ |
| 9 | Terms & Conditions | A Terms & Conditions page you can read in-app; admin can edit its text | ✅ |

### Phase 2 — Home & navigation ✅
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 10 | Impact slider | The home shows a rotating banner of impact numbers (grantors, eligibles, completed works, total given) | ✅ |
| 11 | One stats panel | Those numbers are grouped neatly into a single panel | ✅ |
| 12 | Profile menu | A profile icon at the top-right opens your account menu | ✅ |
| 13 | Simpler eligible view | For eligible users, messages & community are tucked into Profile to keep their screen simple | ✅ |

### Phase 3 — Donations & finance ✅
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 14 | Reference codes | Every donation gets a tidy reference code per section (e.g. `CAM-000042`) for tracking | ✅ |
| 15 | Arrival SMS | When a donation arrives, the section's contact person can receive an SMS alert | ✅ |
| 16 | Donation type | Donors can mark a gift as **general / zakat / sadaqah** | ✅ |
| 17 | Managed categories | Admin manages the list of project categories (4 languages) that eligibles choose from | ✅ |
| 18 | Give Now | A quick "Give Now / Comprehensive Giving" shortcut to donate fast | ✅ |
| 19 | Managed payment methods | Admin controls which payment methods (bank/cash/wallet) show, with account details | ✅ |

### Phase 4 — Sponsorship calendar ✅
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 20 | Auto reminders | Sponsors are automatically reminded when their monthly sponsorship payment is due | ✅ |
| 21 | My Entitlements + voice | An eligible person sees the sponsorships supporting them and can **hear a spoken summary** (helps low-literacy users) | ✅ |

### Phase 5 — Content sections 🔨 (7/9)
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 22 | "Our Work" categories | News & activities are grouped into categories with filter chips; admin manages the list | ✅ |
| 23 | Richer posts | Posts can include a **location** and a **photo gallery** | ✅ |
| 24 | Like / comment / share | People can like, comment on, and share posts | ✅ |
| 25 | Clean comments | Admins review comments; comments with bad words are auto-held for review | ✅ |
| 26 | Reachable partners | Partner cards show tappable **email, social links, and a map location** | ✅ |
| 27 | Partner ratings | Users rate partners **1–5 stars**; the average shows on the card | ✅ |
| 28 | Richer marketplace | Products get **categories, an SKU, a spec sheet, and badges** (new/sale/featured/used/in-stock) | ✅ |
| 29 | City Guide sectors | The City Guide gets **6 sectors, opening hours, a gallery, map links, and a call button** | ⬜ **NEXT** |
| 30 | Add an Activity | Users can **submit a new place/activity** that admins approve before it shows | ⬜ |

### Phase 6 — Settings, profile, privacy ⬜
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 31 | Notification switch | Turn notifications on/off in settings | ⬜ |
| 32 | Field privacy | Choose which of your profile fields are public or hidden | ⬜ |
| 33 | Global search | Search across the whole app from one box | ⬜ |
| 34 | Clear cache | A button to clear the app's stored/cached data | ⬜ |
| 35 | About & Contact | An About Us + Contact Us page, editable by admin | ⬜ |
| 36 | WhatsApp handoff | After 3 support messages, offer to continue on WhatsApp | ⬜ |
| 37 | Mute switch | A toggle to mute the app's sounds & vibrations | ⬜ |
| 38 | Language dropdown | Pick the app language from a dropdown | ⬜ |

### Phase 7 — Registration forms ⬜
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 39 | Grantor sign-up | A complete sign-up form for grantors with all needed fields | ⬜ |
| 40 | Eligible sign-up | A complete sign-up form for eligibles | ⬜ |
| 41 | Volunteer sign-up | A sign-up form for volunteers/employees | ⬜ |
| 42 | Marriage form | A marriage/engagement profile form with privacy controls | ⬜ |
| 43 | Field rules (admin) | Admin decides which registration fields are required vs optional | ⬜ |
| 44 | Guest gating | Guests can browse but are prompted to sign in before acting | ⬜ |

### Phase 8 — Cross-cutting / advanced ⬜
| # | Feature | What it means in the app | Status |
|---|---|---|---|
| 45 | Direct chat | Chat between grantor↔eligible, volunteer↔tech support, and marriage↔tech | ⬜ |
| 46 | Marriage search | Search, save, and request a meeting on marriage profiles | ⬜ |
| 47 | World phone codes | Login supports international phone country codes | ⬜ |
| 48 | Approx. location | Show an approximate (~500m) map location for privacy | ⬜ |
| 49 | Share app/post | Share the app or a post to other apps | ⬜ |
| 50 | Digital receipt | A digital aid-delivery receipt with photos | ⬜ |
| 51 | Word export | Export reports as Word documents | ⬜ |
| 52 | AI helper per section | An AI assistant icon in each section | ⬜ |
| 53 | Hide sponsorship money | Hide the sponsorship money details from the eligible person | ⬜ |
| 54 | ID-code privacy | Protect/hide ID codes everywhere they appear | ⬜ |

---

## 5. What was built this session (tasks #10–#28) — detailed log

> Every task below is **built + verified (go build/vet, admin tsc + vite build, flutter analyze all clean)** and committed to `new-update`. **None deployed.**

### #10 Home impact stats slider
Public `GET /api/stats/impact` (grantors/eligibles/volunteers/completed_works/total_given) + auto-rotating "Our impact" home slider (`humanitarian/lib/widgets/impact_stats_slider.dart`). Handler `internal/handlers/stats.go`, api `lib/api/stats_api.dart`. Fixed an Arabic/Kurdish glyph RenderFlex overflow (dynamic card height + clamped text scale).

### #11 Grouped stat cards
Replaced separate metric cards with one `_StatPanel` rectangle in `humanitarian/lib/widgets/dashboard.dart`.

### #12 Profile menu (top-right)
`humanitarian/lib/widgets/profile_menu.dart` + `ProfileMenuButton` added to dashboard header trailing. **Badini gotcha discovered here** (mixed quote styles → duplicate keys).

### #13 Beneficiary nav cleanup
`dashboard_screen.dart` `_hiddenNavIndices()` hides messages+community for beneficiaries (role '2').

### #14 Per-section transaction-code namespaces
Migration **026**. `internal/sectioncodes` (atomic `NextReference` → e.g. `CAM-000042` per donation kind). Wired into donor + admin donation-create paths. Admin donation-codes CRUD page (`DonationCodesPage.tsx`). *(Also fixed a `digitsOnly` redeclare — reuse the package one in events.go.)*

### #15 Per-section arrival SMS
Migration **027** (notify columns). `internal/auth/otpiq.go` gained `SendMessage` (free-form SMS via OTPIQ `smsType:"custom"` — **requires `OTPIQ_SENDER_ID`**). `donations.Insert` fires a detached goroutine `notifySectionArrival` after commit. Wired `donationStore.SendSMS` in main.go (nil-safe).

### #16 / #16b Donation type
Migration **028** (`donation_type`: general/zakat/sadaqah). Donor selector on the donate screen + `/donate` + admin list column/edit/create. Distinct from `donation_kind`.

### #17 Project-category CMS
Migration **029** (`project_categories`). First CMS clone. Public GET + admin CRUD/reorder page (`ProjectCategoriesPage.tsx`) + beneficiary submit-screen dropdown (free-text fallback).

### #18 Give Now
`donations_section.dart` `_GiveNowCard` + `_giveNow()` (clears campaign, scrolls to quick-amount). Rebranded "General Support" → "Comprehensive Giving".

### #19 Payment-method CMS
Migration **030** (`payment_methods`: cash/bank/wallet + account details, 4-lang). Donate screen fetches dynamically (Cash/FIB fallback). Admin CRUD/reorder page (`PaymentMethodsPage.tsx`). Store uses a shared `const cols` + `scan()` helper.

### #20 Reminder scheduler (cron)
Migration **031** (`sponsorships.last_reminder_due_date` + partial index). **First periodic-job infra in the backend**: `internal/scheduler` (ticker loop, boots 30s after start, scans every `SCHEDULER_INTERVAL`, exits on ctx cancel). Sends sponsors a 4-language "payment due" reminder (`notify.SponsorshipPaymentDueMsg`). Per-cycle dedup: remind only when `last_reminder_due_date != next_due_date`, then stamp it → auto re-arms when a payment advances the date. **Config:** `RUN_SCHEDULER=1` (off by default), `SCHEDULER_INTERVAL` (default 6h), `REMINDER_DAYS_BEFORE` (default 3). No app/admin UI — reminders surface via the existing notifications system.

### #21 Entitlement tracking + voice alert
**No migration.** Beneficiary sees sponsorships that BENEFIT them (their case is sponsored): new `sponsorships.ListByBeneficiary` + `GET /api/sponsorships?as=beneficiary` (joins `beneficiary_cases` on `beneficiary_case_id`). New Flutter **"My Entitlements"** screen (`modules/sponsorship/screens/beneficiary_entitlements_screen.dart` + controller) added to the beneficiary section. **Voice alert:** added `flutter_tts: ^4.2.0`, new `lib/core/app_voice.dart` (`AppVoice.speak`, safe no-op, langs en-US/ar-SA; Kurdish falls back to Arabic voice). Screen auto-reads a summary once on open + Listen/Stop buttons (accessibility for low-literacy users).

### #22 "Our Work" media-category CMS
Migration **032** (`media_categories` + 10 seeds + `media_posts.category_slug`). CMS clone (`internal/mediacategories`, `MediaCategoriesPage.tsx`). App: News & Activities gets category **filter chips** + a per-post category pill.

### #23 Post location + media gallery
Migration **033** (`media_posts.location`+3-lang + `gallery TEXT[]`). New EditModal **`gallery`** field type + `GalleryInput.tsx` (repeatable uploads). App card shows a location pill + a tappable **gallery strip** (full-screen pinch-zoom viewer).

### #24 Posts: like / comment / share
Migration **034** (`post_likes`, `post_comments`, `media_posts.share_count`). `internal/postengagement` store + `internal/handlers/media_engagement.go`. Authed routes: `POST /media/:id/like` (toggle), `GET·POST /media/:id/comments`, `POST /media/:id/share`. Feed now returns `like_count`/`comment_count`/`share_count`/`liked_by_me` (via optional `?user_id`). App: engagement bar on each post + a comments bottom-sheet + native **share sheet** (`share_plus`). Comment notifies the post author.

### #25 Comment moderation + banned-words
Migration **034** (`banned_words`). `internal/moderation` (cached blocklist). Comment submit: clean → **approved** (visible); contains a banned word → **pending + flagged** (held, user not told which word). Admin: **Comments** moderation page (`CommentsPage.tsx`) + **Banned words** page (`BannedWordsPage.tsx`). Status change via `updateStringStatus("post_comments",...)`.

### #26 Partners: email / social / location
Migration **035** (partners `email`, `social_links` TEXT one-per-line, `location`+3-lang). App partner card chips are now **tappable**: phone→dialer, email→mail, website, location→Google Maps, + one chip per social link (auto-labels Facebook/Instagram/WhatsApp/Telegram/YouTube/TikTok/X/LinkedIn).

### #27 Partners: rating
Migration **035** (`partner_ratings` 1–5 stars one-per-user + denormalized `avg_rating`/`rating_count`). `internal/partnerratings` (upsert + recompute avg). Authed `POST /api/partners/:id/rate`. Partners list returns `avg_rating`/`rating_count`/`my_rating`. App: star display + a **"Rate" bottom-sheet** star picker. Admin: read-only **Rating** column.

### #28 Marketplace: categories + SKU + specs + labels
Migration **036** (`marketplace_categories` CMS + 12 seeds; products `category_slug`, `sku`, `specs` TEXT, `labels TEXT[]`). `internal/marketplacecategories` + `admin_marketplace_categories.go`. **Labels** are a fixed enum (`new/sale/featured/used/in_stock`) validated backend-side (`sanitizeLabels`). New EditModal **`multiselect`** field type. Admin: **Product categories** page + SKU/Specs/Labels fields + dynamic category dropdown. App: card shows category + colored **label badges**; details sheet shows SKU + parsed **specs** ("Key: Value" per line).

---

## 6. Database migrations delivered this session (025–036)

Applied automatically in filename order when `RUN_MIGRATIONS=1`. All idempotent. **These have NOT run in production yet.**

| File | Adds | Task |
|---|---|---|
| `025_app_content.sql` | `app_content` key-value CMS (Terms/About/Contact) | #9 |
| `026_donation_section_codes.sql` | per-kind transaction-code sequences | #14 |
| `027_donation_notify.sql` | per-section notify phone/enabled columns | #15 |
| `028_donation_type.sql` | `donations.donation_type` | #16 |
| `029_project_categories.sql` | `project_categories` CMS + seeds | #17 |
| `030_payment_methods.sql` | `payment_methods` CMS + seeds | #19 |
| `031_sponsorship_reminders.sql` | `sponsorships.last_reminder_due_date` + index | #20 |
| `032_media_categories.sql` | `media_categories` + 10 seeds + `media_posts.category_slug` | #22 |
| `033_media_post_location_gallery.sql` | `media_posts.location`(+3) + `gallery TEXT[]` | #23 |
| `034_post_engagement.sql` | `post_likes`, `post_comments`, `banned_words`, `media_posts.share_count` | #24/#25 |
| `035_partners_extend.sql` | partners email/social/location + `partner_ratings` + avg | #26/#27 |
| `036_marketplace_extend.sql` | `marketplace_categories` + products category_slug/sku/specs/labels | #28 |

*(Migrations 001–024 were applied in prior sessions and are on `main`.)*

---

## 7. Deploy / environment status

**Hosting:** Railway (Postgres + Go service). Push notifications: **FCM live in prod** via `FIREBASE_CREDENTIALS_JSON` env var.

**Environment variables the backend reads:**
| Var | Purpose | State |
|---|---|---|
| `DATABASE_URL` | Postgres connection | set (prod) |
| `RUN_MIGRATIONS=1` | apply pending migrations on boot | **must be set on next deploy** to apply 025–036 |
| `RUN_SCHEDULER=1` | enable #20 reminder cron | **not set — scheduler off until set** |
| `SCHEDULER_INTERVAL` | scan interval (default `6h`) | optional |
| `REMINDER_DAYS_BEFORE` | reminder look-ahead (default `3`) | optional |
| `OTPIQ_API_KEY` | OTP + SMS (OTPIQ) | set (prod) |
| `OTPIQ_SENDER_ID` | **required for #15 free-form arrival SMS** | **not set — #15 SMS won't send until set** |
| `ANTHROPIC_API_KEY` | AI assistant (optional; keyword fallback otherwise) | optional |
| `FIREBASE_CREDENTIALS_JSON` | FCM push | set (prod) |
| `PORT` / `HTTP_PORT`, `APP_ENV` | server port / env | set |

**DEPLOY CHECKLIST (when the owner says "go"):**
1. Merge/deploy the `new-update` branch.
2. Ensure `RUN_MIGRATIONS=1` so migrations **025–036** apply (Railway var-cache can be stale — verify).
3. (Optional) set `RUN_SCHEDULER=1` + interval to turn on sponsorship reminders (#20).
4. (Optional) set `OTPIQ_SENDER_ID` to turn on section-arrival SMS (#15).
5. Rebuild the admin (`npm run build`) and the Flutter app as needed.

---

## 8. New code inventory (quick map for the next Claude)

**New backend packages (`backend/internal/`):** `sectioncodes`, `content`, `projectcategories`, `paymentmethods`, `scheduler`, `mediacategories`, `postengagement`, `moderation`, `partnerratings`, `marketplacecategories`.

**New backend handlers (`backend/internal/handlers/`):** `stats.go`, `content.go`, `donation_codes.go`, `admin_project_categories.go`, `admin_payment_methods.go`, `admin_media_categories.go`, `media_engagement.go`, `admin_banned_words.go`, `partner_engagement.go`, `admin_marketplace_categories.go`.

**New admin pages (`admin-web/src/pages/`):** `TermsPage`, `DonationCodesPage`, `ProjectCategoriesPage`, `PaymentMethodsPage`, `MediaCategoriesPage`, `CommentsPage`, `BannedWordsPage`, `MarketplaceCategoriesPage`. **New component:** `GalleryInput.tsx`. **EditModal** gained `gallery` + `multiselect` field types.

**New Flutter files (`humanitarian/lib/`):** `core/app_voice.dart`; `api/{stats,content,payment_methods,project_categories}_api.dart`; `widgets/{impact_stats_slider,profile_menu}.dart`; `modules/legal/` (Terms); `modules/sponsorship/{controllers/beneficiary_entitlements_controller,screens/beneficiary_entitlements_screen}.dart`. **New deps in `pubspec.yaml`:** `share_plus: ^10.1.4`, `flutter_tts: ^4.2.0`.

---

## 9. Known pending / follow-ups (don't lose these)

1. **OPOS backfill:** the OPOS connector was DOWN the entire session. Tasks **#14–#28** were built but **NOT logged** as OPOS review/build tasks. When the connector recovers, backfill them in office "-129- Charity App" (see §2 rule 5).
2. **`OTPIQ_SENDER_ID`** must be set in prod before #15 arrival-SMS actually sends.
3. **`RUN_SCHEDULER=1`** must be set before #20 reminders fire.
4. **Nothing is deployed.** Migrations 025–036 have not run in prod. Get an explicit "go" first.
5. **Marketplace category filter:** #28 stores + displays the category, but the app product feed is paginated and there is **no server-side category filter** yet (only client-side name display). If a filter UI is wanted, add a `category` query param to `marketplace.ListProducts`.
6. **Kurdish translations** for the many new keys were first-pass (owner-reviewable). Native-speaker review recommended before a public launch (esp. Badini).

---

## 10. What's next

**Immediate (finish Phase 5):**
- **#29 City Guide: 6 sectors + hours + gallery + maps + call.** The City Guide / community directory lives in `city_directory_entries` (has `city`, `address`, `latitude`, `longitude` already). Likely work: a 6-sector taxonomy (CMS clone or fixed enum), opening-hours field, a photo gallery (reuse the `gallery TEXT[]` + `GalleryInput` pattern from #23), map link (reuse the `_openMaps` Google-Maps-search pattern from #26), and a call button (tel: launch). **Map it with an Explore agent first.**
- **#30 City Guide: "Add an Activity" submission** — a user-submitted activity that lands in the admin moderation queue (mirror the beneficiary-submit + admin-status-approve pattern).

**Then Phases 6–8** (see §4). Notable reuse:
- **#35 About/Contact** — extend the existing `app_content` CMS (slugs already whitelisted; Terms already uses it).
- **#49 Share app/post** — `share_plus` is already a dependency (added in #24).
- **#37 sounds/haptics mute** — `AppSound`/`AppHaptics`/`AppVoice` already exist; add a persisted toggle.

**Recommended working loop for the next Claude (matches the owner's expectations):**
1. Owner names a task → **map it first with an Explore agent** (find exact tables/files/patterns) before writing.
2. Build "their way" (polished, all 4 languages, reuse existing patterns).
3. Verify: `go build ./... && go vet ./...`, admin `tsc -b` + `vite build`, `flutter analyze` — all clean.
4. (When connector is up) log OPOS review + build tasks and mark done.
5. Report concisely + re-send the phase/task table with updated status.
6. **Commit/push only when asked; deploy only on an explicit "go".**

---

*End of handoff. If anything here disagrees with the code, trust the code — but tell the owner what changed.*
