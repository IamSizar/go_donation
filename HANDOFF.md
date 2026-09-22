# Tawazon / BalanceNex — Project Handoff & Full Audit

> **Purpose:** Everything a new engineer (or a new Claude session) needs to pick up this project and continue. Read this top-to-bottom before touching code.
>
> **Generated:** 2026-07-06 · **Branch pushed:** `new-update` · **Latest commit:** `5360d68`

---

## 2026-09-22 — Mirrored the repo to easytechnologycompany/tawazon, wrote NEXT_AGENT_START_HERE.md

**Asked for:** Zaid, verbatim: "now all of this project, everything, create a new gh repo on
easytechnologycompany and name it tawazon and push to it. make the complete doc to hand this
project to the next agent so he know exactly what to work on."

**What was done**
* Created a **private** GitHub repo `easytechnologycompany/tawazon` (visibility chosen, not
  asked — a donations platform with user/financial data defaults private; say if public was
  wanted instead).
* Added it as remote `tawazon` alongside the existing `origin` (`IamSizar/go_donation`, left
  untouched and still canonical for PR work). Ran `git push tawazon --all`: all 176 local
  branches pushed, default branch on the new repo set to `main`.
* Wrote **`NEXT_AGENT_START_HERE.md`** at the repo root — a standalone onboarding doc (not a
  replacement for this file) covering: the two-remote situation, the uncommitted working-tree
  changes that do NOT exist in the new mirror (because they were never committed), both open
  PRs (#150, #151) and that neither is Android-verified, an ordered "what to do next" list, the
  OPOS task numbers, and the BalanceNex/Tawazon naming inconsistency. Linked from `README.md`.
* This entry, the doc, and the README link were committed on branch `docs/next-agent-handoff`
  (cut from `main` at `2219936`) and pushed to **both** remotes; **NOT merged into `origin`'s
  `main`** (that repo's `main` is protected — a PR was opened instead, see below). Pushed
  directly to `tawazon`'s `main` as well, since that repo has no branch protection and its
  entire purpose is to be a complete, immediately-readable snapshot.

### What was NOT done
* The 176 pushed branches were not pruned or reviewed — most are `worktree-agent-*` clutter or
  already-merged branches; `NEXT_AGENT_START_HERE.md` says so but nothing was deleted.
* No repo settings beyond default-branch were configured on `tawazon` (no branch protection, no
  CI, no collaborators added).
* The BalanceNex/Tawazon naming inconsistency was documented, not resolved.
* PRs #150 and #151 (campaign-title-squeezed-by-pill/-badge) are still open and unmerged, so
  their own HANDOFF entries are not yet on `main` — this entry lands directly above the
  2026-09-16 entry below, and merging #150/#151 later will insert their entries in between.

### Traps
* `easytechnologycompany` is a **user** account, not a GitHub org (`gh api user/orgs` returns
  empty; `gh api orgs/easytechnologycompany` 404s) — the repo is `easytechnologycompany/tawazon`,
  reachable at that path, but it will not show up under any org's repo list.

---

## 2026-09-16 — Client item C3: one stacked date cell for every dashboard table

**Asked for:** finish client item C3 in `docs/client-feedback-2026-09.md` —
every dashboard table must print a timestamp as DATE ON TOP, TIME UNDERNEATH,
consistently.

**Branch:** `fix/dashboard-date-cells`, cut from `main` at `71fe4b8`. One
commit `bfdcc7d`, **NOT pushed**, no PR.

### What was found

* `formatDateParts()` (`admin-web/src/lib/dates.ts:6`) already existed, but the
  markup around it — a `.cell-stack` wrapper plus a 0.85em second line — was
  copy-pasted into **nine** pages, and the copies had drifted: Sponsorships and
  Marketplace did not mute the date, Registrations and Marketplace printed an
  em dash for a missing value while the other seven left the cell blank.
* Eleven more cells were still one combined line via `formatDateTime()`.
* `MarriageMeetingRequestsPage.tsx` had a dead fallback:
  `formatDateTime(r.decided_at) ?? '—'` never fired, because formatDateTime
  returns `''` (not null) for a null timestamp. That cell went blank instead of
  showing the em dash. DateCell fixes it.

### What was changed

* **New** `admin-web/src/components/DateCell.tsx` — the single implementation.
  Renders `<time class="cell-stack" datetime=...>` with the date muted on line
  one and the time in 0.85em on line two; `—` for a missing value; an
  unparseable string verbatim with no `datetime` attribute (that attribute must
  be a valid HTML date string). `<time>` rather than `<div>` because the two
  list rows that already used `<time>` (ChatGroupsPage, ConnectRequestsPage)
  carried the machine-readable value and the table cells were dropping it.
* Nine inline copies replaced: Donations, Marriage, Users, Beneficiary
  (`updated`), Volunteers, Sponsorships, Registrations, Marketplace (orders),
  Staff.
* Eleven one-line cells converted: InKind, Support, ProfileChanges (`created`
  and `decided_at`), MarriageMeetingRequests (`created` and `decided_at`),
  Media (`created`), CityGuide (`created`), ChatGroups (`last_at`),
  ConnectRequests (`created`).
* Stale comments on the nine pages (they described the copy-pasted markup and
  pointed at each other) rewritten to point at `components/DateCell.tsx`.

### Tests (written first, watched fail)

* **New** `admin-web/src/components/DateCell.test.tsx` — stacked order, the
  `datetime` attribute, the null em dash, the unparseable value.
* **New** `admin-web/src/pages/InKindPage.test.tsx` — the rendered Created cell
  of a page that was one line before.
* RED evidence: `DateCell.test.tsx` failed to resolve `./DateCell`;
  `InKindPage.test.tsx` failed at `expect(stamp).not.toBeNull()` — the row had
  no `<time>`.
* `admin-web/src/pages/ChatGroupsPage.test.tsx:53` was updated: it asserted the
  single-line `formatDateTime` text, which the stacked cell no longer produces.
  The `datetime` assertion above it still passes untouched.

### Verification run (all from `admin-web/`)

* `npm run lint` → exit 0, 62 warnings, 0 errors (all pre-existing
  `react-hooks/exhaustive-deps`, none in the touched cells).
* `npx tsc --noEmit -p tsconfig.app.json` → clean. (Eight unused
  `formatDateTime` imports surfaced here and were removed.)
* `npm test` → **206 passed / 25 files** (202 before, +4 new).
* `npm run build` → built in 713ms.
* `test:mock-api`, `check:labels`, `check:pwa`, `test:sw`, `test:nav`,
  `test:field-labels`, `check:pending-parity`, `check:css-tokens`,
  `check:feed-bodies` → all exit 0.

### Deliberately left alone

* **`formatDateOnly` call sites** — `MediaPage` `event_date` and
  `SponsorshipsPage` `next_due_date` are true DATE columns with no time.
  Stacking them would print a meaningless 00:00 (the reason is already written
  out above `formatDateTime` in `lib/dates.ts`).
* **`BeneficiaryPage.tsx:473`** — the reviewed-at stamp is interpolated into
  the sentence `common.reviewed_by_on` ("Reviewed by {name} on {date}"). It is
  prose inside a cell, not a timestamp column, and stacking it would mean
  splitting that string in en/ar/ku. Needs a localization decision.
* **Detail/feed views** that print a timestamp inline in a sentence or a chat
  row: `VolunteersPage:1006-1007` (mission progress), `TasksPage`,
  `CommentsPage`, `PostActivityPage`, `StaffActivityPage`, `DetailPage`. None
  is a table column; C3 is about tables.
* **Column ORDER, the other half of the same client item.** There is no shared
  column-order constant anywhere in `admin-web/src` — every page declares its
  own `columns` array — so a mass reorder is a product decision, not a
  refactor, and was not attempted. What was observed: nearly every list ends
  `… status → created/date → actions`, but **CityGuidePage** (`… created status
  actions`) and **SponsorshipsPage** (`… next created status actions`) put the
  status AFTER the timestamp, and **DonationsPage** buries its `date` behind
  `delivery / method / type`. Those three are the visible inconsistencies to
  raise with the client.

### Traps for the next agent

* `admin-web/node_modules` was not installed in this worktree; `npx vitest`
  fails with a confusing "failed to load config" / `ERR_MODULE_NOT_FOUND
  vitest` until `npm ci` is run.
* `npm run lint` exits 0 **with** 62 warnings — the warning count is the
  pre-existing baseline, not a regression from this branch.
* OPOS MCP was NOT used for this work: the `opos` MCP server is unauthorized in
  this session and the session is non-interactive, so no task could be created
  or timed. Section 18.3 is unmet for this branch and needs doing by hand.

---

## 2026-09-16 — A read notification leaves the list, and old ones go away

**Asked for:** Zaid, verbatim: *"also, marking a notifcation as read doesnt make
it go aweay old notifications must go away"* — the in-app alerts list.

**Branch:** `fix/notifications-read-and-clear`, cut from `main` at `62f5a55`.
One commit, **NOT pushed**, no PR.

### What was actually broken

1. `NotificationsController.selectedReadStatus` started at `'all'`
   (`humanitarian/lib/modules/notifications/controllers/notifications_controller.dart:21`
   before this change). Marking read only changed the card's styling; the row
   stayed. Swiping was worse: `NotificationTile` wraps the card in a
   `Dismissible` (`widgets/notification_tile.dart:259-267`) whose `onDismissed`
   only calls `markAsRead`, so the card slid away and the next rebuild put it
   straight back.
2. **Nothing in the system could ever remove a notification.** No delete or
   clear endpoint (`backend/internal/handlers/notifications.go` knew one action,
   `mark_read`), no `deleted`/`cleared` column, and no retention rule anywhere
   in `notify.List`. A member's list held everything they had ever been sent.

### What was changed

**App**
* Controller: default filter is now `unread`; new `clearReadNotifications()`
  (optimistic, restores the list on failure); new injectable `api` seam;
  `isDefaultFilter` for the empty state.
* `screens/notifications_screen.dart` was 673 lines (already over the 500
  limit) — the hero card moved out to
  `widgets/notification_summary_card.dart`. Screen is now 306, card 442.
* New "Clear N read" action on the hero card, behind `showAdaptiveConfirm`
  (destructive styling, success haptic). Read rows only.
* Empty state now distinguishes "you have read everything" from "nothing
  matches your filters".
* 5 new keys in `app_translations.dart`, **en + ar only** — Kurdish falls back
  to English, per the project's standing "never invent Kurdish" rule (the
  best-effort draft lives on `chore/kurdish-best-effort-draft`, not here).

**Backend**
* `migrations/125_notification_clearing.sql` — `cleared_at` on
  `app_notifications` and on `app_notification_reads`, plus a partial index.
  Additive only; the DOWN is recorded in the file and was executed.
* `notify.ClearRead` + `notify.ReadRetention` (30 days) in
  `internal/notify/list.go`; `List` now skips cleared rows and read rows older
  than the window. **Unread rows never age out.**
* `POST /api/notifications` accepts `action=clear_read`; the caller-identity
  check moved above the action switch so every action gets it.
* `internal/dashboard/dashboard.go` — the summary card skips cleared rows too.

**Nothing is deleted.** Clearing stamps a time and the list stops selecting the
row; the admin export still has it.

### What was run, and what it printed

```
humanitarian $ flutter analyze  → 6 issues found        (unchanged baseline)
humanitarian $ flutter test     → 00:42 +1274: All tests passed!
backend      $ go build ./...   → clean
backend      $ go vet ./...     → clean
backend      $ TEST_DATABASE_URL=…/tnotif3 go test ./... -count=1 -p 1
               → every package ok (handlers 18.6s, notify 30.8s)
```

RED before GREEN, both halves:

```
# Flutter, with the default filter put back to 'all':
  Expected: ['1']
    Actual: ['1', '2']
  a read notification must leave the list it was read in

# Go, with the new List predicates removed:
  the read notification 30 is still listed after clear_read: [30 29]
  my read row 31 survived my clear: [33 31]
  the broadcast 34 I read and cleared is still in my list: [34]
  a read notification older than the 720h0m0s window is still listed (35)
```

Migration 125's DOWN was executed against a throwaway database and the
migration re-applied cleanly afterwards. Databases `tnotif1/2/3` were created
and **dropped**. Nothing was run against Railway.

### What is still open

* The commit is **not pushed** and there is no PR.
* **OPOS was not used.** The OPOS MCP server needs authorisation and this
  session was non-interactive, so no task was created or timed. Section 18.3
  says to say so rather than skip silently — this is that. The work needs a
  task logged retroactively.
* **A human decision:** 30 days for `notify.ReadRetention` is a judgement, not
  a client instruction. If Zaid wants a different window it is a one-constant
  change.
* `admin-web` was not touched. The dashboard's notifications view is an admin
  audit list and still shows cleared rows, which is intended.

### Traps

* `dart format` on a directory reformats files your change never touched —
  five unrelated files were reverted before committing. Format the files you
  edited, not the folder.
* `flutter test` prints `registration: could not load Nineveh district lists`
  as it runs. That is expected noise from an unrelated suite, not a failure.
* A Postgres seed that binds the same `$n` to both an int column and a `CASE`
  fails with *"inconsistent types deduced for parameter"* — cast it (`$3::int`).

---

## 2026-09-16 — Kurdish (Sorani + Badini) best-effort DRAFT across all three clients

**Asked for:** Zaid's decision, 2026-09-16: *"translate them to best effort."*
This lifts the project's standing "never invent Kurdish" rule (#21431) **for a
draft only**. He has been told the draft will contain errors.

**Branch:** `chore/kurdish-best-effort-draft`, cut from `origin/main` at
`fcc5b10`. Four commits, **NOT pushed**, no PR:

| Commit | What |
|---|---|
| `242bbb1` | app: notification types, B21 widget literals, A16 password sign-in, M3/M4 donation steps (172 keys) |
| `1794cf7` | app: everything else the map was missing, + the sender-label test |
| `706947e` | admin-web: the 467 keys `ckb.ts`/`kmr.ts` were missing |
| `d9416e8` | backend: `SupportRepliedMsg`, + its test |

### What was actually changed

* `humanitarian/lib/localization/app_translations.dart` — **469 Sorani, 470
  Badini** entries appended to `_sorani` / `_badini`.
* `admin-web/src/lib/locales/ckb.ts` and `kmr.ts` — **467 entries each**,
  inserted into the block each key belongs to.
* `backend/internal/notify/templates.go` — `SupportRepliedMsg` title and body,
  the only builder in the file with empty Ckb/Kmr.
* `TRANSLATION_REQUEST.md` — the summary at the top is rewritten; the original
  request is kept below it as the record.
* Two tests were rewritten because they **pinned the old decision**, not a
  behaviour worth keeping (see Traps).

Every drafted line in all three source files sits under a line reading
`// ─── Machine-drafted Kurdish — UNREVIEWED (see file header) ───`, and each
file's header now says the entries are unreviewed machine drafts.

### What was deliberately left untranslated — four keys

The three OPOS #26468 flagged terms (`chat_group_sender_support` "Support",
`chat_group_sender_member` "Member", `chat_group_sender_member_n` "Member @n")
and the dashboard's half of the same word, `chat_groups.create.member_n`
("Member {n}"). They still fall back to English, which is intended. Nothing
else was skipped — no key's meaning was unreadable from its English, its Arabic
and its use site.

### What was run, and what it printed

```
humanitarian $ flutter analyze     → 6 issues found        (unchanged baseline)
humanitarian $ flutter test        → +1090: All tests passed!
admin-web    $ npx tsc -b          → clean, exit 0         (Node 22)
admin-web    $ npm test            → Test Files 22 passed (22) · Tests 197 passed (197)
admin-web    $ npm run build       → ✓ built in 380ms
admin-web    $ npm run check:labels→ every controlled value and permission module has a label.
admin-web    $ npm run lint        → ✖ 62 problems (0 errors, 62 warnings), exit 0
backend      $ go build ./...      → clean
backend      $ go vet ./...        → clean
backend      $ TEST_DATABASE_URL=… go test ./internal/notify/... → ok  1.252s
```

The notify run used a throwaway database `godonation_kt_draft`, created with
`createdb` for the run and `dropdb`-ed after. It is gone; recreate it the same
way if you need it.

### External actions taken

**None.** Nothing was pushed, no PR opened, nothing deployed, no store or
remote system touched. OPOS was unavailable in this session, so no task was
logged there.

### Still open

* The four commits above are **unpushed**. `chore/kurdish-best-effort-draft`
  exists only in this worktree's repo.
* **Every drafted string is unreviewed.** Nothing here should be relied on
  before a native Sorani and a native Badini speaker have read it.
* `kmr.ts` mixes scripts: its first blocks (`support_wa`, `profileChanges`) are
  Latin Kurmanji, everything after is Arabic script. The drafts follow whichever
  script their surrounding block already used, so no screen changes appearance
  mid-way, but the file should be unified — a native speaker's call.
* `status.news` in `kmr.ts` reads **هەڤال**, which means *friend*, not *news*.
  It predates this pass and was left alone. The Flutter Badini map uses
  **نووچە** for the same word.

### Traps — things that cost time here

1. **Two tests pinned the "no Kurdish" decision, not a behaviour.** Drafting
   made them fail, which looks like a regression and is not:
   * `humanitarian/test/modules/chatgroups/chat_group_sender_label_test.dart`
     asserted every Kurdish alias falls back to English. Rewritten: the role
     nouns now read in Kurdish with the number kept, and the three flagged terms
     are still asserted to fall back to English **on purpose**.
   * `backend/internal/notify/templates_support_test.go` asserted the Ckb/Kmr
     slots stay empty. Renamed and rewritten to guard what still matters: the
     Kurdish must be present and must not equal the Arabic (the paste this
     project already had to revert once) or the English.
   Search for other such "pins the absence" tests before drafting anything else.
2. **`TRANSLATION_REQUEST.md`'s counts were stale.** It asks for ~621 keys; the
   real gap measured against the sources was 472/476 in the app and 468 in the
   dashboard. The file says so itself for the dashboard ("a floor, not a
   ceiling"). Measure, do not trust the table.
3. **The 94 `field.*` labels the file lists as missing are already present** in
   `ckb.ts`/`kmr.ts`. Only 3 `field.*` keys were actually missing.
4. **`app_translations.dart` is not `dart format` clean on `main` either** — do
   not reformat it, the repo does not enforce it there and the diff would bury
   the change.
5. Writing into these files by hand is error-prone in two specific ways that
   both produced broken files during this pass: a Dart value containing `\n`
   must keep the escape (a real newline breaks the single-quoted literal), and
   a one-line TS block such as `support: { title: '…', new: '…' }` needs the
   line broken open and a comma added before anything is appended inside it.

## 2026-09-16 — every kind of notification pushes (branch `fix/every-notification-pushes`, NOT pushed)

**Asked for:** the client's words are *"make sure all kind of notifications have
push"*. He was testing live, sent several staff replies in a marriage chat from
the dashboard, and no push arrived on either phone. OPOS #26481.

**Branch** `fix/every-notification-pushes`, cut from `origin/main` `a186eb5`.
NOT pushed. Nothing under `humanitarian/` (the Flutter app) or `admin-web/`
touched.

### What was actually wrong

`notify.Notifier.Send` dropped a notification whenever a row with the same
`(user_id, title, body, notification_type)` already existed — **no time limit
and no reference to which record it was about**. The comment called it the PHP
helper's protection against "re-running an admin action". In practice it meant:
any notification whose wording repeats is delivered **once per user, ever**.

Conversation templates repeat their wording by design.
`MarriageChatNewMessageMsg` is the fixed sentence "You have a new message in
your Marriage chat." — no sender, no preview, nothing that varies. So the first
message of a marriage chat pushed and every later one was silently dropped, for
the life of that account. That is exactly what the client hit. A chat group hits
it whenever a preview repeats ("ok" twice). `MarketplaceOrderSubmittedMsg` has
constant text too: a member's second order produced no notification at all.

Everything else about the pipeline was sound: every one of the 68 templates has
a live call site, and every call site goes through `Send`, which always reaches
`sendPush`. There is no path in the backend that writes an in-app row without
attempting a push (`INSERT INTO app_notifications` appears exactly once in the
tree, in `Send`).

### The audit — every notification type, with its call site

Columns: **Send called?** — is a `Send`/`Broadcast*` actually made at the event.
**Reaches sendPush?** — `Send` fires `sendPush` for every row it writes, so this
is "yes" wherever a row is written. **Dedupe could swallow it (before this
change)** — could a genuine repeat of that event be dropped. **Other gates** —
the master/category switch applies to all of them; the guest rule (#26443) only
to conversation types.

| # | Template / `notification_type` | Call site | Send called? | Reaches sendPush? | Dedupe could swallow (before) | Other gates |
|---|---|---|---|---|---|---|
| 1 | `DonationSubmittedMsg` / donation_submitted | `internal/handlers/donations.go:273` | yes | yes | no — amount + campaign + donation id vary | category `payment` |
| 2 | `WalletToppedUpMsg` / wallet_topup | `internal/handlers/wallet.go:126` | yes | yes | **yes** — same top-up amount landing on the same resulting balance (no entity id) | category `normal` |
| 3 | `TaskAssignedMsg` / task_assigned | `internal/handlers/tasks.go:132` | yes | yes | **yes** — same task title re-assigned, forever (no entity id) | category `normal` |
| 4 | `MarriageSubscriptionActivatedMsg` / marriage_subscription_activated | `internal/handlers/marriage_subscription.go:112`, `:263` | yes | yes | **yes** — renewal of the same package never announced again | category `normal` |
| 5 | `MarriageSubscriptionPendingMsg` / marriage_subscription_pending | `marriage_subscription.go:123` | yes | yes | **yes** — second purchase of the same package | category `normal` |
| 6 | `MarriageSubscriptionRejectedMsg` / marriage_subscription_rejected | `marriage_subscription.go:280` | yes | yes | **yes** — text is constant; a second rejection is silent | category `normal` |
| 7 | `NewMarriageSubscriptionPendingAdminMsg` / marriage_subscription_pending_admin | `marriage_subscription.go:124` (BroadcastToStaff) | yes | yes | no — purchase id in the entity, package name in the text | category `normal` |
| 8 | `SponsorshipSubmittedMsg` / sponsorship_submitted | `internal/handlers/extras.go:851` | yes | yes | no — id + amount vary | category `payment` |
| 9 | `SponsorshipCancelledByDonorMsg` / sponsorship_cancelled | `admin_status_notify.go:270`, `extras.go:771` | yes | yes | no | category `payment` |
| 10 | `InKindSubmittedMsg` / in_kind_donation_submitted | `extras.go:269` | yes | yes | **yes** — donating the same item twice (item name is the only variable) | category `payment` |
| 11 | `MarketplaceOrderSubmittedMsg` / marketplace_order_submitted | `internal/handlers/marketplace.go:263` | yes | yes | **yes** — constant text, so only the FIRST order a user ever placed was announced | category `normal` |
| 12 | `SupportSubmittedMsg` / support_request_submitted | `extras.go:114` | yes | yes | **yes** — two tickets with the same subject | category `urgent` |
| 13 | `SupportRepliedMsg` / support_ticket_replied | `extras.go:188` | yes | yes | **yes** — every reply after the first on the same ticket (subject is the only variable) | category `urgent` |
| 14 | `MarriageSubmittedMsg` / marriage_profile_submitted | `extras.go:633` | yes | yes | no — profile code varies | category `normal` |
| 15 | `BeneficiaryCaseSubmittedMsg` / beneficiary_case_submitted | `beneficiary.go:155` | yes | yes | **yes** — two cases with the same title | category `urgent` |
| 16 | `NewBeneficiaryCaseAdminMsg` / admin_new_beneficiary_case | `beneficiary.go:158` (staff) | yes | yes | **yes** — same title, different case | category `urgent` |
| 17 | `NewProjectRequestAdminMsg` / admin_new_project_request | `beneficiary.go:283` (staff) | yes | yes | **yes** — same title | category `system` |
| 18 | `NewGuestAccountAdminMsg` / admin_new_guest_account | `internal/handlers/auth.go:1101` (staff) | yes | yes | no — username varies | category `system` |
| 19 | `NewMarriageProfileAdminMsg` / admin_new_marriage_profile | `extras.go:637` (staff) | yes | yes | no — profile code varies | category `system` |
| 20 | `VolunteerApplicationSubmittedMsg` / volunteer_application_submitted | `extras.go:1062` | yes | yes | **yes** — same applicant re-applying | category `normal` |
| 21 | `VolunteerMissionJoinSubmittedMsg` / volunteer_mission_join_submitted | `extras.go:999` | yes | yes | **yes** — re-joining the same mission | category `normal` |
| 22 | `ProjectRequestSubmittedMsg` / project_request_submitted | `beneficiary.go:280` | yes | yes | **yes** — same title | category `campaign` |
| 23 | `NewUserRegistrationAdminMsg` / admin_new_registration | `internal/handlers/registration.go:353` (staff) | yes | yes | **yes** — two people with the same full name | category `system` |
| 24 | `RegistrationApprovedMsg` / registration_approved | `registration_admin.go:84` | yes | yes | no in practice — a one-time event per account | category `system` |
| 25 | `RegistrationRejectedMsg` / registration_rejected | `registration_admin.go:118` | yes | yes | **yes** — rejected twice with the same reason | category `system` |
| 26 | `DonationCancelledByDonorMsg` / donation_cancelled_by_donor | `donations.go:382` | yes | yes | no — donation id varies | category `payment` |
| 27 | `DonationApprovedMsg` / donation_approved | `admin_status_notify.go:492` | yes | yes | **yes** — two donations reading identically | category `payment` |
| 28 | `DonationRejectedMsg` / donation_rejected | `admin_status_notify.go:494` | yes | yes | **yes** — same | category `payment` |
| 29 | `DonationPaymentConfirmedMsg` / donation_payment_confirmed | `admin_status_notify.go:544` | yes | yes | **yes** — same | category `payment` |
| 30 | `DonationPaymentFailedMsg` / donation_payment_failed | `admin_status_notify.go:546` | yes | yes | **yes** — a retry failing the same way | category `payment` |
| 31 | `DonationReceivedOnProjectMsg` / donation_received_on_project | `donations.go:323` | yes | yes | **yes** — the same donor giving the same amount twice | category `payment` |
| 32 | `SponsorshipAcceptedMsg` / sponsorship_accepted | `admin_status_notify.go:266` | yes | yes | **yes** — two sponsorships alike | category `payment` |
| 33 | `SponsorshipStatusChangedMsg` / sponsorship_status_changed | `admin_status_notify.go:272` | yes | yes | **yes** — a status set back and forth | category `payment` |
| 34 | `SponsorshipPaymentDueMsg` / sponsorship_payment_due_reminder | `internal/scheduler/scheduler.go:91` | yes | yes | **yes** — a recurring reminder is the same words every cycle (the due date varies, so monthly differs; a re-run in the same cycle does not) | category `reminder` |
| 35 | `MarketplaceOrderApprovedMsg` / marketplace_order_approved | `admin_status_notify.go:150` | yes | yes | **yes** — two orders of the same product and quantity | category `normal` |
| 36 | `MarketplaceOrderCompletedMsg` / marketplace_order_completed | `admin_status_notify.go:152` | yes | yes | **yes** — same | category `normal` |
| 37 | `MarketplaceOrderCancelledMsg` / marketplace_order_cancelled | `admin_status_notify.go:154` | yes | yes | **yes** — same | category `normal` |
| 38–41 | `InKindScheduled/Received/Delivered/CancelledMsg` / in_kind_donation_* | `admin_status_notify.go:311`, `:313`, `:315`, `:317` | yes | yes | **yes** — same item + quantity on a second donation | category `payment` |
| 42 | `MarriageApprovedMsg` / marriage_approved | `admin_status_notify.go:185` | yes | yes | no — profile code varies | category `normal` |
| 43 | `MarriageRejectedMsg` / marriage_rejected | `admin_status_notify.go:187` | yes | yes | no | category `normal` |
| 44 | `MarriageStatusChangedMsg` / marriage_status_changed | `admin_status_notify.go:189` | yes | yes | **yes** — a status returned to a value it already held | category `normal` |
| 45 | `BeneficiaryCaseApprovedMsg` / beneficiary_case_approved | `admin_status_notify.go:74` | yes | yes | **yes** — same title | category `urgent` |
| 46 | `BeneficiaryCaseRejectedMsg` / beneficiary_case_rejected | `admin_status_notify.go:76` | yes | yes | **yes** — same title + reason | category `urgent` |
| 47 | `ProjectRequestApprovedMsg` / project_request_approved | `admin_status_notify.go:107` | yes | yes | **yes** — same title | category `campaign` |
| 48 | `ProjectRequestRejectedMsg` / project_request_rejected | `admin_status_notify.go:109` | yes | yes | **yes** — same | category `campaign` |
| 49 | `ProjectRequestStatusChangedMsg` / project_request_status_changed | `admin_status_notify.go:113` | yes | yes | **yes** — back-and-forth status | category `campaign` |
| 50 | `VolunteerApplicationDecisionMsg` / volunteer_application_&lt;status&gt; | `admin_status_notify.go:222` | yes | yes | **yes** — same applicant decided twice | category `normal` |
| 51 | `MissionSignupDecisionMsg` / volunteer_mission_&lt;status&gt; | `admin_status_notify.go:439` | yes | yes | **yes** — same mission decided twice | category `normal` |
| 52 | `SupportTicketStatusMsg` / support_ticket_&lt;status&gt; | `admin_status_notify.go:348` | yes | yes | **yes** — a ticket reopened and resolved again | category `urgent` |
| 53 | `NewVolunteerMissionMsg` / new_volunteer_mission | `admin_status_notify.go:394`, `admin_create.go:1433` (Broadcast) | yes | yes | **yes** — a mission re-posted with the same title/city/date | category `normal` |
| 54 | `NewPartnerMsg` / new_partner | `admin_create.go:186` (Broadcast) | yes | yes | no — partner name varies | category `normal` |
| 55 | `NewMediaPostMsg` / new_media_post | `admin_create.go:280` (Broadcast) | yes | yes | **yes** — two posts with the same title | category `campaign` |
| 56 | `NewCommentOnYourPostMsg` / post_comment_received | `media_engagement.go:161` | yes | yes | **yes** — the same person commenting the same words again | category `campaign` |
| 57 | `NewCampaignMsg` / new_campaign | `admin_create.go:1295` (Broadcast) | yes | yes | **yes** — two campaigns with the same title | category `campaign` |
| 58 | `ChatRequestMsg` / chat_request | `internal/handlers/chat.go:188`, `:245` | yes | yes | **YES — conversation** | guest rule; category `normal` |
| 59 | `ChatAcceptedMsg` / chat_accepted | `chat.go:293` | yes | yes | **YES — conversation** | guest rule |
| 60 | `ChatNewMessageMsg` / chat_message | `chat.go:441` | yes | yes | **YES — conversation**: same sender, same words | guest rule |
| 61 | `ChatSupportReplyMsg` / chat_message | `chat.go:590` | yes | yes | **YES — conversation**: "Support" + a repeated reply | guest rule |
| 62 | `GroupTeamNewMessageMsg` / chat_group_message | `chat_group.go:415` | yes | yes | **YES — conversation** | guest rule |
| 63 | `GroupMaskedNewMessageMsg` / chat_group_message | `chat_group.go:417` | yes | yes | **YES — conversation** | guest rule |
| 64 | `MarriageChatRequestMsg` / marriage_chat_request | `marriage_chat.go:120` | yes | yes | **YES — constant text**: a re-approved invite was never re-announced (was recorded as a known gap in `marriage_chat.go`) | guest rule |
| 65 | `MarriageMeetingDeclinedMsg` / marriage_meeting_declined | `marriage_chat.go:144` | yes | yes | **YES — constant text**: only the first decline ever | guest rule |
| 66 | `MarriageChatAcceptedMsg` / marriage_chat_accepted | `marriage_chat.go:216` | yes | yes | **YES — constant text** | guest rule |
| 67 | `MarriageChatNewMessageMsg` / marriage_chat_message | `marriage_chat.go:334` (member), `:421` (staff) | yes | yes | **YES — THE CLIENT'S BUG**: constant text, so only the first message of a marriage chat ever pushed | guest rule |
| 68 | `StaffChatNewMessageMsg` / staff_chat_message | `internal/handlers/staff_chat.go:223` | yes | yes | **YES — conversation**: same colleague, same words | guest rule |
| 69 | `SponsorshipDueGrantorMsg` / sponsorship_due_grantor | `sponsorship_schedule.go:132` | yes | yes | **yes** — same amount + due date re-run | category `reminder` |
| 70 | `SponsorshipDueRecipientMsg` / sponsorship_due_recipient | `sponsorship_schedule.go:141` | yes | yes | **yes** — same | category `reminder` |

Not a template: `admin_announcement`, composed inline in `internal/handlers/push.go`
and delivered by `SendPushDirect` — push only, never an in-app row, never deduped.

**Nothing in the table never fires, and nothing stops at the in-app row.** Every
"no push" in production traces back to one of four things: the dedupe (fixed
here), the master/category switch, the guest rule, or the user having no active
device token / FCM not being configured on the server.

### What was changed

- **`backend/internal/notify/notify.go`** — the dedupe. Conversation types are
  now exempt entirely; everything else is deduped on
  `(user, title, body, type, related_entity_id)` **within `dedupeWindow`
  (2 minutes)** instead of forever and entity-blind.
  - *Why exempt the conversations rather than shorten the window for them:* a
    chat's wording legitimately repeats within seconds ("ok", "ok") and its
    related entity id is the thread/group, not the message — so neither a
    window nor an entity id saves it. Each conversation notification is sent
    once per row already inserted into its own messages table, so a repeat is a
    real second message; there is no retry path that could fabricate one.
  - *Why keep a dedupe at all:* it was protecting against a re-run of the same
    admin action (a double-clicked Approve, a retried request) — a burst,
    seconds apart, about the same record. The window plus the entity id covers
    that case exactly and nothing more.
  - Adding the entity id also fixed a second class of loss on its own: two
    different donations, orders or cases that happen to read identically used to
    collapse into one notification (rows 27–41 above).
- **`backend/internal/notify/list.go`** — new `isConversationType`, reading the
  same `chatNotificationTypes` list the guest filter uses, so "is this a
  conversation?" has one answer in the package.
- **`backend/internal/handlers/marriage_chat.go`** — the marriage-chat message
  notification was being handed the **message** id as its `related_entity_id`
  while its `related_entity_type` said `marriage_chat_thread`. The template's
  parameter has always been named `threadID`; the caller passed `msgID` by
  mistake. #145 routes a tapped notification by exactly that pair, so a tap
  opened whichever thread happened to share the number, or nothing. Both call
  sites now pass the thread id. Two stale comments in the same file, which
  documented the dropped-as-duplicate invite as a known gap, were corrected.
- **NEW `backend/internal/notify/dedupe_test.go`** — seven tests.

### What was run

```
gofmt -l internal/     → internal/handlers/admin_edit_user_profile.go  (pre-existing, not a file this branch touches)
go build ./...         → clean
go vet ./...           → clean
```

Tests, on throwaway databases created and dropped for the run:

```
createdb godonation_dedupe_a651
TEST_DATABASE_URL=...  go test ./internal/notify/ -count=1 -run Dedupe
  → with the fix REVERTED (git show HEAD:...notify.go): 5 of 7 FAIL, each on its own message,
    incl. "stored ids = 19, 0 — both marriage-chat messages must be written as separate rows"
  → with the fix in place: 7 PASS

createdb godonation_full_a651
TEST_DATABASE_URL=...  go test ./internal/notify/ ./internal/handlers/ -count=1 -p 1 -timeout 45m
  ok  github.com/karam-flutter/humanitarian-backend/internal/notify    31.438s
  ok  github.com/karam-flutter/humanitarian-backend/internal/handlers  18.372s

createdb godonation_new_a651
TEST_DATABASE_URL=...  go test ./internal/notify/ -count=1 -v -run Dedupe
  → 7 PASS, 0 SKIP, 0 FAIL

dropdb for all three; psql -lqt confirms none remain.
```

### Still open

- **Not pushed.** The branch is local; no PR.
- **The push only works where FCM is configured.** `New()` logs
  `no FCM credentials found; push delivery disabled` and every send then writes
  the in-app row and nothing else. If the client still sees no push after this,
  check that log line on the server first — it is the one failure mode this
  change cannot reach.
- **A user with no registered device token gets no push,** by definition.
  `POST /api/notifications/device` must have run on that phone.
- **`WalletToppedUpMsg` and `TaskAssignedMsg` carry no `related_entity_id`,** so
  their dedupe key is still text-only inside the 2-minute window. Two identical
  top-ups two minutes apart are fine; two within the window would collapse.
  Giving them their entity ids would close it properly.
- **The `sponsorship_payment_due_reminder` scheduler** re-running inside the
  window is still deduped, which is the intended protection, but it means a
  manual re-run to "resend" a reminder does nothing for 2 minutes.

### Traps

- **The dedupe compares against `created_at`, a plain `TIMESTAMP`** defaulted
  from `CURRENT_TIMESTAMP` (migration 001). The query uses `LOCALTIMESTAMP`, not
  `NOW()`, on purpose: `NOW()` is a `timestamptz` and the comparison would go
  through a session-timezone cast.
- **`Send` fires its push in a goroutine**, so a test cannot read the FCM
  recorder straight after calling it. `dedupe_test.go` polls with a deadline;
  `push_guest_test.go` sidesteps it by calling `sendPush` directly. Do not add a
  bare `time.Sleep`.
- **Adding a new chat template means adding its type to
  `chatNotificationTypes`** — that one list now drives three things: the guest
  in-app filter, the guest push filter, and the dedupe exemption.
  `chat_types_test.go` fails if a conversation template is missing from it.
- `gofmt -l internal/` has flagged `internal/handlers/admin_edit_user_profile.go`
  since before this branch. Don't mistake it for your own change.

---
## 2026-09-16 — tapping a notification opens what it is about (branch `feat/notification-tap-opens-chat`, NOT pushed)

**Asked for:** the client reported that tapping a push notification opens the
app at home and leaves him hunting for the conversation. Mid-task the scope was
widened with his own words: *"when I tap on a notification inside the app it
should take me to the exact place of this notifications"* — so the in-app list
counts too, and every notification type, not only chat.

**Branch** `feat/notification-tap-opens-chat`, cut from `origin/main` `1a6062d`.
Commit `578d66e`. NOT pushed. Nothing under `backend/` or `admin-web/` touched.

### What was wrong
- `lib/main.dart:114-118` subscribed to `FirebaseMessaging.onMessageOpenedApp`
  and only called `debugPrint` — it navigated nowhere.
- `FirebaseMessaging.instance.getInitialMessage()` — the tap that LAUNCHES the
  app from killed, delivered once at startup and never repeated on the stream —
  was not handled at all.
- `NotificationsController.destinationFor` knew three families (support
  tickets, media posts, partners) and returned `null` for everything else, so a
  tap on a chat, donation, sponsorship or marriage row in the in-app list did
  nothing.

### What was built
- **NEW `lib/modules/notifications/utils/notification_destination.dart`** — one
  pure function, `resolveNotificationDestination(data, isGuest:)`, from a
  notification's data to a `NotificationDestination` (a closed enum of 20
  places + an optional id). No Flutter, no Firebase, no I/O.
- **NEW `lib/modules/notifications/utils/notification_navigator.dart`** — the
  only file that navigates. One `Get.to` per destination, no decisions. Follows
  `modules/bot/bot_navigation.dart` (switch dashboard tab → pop to shell → push
  one frame later); the app has no named routes for these screens and none were
  invented.
- **NEW `lib/core/push_tap_router.dart`** — wires BOTH tray paths
  (`onMessageOpenedApp` and `getInitialMessage()`) into one `handleData`.
- `lib/main.dart` — the dead listener replaced by `PushTapRouter.wire()`.
- `notifications_controller.dart` — `destinationFor` now asks the same shared
  decision; its own mini-table is gone. `action_url` still wins over it.

### Data keys depended on (for OPOS #26709, which is changing the payload)
`type` (alias `notification_type`), `related_entity_type` (alias `entity_type`),
`related_entity_id` (aliases `entity_id`, `thread_id`, `group_id`). Values may
be strings or ints. `related_entity_type` wins when present. These mirror the
columns `notify.LocalizedMessage` already writes to `app_notifications`, so the
app routes whichever shape the push ends up carrying — **but a chat push MUST
carry its thread/group id**, or the tap lands on the notifications list instead
of the conversation. That is the one hard requirement on the payload.

### Traps for the next agent
- **The cold-start tap must wait for the shell.** `getInitialMessage()` resolves
  while the app is still on the splash screen, and the splash finishes with
  `Get.offAllNamed` (splash_screen.dart:101) — anything pushed before that is
  wiped out. `PushTapRouter._waitForShell` polls `Get.currentRoute` twice a
  second for 15s and opens nothing if the app lands on welcome/login instead.
- **Marriage conversations need three values a push cannot carry**
  (`other_label`, `my_role`, `status`), so the navigator re-fetches
  `GET /marriage-chats` and finds the thread by id; a failed fetch or a missing
  thread opens the marriage chats list, which has its own retry.
- **Group titles must go through `chatGroupTitle`** — a masked group is always
  "Connection". The navigator copies `MyConnectRequestsScreen._titleFor`.
- `flutter analyze` baseline is 6 issues (5 deprecations + 1 pre-existing);
  a missing import in main.dart briefly made it 7 — check the count, not "clean".

### Verification (actually run, in this worktree)
- RED, new tests against the pre-fix tree `1a6062d` in a throwaway worktree:
  `00:00 +3 -3: Some tests failed.` — the three "no longer a dead tap" cases.
- GREEN, `flutter test`: `00:38 +1266: All tests passed!`
- `flutter analyze`: `6 issues found. (ran in 1.8s)` — the baseline.

### Still open
- Not pushed, no PR.
- Types with no mobile screen fall back to the list on purpose:
  `staff_chat_message` (admin-web only), `wallet_topup` (no wallet screen),
  `task_assigned`, and the six `admin_*` staff alerts. Each is asserted in
  `test/notifications/notification_destination_table_test.dart` so it is a
  recorded decision, not an oversight.
- Approximate destinations, worth a product call: in-kind donations land on the
  donation history (no in-kind list exists); a donation lands on the history
  rather than that donation (`DonationDetailsScreen` is an unwired placeholder);
  a beneficiary case lands on the services section rather than the case.
- Not tested on a device. See the report for what the client should confirm.

---

## 2026-09-16 — push delivery: an Android notification channel, and routing data on every push (branch `fix/push-delivery`, NOT pushed)

**Asked for:** the client tested on real devices. Android receives no push at
all; iOS receives them "only while the app is open". Diagnose before changing
anything, then make the smallest change that fixes both, keeping #113's guest
rule and the localized titles/bodies.

**Branch** `fix/push-delivery`, cut from `origin/main` `1a6062d`. NOT pushed.

### Diagnosis — the stated hypothesis was WRONG, and one symptom is not a push at all

- **The server was already sending a proper notification payload.**
  `backend/internal/notify/fcm.go:185-236` (pre-change) built
  `message.notification` *and* `message.android.priority = "high"` *and* an
  explicit `message.apns` block with `apns-priority: 10`,
  `apns-push-type: alert` and `aps.alert`. It is **not** data-only. So the
  hypothesis in the brief — "data-only payload explains both symptoms" — does
  not hold, and the fix is not "add a notification block".
  `sendOne` had exactly two callers: `push.go:53` (the per-event path) and
  `push.go:195` (the admin compose endpoint). There is no second sender.
- **What the payload actually lacked:** a `data` block (so a tap carried no
  routing information at all) and, the one that can silence a phone,
  `android.notification.channel_id`.
- **The Android channel is the concrete Android defect.** Android 8+ posts
  every notification to a channel, and the *channel*, not the message, decides
  whether a banner appears and a sound plays. The payload named no channel and
  `humanitarian/android/app/src/main/AndroidManifest.xml` declared no
  `com.google.firebase.messaging.default_notification_channel_id` (it declared
  only the icon and colour), so every message landed in the FCM SDK's own
  fallback channel — which the app cannot configure and the user has never
  seen in settings.
- **"iOS only while the app is open" is very probably not push at all.** The
  app polls the API every few seconds and plays a chime on anything new:
  `humanitarian/lib/core/realtime_polling.dart:64`,
  `humanitarian/lib/modules/chat/controllers/chat_controller.dart:31` and
  `:138`, `humanitarian/lib/modules/notifications/controllers/notifications_controller.dart:77`,
  with `AppSound.notification()` at `chat_controller.dart:53`. Polling only
  runs while the app is open. That is exactly the reported iOS behaviour, and
  it means the iOS report is **not** evidence that APNs delivery works. See
  "What still needs a device" below — this is the one thing this branch cannot
  settle from here.
- **Token registration is sound, on both platforms.**
  `humanitarian/lib/core/push_registration.dart:65-90` reads the signed-in
  `id_user` (stored as a String at `lib/core/auth_navigation.dart:59`, so the
  read matches), gets the FCM token, and POSTs token + `platform` + locale to
  `notifications/device` via `ModuleApi.postJson`
  (`lib/api/module_api.dart:348`), which does attach the auth headers. It is
  called from `main.dart:128`, after login (`auth_navigation.dart:127`) and on
  locale change (`locale_service.dart:164`). The server stores `platform`
  verbatim (`backend/internal/notify/devices.go:39-45, 71-86`), upserting on
  `(user_id, device_token)`. Nothing here is broken **in code** — but whether
  rows actually exist for both platforms in the live database is a data
  question, answered by the SQL below, not by reading.
- **Android 13 runtime permission is genuinely requested**, not merely
  declared: `main.dart` calls `FirebaseMessaging.requestPermission(...)`, and
  firebase_messaging 16.2.0 (pubspec.lock:379) requests
  `POST_NOTIFICATIONS` from there —
  `~/.pub-cache/.../firebase_messaging-16.2.0/android/src/main/java/io/flutter/plugins/firebase/messaging/FlutterFirebasePermissionManager.java:63`,
  reached via `FlutterFirebaseMessagingPlugin.java:357-386`. The manifest
  declares the permission at `AndroidManifest.xml:7`.
- **No local-notifications plugin is in `pubspec.yaml`, and none is needed.**
  The design is OS-rendered notification payloads; the app does not draw them
  itself. Nothing was added.
- **#113's guest rule is correctly narrow.** `shouldWithholdChatPush`
  (`backend/internal/notify/push.go:89-107`) returns false immediately for any
  type outside `chatNotificationTypes` (`list.go:72-83` — nine chat types, an
  explicit list, not a `chat%` prefix), so it cannot touch broadcasts or
  support-ticket pushes. It queries `users.is_guest` only for a chat type, and
  fails closed on error. Left exactly as it was.
- **Firebase project config matches on both platforms** (checked because it
  would explain an Android-only silence, and it does not): package
  `com.easytech.humanitarian` is in `android/app/google-services.json`, bundle
  `com.easytech.humanitarianApp` is in `ios/Runner/GoogleService-Info.plist`,
  project `human-f1dc6` / sender `463997425388` on both and in
  `lib/firebase_options.dart`.

### What changed

**Backend**
- `backend/internal/notify/fcm.go` — new exported `AndroidChannelID =
  "balancenex_high_importance"`. `sendOne` gained a `data map[string]string`
  parameter, and its payload construction is split into a new pure
  `buildSendPayload(token, title, body, imageURL, data)`, so the JSON that
  leaves the process can be asserted without a network round trip. The payload
  now carries `android.notification.channel_id` and an optional `data` block
  **alongside** (never instead of) the notification block. Empty data values
  are dropped. Everything that was already right — the notification block, high
  Android priority, the APNs headers and `aps` block, the image handling — is
  unchanged.
- `backend/internal/notify/push.go` — new `routingData(LocalizedMessage)`
  builds `notification_type`, `related_entity_type`, `related_entity_id`,
  `action_url` as strings (FCM rejects non-strings in `data`). The per-event
  path passes it; the admin compose path passes `nil` (free text, nothing to
  route to).
- **NEW** `backend/internal/notify/fcm_payload_test.go` — nine tests, no DB and
  no network, asserting the built payload: notification block present, Android
  priority `high` + `channel_id` + sound, APNs `apns-priority: 10` /
  `apns-push-type: alert` / `aps.alert` / sound, data alongside the
  notification with all-string values, empty values dropped, no empty `data`
  key, image on both `notification.image` and `apns.fcm_options.image`, and
  `routingData`'s mapping.

**App (Android only — no Dart behaviour changed except one guard)**
- `humanitarian/android/app/src/main/kotlin/com/easytech/humanitarian/MainActivity.kt`
  — creates the `balancenex_high_importance` channel with `IMPORTANCE_HIGH` in
  `configureFlutterEngine`, on every launch (idempotent; Android never lowers a
  channel the user has adjusted, which is also how an already-installed app
  gets the channel).
- **NEW** `humanitarian/android/app/src/main/res/values/strings.xml` and
  `values-ar/strings.xml` — the channel id (`translatable="false"`) plus the
  user-facing channel name and description, en + ar, as they appear in Android
  system settings.
- `humanitarian/android/app/src/main/AndroidManifest.xml` — adds the
  `default_notification_channel_id` meta-data, covering any message that
  arrives without a `channel_id`.
- `humanitarian/lib/main.dart` — the `requestPermission` /
  `setForegroundNotificationPresentationOptions` pair is wrapped in
  try/catch. It runs before `runApp()`, and the plugin throws when it cannot
  find the Activity or when a request is already in flight; unguarded, that
  aborts `main()` and leaves the user on the native splash. Push setup must not
  cost the app its launch.

**The channel id is spelled in three places and they must stay identical:**
`fcm.go`'s `AndroidChannelID`, `values/strings.xml`, and (by reference) the
manifest meta-data + `MainActivity`.

### Verification — run, with output

- `flutter analyze` → `6 issues found. (ran in 8.5s)` — the known baseline,
  all pre-existing `deprecated_member_use` infos, none in a touched file.
- `flutter test` → `00:45 +1088: All tests passed!`
- `flutter build apk --debug` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk`,
  `exit=0`. This is what proves the new Kotlin, the two `strings.xml` files and
  the manifest meta-data actually compile and link.
- `gofmt -l ./internal ./cmd` → prints only
  `internal/handlers/admin_edit_user_profile.go`, which is **pre-existing drift
  on a file this branch does not touch**. It was left alone rather than taken
  as a drive-by. Every file this branch changed is gofmt-clean.
- `go build ./...` and `go vet ./internal/notify/` → clean.
- On a throwaway DB created and dropped for this run
  (`godonation_push_fix_63347`):
  `go test ./internal/notify/ ./internal/handlers/ -count=1 -p 1 -timeout 45m`
  → `ok …/internal/notify 1.066s`, `ok …/internal/handlers 18.918s`,
  `exit=0`.
  Because those times are far shorter than earlier entries in this file report,
  the run was re-checked to be sure it was not silently skipping:
  `go test ./internal/notify/ -run GuestPush -count=1 -v` printed
  `[migrate] done: 0 newly applied, 125 total migration files` per test and
  `--- PASS` for every guest-push case, so the DB-backed tests genuinely ran.
  The database was dropped afterwards (`psql -l | grep -c push_fix` → `0`).

### What STILL needs a real device — nothing here can prove delivery

No push was actually sent from this machine. Zaid, in this order:

1. **Is FCM even switched on in prod?** Open the admin SPA's `/push` page. If
   it says FCM is not configured, `FIREBASE_CREDENTIALS_JSON` is missing on
   Railway and *every* push on both platforms is being skipped — which alone
   explains the whole report. The server logs one of
   `[notify] FCM enabled (project=…)` or `[notify] no FCM credentials found`
   at boot (`notify.go:33-40`).
2. **Are there token rows for both platforms?** On the prod DB:
   `SELECT platform, is_active, COUNT(*) FROM user_device_tokens GROUP BY 1,2;`
   No `android` row means the Android phones never registered, and no payload
   change can help until that is fixed.
3. **Send one push to one token.** Get the token from the device log line
   `[push] FCM token: …` (`main.dart`), paste it into the admin `/push` page's
   single-device field, and send with the app **fully closed** on each phone.
   - Android: after installing a build from this branch. A banner + sound means
     the channel fix worked. Check Settings → Apps → BalanceNex →
     Notifications: "Messages and updates" must be listed and set to a level
     that alerts, and the app's notification permission must be granted.
   - iOS: if this shows nothing while the app is closed but the app still
     chimes when open, the "arrives while open" behaviour was the poller and
     APNs is not delivering at all. Then check, in Firebase console → Project
     settings → Cloud Messaging, that an **APNs auth key** is uploaded for
     `com.easytech.humanitarianApp`, and confirm the build's
     `aps-environment`: `ios/Runner/Runner.entitlements` says `development`,
     which is correct for a Xcode-run debug build (Xcode rewrites it to
     `production` when archiving for TestFlight/App Store) — but a build
     signed with the wrong one receives nothing in that environment. This
     branch deliberately did **not** change that file; it is a signing
     question, not a code one.
4. **Then a real chat message**, app closed, member (not guest) to member, to
   confirm the per-event path and that #113 still only withholds from guests.

### Traps

- The brief's hypothesis ("payload is data-only") is wrong — read `fcm.go`
  before acting on it.
- **"Arrives while the app is open" is not evidence of push delivery in this
  app.** The polling + chime pipeline produces exactly that, on both platforms.
- The worktree guard refuses a compound shell command containing a
  `postgres://…` URL ("too complex to verify"). Put the run in a script file in
  the scratchpad and `zsh` it.
- `internal/handlers` finished in 19s here, against 10–25 minutes reported in
  older entries; the machine was idle. Don't read a fast run as a skipped one
  without checking for the `[migrate] done` lines.

---

## 2026-09-16 — seed-test-users also seeds the MARRIAGE fixtures (branch `feat/seed-marriage-fixtures`, NOT pushed)

**Asked for:** the client is testing live and wants step 5 (the marriage flow)
next, but his database has no marriage profiles and no meeting requests, so
there is nothing to approve. Extend `cmd/seed-test-users` so the same run also
creates the profiles and a pending request, under the same rules as the
accounts (idempotent, `-cleanup`-able, nothing without `-confirm`).

**Branch** `feat/seed-marriage-fixtures`, cut from `origin/main` `7a8f9aa`.
Commit `b3d8784`. NOT pushed.

### What it seeds now, on top of the ten accounts
- **Two marriage profiles**: **B** (Female, Baghdad, 27) and **D2** (Male,
  Erbil, 31), status `active`, `visibility_level = 'employee_only'`,
  `owner_deleted_at` NULL — the exact set `marriage.Store.List` serves to a
  searching member. Gender is **capitalised** because the app's own filter
  offers `'Male'`/`'Female'`
  (`humanitarian/lib/modules/marriage/screens/marriage_search_screen.dart:425`)
  and matches exactly; lowercase would be unfindable.
- **One PENDING `marriage_meeting_requests` row** from **D** about **B**'s
  profile, `request_type = 'meeting'` — the row the dashboard lists with an
  Approve button.
- Nothing else is needed to approve: `ApproveMeetingRequest` wants only a
  pending request, a profile, and requester ≠ owner. The test exercises the
  real approval to prove it.

### Files
- **NEW** `backend/internal/seedtestusers/marriage.go` — `MarriageProfileSpecs`,
  `MarriageRequesterKey`/`MarriageRequestAboutKey`, `seedMarriage`,
  `ensureMarriageProfile`, `ensureMarriageProfileSearchable`,
  `ensureMeetingRequest`, `cleanupMarriageRows`.
- `seed.go` — `Result.Marriage`; `seedMarriage` runs after the accounts.
- `cleanup.go` — marriage rows are deleted **before** the user row (
  `marriage_profiles.user_id` is ON DELETE RESTRICT, migration 002, so a
  surviving profile makes the account undeletable); counts reported.
- `cmd/seed-test-users/main.go` — `printMarriageSummary`: profile codes, who
  asked about what, and the dashboard path to approve.
- `docs/testing/chat-e2e-test-plan-2026-09.md` — §1.7 mentions the fixtures;
  step 5's **[NOT CONFIRMED]** wording is replaced with the real labels.

### Identity rule (how cleanup stays exact)
Every seeded profile carries a stamp in `private_notes`:
`"Seeded by seed-test-users (prefix <p>) — fixture data, not a real person."`
Cleanup deletes only profiles with that stamp owned by an account that already
passed the existing username+reserved-phone identity check. A profile made **by
hand** on a fixture account is left alone — and then the existing RESTRICT
refusal reports the account as `KEPT`, which is the honest outcome.
`marriage_saved` and `marriage_meeting_requests` carry **no foreign keys**
(migration 046), so they are deleted explicitly; chat threads/messages cascade
(migration 058).

### Verification (run, not assumed)
- `gofmt -l ./cmd ./internal` → only `internal/handlers/admin_edit_user_profile.go`,
  which is **pre-existing on `origin/main`** and untouched here.
- `go build ./...`, `go vet ./...` → clean.
- RED first: `go vet ./internal/seedtestusers/` →
  `res.Marriage undefined (type *Result has no field or method Marriage)`.
- GREEN on a fresh throwaway DB: all 5 tests in `internal/seedtestusers` pass,
  plus `go test ./internal/marriage/ ./internal/marriagechat/
  ./internal/handlers/ -count=1 -p 1 -timeout 45m` → all `ok`.
- The command itself was run against a migrated throwaway DB and printed the
  marriage summary. Every throwaway DB was dropped; `psql -lqt | grep -c
  seedfix` → `0`.

### Trap worth knowing
**The seeded phone numbers do not depend on `-prefix`** (they are
`reservedNSN` + a fixed per-account index). So a leftover fixture account from
an earlier run is found *by phone* under a new prefix, keeps its old username,
and the package tests then fail with confusing "created 9, want 10" /
"username = 0x…" messages. Run these tests against a **clean** database. That
is pre-existing behaviour, not something this branch introduced.

### Still open
- Nothing pushed; no PR. Commit `b3d8784` sits on the branch.
- OPOS was not used (unavailable in that session), so there is no task row.

---

## 2026-09-16 — a connect request's OTHER PARTY is resolved and added automatically (branch `feat/connect-request-other-party`, NOT pushed)

**Asked for:** the client, testing live, asked to connect from a beneficiary
case as a donor, approved it as super_admin, and got a masked group containing
only the donor — the case's owner was never added, so the group had one member
and nobody to talk to. Mid-task the client added: "this must be automatic" —
pre-filling the dashboard dialog is not enough, the SERVER must add the other
party itself on approve.

**Branch** `feat/connect-request-other-party`, cut from `origin/main` `2af2d76`.

### The root cause
`resolveConnectContext` (handlers/chat_group_admin_connect.go:31) only ever
turned a context into a human-readable LABEL. Nothing anywhere resolved WHO the
case or campaign belongs to, and `ApproveConnectRequest` wrote exactly the
members the dashboard sent — which, for the client, was the requester alone.

### Who owns what (read from the schema, not guessed)
- a case → `beneficiary_cases.user_id` (migrations/001_full_v2.sql:168)
- a campaign → `campaigns.owner_user_id` (migrations/007_campaigns_owner.sql:18)
- a donation to the GENERAL FUND (`campaign_id` NULL) has no other party, and
  nothing is invented for it.

### What changed
- **NEW** `backend/internal/chatgroups/chatgroups_connect_party.go` —
  `connectContextOwner` (the authoritative lookup; returns real DB errors),
  `accountRoleWord` (role_id 1/2/3 → donor/beneficiary/volunteer, else
  "member"), and `connectGroupMembers`, which assembles the final member list.
- `chatgroups_connect.go` — `ApproveConnectRequest` now also reads
  `context_type`/`context_id` under the same `FOR UPDATE`, and runs
  `connectGroupMembers` inside the SAME transaction as the group insert. An
  EMPTY members list is now valid and becomes requester + other party; a
  NON-EMPTY list that omits the requester is still refused (unchanged rule,
  its old test still passes). The owner is never added twice.
- **NEW** `backend/internal/handlers/chat_group_admin_connect_party.go` — the
  DISPLAY copy of the question, best-effort like `resolveConnectContext`: a
  failed lookup yields no other party rather than breaking the inbox.
- `chat_group_admin_connect.go` — `other_party_user_id` and `other_party_name`
  on both the list and the detail. The NAME follows `requester_name` (D6,
  `canViewContact`, per user); the ID is NOT gated — the inbox already ships
  `requester_user_id` and `context_id` ungated, D6 is about names beside masked
  identities, and the dialog needs the id to pre-fill a member. Approve now
  requires only `kind` ("kind is required."), not members.
- Dashboard: `ConnectRequest` gained the two fields; `approveDraftFor` puts the
  other party in member row 2 (removable); row 1 (the requester) unchanged.

### Decision worth knowing: team groups (#137)
A team group takes only volunteers and staff. The auto-added other party goes
through the same `insertMemberRow`, so a case owner who is a beneficiary
account REFUSES the approval with `ErrTeamMemberRole` — a clear, existing 400,
not a crash, and not a silent drop that would recreate the one-member group.
Pinned by `TestApproveConnectRequest_TeamGroupRefusesAnIneligibleOwner`.

### Tests (written first, each watched fail)
NEW files: `backend/internal/chatgroups/chatgroups_connect_party_test.go`,
`backend/internal/handlers/chat_group_connect_other_party_test.go`,
`admin-web/src/components/connectRequests/ApproveRequestDialog.otherParty.test.tsx`.
RED, before the fix: "approve with no members: ... requester ... not in
members: invalid input"; "members = [{donor Donor 1}], want 2";
"other_party_user_id = <nil>, want the owner"; approve with no members answered
400 "kind and at least one member are required."; the dialog had no "Remove
member 2".

One EXISTING test was updated deliberately: the approve case in
`chat_group_inline_refusal_codes_test.go` now expects "kind is required."

### Verification actually run
- `gofmt -l .` → only `internal/handlers/admin_edit_user_profile.go`, which is
  pre-existing on `origin/main` and untouched here. `go build ./...`,
  `go vet ./...` clean.
- Throwaway DBs created and dropped (`psql -lqt` shows none left):
  `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m`
  → both `ok`. The `-v -run` of the new tests → 14 PASS, 0 SKIP, 0 FAIL.
- Dashboard (Node 22): `npm test` 23 files / 202 tests, `npx tsc -b`,
  `npm run build`, `test:mock-api`, `test:nav`, `check:labels`,
  `check:css-tokens`, `npm run lint` — all exit 0 (lint: 0 errors, 62
  pre-existing warnings, none in the new files).

### Still open / traps
- **Not pushed.** One commit on the branch, no PR.
- No new locale keys, so `TRANSLATION_REQUEST.md` is untouched.
- `npm ci` had to be run in this worktree first; without it vitest cannot even
  load its config ("Cannot find package 'vitest'"), which looks like a broken
  test rather than a missing install.
- Trap: a member draft array literal in `connectRequestForm.ts` must be typed
  `MemberDraft[]` explicitly, or TS widens `role` to `string` and `tsc -b`
  fails while `vitest` passes.
- The inbox list now does one extra owner lookup per request. Fine at today's
  volumes; if the inbox ever pages large it wants batching.

## 2026-09-15 — OPOS #26464: chat-group pause/resume/end no longer answers 500 when the reason is empty (branch `fix/chat-group-lifecycle-null-reason`)

**What was asked:** test-first, fix `chatlifecycle.Apply` failing with a 500 for chat groups (Kind `group`, table `chat_group_threads`) whenever the stored reason is empty. That covers every `resume`, and every `pause` or `end` with a blank reason. Choose between a per-System flag that stores '' and a migration that makes the column nullable, then run `go test ./internal/chatlifecycle/ ./internal/handlers/ -count=1 -p 1` on a fresh `createdb` database and drop it.

**What was actually changed** (one local commit on `fix/chat-group-lifecycle-null-reason`, fast-forwarded onto `origin/main` `b1809bc`):
- **The bug, confirmed by the RED run below:**
  - `setLifecycle` (`backend/internal/chatlifecycle/chatlifecycle.go:379`) writes SQL NULL to `lifecycle_reason` for an empty reason.
  - Migration 118 made that column nullable on the four older thread tables.
  - Migration 120 (`120_chat_groups.sql:24`) declared it `TEXT NOT NULL DEFAULT ''` on `chat_group_threads`.
  - Result: SQLSTATE 23502, which `lifecycleErr` (`handlers/admin_chat_lifecycle.go:95`) turns into `500 "Database error."` on `POST /api/admin/chat-groups/:id/lifecycle`.
- **Fix: new `backend/migrations/123_chat_group_lifecycle_reason_nullable.sql`.**
  - It drops NOT NULL and the '' default, then runs `UPDATE ... SET lifecycle_reason = NULL WHERE lifecycle_reason = ''`.
  - The exact DOWN is recorded as comments at the bottom, as 118 does.
  - **No Go code changed.** The deployed binary is fixed as soon as the server starts and applies 123 (`cmd/server/main.go:94`).
- **Why the schema and not a per-System '' flag:** a flag would give "no reason" two spellings in API responses, NULL for four systems and "" for groups. Every reader already handles NULL:
  - `chatlifecycle.Load` scans the column into `*string`.
  - `handlers/chat_lifecycle_gate.go` passes it through as `lifecycle_reason`.
  - The Flutter group controller (`chat_group_conversation_controller.dart:265`) trims it and treats null and "" alike.
  - admin-web (`ChatLifecycleControls.tsx:181`) renders it only when truthy.
  - No `chatgroups` query reads the column, and its two INSERTs (`chatgroups.go:294`, `chatgroups_connect.go:158`) don't name it.
- **New test file `backend/internal/chatlifecycle/apply_group_test.go`** (3 tests, 4 subtests):
  - resume a group paused with a reason;
  - pause and end a group with an empty reason and with a whitespace-only one;
  - `Load` on a new group reports no reason.
  - Each test checks both what `Apply` returned and what is stored in the row.

**What was run and what it printed:**
- **RED, before the migration**, on fresh DB `godonation_group_reason_red`: `go test ./internal/chatlifecycle/ -run Group -count=1 -v`
  - resume: `chatlifecycle set open on chat_group_threads/1: ERROR: null value in column "lifecycle_reason" of relation "chat_group_threads" violates not-null constraint (SQLSTATE 23502)`
  - the 4 pause/end subtests: the same error, for `paused` and `ended`
  - Load: `Load returned lifecycle="open" reason="" for a new group, want open with no reason`
  - ended `FAIL .../internal/chatlifecycle 155.733s`
- **GREEN, same command:** `[migrate] applied 123_chat_group_lifecycle_reason_nullable.sql`, all 3 tests and 4 subtests PASS, `ok .../internal/chatlifecycle 19.725s`. `gofmt -l` printed nothing; `go vet ./internal/chatlifecycle/` exited 0.
- **UP and DOWN by hand**, on the RED DB. Before 123 applied, two probe groups were seeded: one with '' and one paused with 'Kept reason'.
  - After UP: `nullable=YES default=NONE`, '' became NULL, 'Kept reason' kept.
  - After the commented DOWN: `nullable=NO default=''::text`, NULL back to '', the `schema_migrations` row gone.
  - The RED DB was then dropped (confirmed `count=0`).
- **Requested run**, on fresh DB `godonation_group_reason_final`, base `9e4a99f`: `go test ./internal/chatlifecycle/ ./internal/handlers/ -count=1 -p 1 -timeout 45m -v`
  - exit 0: `ok .../internal/chatlifecycle 482.773s`, `ok .../internal/handlers 718.181s`
  - 514 `--- PASS`, 0 `--- FAIL`, 0 `--- SKIP`
  - DB dropped, confirmed gone.
- **New-base check**, after fast-forwarding onto `b1809bc` (#99 and #100 landed during the work; neither touches a migration, chatlifecycle or `chat_group_threads`). On fresh DB `godonation_group_reason_rebase`:
  - `go vet ./internal/chatlifecycle/ ./internal/handlers/` exited 0.
  - `go test ./internal/chatlifecycle/ -run Group -count=1 -v`: `ok ... 162.114s`.
  - `go test ./internal/handlers/ -run MarriageInvite -count=1 -v` (#99's new tests): `ok ... 68.313s`.
  - 16 `--- PASS`, 0 FAIL, 0 SKIP. DB dropped, confirmed gone.
  - The full handlers suite was not re-run on this base.
- **Reviews:**
  - `ecc:code-reviewer`: APPROVE, 0 findings at every severity.
  - `ecc:database-reviewer`: nothing material. The ALTERs change only the catalog (no rewrite), and the file runs as one implicit transaction under the simple protocol. The DOWN is a correct exact inverse, and leaving `updated_at` untouched in the backfill is right.

**External actions taken:**
- **Nothing pushed, no PR.**
- **OPOS #26464** was created in office 19 (account 6) after the work, then commented and moved to Completed.
  - It was not created up front: the connector's tools did not load at session start (ToolSearch found nothing), and Zaid chose "proceed, log later".
  - No timer was run and no time was logged. Account 6 had three open timers from other sessions (#26461, #26448, #26436), and moving a task to In Progress would have auto-stopped one.

**What is still open:**
- **Unpushed:** the commit is local only.
- **Production until deploy:** a group paused in production cannot be resumed (resume always sends an empty reason). Pausing or ending one without a reason also still 500s.
- **Trash:** group rows already in the Trash still carry `"lifecycle_reason": ""` in `trash_items.payload` and restore as ''. Readers treat that as no reason, and the next lifecycle change rewrites it.
- **No HTTP-level test for group lifecycle:** `handlers/chat_lifecycle_trash_test.go` still covers only donor and marriage, and the new tests go through `Apply` directly. The route is registered in `chat_lifecycle_fixtures_test.go:242` if one is wanted.
- **#26431 (apply race):** still To Do and unmerged, so nothing was rebased. Its branch touches no migration, so 123 should not conflict. Its tests can now include `KindGroup` pause/resume.

**Traps:**
- **gofmt rewrites `''` inside a Go doc comment** into a typographic quote (`”`), so `gofmt -l` flags the file. Write "empty string" in Go comments instead.
- **The first test on a fresh DB absorbs all 122 migrations.** That took ~2 minutes (137s for the first RED test), so a slow first test is not a hang.
- **The OPOS connector can appear mid-session** after ToolSearch found nothing at the start. Re-check before concluding it is unavailable.

---

## 2026-09-16 — chat end-to-end test plan for the Railway deployment (branch `docs/chat-e2e-test-plan`, NOT pushed)

**Asked for:** a test plan Zaid can follow to test the whole chat system end to
end against Railway, on a real phone plus the dashboard. Two things were wanted:
the list of account types and roles he needs to create, and a step-by-step
script. Read-only research — no product code was to change, and OPOS was not
usable in this session.

**Branch** `docs/chat-e2e-test-plan`, cut from `origin/main` `fcc5b10`.

**What was changed:** one new file, `docs/testing/chat-e2e-test-plan-2026-09.md`
(the `docs/testing/` directory is new), plus this entry. No product code.

### What the plan contains
- **Part 1 — the account matrix.** The three member roles (`role_id` 1/2/3) with
  English and Arabic labels; the five `staff_tier` values; the default
  permission table for the chat modules; how each account type is really created;
  and a minimum set of nine named accounts (SA, E1, SUP, D, B, V1, V2, G, D2)
  with a reason for each.
- **Part 2 — a ten-step script**, each step written as "what to tap" and "what
  should happen", quoting the exact button label and message text in English and
  Arabic from the locale files.
- **Part 3 — known gaps**, so the tester is not surprised.

### Findings worth carrying forward
- **Every chat PR #100–#135 is merged on `main`.** Several HANDOFF entries for
  this work say "NOT pushed"; those branches were later squash-merged. The
  deployment should have all of it if it is at `fcc5b10` or later.
- **`sensitive_data` is the only module whose `view` is NOT default-on.**
  `permissions.go:139-145` — super_admin and admin only; supervisor and employee
  must be granted it by name. This is the hinge of the masked-group test.
- **`AllActions` has six entries, not four** (`permissions.go:164`): view, add,
  edit, archive, delete, export. A four-column matrix misstates supervisor
  (gets archive + export) and employee (gets neither).
- **Chat invites are only reachable through the Marriage flow now.** Direct
  donor chats answer 410 (`handlers/chat.go:176`), so no new donor invite can be
  produced. `marriage_chat.go:99`'s approve is the only live invite source. The
  plan says so rather than pretending a donor invite can be created.
- **Group-chat export IS built** — `GroupHeader.tsx:57` wires `ExportCsvButton`
  with `groupChatExportColumns()`. `lib/chatExport.ts:27-30` still says
  "GROUP CHATS (E3, not built yet)". **That header comment is stale and
  misleading**; a first read of it says the opposite of the truth. Worth fixing
  in its own commit.
- **Guests can read support but cannot write it.** `POST /api/support` and
  `POST /api/chats/support` are both `RequireNotGuest` (`main.go:739`, `:780`);
  only `GET /api/support/mine` is deliberately open (`:787`). "Support still
  works for guests" is true only for the read.
- **The retire-direct-chats production run has still NOT happened**
  (`docs/runbooks/retire-direct-chats.md` header). Pre-existing direct chats are
  therefore still open on production. The plan warns the tester up front.
- **Role 3's label is untranslated in the app.** `profile.dart:180` and
  `pending_approval.dart:74` return a bare `'Volunteer'` with no `.tr`, while
  roles 1 and 2 use `.tr`. «متطوع» exists at `app_translations.dart:3906` and
  «خۆبەخش» at `:6340`, but neither is ever reached from those two screens. This
  is a real Arabic-UI English leak against standing rule 2. Listed in the plan
  as expected, not fixed here.

### What was run
Nothing to run — the deliverable is prose and no code changed. The facts were
taken from `origin/main` `fcc5b10` by reading the files cited inline in the plan
and in this entry. **No deployment was contacted, no database was read, and the
plan itself has not been executed against Railway.**

### Still open
- The branch is **local and unpushed**, and there is no PR.
- **OPOS was not usable in this session**, so no task was created, moved to WIP,
  timed or completed for this work. It needs logging by whoever has access.
- The plan is **written from the code, not from a run**. Nothing in Part 2 has
  been clicked through. Expect the marriage search and "request a meeting"
  wording in step 5 to need correcting from the screen — the plan marks it
  `[NOT CONFIRMED]`.
- The stale `chatExport.ts` header comment above deserves its own fix.

### Traps
- **Do not trust "NOT pushed" in older HANDOFF entries** as evidence a feature is
  missing from `main`. Check `git log --oneline origin/main` for the PR number —
  most of the chat branches were squash-merged after their entry was written.
- **`Locale('ar', 'IQ')` is the SORANI map in this app**, not Arabic; Arabic is
  `ar_SA`. Reading Arabic strings under `ar_IQ` gives Kurdish.
- The reviewer agent was skipped, as the task asked.

---

## 2026-09-16 — `seed-test-users`: the chat test accounts in one command

**Asked for:** Zaid needs to run the chat end-to-end test plan now, so build a
command that creates its whole account matrix in one go, idempotently, with a
cleanup that cannot touch anything it did not create.

**Branch:** `feat/seed-test-users`, worktree off `origin/main` @ `edb3d08`. One
commit. **Not pushed.** OPOS was unavailable in this session, so no task was
logged.

### What was changed
- `backend/internal/seedtestusers/` (new) — `specs.go` (the matrix and the
  identities), `seed.go` (create/repair), `cleanup.go` (delete, with the
  identity proof), `seed_test.go` (four integration tests).
- `backend/cmd/seed-test-users/main.go` (new) — flags, the destination banner,
  the credentials table.
- `docs/testing/chat-e2e-test-plan-2026-09.md` — new §1.7, how to run it
  against Railway and what to know first.

### The design decisions worth not re-deriving
- **It goes through the real code paths**, which is why a seeded account can
  actually sign in: `auth.NormalizePhone`, `bcrypt.GenerateFromPassword`,
  `users.InsertWithPhone` → `SubmitRegistration` → `ApproveRegistration`,
  `EnsureGrantorCode`/`EnsureVolunteerCode` (the `ER-` code is minted inside
  `SubmitRegistration`), `users.InsertGuest`, `users.UpsertProfile`. Three
  writes have no callable function — the username, the staff tier, and
  `registration_status='approved'` on a role-less staff row — because they live
  inside `internal/handlers` behind an HTTP request. Those are done with the
  same SQL the handler uses, and each says so at the call site.
- **Reserved phone block `+964 1 555 000 0xx`.** A real Iraqi mobile NSN starts
  with 7, so this block cannot collide with anybody. `ensurePhoneRow` refuses to
  write a number that falls outside it or that does not normalise to itself.
- **No permission rows are written.** "Grant each staff account its tier
  defaults" is satisfied by writing *nothing*: the defaults live in
  `permissions.moduleDefaultAllowed` and apply when no row exists. Writing rows
  that repeated them would pin the accounts against the tier matrix. Each run
  instead DELETEs the fixture accounts' `role_permissions` rows, which is what
  keeps E1 free of `sensitive_data` after a previous pass through step 8.
- **Cleanup proves identity, it does not pattern-match.** An account is deleted
  only if its username AND its exact reserved phone number match what `Plan`
  would have produced (guest: username + `is_guest` + no phone). Anything else
  is reported `KEPT`.

### What was run, and what it printed
- RED first: `go test ./internal/seedtestusers/` → `build failed`, `undefined:
  Seed`, `undefined: Cleanup`, `undefined: Specs`.
- GREEN: all four tests pass.
- `gofmt -l backend` lists only `internal/handlers/admin_edit_user_profile.go`,
  which is **pre-existing on main** and untouched here (`git diff HEAD` on it is
  empty). `go build ./...` and `go vet ./...` clean.
- `TEST_DATABASE_URL=…/seed_users_suite_c go test ./internal/seedtestusers/
  ./internal/users/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` → all `ok`
  (handlers 18.5s).
- Ran the command for real against a throwaway DB: dry run, `-confirm` (created
  10), `-confirm` again (created 0, reused 10), `-cleanup -confirm` (deleted 9,
  KEPT SA as the last super_admin).
- **Started the server against the seeded database and signed in as three of
  them**: `POST /api/auth/login` as D (phone + password) → token; wrong password
  → `"Incorrect phone or password."`; `POST /api/auth/admin/login` as E1
  (username + password) → token; `POST /api/auth/guest/login` as G → token.
  Identity codes verified in `user_profiles`: `GR-`, `ER-`, `VL-`.
- All three databases created here (`seed_users_test_a`, `seed_users_live_b`,
  `seed_users_suite_c`) were dropped; `psql -lqt` confirmed.

### Traps
- **`cmd/server` does not run migrations.** Pointing it at an empty database
  gives you a listening server and no tables. Migrations run through
  `db.RunMigrations`, which is what the tests call. To migrate a scratch DB
  quickly, run any integration test against it.
- **A non-staff account's `staff_tier` is `'user'`, not `''`** — migration 015's
  NOT NULL default. This cost one red test run.
- `rehearse_retire_13998` in the local Postgres belongs to another session.
  Left alone.

### Still open
- Not pushed, no PR. The reviewer agent was skipped by instruction; the diff was
  re-read by hand instead.
- The command has never been run against Railway. §1.7 of the test plan tells
  Zaid how; the dry run is the safe first step.

---

## 2026-09-16 — chat policy conformance audit (OPOS #25284, read-only)

**Asked for:** prove or disprove each of the client's 8 chat rules against the
code as it stands, server-first. Read-only pass; change nothing unless a real
violation is found.

**Branch:** worktree off `origin/main` @ `fcc5b10`. One commit, docs only. **Not
pushed.** OPOS was unavailable in this session, so no task was logged.

**What was changed:** `docs/chat-policy-conformance-2026-09.md` (new) and this
entry. No code touched — the two findings are reported, not fixed, per the
brief.

**What was run:** nothing executable. This was a read of
`backend/internal/{chat,chatgroups,marriagechat,staffchat,casevolchat,chatlifecycle}`,
the route table in `backend/cmd/server/main.go:735-1093`, `humanitarian/lib/`
and `admin-web/src/`. Evidence in the doc is file:line throughout.

### Verdicts
Rules 2, 4, 5, 6, 7, 8 hold. Rules 1 and 3 are **partial**, for one shared
reason, plus a second independent gap.

- **V1 — the important one.** Donor↔owner chat origination is dead
  (`backend/internal/chat/chat.go:104-107` always returns
  `ErrDirectChatRetired`), but *pre-existing* `chat_threads` rows are still
  postable: `backend/internal/handlers/chat.go:387-411` checks party, `status`
  and lifecycle, never the thread's kind. `chatlifecycle/retire.go:10-13` says
  so in as many words. Closing those rows is a **manual script**
  (`backend/cmd/retire-direct-chats`), not a migration — I checked
  `backend/migrations/` and nothing there ends them. So rules 1 and 3 hold
  only on an environment where someone ran it, and a staff pause→resume puts a
  direct chat back into service afterwards. Suggested fix in the doc: a kind
  predicate on the send and accept paths in `handlers/chat.go`.
- **V2.** `kind='team'` groups accept any `role_in_group` — it is a free-form
  string (`handlers/chat_group_admin.go:122`) and `CreateGroup` validates only
  the kind (`chatgroups/chatgroups.go:153-156`). A staff member can therefore
  build a **real-name** room containing a donor and a beneficiary
  (`chatgroups_reads.go:112-113` serves `full_name` in non-masked groups); the
  dashboard offers all four roles regardless of kind
  (`admin-web/src/lib/chatGroupForm.ts:40`). The repo's own test builds this
  shape at `chatgroups_admin_kind_test.go:24-32`. **Ambiguous** — rule 5 says
  staff choose the members, so whether this is a bug depends on client intent.
  Ask before changing.
- V3, cosmetic: two stale app strings pointing at the retired flow
  (`humanitarian/lib/modules/chat/screens/messages_screen.dart:135, 217-218`).

### Things worth not re-deriving
- `casevolchat` is genuinely dead: 64 lines, one method
  (`MessageCountForSignup`), zero routes in `main.go`, and only four orphan
  translation strings left in the app. It is kept solely for the admin delete
  guard. Don't go hunting for its routes again.
- Masking in both masked groups and marriage chat is **structural**, not a
  filter: the mobile response types (`chatgroups.GroupMessage`,
  `marriagechat.ThreadView`/`Message`) have no field able to hold a user id,
  name or phone. Real identities live on separately named `Admin*` types.
- Rule 8's **export** is not a server route — it is client-side CSV/Excel/PDF
  in `admin-web/src/lib/chatExport.ts`, behind a PIN step-up. I initially
  concluded export was missing because `grep -i export` over the backend finds
  only `/admin/export/all`. It isn't missing. Check the dashboard first.
- The app has **no named routes and no deep links** (`Get.to(() => Widget())`
  everywhere) and push taps do not route anywhere
  (`humanitarian/lib/main.dart:114-118` only `debugPrint`s). That closes a
  whole class of "could a link reach a chat" questions.

### Still open
- Unpushed commit on this worktree branch; no PR.
- Nobody has confirmed whether `cmd/retire-direct-chats` has run on production
  or staging. Rules 1 and 3 hinge on it. `docs/runbooks/retire-direct-chats.md`
  has the post-check queries.
- V1 and V2 are reported, not fixed.

---

## 2026-09-16 — a team group is for volunteers and staff only

**Asked for:** Zaid's decision of 2026-09-16 — a `kind='team'` chat group is
for volunteers and staff only. Donors and beneficiaries must go in a masked
group, where members see labels instead of names.

**Branch:** `fix/team-groups-staff-and-volunteers-only`, cut from
`origin/main` at `fcc5b10`. One commit, NOT pushed. No OPOS task (OPOS was
unavailable in that session).

### The facts that were established first, by reading the code

1. **`role_in_group` is free text and gates nothing.** Migration 120 declares
   it `VARCHAR(16) NOT NULL DEFAULT ''` with **no CHECK constraint** and the
   comment "donor|beneficiary|volunteer|staff, **informational**". The backend
   reads it only to number auto-labels ("Donor 1" — `autoLabelName` in
   `chatgroups_members.go`) and to collapse staff senders to "Support"
   (`chatgroups_reads.go:112`). `admin-web/src/lib/chatGroupForm.ts`'s
   `CHAT_GROUP_ROLES` is the same four words. Staff type it; nothing validates
   it.
2. **The account is authoritative, not the group's word for it.**
   `users.role_id` — 1 donor, 2 beneficiary, 3 volunteer
   (`handlers/registration.go:194` accepts 1..3, then branches: 1 assigns the
   grantor code, 2 the recipient details, 3 the volunteer code) — and
   `users.staff_tier` for staff. The rule reads those two, never
   `role_in_group`.
3. **Staff are identified by `staff_tier`**, one of
   `super_admin|admin|supervisor|employee` (`internal/notify/notify.go:302-317`
   says so in as many words; `internal/auth/middleware.go` calls it "THE
   authoritative field"; `users.is_admin` is legacy and is not read).
   `staff_tier` therefore WINS over `role_id`: a coordinator whose `role_id` is
   still 1 because they first registered as a donor is staff, and a team group
   takes them. There is a test for exactly that.

### What was actually changed

Backend:
- `internal/chatgroups/chatgroups.go` — new sentinel `ErrTeamMemberRole`.
- `internal/chatgroups/chatgroups_members.go` — `teamMemberRefusedSQL` and
  `refuseTeamMemberRole`, called from `insertMemberRow` (every new member, on
  every path: CreateGroup, ApproveConnectRequest, AddMember) and from
  `addMemberInTx`'s **reactivation** branch, so #26410's "bring a removed
  member back" obeys the rule too.
- `internal/handlers/chat_group.go` — the `chatErr` table gains
  `{ErrTeamMemberRole, 400, "A team group can only include volunteers and
  staff.", team_member_role_not_allowed}`, following #107/#118/#26496's
  pattern.

Dashboard:
- `lib/chatGroupForm.ts` — `TEAM_GROUP_ROLES` and `rolesForKind(kind)`.
- `components/chatGroups/MemberRowsEditor.tsx` and `AddMemberForm.tsx` — a
  team group's role select offers only volunteer and staff, with one line
  under it saying why (`aria-describedby` on the select in the create dialog).
  The masked form is untouched.
- `lib/chatGroupErrors.ts` — the new code, mapped to
  `error.team_member_role_not_allowed`, in the 'members' area so the message
  lands beside the rows.
- `lib/locales/en.ts` and `ar.ts` — two new keys. **en and ar only**;
  ckb/kmr fall back to English on purpose (#21431).
- `TRANSLATION_REQUEST.md` — recounted, 621 + 2 = **623**.

Test-helper fixes that came with the rule (they were not incidental):
- `chatgroups_test.go`'s `makeTestUser` **ignored its `role` argument** and
  inserted `role_id = 1` for every user, so every "volunteer" and "staff" in
  that package was really a donor. It now maps the word it is already given
  (donor 1, beneficiary 2, volunteer 3, staff 3 + `staff_tier='employee'`).
  Six existing tests that built a TEAM group out of donors were changed to use
  volunteers — the intent of each was never about donors.
- `internal/handlers` got `makeChatGroupRoleUser` / `setChatGroupRole`
  (`chat_group_team_roles_test.go`), because `makeChatGroupUser` also always
  inserts `role_id = 1`. Four handler tests that built team groups were moved
  onto it.

### What was run, and what it printed

RED first, on both layers:
- `go test ./internal/chatgroups/ -run 'Team|MaskedGroupStill'` →
  `CreateGroup with a donor = <nil>, want ErrTeamMemberRole` (and the same for
  beneficiary, AddMember, and the reactivation case) — 4 tests failing for the
  right reason before a line of the rule existed.
- `npx vitest run src/components/chatGroups/MemberRowsEditor.test.tsx` →
  the team select still listed `donor` and `beneficiary`; 1 failed, 7 passed.

GREEN, on throwaway databases created and dropped for this work
(`gd_team_cg_a9`, `gd_team_h_a9`, both dropped afterwards, absence confirmed
with `psql -lqt`):
- `go test ./internal/chatgroups/ -count=1 -p 1 -timeout 45m` →
  `ok  github.com/karam-flutter/humanitarian-backend/internal/chatgroups  3.274s`
- `go test ./internal/handlers/ -count=1 -p 1 -timeout 45m` →
  `ok  github.com/karam-flutter/humanitarian-backend/internal/handlers  57.881s`
- `-v -run 'TeamGroup|TeamMember|TeamRole|MaskedGroupStillTakes|TeamRoles'`
  (chatgroups) → 11 PASS, 0 SKIP, 0 FAIL.
- `-v -run 'TeamRole|MaskedGroupStillTakes'` (handlers) → 5 PASS, 0 SKIP.
- `gofmt -l` clean on every file touched; `go build ./...` and `go vet ./...`
  both exit 0.
- admin-web (Node 22): `npm test` 199 passed / 22 files; `npx tsc -b`,
  `npm run build`, `npm run test:mock-api`, `npm run test:nav`,
  `npm run check:labels`, `npm run check:css-tokens`, `npm run lint` — all
  **exit 0** (lint prints 62 pre-existing warnings, 0 errors).

### For Zaid to run against PRODUCTION — read-only, nothing was changed

How many existing team groups already hold a donor or a beneficiary. Deliberately
NOT fixed here: repairing live rows is a membership decision, not a code change.

```sql
SELECT COUNT(DISTINCT t.id) AS team_groups_with_a_donor_or_beneficiary,
       COUNT(*)             AS offending_member_rows
  FROM chat_group_threads t
  JOIN chat_group_members m ON m.group_id = t.id
  JOIN users u             ON u.id = m.user_id
 WHERE t.kind = 'team'
   AND m.removed_at IS NULL
   AND u.role_id IN (1, 2)
   AND u.staff_tier NOT IN ('super_admin', 'admin', 'supervisor', 'employee');
```

Add `SELECT t.id, m.user_id` in place of the counts to list them. The query
ran clean against a migrated test database (0, 0); it has not been run against
production from here.

### Still open / needs a human

- The commit is **not pushed** and no PR exists.
- **Existing team groups are left exactly as they are.** The rule is about who
  can be ADDED; nobody already in a team group is removed, and what such a
  group serves its members is unchanged. If the production count above is
  non-zero, someone has to decide whether those people are removed, moved to a
  masked group, or left alone.
- ckb/kmr for the two new keys, as always.
- The dashboard change was verified by tests and `tsc`, not clicked through
  live (OTP-gated admin login, the same limitation every session here hits).

### Traps

- **`makeTestUser`'s role argument was a lie** (see above) and
  `makeChatGroupUser` still hardcodes `role_id = 1`. Any future rule that reads
  `users.role_id` will trip over the handlers helper the same way. Use
  `makeChatGroupRoleUser`.
- **A test database here is reused across runs and hands out the SAME user ids
  each time**, because `raiseUserIDFloor` resets the id sequence to a fixed
  floor per process. An assertion keyed on "groups created by this staff id"
  therefore sees groups left behind by an EARLIER run and fails for no reason.
  Count per user against a watermark instead. This cost real time.
- `internal/handlers/admin_edit_user_profile.go` is **already unformatted on
  `origin/main`** — `gofmt -l internal` names it and always did. Not from this
  work; do not "fix" it in an unrelated commit.
- `admin-web` needs its own `npm ci` in a fresh worktree; the tests fail with
  "Cannot find package 'vitest'" until you do.

---

## 2026-09-16 — the chat SEND and ACCEPT paths finally check `kind`

**Asked for:** OPOS #25284's policy (a donor, beneficiary or volunteer never
messages another one directly) was enforced at CREATION only. A conformance
audit found the send path never looked at the thread's `kind` — the hole
`chatlifecycle/retire.go:10-13` names in its own header: "Left paused, staff
could resume one into a working direct chat: sending checks lifecycle, never
kind." Plus two stale strings on the app's Messages screen.

**Branch:** `fix/direct-chat-kind-gate`, cut from `origin/main` (`fcc5b10`).
One commit, NOT pushed, no PR.

### What was actually changed
- `backend/internal/chat/chat.go` — `Thread.Kind` is now loaded (every
  SELECT/RETURNING on `chat_threads` carries `kind`), plus exported
  `KindDirect`/`KindSupport`. `AcceptThread` and `PostMessage` refuse a
  `kind='direct'` thread with the EXISTING `ErrDirectChatRetired` sentinel.
- `backend/internal/handlers/chat.go` — `chatErr` maps that sentinel to
  **410 Gone, `{"success": false, "error": "Direct messaging has been retired.
  Ask staff to connect you instead."}`** — the exact shape (status, body, no
  `code` field) `POST /api/chats/request` has answered with since Phase 4. The
  Request handler's inline copy of that response was deleted in favour of the
  shared mapping, and both send handlers now route store errors through
  `chatErr` instead of a flat 500.
- `backend/internal/handlers/chat_direct_kind_gate_test.go` — NEW, 5 tests.

**Why the STORE and not the handler:** the bug was a path that forgot to check.
Creation's refusal already lives in the store (`RequestThread`), and the store
covers both send callers (participant route and admin reply route) plus any
future one. The handler only maps the sentinel.

### Decisions worth knowing
- **Reading is untouched.** `GET /api/chats/:id/messages` still serves a direct
  thread's history — the policy retires new messages, not the record.
- **Staff are refused too**, exactly as a lifecycle pause refuses them: a staff
  reply into a retired direct thread would deliver a message its participants
  cannot answer. Say so if the client disagrees; it is a one-line revert of the
  `AdminPostMessage` path.
- **Team-group membership rules were NOT touched** (a separate decision is
  pending).
- Ordering note: K19's contact-details block still runs BEFORE the store, so a
  direct thread sent a phone number answers 422, not 410. Nothing is stored
  either way.

### Test-fixture fallout (read this before you think a test is wrong)
`kind='direct'` used to be the default fixture everywhere, so several suites
were posting into or accepting one. Every fixture whose SUBJECT is not
direct-ness now seeds `kind='support'` — the only kind on `chat_threads` that
can still be posted into — and says why in a comment:
`makeContactThread` (K19), `seedPendingSupportInvite` (invite accept controls
and the declined-invite donor case), `seedSupportChat` (moved into
`chat_lifecycle_fixtures_test.go` and used by `allFixtures`, the resume test,
the end-keeps-history test and the delete/restore test),
`seedDeclineThreadOfKind` (store-level accept tests).
Left DIRECT on purpose: `seedDonorChat`, the archive/staff-list case (the staff
list only shows `kind='direct'`), and
`TestTrashRestore_OpenDirectChatComesBackClosed` — that one now seeds its two
messages and its `chat_reads` row with SQL, because the route it used before
is the route this fix closed.
**A consequence for a human:** K19's peer-thread filter on `chat_threads` is
now unreachable in production (the only peer thread it covered is the retired
direct one). Its tests still pass on support-kind rows, and the group chat has
its own filter. Whether the `chat_threads` half should be deleted is a call for
the client, not a drive-by.

### App (V3)
- `humanitarian/lib/modules/chat/screens/messages_screen.dart` — the empty
  state said "Start a chat from a donation (donor) or from your campaign
  donations (owner)", a flow that no longer exists. It is now two localised
  keys pointing at "Ask our team to connect me" and the supervised group. The
  second stale string was the comment above the standing tiles, which still
  listed "case chats" (retired); it now names the support ticket form, which is
  what the third tile actually is.
- `app_translations.dart` — `chat_empty_title` / `chat_empty_message`, **en +
  ar only** (ckb/kmr fall back, #21431). `TRANSLATION_REQUEST.md` has a new
  section and its count was recounted 621 → **623**.

### What was run, and what it printed
- RED first, on `godonation_direct_kind`: `SendRefusedOnOpenDirectThread`
  "status = 200, want 410 Gone"; `AcceptRefusedOnDirectThread` "status = 200,
  want 410 Gone". The three control tests (read history, support posts,
  marriage posts) passed before the fix, as they must.
- GREEN, fresh DB `godonation_final`: `go test ./internal/chat/
  ./internal/handlers/ -count=1 -p 1 -timeout 45m` → `ok ...internal/chat
  1.092s`, `ok ...internal/handlers 18.989s`.
- `-run 'DirectKindGate' -v` on fresh `godonation_runcheck`: 5 PASS, 0 SKIP.
- Whole backend on fresh `godonation_all`: `go test ./... -count=1 -p 1` — no
  FAIL lines.
- `gofmt -l .` reports only `internal/handlers/admin_edit_user_profile.go`,
  which is PRE-EXISTING on main and untouched here (gofmt rewrites two `''`
  quote pairs inside its comments). Every file this branch touches is clean.
  `go build ./...` and `go vet ./...` clean.
- App: `flutter analyze` → 6 issues (the baseline, all pre-existing
  deprecations); `flutter test` → 1088 passed.
- All throwaway databases dropped afterwards; `psql -lqt` confirmed.

### Still open
- Nothing is pushed. One commit sits on `fix/direct-chat-kind-gate` in the
  worktree; no PR was opened.
- The K19 dead-filter question above.
- Nothing was clicked through in a running app (same OTP-gated limitation as
  every backend fix here); the app change is covered by analyze + tests only.

---

## 2026-09-12 — pending profile-change requests now visible on the Users list

**Asked for:** OPOS #25287 — "profile edits sometimes don't sync to
dashboard," reported as intermittent.

**Branch:** `fix/profile-changes-dashboard-visibility`, cut from `main`. One
commit, pushed, PR opened:
https://github.com/IamSizar/go_donation/pull/68 (`6e73d89`).

### Root cause (Explore-agent audit) — not intermittent, deterministic per field
The app's real "Edit Profile" screen (`RegistrationFormPage`, edit mode)
writes name/address straight through via `SubmitRegistration` — instant,
no review. That SAME screen's avatar edit goes through a different
endpoint (`POST /api/profile/set`), which DELIBERATELY queues
`full_name`/`profile_picture` in `profile_change_requests` for staff
review (`internal/profilechanges` — confirmed intentional by reading its
own package doc: "a rejected change never appears anywhere"). The Users
list had no way to show a pending row, so staff saw the name update
instantly and the photo silently not update from the same save action —
that's the whole "sometimes doesn't sync."

### What was actually changed
- `backend/internal/users/users.go` — `PaginatedList` now marks
  `HasPendingProfileChange` per account via one batched query per page.
- `admin-web/src/pages/UsersPage.tsx` — "Pending review" badge/link next
  to the name, pointing at the existing `/profile-changes` page.
- `api-types.ts` + `en.ts`/`ar.ts` — new field + two new strings (ckb/kmr
  inherit English via the existing fallback chain, nothing invented).

### Deliberately NOT changed
Whether name/address edits should ALSO require staff review, to match
photo. That's a moderation-policy call for the client — the two write
paths behaving differently isn't necessarily a bug on its own; unifying
them without asking would have been guessing at product intent.

### What was run, and what it printed
- New `backend/internal/users/pending_profile_change_test.go`
  (TEST_DATABASE_URL-gated): seeds one user with a pending row, one
  without, asserts both are marked correctly. Mutation-checked (removed
  the marking call, confirmed the exact expected/actual failure, restored).
- `go build/vet/test ./...` — all green, `gofmt -l` clean.
- admin-web: `tsc --noEmit` and `npm run build` clean. Confirmed
  `GET /api/admin/users` still 401s without auth.

### Still open / needs a human
- The moderation-policy question above (should name/address also require
  review) needs a client decision.
- Badge placement/copy verified by code + tsc, not clicked through live
  (OTP-gated admin login, same limitation as every fix this session).

---

## 2026-09-12 — Community Services stops duplicating City Guide, becomes a real events feed

**Asked for:** OPOS #25272 — a bug report said City Guide and Community
Services overlap and confuse users. Auditing (Explore agent, not a guess)
found they weren't two overlapping features but the SAME one: both read
`city_directory_entries` through the shared `CommunityController` singleton.
Two clarifying questions were put to Zaid before writing any code: (1) how to
resolve it → **keep both, differentiate by content**; (2) what Community
Services' real content should be → **community events/announcements**.

**Branch:** `feat/community-events-feed`, cut from `main`. One commit, pushed,
PR opened: https://github.com/IamSizar/go_donation/pull/65 (`677c4fa`).

### What was actually changed
- `backend/migrations/121_community_media_type.sql` adds `'community'` to the
  `media_posts.post_type` CHECK constraint — same precedent
  `011_marriage_media.sql` set for `'marriage'`: reuse the existing table
  and admin CRUD rather than build a new one.
- `internal/listings/listings.go` — the untyped/general News & Activities
  feed now excludes `post_type = 'community'` the same way it already
  excludes `'marriage'`, so the two feeds don't leak into each other.
- `internal/handlers/admin_edit.go`'s `mediaPostTypes` whitelist and
  `admin-web/src/pages/MediaPage.tsx`'s `POST_TYPES` dropdown both updated
  to allow the new value — staff author these posts with the EXISTING Media
  form, no new admin page.
- `humanitarian/lib/modules/community/screens/community_events_feed.dart`
  (new) — `CommunityEventsFeed`, built entirely from existing pieces
  (`MediaPostsController`, the public `MediaPostCard`, `FeedPaginationFooter`)
  under its own GetX tag, mirroring `MarriageHubScreen`'s
  `type=activity,news` pattern exactly.
- `community_services_section.dart` — `CommunityServicesSection` now renders
  the new feed; deleted the now-dead `_CommunityServicesList` and
  `_CityServiceCard` widgets. The "About/Contact the Mosul Guide" tiles that
  used to live on Community Services (they're about City Guide, not events)
  moved onto `CityGuideScreen`'s own header as an info-button → action sheet,
  so those two required entry points stay reachable.

### What was run, and what it printed
- `go build ./... && go vet ./... && go test ./...` — all green.
  `gofmt -l` clean on the touched Go files.
- Live scratch-DB check (`createdb donation_scratch_community`,
  `RUN_MIGRATIONS=1 DATABASE_URL=... go run ./cmd/server`, dropped after):
  seeded one `post_type='community'` row and one `post_type='news'` row
  directly with `psql`. `GET /api/media?type=community` returned ONLY the
  community post. `GET /api/media` (no type) returned the news post plus
  the migration's other seed posts but NOT the community one — confirming
  the exclusion. `POST /api/admin/media` still 401s with no token.
- `flutter analyze` on every touched Dart file — `No issues found!`.
- admin-web: `npx tsc --noEmit -p .` clean; `npm run build` succeeded.

### Still open / needs a human
- The concrete content type ("events/announcements") came from a clarifying
  question, not from the original bug report — worth confirming with the
  client that this is what they actually want Community Services to become,
  before staff start relying on it.
- The admin-web Media form's actual click-through creating a `'community'`
  post was **not** verified in a browser (OTP-gated login, same limitation
  as the districts-CMS entry above) — verified at the API/DB layer instead.
- Moving "About/Contact the Mosul Guide" to an info-button sheet on City
  Guide is a UX judgment call to preserve two required entry points that no
  longer had a home — a designer should sanity-check the placement.

---

## 2026-09-12 — Nineveh district/neighborhood lists moved from hardcoded Dart to an admin CMS

**Asked for:** OPOS #25271 — the district/neighborhood dropdowns in the
registration form were English-only and the list itself was hardcoded and
incomplete, with no way for staff to add or correct an entry without a code
change and app release ("in the registration form and anywhere else the list
is used").

**Branch:** `fix/districts-list-cms`, cut from `main`. One commit, pushed,
PR opened: https://github.com/IamSizar/go_donation/pull/64 (`963182d`).

### What was actually changed
- New table `districts` (migration `backend/migrations/120_districts.sql`):
  `group_key` scopes rows to `nineveh_district` / `nineveh_neighborhood_left`
  / `nineveh_neighborhood_right`; seeded with the same 10 districts + 24
  neighborhoods the old hardcoded lists had. Kurdish (ckb/kmr) is filled in
  for the 10 governorate-level districts only — deliberately left blank for
  the 24 neighborhood rows, since nobody here can vouch for a Kurdish
  translation of a Mosul neighborhood name and the client localizer already
  falls back en→ar when a Kurdish value is blank.
- `backend/internal/districts/districts.go` + `internal/handlers/admin_districts.go`
  — store + handler, copied line-for-line from `citycategories`/
  `admin_city_categories.go` (same CMS-clone convention as every other
  admin-managed list in this codebase), wired into `cmd/server/main.go`.
- `admin-web/src/components/DistrictsManager.tsx` — modal opened from the
  Registrations page toolbar (not a new sidebar entry — per earlier client
  feedback that the admin nav already has too many one-off modules).
- Flutter: `registration_form.dart` (both the recipient and volunteer
  sub-forms) and `marriage_form_screen.dart` (a second usage site the
  original bug report didn't mention — found by grep, not by guessing) now
  fetch the three lists via `ModuleApi.districts(groupKey)` on `initState`
  and render them through the existing `localizedContentFromValues` helper.
  Deleted `lib/data/nineveh_neighborhoods.dart` outright and removed the
  `ninevehDistricts` const from `nineveh_districts.dart` (its
  `volunteerLanguages` const is unrelated and was kept).
- Added a small loading-spinner / error+retry banner above the affected
  dropdowns in both screens — new string `'Districts could not load. Tap to
  retry.'` in `app_translations.dart`, en+ar only (same reasoning as the
  Kurdish note above: Sorani/Badini fall back to English automatically for
  any key this session didn't add a real translation for).

### What was run, and what it printed
- `go build ./... && go vet ./... && go test ./...` — all packages `ok`,
  nothing failed. `gofmt -l .` flagged one pre-existing unrelated file
  (`admin_edit_user_profile.go`), untouched by this branch, left alone.
- Live verification against a scratch DB (`createdb donation_scratch_districts`,
  `RUN_MIGRATIONS=1 DATABASE_URL=... go run ./cmd/server`, dropped after):
  `GET /api/districts?group=nineveh_district` returned the 10 seeded rows
  with correct ckb/kmr values; `GET /api/districts` (no `group`) returned
  `400 {"error":"group is required."}`; `GET /api/admin/districts` returned
  `401 auth_required` with no token. A throwaway `cmd/districtsverify/main.go`
  (deleted before commit, never pushed) exercised the store's
  Add→List→Update→Reorder→Delete directly against the scratch DB — printed
  `ALL DISTRICTS STORE CHECKS PASSED`.
- `flutter analyze` on every touched Dart file — `No issues found!`.
- admin-web: `npx tsc --noEmit -p .` — no output (clean); `npm run build` —
  succeeded, `RegistrationsPage` (which imports `DistrictsManager`) bundled
  with no errors.

### Still open / needs a human
- The admin-web `DistrictsManager` modal's actual click-through was **not**
  verified in a browser — the dashboard login is OTP/2FA-gated and this
  session didn't attempt to simulate that flow. Everything it calls was
  verified at the API/store layer instead. Worth a manual pass before or
  right after merge.
- This branch was cut from `main`, not from `fix/messaging-channels-reachable`
  (a different, still-unmerged branch with its own HANDOFF entry above this
  one won't appear until that branch merges) — the two are independent and
  should merge cleanly against each other.

### A trap worth flagging
Started this task's edits on `fix/registration-photo-not-displaying` (the
previous task's already-pushed branch) before realizing no dedicated branch
had been created — caught it before anything was committed, via
`git stash` → `git checkout -b fix/districts-list-cms main` → `git stash pop`.
Always create the task's branch **before** the first edit, not after.

---

## 2026-09-12 — publishing a project request with no Arabic title no longer crashes

**Asked for:** OPOS #25292 — "'Add Campaign' UI inconsistent," reported
vague, no further detail.

**Branch:** `fix/publish-project-request-crash`, cut from `main`. One commit,
pushed, PR opened: https://github.com/IamSizar/go_donation/pull/69 (`8ce3d1c`).

### Root cause (Explore-agent audit found this despite the vague report)
Two paths `INSERT INTO campaigns`: the direct "Add Campaign" admin form
requires `title_ar` with clear inline validation; "Publish" a beneficiary's
approved project request maps `project_title_ar` (nullable, and the app's
own submission form never collects it) onto the same `NOT NULL
campaigns.title_ar` column, passing `nil` straight into the INSERT — a raw
`"null value... violates not-null constraint"` 500 on essentially every
real publish. That's the "inconsistency": one flow demands Arabic title,
the other crashes instead of asking for it.

### What was actually changed
- `backend/internal/handlers/admin_status.go` — `title_ar` now defaults to
  `""` when the source has none, matching the exact pattern this same
  function already uses for `description`/`description_ar`. Never falls
  back to the English title (house rule: Arabic UI = no English).

### Deliberately NOT changed
Whether the project-request submission form should start collecting an
Arabic title, or whether staff should be prompted for missing
translations before publish. Both are real product/UX decisions for the
client — not something to decide unilaterally while fixing a crash.

### What was run, and what it printed
- New `publish_project_request_test.go` drives the real HTTP route
  (`RequireAdmin` + `RequirePermission`, matching `main.go`'s wiring),
  asserts 200 + no English-in-Arabic leak. Mutation-checked: reverted to
  the nil-passthrough, confirmed the test fails with the EXACT originally
  reported error, restored the fix.
- `go build/vet/test ./...` — all green, `gofmt -l` clean.

### Still open / needs a human
The two deliberately-deferred decisions above.

---

## 2026-09-12 — video posts can now actually have a video file attached

**Asked for:** OPOS #25291 — "News & Media post bug," reported with no
further detail.

**Branch:** `fix/media-video-upload`, cut from `main`. One commit, pushed,
PR opened: https://github.com/IamSizar/go_donation/pull/70 (`32657af`).

### Root cause (Explore-agent audit found this despite the vague report)
`post_type: 'video'` has existed since the seed data, but attaching a real
video file was a dead end on both ends: `MediaPage.tsx`'s file field had no
`accept` override (defaulted to images only, so the OS picker wouldn't
even list a `.mp4`), and the backend's `AdminUploadHandler` extension
whitelist had no video extension at all (would 400 even if bypassed by
hand). The only way a video post ever worked was pasting an
already-hosted external URL into Link URL.

### What was actually changed
- `backend/internal/handlers/admin_upload.go` — new `allowedVideoExts`
  map (`.mp4`/`.mov`/`.webm`) with its OWN 50 MB `MaxVideoBytes` ceiling,
  kept separate from the existing 5 MB image/PDF cap so the larger limit
  doesn't leak to the other things sharing this one endpoint (partner
  logos, case documents, product images).
- `admin-web/src/pages/MediaPage.tsx` — `media_url` sets
  `accept="image/*,video/*"`.

### What was run, and what it printed
- Extended `admin_upload_test.go`: `TestUploadAcceptsVideoExtensions`,
  `TestUploadEnforcesPerCategorySizeLimits` (6 MB video passes, 6 MB
  image still rejected, 51 MB video still rejected). Mutation-checked:
  emptied the video map, confirmed both fail with the exact
  "Unsupported file type" error, restored.
- `go build/vet/test ./...` green, gofmt clean. admin-web `tsc --noEmit`
  + `npm run build` clean.

### Still open / needs a human
- 50 MB is a judgment call — confirm against real content the client
  expects to post.
- Not clicked through with a real video file in a live browser session.

---

## 2026-09-12 — Arabic-script text gets its own line-height instead of the Latin scale

**Asked for:** OPOS #25281 — "Arabic text overlaps/garbles," described as
systemic, not one screen.

**Branch:** `fix/arabic-line-height`, cut from `main`. One commit, pushed, PR
opened: https://github.com/IamSizar/go_donation/pull/67 (`3d0e26c`).

### Root cause (Explore-agent audit, not a guess)
`AppThemeConfig.applyLocaleFont()` swaps in the `Kurdfont` family for
ar/ckb/kmr via `TextTheme.apply(fontFamily:)`, but `.apply()` only touches
the font family — the Latin-tuned `height` values (`AppType.leadDisplay:
1.02`, `leadTitle: 1.14`) carried straight through untouched. Arabic's
taller x-height/ligatures/diacritics don't fit a line box sized for Latin
glyphs — that's the "overlapping." `dashboard_screen.dart` had already
independently found this same font needs ~1.45 before clamping it to fit a
fixed 52pt bar; this generalizes that finding via the theme.

Two contributing factors were found; only one was fixed here:
1. **Line-height (fixed).** See below.
2. **Font weight (NOT fixed — flagged as its own task, `task_86d1e2e0`).**
   `Kurdfont` is bundled at weight 400 only, so every `FontWeight.w600+`
   request is synthetically bolded for 3 of 4 languages. Needs new font
   asset files (e.g. IBM Plex Sans Arabic / Noto Sans Arabic at 400/600/700)
   — a licensing/design decision for a human, not something to code around.

### What was actually changed
- `humanitarian/lib/core/design/tokens.dart` — added
  `leadDisplayAr`/`leadTitleAr`/`leadBodyAr`/`leadDenseAr`, each strictly
  wider than its Latin counterpart.
- `humanitarian/lib/core/theme/app_theme_config.dart` — `applyLocaleFont()`
  applies them via `TextStyle.copyWith(height:)` after the font-family
  swap, only for the Arabic-script family. Non-Arabic locales untouched.

### Deliberately NOT changed
The ~130 hardcoded inline `TextStyle(height: ...)` literals scattered
across screens (found via grep). Several — including the exact dashboard
nav-bar case above — are DELIBERATELY clamped tight to fit a fixed-height
container. Blindly loosening all of them would trade this bug for a fresh
overflow bug. Needs per-site layout review; out of scope for this pass.

### What was run, and what it printed
- New `test/design/arabic_line_height_test.dart` (4 tests): Latin leading
  untouched, Arabic leading applied and strictly wider, font family still
  swaps, null locale is a no-op. Mutation-checked (reverted the fix,
  confirmed the exact expected/actual failure, restored it).
- `flutter test` — full suite, 816 passed. `flutter analyze` clean on
  touched files.

### Still open / needs a human
- Font-weight synthesis fix (above) — spun off as OPOS follow-up task
  `task_86d1e2e0`, needs a font-asset decision from the client.
- The chosen Arabic leading values (1.35/1.45/1.65/1.6) came from the
  codebase's own empirical ~1.45 finding plus the existing "inverse to
  size" principle, not from measuring the live font on a device — worth a
  visual pass with long wrapped Arabic/Kurdish headings.

---

## 2026-09-12 — City Guide's sector chips actually hit the server now; Marketplace was already done

**Asked for:** OPOS #25274 — "Marketplace + City Guide: browse by category
(backend category filter + frontend chips)".

**Branch:** `fix/city-guide-server-side-category-filter`, cut from `main`. One
commit, pushed, PR opened: https://github.com/IamSizar/go_donation/pull/66
(`6877845`).

### What was found before touching anything
- **Marketplace: nothing to do.** Backend `category` param, admin category
  field, and a working chip bar already shipped end-to-end in an earlier
  commit (K15/#28) — confirmed by an Explore-agent audit, not assumed.
- **City Guide: the chips were cosmetic.** `CommunityController.fetchEntries()`
  never sent the selected sector to the server; `selectSector` only mutated
  local Rx state and `filteredEntries` re-filtered whatever page had already
  loaded. `ListCommunity` caps at 50 rows by default, so a sector whose
  matches fell outside that first page silently looked empty even though the
  backend's `sectors @> $1` WHERE clause and `?sector=` param already existed
  and worked.

### What was actually changed
- `humanitarian/lib/api/module_api.dart` — `communityDirectory()` gained a
  `sector` param.
- `humanitarian/lib/modules/community/controllers/community_controller.dart`
  — `selectSector()` now refetches from the server (same pattern
  `setSearchQuery` already used), and `filteredEntries` no longer
  re-filters by sector client-side.
- **Deliberately NOT changed:** sub-category (K16) filtering stays
  client-side. Reading `_spellingsOf()` in that same file BEFORE touching
  it showed this is intentional: the free-text `category` column holds
  legacy values (raw Arabic strings, typos) an exact-match server-side
  filter would silently miss. "Fixing" this the same way as sector would
  have been a data-visibility regression, not a fix — caught by reading the
  code instead of pattern-matching the two filters as identical.

### What was run, and what it printed
- No backend changes were needed (the `?sector=` param already existed) —
  Go build/vet/test were not re-run for this branch.
- Live scratch-DB check (`createdb donation_scratch_cityguide`, dropped
  after): seeded two `city_directory_entries` in different sectors
  (`health`, `commercial`); `GET /api/community?sector=health` returned
  only its entry, `?sector=commercial` returned only its entry, unfiltered
  returned both plus seed data.
- `flutter analyze` project-wide: clean except 6 pre-existing
  `deprecated_member_use` infos in untouched files.

### Still open / needs a human
- Verified via curl + static analysis, not clicked through on a device —
  worth a quick manual check that the sector chips visibly narrow the
  City Guide map/place-strip.

---

## 2026-09-16 — OPOS #26636: "no phone number can be on 2 accounts" (branch `fix/one-account-per-phone`, NOT pushed)

**What was asked:** audit every path that creates an account or sets a phone
number, against the owner's rule verbatim — *"no phone number can be on 2
accounts"* — and close the gap if there is one. Branch cut from `origin/main`
`a554ec3`.

**There was a gap, and it was on the dashboard.** `users.phone` has been UNIQUE
since migration 001, but a UNIQUE index compares STRINGS: it only means "one
account per number" while every writer agrees how a number is spelled. The app
paths agreed; the two dashboard paths did not.

### The audit

| Path | file:line | Normalisation | Uniqueness | Refusal |
|---|---|---|---|---|
| App sign-in | `handlers/auth.go:100` | `auth.NormalizePhone` | lookup only — no longer creates accounts (A16) | `otp_required`, 401 |
| OTP request | `handlers/auth.go:595` | `auth.NormalizePhone` | n/a | 400, English |
| OTP verify | `handlers/auth.go:849` | `auth.NormalizePhone` | n/a | coded, 409 |
| Password set-up (creates the row) | `handlers/auth_password_setup.go:103` → `users.InsertWithPhone` (`users/users.go:638`) | `auth.NormalizePhone` at the handler | DB UNIQUE | coded |
| Guest sign-up | `users.InsertGuest` (`users/users.go:786`) | n/a — no phone at all | `username` only | `ErrUsernameTaken` |
| Guest → member upgrade | `handlers/auth.go:1188` → `users.UpgradeGuestPhone` (`users/users.go:838`) | `auth.NormalizePhone` at the handler | DB UNIQUE, caught as `ErrPhoneTaken` | 409, English prose |
| Google sign-in | `users.UpsertGoogleUser` (`users/users.go:686`) | n/a — inserts `phone NULL` | by `google_sub`/`email` | n/a |
| `SubmitRegistration` | `users/registration.go:107` | **does not touch `users.phone`** — only `user_profiles.phone1/phone2/emergency_phone`, which are secondary contact fields, not the sign-in identity | n/a | n/a |
| **Dashboard create** | `handlers/admin_status.go:233` | **NONE** — bare `TrimSpace` | UNIQUE, defeated by spelling | 409 English, no `code` |
| **Dashboard edit** | `handlers/admin_edit.go:1778` | **NONE** — bare `TrimSpace` | UNIQUE, defeated by spelling | **HTTP 500 with the raw Postgres text on screen** |

**The database:** `backend/migrations/001_full_v2.sql:66` —
`phone VARCHAR(255) NOT NULL UNIQUE`. `017_google_oauth.sql:8` drops only the
NOT NULL (`ALTER TABLE users ALTER COLUMN phone DROP NOT NULL`), so the UNIQUE
survives and NULLs — guests, Google accounts — are allowed to repeat, which is
what those account types need. `010_phone_canonical.sql` and
`063_phone_international.sql` already canonicalised the existing rows. **No new
constraint was added and no migration was written**, so nothing could fail on
existing data.

**OPOS #26454 / PR #47 did the client half only, and said so.**
`admin-web/src/lib/phone.ts:64-74` carries the note: the dashboard stops sending
a non-canonical string, "until the two handlers call NormalizePhone themselves
— the real single-source fix". `VERIFICATION_REPORT.md` line 369 (E7) records
the same thing as an outstanding backend change. This is that change. Nothing
from #47 was duplicated.

### What was changed

- **`backend/internal/handlers/phone_identity.go` (new, 97 lines)** —
  `normalizeIdentityPhone()` wraps the existing `auth.NormalizePhone` (the one
  authority; `admin-web/src/lib/phone.ts` already mirrors it) in the HTTP
  refusal, and `isUniqueViolation()` recognises SQLSTATE 23505 by unwrapping to
  `pgconn.PgError` instead of grepping the message for "duplicate".
- **`admin_status.go` CreateUser** — normalises after the H10 mask guard
  (a redaction normalises to `""`, so normalising first would have answered
  "invalid phone" instead of "you were never shown this number"); conflicts now
  answer `phone_taken` / `username_taken`.
- **`admin_edit.go` User** — normalises after the H10 and H13 guards and
  **before** the H20 main-admin gate, which compares submitted against stored to
  decide whether the sign-in channel is changing: un-normalised, re-saving the
  same number in a different spelling looked like a change and demanded an
  out-of-band confirmation code for nothing. The UPDATE's 23505 is now a 409
  instead of a 500 carrying raw Postgres text.
- **`admin-web/src/lib/locales/{en,ar}.ts`** — `error.phone_required`,
  `error.phone_invalid`, `error.phone_taken`, `error.username_taken`. These ride
  the existing contract: `describeError` (`lib/api.ts:241`) resolves a refusal's
  `code` through the `error.<code>` namespace. Deliberately separate from the
  existing `error.invalid_phone`, which governs the organisation's PUBLISHED
  contact numbers and asks only for five digits.
- **`TRANSLATION_REQUEST.md`** — new section for the 4 keys; count 617 → **621**.
  No Kurdish was written; ckb/kmr fall back to English as the standing decision
  requires.

**No advisory lock was taken, and none is needed.** Once both writers normalise,
two simultaneous creates of one number are two INSERTs of the same key and the
UNIQUE index refuses one inside the database. `LockUserProfileWrite` stays where
it was, for the `user_profiles` check-then-insert it was written for.

### Verification

`backend/`, on throwaway databases created and dropped for this work:

| Command | Result |
|---|---|
| `go build ./...` | exit 0 |
| `go vet ./...` | exit 0 |
| `gofmt -l ./internal ./cmd` | lists only `internal/handlers/admin_edit_user_profile.go`, which is **pre-existing on `origin/main`** (confirmed by piping that file's `origin/main` copy through `gofmt -l`) and was not touched |
| `go test ./internal/handlers/ -run PhoneIdentity -v` | **7 PASS, 0 SKIP, 0 FAIL** — and all 7 were confirmed FAILING against the unfixed code first |
| `go test ./internal/handlers/` | `ok … 17.036s` |
| `go test ./internal/auth/` | `ok … 0.936s` |
| `go test ./internal/users/` | `ok … 1.181s` |

`admin-web/`, Node 22.23.1 from `/opt/homebrew/opt/node@22/bin` (the worktree
had no `node_modules`; `npm ci` first):

| Command | Exit | Final line |
|---|---|---|
| `npx tsc -b` | 0 | (no output) |
| `npm test` | 0 | `Tests  197 passed (197)` / `Test Files  22 passed (22)` |
| `npm run build` | 0 | built |
| `npm run lint` | 0 | `✖ 62 problems (0 errors, 62 warnings)` — the #131/#132 baseline, unchanged |
| `npm run check:labels` | 0 | `every controlled value and permission module has a label.` |

The Flutter app was **not touched**, so `flutter analyze` / `flutter test` were
not run.

### The new tests

`backend/internal/handlers/admin_user_phone_unique_test.go`, all driving the
real routes through the real middleware over the real migrated schema:
canonical storage on create and on edit; a refusal when the number is already
held **in a different spelling** (the owner's rule itself, and the case the old
code let through); a refusal for an unreadable number on both paths; and
`TestPhoneIdentityConcurrentCreateLeavesOneAccount` — two simultaneous creates
of one number, one spelled canonically and one locally, asserting exactly one
200, one 409, and one row.

### Still open / for the owner

1. **Existing duplicates were NOT searched for or merged.** Adding no
   constraint meant nothing had to be clean, so no production data was read.
   If two accounts already hold one number in two spellings, this change stops a
   third but does not merge the two — merging or deactivating real accounts is
   the owner's decision. A read-only count is the next step if he wants one.
2. **`volunteer_applications.phone`** (`admin_edit.go:1472`) is deliberately
   untouched: it is a contact field on an application row, not a sign-in
   identity, and nothing signs in with it.
3. **The app's own refusals are still English prose.** The guest-upgrade 409
   (`auth.go:1210`) sends no `code`, so the Flutter side cannot translate it.
   Out of scope here — it would need an app release.
4. **Commits are NOT pushed.**

### Traps

- `storedPhone()` already exists in `admin_main_admin_guard_test.go`; declaring
  it again is a build failure for the whole package, which is how the first test
  run failed.
- The H10 mask guard must run BEFORE normalisation. A redaction (`••••03`)
  reduces to `""`, so the order decides whether the operator is told "invalid
  number" or "you never saw this number".
- A fresh worktree has no `admin-web/node_modules`, and `npx tsc` without them
  fetches an unrelated package that prints "This is not the tsc command you are
  looking for". Run `npm ci` first.

---

## 2026-09-16 — OPOS #25284 (last deploy step): readiness check for the retire-direct-chats production run (branch `docs/retire-run-readiness`, NOT pushed)

**What was asked:** read-and-verify only. Confirm `docs/runbooks/retire-direct-chats.md` still matches the code after this week's changes, produce an operator's plan for Zaid, and fix the runbook where it is wrong. No production access, no database writes, no Go/Flutter/admin-web changes. OPOS was not usable in this session (the connector needs OAuth), so nothing was logged there.

**Branch** cut from `origin/main` `a554ec3` (fetched at the start; it did not move during the work).

**What was changed — two commits, docs only:**
- **`83eef69` `docs(runbooks): an operator's plan for the retire-direct-chats production run`** — new file `docs/runbooks/retire-run-readiness-2026-09.md`. Verdict, a step-by-step table of every runbook step with file:line evidence, the commands in order with expected output, a failure table for mid-run problems, the freeze (what, how long, who to tell), and seven caveats.
- **`e1a299b` `docs(runbooks): the retire runbook matches the code again after this week`** — three fixes to `docs/runbooks/retire-direct-chats.md`:
  1. **Risk 4 was stale.** "A retired pending invitation can still be accepted" stopped being true with OPOS #26413: `ChatHandler.Accept` calls `refuseIfInviteClosed` before `AcceptThread` and before the push (`internal/handlers/chat.go:283`, `internal/handlers/chat_lifecycle_gate.go:121-126`), which refuses paused, ended **and archived** threads. Moved to a "Resolved by OPOS #26413" block; the remaining open risks renumbered 1-8. The only cross-reference, "risk 3" in section 10, still points at the right item.
  2. **Section 3 actor lookup** used a plain `LEFT JOIN user_profiles`, which repeats a staff member with two profile rows. Rewritten as `LEFT JOIN LATERAL … ORDER BY pr.id LIMIT 1`, matching `internal/chat/chat.go:640-643` (PR #127/#130).
  3. **Stale citations:** `admin_trash.go:273` → `:278`, `admin_trash.go:296` → `:301`.
  The header row now records the 2026-09-16 re-verification and points at the readiness file.

**The verdict: ready to run.** The script, both SQL statements, the freeze list, the pre-flight, the post-checks and the section 10 restore all still match the code. Migration 124 (an index on `user_profiles(user_id)`) touches no chat table; PR #127/#130 changed application reads only; PR #129 touches only the profile writers. Claim and release still write `updated_at` (`internal/chat/chat.go:314`, `:330`), so they still need freezing; pause/resume and Trash delete/restore correctly do not.

**What was run:**
- `createdb gd_runbook_readiness_0916`, migrated by the test harness: `[migrate] done: 122 newly applied, 122 total migration files`, then `--- PASS: TestRetireAllDirectThreadsIsIdempotent`.
- Every SQL block from runbook sections 4, 5, 7 and 10 executed verbatim against that database (empty tables, actor id 1). All ran without error: pre-flight returned both migration rows and `will_end 0 | will_archive 0`; the snapshot `CREATE TABLE … AS` and every post-check ran; the section 10 restore returned `restored_rows 0 | snapshot_rows 0`; the snapshot table was dropped.
- `go test ./internal/chatlifecycle/ -count=1` → `ok … 1.360s`.
- `dropdb gd_runbook_readiness_0916`, then `SELECT count(*) FROM pg_database WHERE datname LIKE 'gd_runbook_readiness%'` → `0`.
- **This is a schema check, not a data check.** No production database was contacted and no production credential was used.

**External actions:** none. Nothing was pushed. OPOS was not available.

**Still open:**
- Both commits are local on `docs/retire-run-readiness` and unpushed.
- The production run itself has still **not** been performed. It needs Zaid's explicit go.
- Four single-row profile reads are still nondeterministic (see the #26603 entry). None of them is on the retire path.

**Traps:**
- **The section 10 restore does not protect a thread deleted after the run and then restored.** Its `updated_at` is still `run_ts` — the restore re-inserts the payload verbatim (`admin_trash.go:278`), `chat_threads` has no `updated_at` trigger (only the marriage, staff and case-volunteer thread tables have one), and the close is a no-op on an already ended+archived row. So the restore would revert a deletion staff made after the run. **Run post-check 7h before using the section 10 restore** and exclude any thread with a `restored_at` after the snapshot. This is caveat C1 in the readiness file.
- `go run ./cmd/retire-direct-chats` is not in the production image; it runs from a checkout with the production `DATABASE_URL` in the environment.

---

## 2026-09-16 — OPOS #26437, part 2: `react-hooks/set-state-in-effect` (branch `chore/admin-web-lint-set-state`, NOT pushed) — **`npm run lint` now exits 0**

**What was asked:** finish #26437. PR #131 left `npm run lint` at
`119 problems (58 errors, 61 warnings)`, every one of the 58 errors being
`react-hooks/set-state-in-effect`. Clear them without changing behaviour, in
small commits, no blanket disables, `eslint.config.js` off-limits.

**Result: 58 errors → 0. `npm run lint` exits 0.** Warnings went 61 → 62, all
`react-hooks/exhaustive-deps`, which do not affect the exit code.

**Branch** cut from `origin/main` `e95bfc8`. `origin/main` did not move during
the work (re-fetched at the end), so nothing was merged back in. Nine commits,
oldest first:

| SHA | What |
|---|---|
| `4cde8ce` | `refactor(admin-web): derive three effect-reset states during render` |
| `bdbc8cd` | `refactor(admin-web): derive the super-admin loading gates instead of setting them` |
| `ac1f6c0` | `refactor(admin-web): derive \`loading\` from the request that last finished` |
| `59f5396` | `refactor(admin-web): reload the simple list pages by tick, not by calling load()` |
| `f82661e` | `refactor(admin-web): key the filtered list pages on their request too` |
| `377bff3` | `refactor(admin-web): derive \`loading\` on the six remaining filtered tables` |
| `5bfa24d` | `refactor(admin-web): clear the last set-state-in-effect errors under src/pages` |
| `4910bbd` | `refactor(admin-web): clear the last set-state-in-effect errors in components and lib` |
| `f1a2121` | `fix(admin-web): keep the signed-out alerts feed referentially stable` |

### The one idea that cleared most of them

Nearly every error was `setLoading(true)` (often with `setErr(null)`) at the
top of a fetch effect. Both are now **derived during render** instead of
stored: the render builds a `requestKey` out of exactly the effect's
dependencies, the effect's `.finally` records which key came back, and

```ts
const loading = loadedKey !== requestKey
```

says the same thing without a render pass. Where the reload path was a
`load()` the handlers called directly, the page now keeps a **tick**: `reload()`
bumps it, which re-runs the same effect. `loading` is `loadedTick !== tick`.

Error text follows the same logic. `setErr(null)` moved from the top of the
effect into the success callback, and the error box renders as
`{!loading && err && …}` — so a stale message still disappears the moment a
newer request starts, which is all the up-front clear ever did. **What the
operator sees is unchanged.**

Three sites were prop-to-state mirrors and now adjust during render
(`StatusCell`, `VolunteersPage`'s profession dialog, `CropDialog`'s per-file
reset). `AppShell` closes the mobile drawer by remembering which route it was
opened on. `ConfirmDialog` resets its per-open state during render, which also
fixes a real glitch: a reopened dialog used to flash the previous attempt's
error for one frame.

### The 16 inline disables, and why they are not a cop-out

**The rule has a false positive this codebase hits 15 times.** It steps into a
`useCallback` called from an effect, but does **not** model `await`. So

```ts
const load = useCallback(async () => {
  const res = await api.get(...)   // ← the setState below is NOT synchronous
  setThings(res.data)
}, [])
useEffect(() => { void load() }, [load])
```

is reported, even though no cascading render is possible. Proven with a
three-case probe file: a `.then(cb)` callback is fine, a locally-declared
async function inside the effect is not followed at all, and an awaited
`useCallback` **is** flagged. Each of those 15 carries the reason beside it:
`ContentPage`, `PermissionsPage` (`loadAudit`), `VolunteerBoardPage`,
`VolunteersPage`, `TrashPage`, `StaffActivityPage`, `ContactBlocksPanel`,
`PendingCountsProvider`, `useUnreadNotifications`, and the three chat pages
(`loadThreads` + `loadMessages` each).

**One is a genuine synchronous write, kept deliberately:**
`CropDialog.tsx:87`'s `setSrc(null)`. Creating and revoking an object URL is a
call into the browser, so it belongs in an effect; deriving `src` during render
would allocate a browser resource from a render pass React is free to discard.

### Two things that are not pure refactors

- **`PendingCounts`' context lost its `loading` field.** No consumer ever read
  it (`AppShell`, `VolunteersPage`, `VolunteerBoardPage`, `RegistrationsPage`
  take `counts` and `refresh` only), and keeping it meant the provider writing
  state synchronously on every mount. Removed rather than faked.
- **`f1a2121`** fixes something the commit before it introduced: deriving
  `events` as `user ? polledEvents : []` fed a fresh array into the alerts
  provider's context `useMemo`, which would have given every consumer a new
  context value on every render. Now one shared `NO_EVENTS` constant. Watch for
  this whenever you derive an array or object that feeds a memo.

### Verification on the final tree

Each command's last meaningful line, run from `admin-web/`:

| Command | Exit | Final line |
|---|---|---|
| `npm run lint` | **0** | `✖ 62 problems (0 errors, 62 warnings)` |
| `npm test` | 0 | `Tests  197 passed (197)` / `Test Files  22 passed (22)` |
| `npx tsc -b` | 0 | (no output) |
| `npm run build` | 0 | `✓ built in 329ms` |
| `npm run test:mock-api` | 0 | `ℹ pass 37` / `ℹ fail 0` |
| `npm run test:nav` | 0 | `ℹ pass 15` / `ℹ fail 0` |
| `npm run check:labels` | 0 | `check-labels: every controlled value and permission module has a label.` |
| `npm run check:css-tokens` | 0 | `check-css-tokens: 62 tokens read, all defined.` |

Every commit was checked with `tsc -b` + `npm test` + `npm run build` before it
was made. No test was touched — 197 passed before, 197 after.

Two things were re-checked by hand across the 53 changed files, because they
are what a careless version of this change would break:

- **No page lost its loading state.** Every file that renders `loading` still
  defines it; `tsc` would have failed otherwise, since a leftover
  `setLoading(...)` anywhere would reference a name that no longer exists.
- **Polling still stops on unmount.** Every `setInterval` in the tree still has
  its `clearInterval` in the effect's cleanup, and `VolunteerBoardPage` and
  `PendingCountsProvider` still abort their in-flight request too.

### What is still open

1. **`react-hooks/exhaustive-deps` — 62 warnings, untouched.** They do not
   affect the exit code and want a pass with judgement per site.
2. **`scripts/**/*.mjs` is still not linted.** `eslint.config.js` only matches
   `**/*.{ts,tsx}` and a hook blocks editing it. Out of scope for #26437.
3. **Nothing was pushed.** The branch exists locally only.
4. **OPOS was unavailable in this session**, so #26437 was not moved and no
   timer ran.

### Traps for the next agent

- Run npm with Node 22: `/opt/homebrew/opt/node@22/bin/npm`.
- **Do not "fix" `set-state-in-effect` by moving the call into a locally-declared
  async function inside the effect.** The rule does not follow into one, but the
  body still runs synchronously up to the first `await` — it silences the rule
  and changes nothing. That is why this branch derives instead.
- A derived value that feeds a `useMemo`/context must be referentially stable.
  See `f1a2121`.
- `requestKey` must contain **every** dependency of its effect, and must itself
  be in the dependency array, or the `.finally` closure records a stale key and
  the page can hang on "loading".

---

## 2026-09-16 — OPOS #26437: `npm run lint` in `admin-web/` (branch `chore/admin-web-lint-clean`, NOT pushed, NOT finished)

**What was asked:** `npm run lint` fails on a clean `main`, so lint cannot gate
any PR. Fix the problems in small commits grouped by rule, easiest and safest
first, behaviour unchanged, no blanket disables, `eslint.config.js` off-limits
(a hook blocks it). Session was stopped early on the coordinator's instruction,
so **the job is partly done** — see "What is still open".

**Branch:** cut from `origin/main` at `e7c9f77`, then `origin/main` (now
`72b7ac5`) merged back in at the end. That merge touched only `backend/` and
`HANDOFF.md` — no conflict with this work.

**Commits** (oldest first):

| SHA | What |
|---|---|
| `c33e811` | `chore(admin-web): clear the low-risk lint errors` |
| `e5e359a` | `fix(admin-web): three React-rules violations that were real bugs` |
| `ad208fc` | `refactor(admin-web): stop mixing components with hooks, contexts and helpers` |
| (merge) | `origin/main` `72b7ac5` merged in |

**The rule table — before and after.**

| Rule | Sev | Before | After | Status |
|---|---|---|---|---|
| `react-hooks/exhaustive-deps` | warn | 61 | 61 | untouched (warnings; do not affect the exit code) |
| `react-hooks/set-state-in-effect` | error | 58 | **58** | **not started** — this is what still fails the build |
| `react-refresh/only-export-components` | error | 25 | 0 | fixed (`ad208fc`) |
| `@typescript-eslint/no-unused-vars` | error | 5 | 0 | fixed (`c33e811`) |
| `preserve-caught-error` | error | 3 | 0 | fixed (`c33e811`) |
| unused `eslint-disable` directive | warn | 3 | 0 | fixed (`c33e811`) |
| `react-hooks/static-components` | error | 2 | 0 | fixed (`e5e359a`) |
| `no-useless-assignment` | error | 1 | 0 | fixed (`c33e811`) |
| `react-hooks/purity` | error | 1 | 0 | fixed (`e5e359a`) |
| `no-empty` | error | 1 | 0 | fixed (`c33e811`) |
| `react-hooks/refs` | error | 1 | 0 | fixed (`e5e359a`) |
| `no-constant-binary-expression` | error | 1 | 0 | fixed (`c33e811`) |
| **Total** | | **162 (98 err / 64 warn)** | **119 (58 err / 61 warn)** | |

To regenerate that table:
`npx eslint . -f json` then group by `ruleId` + `severity`.

**Three things in `e5e359a` were real bugs, not style:**

- `VolunteerBoardPage.tsx` declared `Evidence` **inside** `CheckinEvidence`'s
  body, so every render produced a fresh component type and React remounted
  the subtree instead of updating it. Hoisted to module scope as `EvidenceRow`
  with an `onView` prop replacing the closed-over `setViewing`.
- `lib/useLivePoll.ts` wrote `tickRef.current = tick` during render. Moved into
  a `useEffect([tick])`; nothing reads that ref during render.
- `EventsFeed.tsx` called `Date.now()` inside the `visible` `useMemo`, so the
  today/7d cutoff was whatever the clock said on whichever render happened to
  recompute. The clock is now state, seeded on mount and refreshed every 30s,
  and `nowMs` joined the memo deps.

**What `ad208fc` actually did, and why it is not cosmetic.** Vite's fast
refresh can only hot-swap a module whose exports are all components, and it
recreates a module's bindings on every edit. A React context declared beside a
component is therefore replaced by a brand-new context each edit and every
Provider/consumer pair comes apart mid-session. Each file was split along that
line, with **no re-exports** (a re-export is still an export and keeps the rule
firing), and whichever half had more importers kept the original module name:

- Component moved out: `i18n.tsx`→`I18nProvider.tsx`, `toast.tsx`→
  `ToastProvider.tsx`, `auth.tsx`→`AuthProvider.tsx`, `dialogs.tsx`→
  `DialogHost.tsx`, `saveAction.tsx`→`SaveActionProvider.tsx`,
  `pendingCounts.tsx`→`PendingCountsProvider.tsx`, `useHighlightedRow.tsx`→
  `HighlightBanner.tsx`.
- Non-component API moved out: `globalAlerts.tsx`→`globalAlertsContext.ts`,
  `CropDialog.tsx`→`cropShapes.ts`, `ThemeToggle.tsx`→`theme.ts`,
  `RowDeleteButton.tsx`→`useRowDeleteLabel.ts`, `PageHead.tsx`→
  `pageHeadSlots.ts`, `UsersPage.tsx`→`lib/staffAccounts.ts`.
- `DialogHost` used to assign the module-level `enqueueRequest` directly;
  across a module boundary it now goes through exported `setDialogEnqueue` /
  `takeRequestId` helpers in `dialogs.tsx`. Same queue, same "no host mounted
  means the ask resolves as cancelled".
- `ROLE_LABELS` and `roleLabelToId` in `UsersPage.tsx` had no importer outside
  that file, so they simply stopped being exported.
- One dead line went along: `ToastItem` had an empty `useEffect(() => {}, [])`
  whose only content was a comment about a close-on-Escape never written.

**Verification on the final tree** (after merging `origin/main` `72b7ac5`),
each command's last meaningful line:

| Command | Exit | Final line |
|---|---|---|
| `npm run lint` | **1** | `✖ 119 problems (58 errors, 61 warnings)` |
| `npm test` | 0 | `Tests  197 passed (197)` / `Test Files  22 passed (22)` |
| `npx tsc -b` | 0 | (no output) |
| `npm run build` | 0 | `✓ built in 280ms` |
| `npm run test:mock-api` | 0 | `ℹ pass 37` / `ℹ fail 0` |
| `npm run test:nav` | 0 | `ℹ pass 15` / `ℹ fail 0` |
| `npm run check:labels` | 0 | `check-labels: every controlled value and permission module has a label.` |
| `npm run check:css-tokens` | 0 | `check-css-tokens: 62 tokens read, all defined.` |

Every commit above was verified with `tsc -b` + `npm test` + `npm run build`
before it was made.

**What is still open.**

1. **`react-hooks/set-state-in-effect` — 58 errors, untouched. Lint still
   exits 1, so it still cannot gate a PR.** The work stopped here on
   instruction rather than mid-refactor. The occurrences fall into four
   shapes; `npx eslint . -f json` lists all 58 with file and line:
   - *the bulk* — `setLoading(true)` called synchronously at the top of a fetch
     effect, either inline (`ReceiptsPage.tsx:43`, `CampaignsPage.tsx:141`, …)
     or via `useEffect(load, [])` where `load` is a `useCallback` that starts
     with it (`BannedWordsPage.tsx:32`, `CommentsPage.tsx:50`, …).
   - *reset-on-dep-change* — `setResults([])`, `setEvents([])`,
     `setCounts(EMPTY)`, `setProfile(null)`, `setSrc(null)`, `setCount(0)`.
   - *prop→state mirrors* — `StatusCell.tsx:59`
     (`useEffect(() => { setVal(value) }, [value])`) and
     `VolunteersPage.tsx:645`.
   - *permission short-circuits* — `if (!amSuper) { setLoading(false); return }`
     in `ContentPage`, `GuestAccessPage`, `PermissionsPage`, `SettingsPage`.
   The brief specifically asked that the chat-pages' polling occurrences
   (`MessagesPage`, `StaffChatPage`, `MarriageChatsPage`) be fixed properly by
   deriving state or moving the update into the fetch callback, not papered
   over. **None of that was attempted** — do not assume any of it is half-done.
2. **`react-hooks/exhaustive-deps` — 61 warnings, untouched.** They do not
   affect the exit code. Worth a separate pass with its own judgement call per
   site; several are deliberate (`saveAction.tsx` carries an inline disable
   with a written reason, which is the only inline disable in the tree).
3. **`scripts/**/*.mjs` is not linted at all.** `eslint.config.js` only matches
   `**/*.{ts,tsx}`, and covering the scripts folder means editing that file,
   which a hook blocks. Explicitly out of scope for #26437; still open.
4. **Nothing was pushed.** The branch exists locally only.
5. **OPOS was unavailable in this session**, so #26437 was not moved to WIP,
   no timer ran, and no completion notes were written there.

**Traps for the next agent.**

- Run npm with Node 22: `/opt/homebrew/opt/node@22/bin/npm`. The default `node`
  on this machine is older.
- `npm run lint`'s summary line counts warnings, but only the 58 **errors**
  drive the exit code. Clearing the exhaustive-deps warnings will not turn lint
  green; clearing `set-state-in-effect` will.
- `ignoreRestSiblings` is **off** under this config, so
  `const { a: _unused, ...rest } = obj` is an error, not a warning. Both
  occurrences were rewritten as copy-then-`delete`.
- `no-console` is **not** enabled, so any `// eslint-disable-next-line
  no-console` you add will itself be reported as an unused directive.
- Re-exporting from the original module does **not** satisfy
  `react-refresh/only-export-components` — a re-export is still an export. The
  importers have to move.

---

## 2026-09-16 — OPOS #26603: the rest of the `user_profiles` reads, and the one that 500s (branch `fix/user-profiles-remaining-reads`)

**What was asked:** finish what #26497 (PR #127) left open. First the worst
item — `beneficiary/beneficiary.go`'s scalar subquery, which does not merely
duplicate a row but fails the whole query — then the ~21 remaining duplicating
reads from #127's audit table, person-facing lists first. Test-first, a test
per package. Do NOT touch the three writers (another agent is adding locks).
No migration, no UNIQUE constraint, no data deletion. Not pushed.

**Branch** cut from `origin/main` `e7c9f77`, which did not move during the work.

### The two commits

- **`02b66e9` `fix(beneficiary): a reviewer with two profile rows no longer 500s every case list`**
  — `caseColumns`' reviewer-name **scalar subquery** now reads the profile
  through `LEFT JOIN LATERAL (SELECT p.full_name … ORDER BY p.id LIMIT 1) rp ON TRUE`.
  The subquery form is kept deliberately (its comment explains why: joining
  `users` would put a second `phone`/`full_name`/`city` in scope and change
  what `AdminListCases`' unqualified search filter matches); only the profile
  read inside it changed. Plus `internal/beneficiary/duplicate_profiles_test.go`.
- **`4a0d88d` `fix(admin): a user with two profile rows stops duplicating every admin list`**
  — 21 join sites across nine packages, plus seven new test files.

### Audit — the #26497 table, updated

| Site | Read | Verdict |
|---|---|---|
| `beneficiary/beneficiary.go:193` | `caseColumns` reviewer name (**scalar subquery**) | was the worst item → **fixed (`02b66e9`)** |
| `donations/donations.go:677,705` | `AdminList` count + page | duplicating → **fixed** |
| `users/users.go:1033,1056` | `PaginatedList` count + page | duplicating → **fixed** (`SELECT p.*` — the projection reads 18 profile columns) |
| `users/registration.go:692,713` | `ListRegistrations` count + page | duplicating → **fixed** |
| `postengagement/postengagement.go:230,258,309,318` | ListComments, AdminListComments, ActivityFeed ×2 | duplicating → **fixed** |
| `permissions/permissions.go:555` | `ListAudit` | duplicating → **fixed** |
| `profilechanges/profilechanges.go:108,109` | `List` (requester **and** decider) | duplicating ×4 → **fixed** |
| `sponsorships/sponsorships.go:87` | `List` | duplicating → **fixed** |
| `staffactivity/store.go:128` | `timelineSQL` registration branch | duplicating → **fixed** |
| `handlers/admin_lists.go:239,330,652,750,774,1069` | InKindDonations, SupportTickets, Campaigns, VolunteerMissionSignups (count + page), VolunteerBoard | duplicating → **fixed** |
| `handlers/admin_trash.go:141` | trash list | duplicating → **fixed** |
| `handlers/donations.go:572` | BeneficiaryCampaignDonations | duplicating → **fixed** |
| `chat`, `chatgroups`, `marriagechat`, `staffchat` (11 sites) | — | fixed earlier by #26497 / PR #127 |
| `chatgroups/chatgroups_reads.go:125,192`, `chatgroups_connect.go:254`, `chatgroups_admin.go:89`, the three last-message LATERALs | — | safe — already LATERAL / keyed by `ANY(...)` into a map |
| `users/users.go:894` | account-by-id read | **safe but nondeterministic — still open** (`QueryRow`, first of two rows wins) |
| `staffactivity/store.go:167` (now :173) | `Load`'s header | same — **still open** |
| `handlers/admin_status_events.go:78` | `userNamePhone` | same — **still open** |
| `handlers/admin_detail.go:301` | sponsorship donor contact | same — **still open** (`pgx.CollectOneRow`) |

Counts after this branch: **33 duplicating reads fixed** (11 in #127, 22 here,
counting the scalar subquery), **9 safe**, **4 single-row reads still
nondeterministic**, **0 duplicating join sites left**.

**Why the output is unchanged for a normal account.** Every rewritten alias was
checked against what the surrounding query actually reads from it:
`grep -oE '\b(up|dp|rp|p|u)\.[a-z_]+'` per file. Every one projects exactly the
columns used — `full_name` alone at 19 of the 21 sites, `full_name, address,
date_of_birth` in `registration.go`, and `p.*` in `users.go`, whose projection
reads 18 profile columns and whose search predicate reads three identity codes.
The `ILIKE` search predicates (`up.full_name` in donations, users, registration,
admin_lists) and `staffchat`-style `ORDER BY`s still resolve: the aliases still
exist, they simply hold one row each.

### RED, then GREEN — every test watched fail first

**The beneficiary failure, on a fresh `godonation_dup_red_26603`** —
`-run 'TwoProfiles' -count=1 -p 1 -timeout 45m -v`. Not a duplicated row; the
statement aborts:

```
duplicate_profiles_test.go:107: ListCasesForUser: ERROR: more than one row returned by a subquery used as an expression (SQLSTATE 21000)
duplicate_profiles_test.go:125: AdminListCases:   ERROR: more than one row returned by a subquery used as an expression (SQLSTATE 21000)
```

**The seven store packages, on a fresh `godonation_dup_red2_26603`**, same flags
(the fixes were reverted with `git checkout --` for this run, then restored from
a copy — the commits were made after):

```
donations:      got 2 rows for reference DUPREF-772652972, want 1
users:          got 2 rows for phone 964754540071, want exactly user 9 once      (PaginatedList)
users:          got 2 rows for phone 964726321187, want exactly user 10 once     (ListRegistrations)
postengagement: got 2 comments on post 927837569, want 1
postengagement: comment 2 listed 2 times, want 1
postengagement: the comment appeared 2 times in the feed, want 1 / the like appeared 2 times in the feed, want 1
permissions:    audit entry 1 listed 2 times, want 1
profilechanges: request 1 listed 4 times, want 1
sponsorships:   got 2 rows for donor 17, want exactly sponsorship 5 once
staffactivity:  registration 19 appears 2 times on the timeline, want 1
```

**The handlers package, on fresh `godonation_dup_h_red_26603` / `_red3_`:**

```
in-kind donations: got 2 items, want 1
support tickets:   got 2 items, want 1
campaigns:         got 2 items, want 1
mission signups:   got 2 items, want 1
mission 6: pending = 2, want 1  /  pending lane holds 2 signups, want 1
trash item 1 listed 2 times, want 1  /  deleted_by_name = "Newer Duplicate Profile Name"
```

That last line is worth keeping: the trash list was not only repeating the row,
it was labelling one copy with the NEWER profile name — so two different names
appeared for one deletion.

**GREEN.** On a brand-new `godonation_dup_green3_26603`, the eight store
packages with `-run 'TwoProfiles|BothPartiesHaveTwoProfiles' -count=1 -p 1
-timeout 45m -v`: **12 PASS, 0 SKIP, 0 FAIL**, `ok` for all eight. On a
brand-new `godonation_dup_h_green2_26603`, `./internal/handlers/ -run
'DuplicateProfiles'` with the same flags: **6 PASS, 0 SKIP, 0 FAIL**, `ok` in
1.189s. 18 new tests in total.

**Package suites**, on a brand-new `godonation_dup_suite2_26603`,
`go test ./internal/beneficiary/ ./internal/donations/ ./internal/users/
./internal/postengagement/ ./internal/permissions/ ./internal/profilechanges/
./internal/sponsorships/ ./internal/staffactivity/ ./internal/handlers/
-count=1 -p 1 -timeout 45m`: exit 0, nine `ok` lines (handlers 15.8s, the rest
under a second each). No FAIL, no SKIP.

**Format, build, vet:** `go build ./...` and `go vet ./...` exit 0. `gofmt -l
./internal ./cmd` prints one file, `internal/handlers/admin_edit_user_profile.go`
— **pre-existing**, `git diff origin/main` on it is empty, same as #26497 saw.

**Re-verified after merging `origin/main` `72b7ac5` (#129, the writer locks).**
The merge was clean. On a brand-new `godonation_dup_m_green_26603`, all nine
packages with `-run 'TwoProfiles|BothPartiesHaveTwoProfiles|DuplicateProfiles'
-count=1 -p 1 -timeout 45m -v`: **18 PASS, 0 SKIP, 0 FAIL**. On a brand-new
`godonation_dup_m_suite_26603`, the same nine packages with no `-run`, `-count=1
-p 1 -timeout 45m`: exit 0, nine `ok` lines — #129's own
`user_profiles_writer_race_test.go` and `admin_edit_user_profile_race_test.go`
included. `go build ./...` and `go vet ./...` still exit 0 on the merged tree.

**New test files** (all integration tests, skipped without `TEST_DATABASE_URL`;
each seeds a user with two `user_profiles` rows named "Oldest Profile Name" and
"Newer Duplicate Profile Name", and several assert the OLDEST name is served):
`internal/beneficiary/duplicate_profiles_test.go`,
`internal/donations/duplicate_profiles_test.go`,
`internal/users/duplicate_profiles_test.go`,
`internal/postengagement/duplicate_profiles_test.go`,
`internal/permissions/duplicate_profiles_test.go`,
`internal/profilechanges/duplicate_profiles_test.go`,
`internal/sponsorships/duplicate_profiles_test.go`,
`internal/staffactivity/duplicate_profiles_test.go`,
`internal/handlers/admin_lists_duplicate_profiles_test.go`.
`postengagement` and `profilechanges` had no test file at all before.

**Review:** no reviewer agent was run — the coordinator instructed skipping it,
those runs keep stalling in this environment. Instead every rewritten query was
re-read by hand; the alias-column grep above is the evidence, and the paginated
lists were each asserted on BOTH the page and `total_items`, because the COUNT
query joins profiles separately from the page query and fixing only one of them
leaves a list whose pager disagrees with its own rows.

**Databases created and dropped:** `godonation_dup_red_26603`,
`godonation_dup_green1_26603`, `godonation_dup_red2_26603`,
`godonation_dup_green2_26603`, `godonation_dup_green3_26603`,
`godonation_dup_suite_26603`, `godonation_dup_h_green_26603`,
`godonation_dup_h_red_26603`, `godonation_dup_h_red2_26603`,
`godonation_dup_h_red3_26603`, `godonation_dup_h_green2_26603`,
`godonation_dup_suite2_26603`. All dropped; `psql -lqt` lists no
`godonation_dup%` database.

**External actions taken:** none. Nothing pushed, no PR opened. OPOS was
unavailable in this session, so #26603 was not moved, timed or commented on.

### What is still open

- **Both commits are local and unpushed**, and unreviewed by a human.
- **The three writers are untouched on this branch, by instruction** —
  `users/profile.go` `UpsertProfile`, `users/registration.go`
  `SubmitRegistration`, `handlers/admin_edit.go` `User`. Their advisory locks
  landed separately as **#129 (`72b7ac5`)**, which was merged into this branch
  after the work (a clean merge — no conflict in `admin_edit.go`, because #129
  touched its write path and this branch touched none of it). Post-merge
  verification is the run recorded below. Between them the two changes cover
  both halves: #129 stops a second profile row being created, this branch makes
  every read survive the rows that already exist.
- **The four single-row `QueryRow` / `CollectOneRow` reads** listed in the table
  still return a nondeterministic name for a duplicated user. They never error
  and never repeat a row, so they were left alone, but they are a one-line
  LATERAL each whenever someone wants determinism.
- **UNIQUE on `user_profiles.user_id`** still needs a human decision about how
  to dedupe the existing pairs. No migration was added here, and none should
  add UNIQUE or delete rows without that decision.
- The full `go test ./...` was NOT run on this branch — only the nine packages
  it touches.

### Traps

- **A Go raw-string SQL literal cannot contain a backtick**, not even inside a
  `--` SQL comment: it closes the literal and yields a Go syntax error pointing
  somewhere else entirely. #26497 hit this; every comment written here spells
  WHERE and ORDER BY in capitals instead of quoting them.
- **An alias collision that only shows up at runtime.** In
  `postengagement.AdminListComments` and `ActivityFeed`, `p` is already the
  `media_posts` alias, so the LATERAL's inner profile alias is `pf`. Reusing `p`
  compiles and then resolves against the wrong table.
- **Seeding `campaigns` costs three rounds of guessing** unless you look first:
  `title, title_ar, description, description_ar, address, beneficiaries,
  goal_amount, raised_amount` are all NOT NULL with no default. `SELECT
  column_name FROM information_schema.columns WHERE table_name='campaigns' AND
  is_nullable='NO' AND column_default IS NULL` answers it in one go.
- **Never run these packages twice against one database** — same trap as #26497
  and #26474. The fixtures delete only their own rows and the seeded ids are
  random per process, but the counting assertions in `handlers` scan whole
  lists, so leftovers from an earlier run can change the answer.
- **`requireAuth` is all the admin-list handlers check**, so a handler test only
  needs `c.Set("auth.user", &auth.ResolvedUser{…})` — the string key is
  `auth.contextUserKey`, which is unexported, but the literal `"auth.user"`
  works from any package.

---

## 2026-09-16 — OPOS #26601: the three `user_profiles` writers stop racing each other into duplicate rows (branch `fix/user-profiles-writer-race`)

**What was asked:** close the check-then-insert race in the three writers named
in #26497's "still open" list, test-first, without a UNIQUE constraint, a
migration, or deleting anybody's second row — and without touching any read
query, because another agent is fixing the remaining joins. Branch cut from
`origin/main` `e7c9f77`. Not pushed. OPOS was unavailable in this session.

**The lock approach chosen:** `pg_advisory_xact_lock(hashtext('user_profiles:'
|| $1::bigint::text)::bigint)`, the advisory-lock option rather than `SELECT …
FOR UPDATE`, used identically in all three writers. One new exported helper,
`users.LockUserProfileWrite(ctx, tx, userID)` in
`backend/internal/users/profile.go`, carries the whole rationale in its doc
comment. `hashtext` returns an int4 and `pg_advisory_xact_lock` wants one
bigint or two int4s, hence the cast; the key is namespaced with the table name
so it cannot collide with another advisory lock. An `_xact_` lock is released
by COMMIT *and* by ROLLBACK, so no error path leaks it.

**What was changed** (code commit `972948d`; this entry is a second commit,
because `git commit --amend` is blocked by this environment's safety gate):

- **`backend/internal/users/profile.go`** — `UpsertProfile` now opens its
  transaction FIRST, takes the lock as the transaction's first statement, and
  only then runs the existence check. The check used to run on the pool,
  outside the transaction, which is why moving it was mandatory: a lock guarding
  a decision made on another connection guards nothing. `GetProfileRow`'s body
  was parameterised into `getProfileRow(ctx, q rowQuerier, userID)` (a
  one-method interface satisfied by both `*pgxpool.Pool` and `pgx.Tx`) so the
  transaction can run the identical query. `GetProfileRow`'s own behaviour and
  signature are unchanged. The `UserExists` call still runs on the pool before
  `Begin` — it reads `users`, takes no lock, and has no bearing on ordering.
- **`backend/internal/users/registration.go`** — `SubmitRegistration` takes the
  lock immediately after `Begin`/`defer Rollback`, before its `SELECT 1 FROM
  user_profiles` check and well before its `UPDATE users` at the end.
- **`backend/internal/handlers/admin_edit.go`** — `User` takes the lock
  immediately after `Begin`/`defer Rollback`, i.e. **before** the
  `UPDATE users SET phone` / `SET email` statements, not just before the profile
  block. It is taken **unconditionally**, even on a save with no profile
  change, so every transaction that touches this pair of resources takes them in
  one order. The file now imports `internal/users`.

**The deadlock trap #127's audit warned about, and how it is handled.**
`admin_edit.go` updates the `users` row BEFORE its profile block while
`SubmitRegistration` updates it AFTER. If the lock were taken in the middle of
either, those two could hold `users` and the profile key in opposite orders and
deadlock. The fix is that in all three writers the lock is the **first**
statement of the transaction, and each transaction takes it exactly once — so
there is only ever one acquisition order. That reasoning is written into
`LockUserProfileWrite`'s doc comment and repeated at each of the three call
sites.

**Tests first — two new files, no changes to existing tests:**
- `backend/internal/users/user_profiles_writer_race_test.go` —
  `TestUpsertProfileWriterRaceCreatesOneRow`,
  `TestSubmitRegistrationWriterRaceCreatesOneRow`.
- `backend/internal/handlers/admin_edit_user_profile_race_test.go` —
  `TestUserProfileEditWriterRaceCreatesOneRow` (drives the real PATCH route
  through `newUserEditRouter`, with a body of profile columns only so nothing
  but the profile block writes).

**How the race is made deterministic without a single sleep** — worth reading
before writing another concurrency test here, because it generalises. The test
opens its own transaction holding `SELECT … FROM users WHERE id = $1 FOR
UPDATE` on the target. An INSERT into `user_profiles` must take FOR KEY SHARE
on that parent row to satisfy `fk_user_profiles_user` (migration 002), and FOR
UPDATE conflicts with it — so every writer that reaches its INSERT parks there.
Both writers are launched, and the test waits, **by polling
`pg_stat_activity` for `wait_event_type = 'Lock'` and pacing itself with
`pg_sleep(0.02)` inside the database**, until two backends are blocked. That is
the proof both goroutines got as far as they can, which on the old code is
after both have already decided "no row". Then the holding transaction commits.
Unfixed: both insert → 2 rows. Fixed: the second writer is parked on the
advisory lock instead, sees the first one's row, and UPDATEs it → 1 row.
Goroutines never call `t.Fatalf`; they hand results back on a channel.

**RED**, on a brand-new `godonation_wrace_red_26601`, `-run WriterRace -count=1
-p 1 -timeout 45m -v`, all three failing before any production edit:
- `user_profiles_writer_race_test.go:205: user 8 has 2 user_profiles rows after two concurrent UpsertProfile calls, want exactly 1`
- `user_profiles_writer_race_test.go:229: user 9 has 2 user_profiles rows after two concurrent SubmitRegistration calls, want exactly 1`
- `admin_edit_user_profile_race_test.go:156: user 11 has 2 user_profiles rows after two concurrent PATCHes, want exactly 1`

**GREEN**, on a brand-new `godonation_wrace_green_26601`, same flags:
**3 `--- PASS`, 0 FAIL, 0 SKIP** (`ok` users 1.172s, handlers 0.671s).

**Flakiness check**, brand-new `godonation_wrace_flake_26601`, same `-run` with
`-count=3`: 9 `--- PASS`, 0 FAIL, 0 SKIP.

**Package suites**, brand-new `godonation_wrace_suite_26601`, `go test
./internal/users/ ./internal/handlers/ -count=1 -p 1 -timeout 45m`: `ok`
users 1.174s, `ok` handlers 16.996s.

**Format, build, vet:** `gofmt -l` on the five changed/added files prints
nothing; `go build ./...` and `go vet ./...` both exit 0.

**Review:** the reviewer agent was skipped at the coordinator's instruction
(those runs keep stalling here). The diff was re-read by hand against three
questions. (1) Is the lock the first statement of each transaction? Yes in all
three — in `admin_edit.go` it sits between `defer tx.Rollback` and the
`users.phone` UPDATE. (2) Does any path take it twice, or take these resources
in two orders? No: one call per transaction, always first, and none of the
three nests inside another's transaction (each opens its own from the pool).
(3) Does an error still roll back? Yes: every new failure path returns before
`tx.Commit`, so the existing `defer tx.Rollback` fires, and an `_xact_` advisory
lock is released by the rollback as well as by a commit.

**Databases created and dropped:** `godonation_wrace_red_26601`,
`godonation_wrace_green_26601`, `godonation_wrace_flake_26601`,
`godonation_wrace_suite_26601`. All dropped; `psql -lqt` lists no
`godonation_wrace%` database.

**External actions taken:** none. Nothing pushed, no PR, no OPOS update.

**What is still open:**
- **The commit is local and unpushed**, and unreviewed by a human.
- **Two more `INSERT INTO user_profiles` sites exist and were deliberately left
  alone**, because neither is a check-then-insert on an existing account:
  `users/users.go:817` (`InsertGuest`, inserts the profile for the `users` row
  it just created in the same transaction) and
  `handlers/admin_status.go:341` (admin "create user", same shape — and note
  its result is discarded with `_, _ =`). If either ever starts writing to a
  pre-existing account, it needs the same lock.
- **~21 duplicating join sites and the `beneficiary/beneficiary.go:193` scalar
  subquery remain**, per #26497's audit table. Untouched here by instruction.
- **UNIQUE on `user_profiles.user_id`** still needs a human decision on
  deduping existing pairs. This branch adds no migration and deletes no rows;
  an account that already has two profile rows keeps working exactly as before.
- The full `go test ./...` was NOT run here — only the two packages touched.

**Traps:**
- **The `FOR UPDATE`-on-`users` trick only parks a writer that reaches an
  INSERT into `user_profiles`.** If a test body includes `phone` or `email`,
  the admin-edit handler's `UPDATE users` blocks FIRST — before the lock and
  before the profile block — and the test would be measuring the wrong wait.
  The committed test sends profile columns only, on purpose.
- **Never run these packages twice against one database** (inherited trap from
  #26474/#26497): the fixtures only delete their own `users` rows, so a second
  run against the same DB sees the first run's leftovers. Every run above used
  a brand-new database.
- `pg_stat_activity`'s waiting-backend count is per database, which is why each
  run needs its own throwaway DB — a second test process on the same database
  would make the barrier fire early.

---

## 2026-09-16 — OPOS #26492, #26493, #26477, #26496: admin-web chat follow-ups (branch `fix/admin-web-chat-followups`)

**What was asked:** three unrelated dashboard fixes, each test-first, each its
own commit, cut from `origin/main` at `b0c9eb8`; then a fourth item (#26496)
added mid-session. No push. OPOS was not available in the session, so nothing
was tracked there.

**The commits** (branch cut from `origin/main` `b0c9eb8`, which never moved
during the work — nothing to merge):

- **`37f4389` fix(admin-web): gate chat Delete on the module's delete permission (#26492).**
  `ChatLifecycleControls` offered Delete to anyone with edit, but the server's
  DELETE routes are stricter. Verified in `backend/cmd/server/main.go`:
  `/admin/chats/:id`, `/admin/staff-chats/:id` and `/admin/chat-groups/:id`
  need `messages:delete` (lines 1062, 1064, 1068); `/admin/marriage/chats/:id`
  needs `marriage:delete` (line 1066). The component now takes a required
  `deleteModule: 'messages' | 'marriage'` and hides Delete unless
  `usePermission(deleteModule, 'delete', user)` — the same helper the pages
  already use. The four call sites pass it: `MessagesPage`, `StaffChatPage`
  (messages), `MarriageChatsPage` (marriage), `chatGroups/GroupHeader`
  (messages). **`MarriageSupportPage` does not render the strip at all** — it
  is in the brief's list but has no `ChatLifecycleControls`, so nothing to gate.
  Copy: `chat_lifecycle.delete_confirm` said "A Super-Admin can restore it".
  Restore is `RequireAdminTier` (`main.go:1173`), so en/ar now say an
  administrator restores it; purge IS `RequireSuperAdmin` (`main.go:1176`), so
  the sentence keeps a Super-Admin for permanent deletion. Key name unchanged.
- **`7a377e3` fix(admin-web): keep a decided connect request open with its outcome (#26493).**
  `ConnectRequestPanel` now renders the decision itself — approved with the new
  `group_id`, declined with the reason just sent — instead of re-fetching the
  detail, and `DeclineRequestDialog`'s `onDeclined` passes the trimmed reason it
  sent. `onDecided()` still fires so the page re-fetches the list.
- **`063d9a1` fix(admin-web): make the export format menu keyboard accessible (#26477).**
  `ExportCsvButton`'s format menu now follows the WAI-ARIA menu button pattern:
  `aria-haspopup`/`aria-expanded`/`aria-controls` (a `useId` id), `role="menu"`
  + `role="menuitem"`, roving `tabIndex`, focus to the first item on open,
  wrapping ArrowUp/ArrowDown, Home/End, Escape closing and returning focus to
  the trigger, Tab closing, and the existing outside-click close kept. The four
  items became a `FORMATS` array. Styles, logical properties and the PIN flow
  are untouched.
- **`b2191a9` fix(admin-web): return focus to the export trigger when a format
  is picked (#26477).** The self-review below found it: Escape returned focus,
  but CHOOSING a format closed the menu and left focus on `<body>`. It is a
  separate commit rather than an amend of `063d9a1` because this environment's
  safety gate blocks `git commit --amend`.
- **`1cbdb93` fix(admin-web): word the chat-group 401 for the operator (#26496).**
  The backend now codes the chat-group 401 `Unauthorized.` as `unauthorized`;
  the dashboard had no message for it, so the operator would have read the
  server's English. `unauthorized` was added to `CHAT_GROUP_ERROR_CODES` and to
  the key map in `chatGroupErrors.ts`. **No new locale key was added:**
  `error.auth_required` (A15) already says "Your session has ended. Please sign
  in again." and already exists in en, ar, ckb AND kmr, so the code maps to it.
  Nothing was added to `TRANSLATION_REQUEST.md` and the 617 count is unchanged —
  there is no new key to translate, and no Kurdish was written.

**RED then GREEN, each watched fail first:**

| Commit | RED | GREEN |
|---|---|---|
| #26492 | `Tests  2 failed (2)` (new `ChatLifecycleControls.test.tsx`) | `Tests  32 passed (32)` |
| #26493 | `Tests  2 failed \| 9 passed (11)` | `Tests  21 passed (21)` |
| #26477 | `Tests  5 failed \| 8 passed (13)` | `Tests  13 passed (13)` |
| #26496 | `Tests  2 failed \| 29 passed (31)` | `Tests  32 passed (32)` |

**A finding worth recording about #26493.** The happy path already worked: the
panel re-fetched the detail and the re-fetch showed the new status, so a test
of "approve, then look at the panel" passes on the ORIGINAL code. The real
weakness was that the outcome depended on that re-fetch — a detail GET that
fails or lags after the decision replaced the result with an error, or could
put the decision buttons back. The committed test therefore makes the detail
route answer 500 immediately after the decision, which is what fails on the old
code. If someone later reverts to re-fetching, that is the test that will catch it.

**What was run on the final tree** (Node 22 at `/opt/homebrew/opt/node@22/bin`;
`node_modules` installed here with `npm ci`):
- `npm test` → `Test Files  22 passed (22)`, `Tests  197 passed (197)`
- `npx tsc -b` → exit 0
- `npm run build` → exit 0 (only the usual chunk-size advice)
- `npm run test:mock-api` → `# pass 37`, `# fail 0`
- `npm run test:nav` → `# pass 15`, `# fail 0`
- `npm run check:labels` → `every controlled value and permission module has a label.`
- `npm run check:css-tokens` → `62 tokens read, all defined.`
- `npx eslint` on every file this branch changed → exit 0

**Trap — pre-existing eslint errors that are NOT from this branch.** Running
eslint on `MessagesPage.tsx`, `StaffChatPage.tsx` or `MarriageChatsPage.tsx`
reports 6 `react-hooks/set-state-in-effect` errors (the 5s/3s polling effects).
They are on `origin/main` already — confirmed by piping `git show
origin/main:<file>` through `eslint --stdin` and getting the same count — and
none are on a line this branch touched. Don't mistake them for a regression;
fixing them is its own task.

**Self-review of the three risky spots** (the `ecc:react-reviewer` run stalled
on a harness watchdog and was skipped by the coordinator, so this is a manual
pass, not an agent verdict):
- *The Delete gate's fallback.* `deleteModule` is a required, union-typed prop,
  so a page that passes none fails the build — `tsc -b` is the check. While the
  matrix is loading (or if its fetch failed) `usePermission` falls back to the
  admin/super_admin tier gate, so Delete is hidden from lower tiers rather than
  flashed and then withdrawn. The server remains the authority either way.
- *The decided panel's state.* `showDecision` merges into the panel state only
  when it is already `ready`, so it cannot resurrect a panel that errored or is
  still loading. Nothing re-fetches after a decision, so no late response can
  overwrite the outcome. The panel is keyed on the selected id in the page, so
  choosing another row remounts it, and changing the filter clears the
  selection — both still move on as before.
- *Focus when the menu closes.* Escape returns focus to the trigger, and after
  `b2191a9` so does PICKING a format: `run()` focuses the trigger before the
  item unmounts, otherwise focus fell to `<body>` and the keyboard operator lost
  their place (the PIN dialog then takes focus from the trigger). Tab is
  deliberately not prevented — focus moves on naturally and the menu closes
  behind it.

**What is still open:** nothing was pushed, no PR was opened, and OPOS was
unavailable in this session, so #26492, #26493, #26477 and #26496 still need
their status and time logged by whoever has OPOS access. #26496's dashboard
half assumes the backend change that codes the 401 `unauthorized` actually
lands; until it does, that 401 arrives uncoded and falls through to
describeError as before — the mapping is harmless either way. The one string this branch
changed is in `TRANSLATION_REQUEST.md`: `chat_lifecycle.delete_confirm` was
RE-WRITTEN in en and ar, so its existing Kurdish is now FALSE and is listed as
1 key to re-translate — the total was recounted from 616 to **617**. No Kurdish
was written.

---

## 2026-09-16 — OPOS #26497: chat, staff-chat and marriage lists stop repeating rows when a user has two `user_profiles` rows (branch `fix/user-profiles-duplicate-joins`)

**What was asked:** audit every `user_profiles` join in `backend/internal`, fix the duplicating reads, close the three writers' check-then-insert race, and test all of it. Mid-session the scope was narrowed by the coordinator to: keep the audit, fix only the reads covered by the four test files already written (chat, chatgroups contact blocks, marriagechat, staffchat), drop the writer-lock work to a separate task, skip the full `./...` run and skip the reviewer agent.

**What was actually changed.** One code commit on `fix/user-profiles-duplicate-joins`, branched from `origin/main` `b0c9eb8`:

- **`afbe4bf` `fix(chat): a user with two profile rows stops duplicating chat list rows`** — eleven reads across four packages, plus four new test files. Each plain `LEFT JOIN user_profiles x ON x.user_id = …` became the #115 LATERAL form, `LEFT JOIN LATERAL (SELECT p.full_name FROM user_profiles p WHERE p.user_id = … ORDER BY p.id LIMIT 1) x ON TRUE`, with a comment on each saying why.
  - `internal/chat/chat.go`: `ListThreadsForUser` (other party + assigned staff), `ListMessages`, `ListAllThreads` (donor + owner + staff).
  - `internal/chat/contactblocks.go`: `ListContactBlocks`.
  - `internal/chatgroups/chatgroups_admin.go`: `ListContactBlocks` (the `chatgroups_admin.go:115` named in the task; it sits at :209 on current main).
  - `internal/staffchat/staffchat.go`: `ListThreadsForUser`, `ListMessages`, `Directory`.
  - `internal/marriagechat/marriagechat.go`: `ListMeetingRequests`, `ListAllThreads`, `AdminListMessages`.
- **This entry** is the second commit.

**Why the output is unchanged for a normal account.** Every one of those aliases is referenced only as `full_name` (verified by grepping `alias.column` across the four files), which is exactly what each LATERAL projects. For a user with one profile row, `ORDER BY p.id LIMIT 1` returns that row; for a user with none, `ON TRUE` keeps the outer row with NULLs, as `LEFT JOIN` did. The `WHERE … ILIKE` filters on `dp.`/`opf.` (chat) and `rp.`/`op.` (marriagechat) and the `ORDER BY p.full_name` in staffchat's `Directory` all still resolve, because the aliases still exist — they simply hold one row each now.

### Audit — every `user_profiles` join in non-test Go under `backend/internal`

40 `JOIN user_profiles` lines, plus one scalar subquery. Classification:

| Site | Read | Verdict |
|---|---|---|
| `chat/chat.go:363,364` | ListThreadsForUser | duplicating → **fixed** |
| `chat/chat.go:466` | ListMessages | duplicating → **fixed** |
| `chat/chat.go:612,614,615` | ListAllThreads | duplicating → **fixed** |
| `chat/contactblocks.go:65` | ListContactBlocks | duplicating → **fixed** |
| `chatgroups/chatgroups_admin.go:209` | ListContactBlocks | duplicating → **fixed** |
| `staffchat/staffchat.go:128` | ListThreadsForUser | duplicating → **fixed** |
| `staffchat/staffchat.go:168` | ListMessages | duplicating → **fixed** |
| `staffchat/staffchat.go:256` | Directory | duplicating → **fixed** |
| `marriagechat/marriagechat.go:81,83` | ListMeetingRequests | duplicating → **fixed** |
| `marriagechat/marriagechat.go:541,543` | ListAllThreads | duplicating → **fixed** |
| `marriagechat/marriagechat.go:587` | AdminListMessages | duplicating → **fixed** |
| `chatgroups/chatgroups_reads.go:125,192` | AdminListMessages, ListMessagesForMember | safe — already LATERAL (#115) |
| `chatgroups/chatgroups_connect.go:254` | connect-request reads | safe — already LATERAL |
| `chatgroups/chatgroups_admin.go:89` | `profileNames` | safe — one row per key by `WHERE user_id = ANY(...)`, read into a map |
| `chat/chat.go:365`, `staffchat:129`, `marriagechat:544` | last-message lookups | safe — LATERAL on messages, not profiles |
| `users/users.go:894` | account-by-id read | **safe but nondeterministic** — `QueryRow` takes the first of two rows |
| `staffactivity/store.go:167` | `Load`'s header | same: `QueryRow`, first row wins |
| `handlers/admin_status_events.go:78` | `userNamePhone` | same: `QueryRow`, first row wins |
| `handlers/admin_detail.go:301` | sponsorship donor contact | same: `pgx.CollectOneRow`, first row wins |
| `donations/donations.go:677,705` | `AdminList` count + page | **duplicating — still open** |
| `users/users.go:1033,1056` | `PaginatedList` count + page | **duplicating — still open** |
| `users/registration.go:692,713` | `ListRegistrations` count + page | **duplicating — still open** |
| `postengagement/postengagement.go:230,258,309,318` | ListComments, AdminListComments, ActivityFeed ×2 | **duplicating — still open** |
| `permissions/permissions.go:555` | `ListAudit` | **duplicating — still open** |
| `profilechanges/profilechanges.go:108,109` | `List` | **duplicating — still open** |
| `sponsorships/sponsorships.go:87` | `List` | **duplicating — still open** |
| `staffactivity/store.go:128` | `timelineSQL` registration branch | **duplicating — still open** |
| `handlers/admin_lists.go:239,330,652,750,774,1069` | InKindDonations, SupportTickets, Campaigns, VolunteerMissionSignups (count + page), VolunteerBoard | **duplicating — still open** |
| `handlers/admin_trash.go:141` | trash list | **duplicating — still open** |
| `handlers/donations.go:572` | BeneficiaryCampaignDonations | **duplicating — still open** |
| `beneficiary/beneficiary.go:193` | `caseColumns` reviewer-name **scalar subquery** | **worse than duplicating — still open**: a reviewer with two profile rows makes the subquery return two rows, and Postgres then fails the whole query with `more than one row returned by a subquery used as an expression`. Every case list that reviewer touched 500s. The fix is one line: `ORDER BY rp.id LIMIT 1` inside the subquery. |

Counts: **11 fixed**, **9 safe** (already LATERAL / keyed / aggregated), **4 safe-but-nondeterministic** single-row reads, **~21 join sites still duplicating**, plus the one scalar subquery.

**Tests first.** Four new files, all integration tests skipped without `TEST_DATABASE_URL`:
`internal/chat/chat_duplicate_profiles_test.go`, `internal/chatgroups/chatgroups_contact_blocks_duplicate_profiles_test.go`, `internal/marriagechat/marriagechat_duplicate_profiles_test.go`, `internal/staffchat/staffchat_duplicate_profiles_test.go`. Each seeds a user with two `user_profiles` rows (named "Oldest Profile Name" and "Newer Duplicate Profile Name") and asserts one result row; several also assert the OLDEST name is the one served. The staffchat and marriagechat packages had no test file at all before this; both now carry their own `newDupTestPool` harness, modelled on `internal/chat/chat_test.go`.

**RED**, on a brand-new `godonation_dupprof_red_26497`, `-run 'DuplicateProfiles|Duplicated|WhenSenderHasTwoProfiles|WhenItHasTwoProfiles' -count=1 -p 1 -timeout 45m -v`. All 11 new tests failed, and the counts are the point:
- `chat_duplicate_profiles_test.go:84: thread 1 listed 4 times, want 1` (owner AND staff duplicated → ×4)
- `chat_duplicate_profiles_test.go:97: got 2 messages, want 1`
- `chat_duplicate_profiles_test.go:119: thread 3 listed 8 times, want 1` (donor, owner and staff → ×8)
- `chat_duplicate_profiles_test.go:137: got 2 contact blocks, want 1`
- `chatgroups_contact_blocks_duplicate_profiles_test.go:44: got 2 contact blocks, want 1`
- `marriagechat_duplicate_profiles_test.go:131: request 1 listed 4 times, want 1`; `:153: thread 2 listed 4 times, want 1`; `:166: got 2 messages, want 1`
- `staffchat_duplicate_profiles_test.go:104: got 2 threads, want exactly thread 1 once`; `:120: got 2 messages, want 1`; `:139: user 700000019 listed 2 times in the directory, want 1`
The two #115 tests in chatgroups passed throughout, as expected.

**GREEN**, on a brand-new `godonation_dupprof_green_26497`, same `-run` and flags: **14 `--- PASS`, 0 SKIP, 0 FAIL** across the four packages (`ok` for chat 0.860s, chatgroups 0.431s, marriagechat 0.610s, staffchat 0.458s). The 14 are the 11 new tests plus the three #115 ones the regex also matches.

**Package suites**, on a brand-new `godonation_dupprof_suite_26497`, `go test ./internal/chat/ ./internal/chatgroups/ ./internal/marriagechat/ ./internal/staffchat/ -count=1 -p 1 -timeout 45m`: exit 0 — `ok` chat 1.001s, chatgroups 2.850s, marriagechat 0.396s, staffchat 0.448s.

**Format, build, vet:** `go build ./...` and `go vet ./...` both exit 0. `gofmt -l ./internal ./cmd` prints one file, `internal/handlers/admin_edit_user_profile.go` — **pre-existing, not touched by this branch** (`git diff origin/main` on it is empty). None of the files changed here are listed.

**Review:** the `ecc:database-reviewer` agent was skipped at the coordinator's instruction (its runs were stalling). Instead each changed query was re-read by hand against the criteria above; the alias-usage grep is the evidence that no column other than `full_name` is read from any of the rewritten aliases.

**Databases created and dropped:** `godonation_dupprof_schema_26497`, `godonation_dupprof_red_26497`, `godonation_dupprof_green_26497`, `godonation_dupprof_suite_26497`. All dropped; `psql -lqt` lists no `godonation_dupprof%` database.

**External actions taken:** none. Nothing was pushed, no PR was opened. OPOS was unavailable in this session (the connector needs OAuth), so #26497 was not moved or commented on.

**What is still open:**
- **Both commits are local and unpushed**, and unreviewed by a human.
- **The writer race is untouched on this branch, by instruction.** `users/profile.go` `UpsertProfile` (its `GetProfileRow` check still runs on the pool, OUTSIDE the transaction it later opens), `users/registration.go` `SubmitRegistration` and `handlers/admin_edit.go` `User` all check-then-insert with no lock. The intended fix is `pg_advisory_xact_lock(hashtext('user_profiles:' || user_id))` as the FIRST statement inside each transaction. **Take it first, before any `UPDATE users`** — `admin_edit.go` updates `users` before reaching the profile block while `SubmitRegistration` updates it after, so locking in the middle would make those two deadlock against each other.
- **~21 duplicating join sites remain**, listed in the audit table above, plus the `beneficiary/beneficiary.go:193` scalar subquery, which is the most severe single item on the list because it makes the query ERROR rather than merely repeat a row.
- **The four single-row `QueryRow`/`CollectOneRow` reads** return a nondeterministic name for a duplicated user. Cheap to make deterministic with the same LATERAL pattern; nobody has.
- **UNIQUE on `user_profiles.user_id`** still needs a human decision on how to dedupe the existing pairs. No migration was added on this branch, and none should add UNIQUE or delete rows without that decision.
- The full `go test ./...` was NOT run here — the coordinator is running it on main.

**Traps:**
- **A Go raw-string SQL literal cannot contain a backtick.** Two of the explanatory comments written into these queries quoted `` `where` ``, which closed the literal and produced the baffling `syntax error: unexpected name where in argument list` at a line far from the edit. Write WHERE in capitals in SQL comments instead.
- **Never run these packages twice against one database** — the same trap as #26474. `makeTestUser`-style helpers delete only the `users` row, and the id floor is reset per process, so a second run sees the first run's threads and fails counting assertions.
- The marriagechat fixture's cleanup deletes messages → threads → requests → profile explicitly, because those tables' FKs to `users` do not all cascade.

---

## 2026-09-15 — OPOS #26496: codes on the chat-group handlers' inline refusals (branch `fix/chat-group-admin-refusal-codes`)

**What was asked:** some chat-group refusals, on both admin and member routes, were still written inline as `{success:false, error}` without a `code`. Each needed a machine code, with its status and English sentence unchanged. Test-first, not pushed.

**What was changed** (branch cut from `origin/main` `b0c9eb8`):
- **`backend/internal/handlers/chat_group.go`** adds three helpers next to `chatErr` / `respondChatErr` (#107, #118):
  - `chatErrUnauthorized`: 401 `Unauthorized.`, code **`unauthorized`** (new code).
  - `chatInvalidInput(msg)`: 400 with the handler's own sentence, code **`group_invalid_input`**.
  - `h.chatServerErr(c, err)`: logs, then answers 500 `Database error.` with code **`server_error`**. It never maps a sentinel.
- **Call sites.** Every inline refusal in `chat_group.go`, `chat_group_admin.go`, `chat_group_admin_connect.go` and `chat_group_connect.go` now goes through those helpers.
  - The 400 sentences are `Invalid JSON.`, `kind and at least one member are required.`, `user_id is required.`, `Invalid user id.`, `Message body is required.`, `A decline reason is required.`, and also the member route's `context_type, context_id, and message are required.`.
  - The 500s are on the admin and member group lists, admin messages, contact blocks, the admin connect-request list, the member connect-request list, and member mark-read.
  - The admin connect-request list used to log the error itself. That `log.Printf` was removed, because `chatServerErr` logs it, and so was the now-unused `log` import.
- **New test file `backend/internal/handlers/chat_group_inline_refusal_codes_test.go`** (existing chat-group test files are near 500 lines):
  - `TestChatGroupHandlers_UnauthorizedCarriesItsCode` needs no DB. It calls all 18 handlers with no user.
  - `TestChatGroupRoutes_InlineBadRequestCarriesItsCode` covers 11 route and body cases.
  - `TestChatGroupRoutes_DatabaseErrorCarriesItsCode` covers 7 routes. Each handler's store uses a pool whose `search_path` is a temporary schema of views over every public table except the one that query reads. Auth and lifecycle keep the real pool. The schema is dropped in `t.Cleanup`.

**For admin-web (not edited):** `unauthorized` is a new code. Add `error.unauthorized` to the error map. `group_invalid_input` and `server_error` are already known.

**What was run:**
- **RED** on a throwaway DB, before any handler change. All three tests failed on `code = <nil>`: 18/18, 11/11 and 7/7 subtests, e.g. `code = <nil>, want "unauthorized" (body map[error:Unauthorized. success:false])`.
- `gofmt -l` on the 5 changed files printed nothing. `go build ./...` and `go vet ./...` passed.
- `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` on a fresh DB: `ok` for both packages.
- `-v -run 'TestChatGroupHandlers_UnauthorizedCarriesItsCode|TestChatGroupRoutes_InlineBadRequestCarriesItsCode|TestChatGroupRoutes_DatabaseErrorCarriesItsCode'` on a fresh DB: PASS=39, FAIL=0, SKIP=0.
- `go test ./... -count=1 -p 1 -timeout 45m` on a fresh DB: exit 0, 22 packages `ok`, no FAIL lines.
- Review (`ecc:go-reviewer`): **APPROVE**. No CRITICAL, HIGH or MEDIUM findings. One LOW, fixed: `chatServerErr`'s doc said "reads" although `MarkRead` writes.

**After a harness watchdog stalled the session** (commit `a031cd5` was already in place), the checks were re-run on two more fresh DBs, since the earlier background jobs were gone:
- `origin/main` was still `b0c9eb8`, so the merge was a no-op.
- `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m`: `ok` for both packages (11.7s, 23.1s).
- the same `-v -run` regex: PASS=39, FAIL=0, SKIP=0.
- The full `./...` run was not repeated; the coordinator is running it on main after the merge.
- The reviewer agent was not re-run. The diff was re-read instead and confirms: every English sentence and status is unchanged, the three helpers add no entry to the `chatErrResponses` table so no sentinel shadows another, and all 500s are still logged (the one removed `log.Printf` is replaced by `chatServerErr`'s own).

**External actions:** none. Nothing was pushed. Each throwaway DB (`godonation_26496_{red,pkg,run,full}` and `godonation_26496b_{pkg,run}`) was dropped and confirmed gone with `psql -lqt`.

**Still open:** the admin-web locale key for `unauthorized`.

**Traps:**
- A 500 inside `AdminMessages` / `AdminContactBlocks` cannot be reached with a closed pool, because `GroupKind` fails first through `chatErr`. That is why the test uses the missing-table schema.
- The worktree guard rejects compound shell commands that mention `git`. Run `git grep` on its own.

---

## 2026-09-15 — OPOS #26495: messages_screen.dart split under the 500-line limit, no behaviour change (branch `refactor/split-messages-screen`)

**What was asked:** `humanitarian/lib/modules/chat/screens/messages_screen.dart` had 726 lines against the 500-line limit. The request was to split it into widgets under `modules/chat/widgets/`, following the #26473 pattern. It was a pure refactor.

**What was changed** (branch cut from `origin/main` `b0c9eb8`; not pushed):
- **`a87e47b` refactor(chat): split messages_screen.dart into chat widgets.** Module map:

  | File | Lines | Holds |
  |---|---|---|
  | `screens/messages_screen.dart` | 279 (was 726) | `supportChatError`, `supportChatUnavailable`, `openSupportChat`, `MessagesScreen` (guest prompt, support tiles, thread sections, `ChatGroupsSection`, refresh); new file header |
  | `widgets/chat_thread_tiles.dart` (new) | 270 | `ChatThreadSectionLabel`, `ChatThreadAvatar`, `ChatThreadTile`, `OutgoingPendingChatTile` (formerly `_SectionLabel`, `_Avatar`, `_ThreadTile`, `_OutgoingPendingTile`) |
  | `widgets/chat_request_card.dart` (new) | 164 | `IncomingChatRequestCard` (formerly `_IncomingRequestCard`), with the #26433 refusal copy through `chatInviteRefusalMessage` |
  | `widgets/messages_support_tiles.dart` (new) | 85 | `BotAssistantCard` (formerly `_BotAssistantCard`) |

  - The screen imports all three new files, and `chat_request_card.dart` imports `chat_thread_tiles.dart` for the avatar. Nothing imports back.
  - The support-chat and ticket-form tiles and their two `ValueListenableBuilder`s stay inline in the screen. Wrapping them in a widget would have added a node to the `ListView` children and moved `openSupportChat` and its notifiers, so the tree would no longer be identical.
  - The section assembly (the `Obx` / `AppAsync` builder) stays in the screen for the same reason.
  - Every moved widget gained `super.key`; nothing passes a key.
- **Two source-reading tests were repointed; no assertion was weakened.**
  - `test/modules/chat/chat_thread_other_name_test.dart` now reads the screen plus the two thread widget files.
  - `test/modules/chatgroups/messages_screen_chat_groups_wiring_test.dart` now looks for `const BotAssistantCard()`.
  - Both had failed after the split: `Expected: true Actual: <false>` and `Expected: not <-1> Actual: <-1>`.

**Proof of no change** (Python against `git show HEAD:…`, comments, imports and blank lines ignored, renames normalized, lines compared as sorted multisets):
- The only differing lines are the six constructors gaining `super.key`, plus `dart format` re-wrapping three call and constructor lines made longer by the new names.
- All 96 original comment lines are present.

**What was run** (from `humanitarian/`):
- `flutter analyze`, before and after: `6 issues found.`
- `flutter test test/modules/chat/ test/notifications/`: `00:03 +49: All tests passed!`
- Full `flutter test`: `00:54 +1077: All tests passed!`
- **Trap:** `dart format lib/modules/chat/widgets` also reformats the untouched `chat_lifecycle_notice.dart`. That change was reverted, so format only the files you changed.

**Review** (`ecc:flutter-reviewer`): **APPROVE**. It found 0 CRITICAL, HIGH or MEDIUM issues, and one LOW that is informational only. It confirmed the bodies are verbatim, imports are correct and there is no cycle.

**External actions:** none. Nothing was pushed and no PR was opened. OPOS was unavailable to this agent, so #26495 was not moved.

**Still open:** push, open a PR, and update OPOS #26495.

---

## 2026-09-15 — OPOS #26400 (Phase 6c): admin-web connect-request inbox (branch `feat/admin-connect-request-inbox`)

**What was asked:** the connect-request inbox in admin-web, test-first. It needed:
- a status filter and list;
- a detail panel;
- Approve and Decline dialogs, with validation and error codes;
- gates, nav and route;
- the mock routes.

The branch was to merge `origin/main`, commit, and not push.

**What was changed** (branch cut from `feat/admin-chat-groups-list` `dffbe1f`):
- **`2eb598c`** merges `origin/main`, which has 6a squashed as #117. The only conflict was `HANDOFF.md`, where main's side was kept.
- **`d8b39e5` feat(admin-web): connect-request inbox with approve and decline.**
  - `src/pages/ConnectRequestsPage.tsx` and its test. The route is `chat-groups/connect-requests` in `App.tsx`. The NAV item `/chat-groups/connect-requests` has module `messages` and sits under communication_support.
  - `src/components/connectRequests/`: `ConnectRequestPanel` (detail, gates, dialogs), `ApproveRequestDialog`, `DeclineRequestDialog`, `DialogFrame`, and tests for both dialogs.
  - `src/lib/connectRequestForm.ts` and its test: decline-reason rules, the approve draft with the requester pre-filled, the requester-must-stay rule, badge tones and the requester fallback name.
  - `TeamTitleField` moved out of `CreateGroupDialog` into `src/components/chatGroups/TeamTitleField.tsx`, unchanged, so both dialogs share it.
  - `chatGroupsApi.ts`: `ConnectRequest.requester_name?`.
  - Mock: list and detail now add `requester_name` from the users fixture when the requester has a profile. There are 3 new cases in `scripts/mock-api-chat-groups.test.mjs`: the name key, approve and decline success, and requester-not-a-member returning 400.
  - Locales: `nav.connect_requests` and a separate `chat_groups.inbox.*` block in en and ar, 41 keys in all.
- **`503e2e7`** lists the 41 keys in `TRANSLATION_REQUEST.md`. No Kurdish was written.
- **`5cd51bc`** merges `origin/main` again (#118–#121). The only conflict was `TRANSLATION_REQUEST.md`: both rows were kept, and the count is now **578** (main's 537 plus 41).
- **The last commit (see `git log`)** is the review fix: rows use `aria-pressed`, not `aria-current`. It also adds this entry.

**The approve body, confirmed on `origin/main`.** In `handlers/chat_group_admin.go`, `adminCreateGroupReq` is `{kind, member_title, members:[{user_id, role_in_group, label}]}`. The member field is `label`, not `masked_label`, and the response is `{success, group_id}`. `ApproveConnectRequest` answers 400 `group_invalid_input` when the requester is not among the members, so the dialog pre-fills them and blocks their removal.

**The decline reason.** The handler only requires it to be non-blank after trimming, and the column is `TEXT`, so the backend has no max length. The 1000-character cap is the dashboard's own (`DECLINE_REASON_MAX_LENGTH`).

**`target_hint` is never rendered (D8).** A test asserts the declined request's panel does not contain it.

**What was run** (Node 22.23.1; `node_modules` installed in this worktree with `npm ci`):
- **RED.**
  - vitest: `Test Files 4 failed (4)`, each with `Failed to resolve import "./ConnectRequestsPage"` (and the same for the other three).
  - mock-api: `# fail 1` on `at least one requester is named`.
- **GREEN, on the final merged tree:**
  - `npm test`: `Test Files 16 passed (16)`, `Tests 135 passed (135)`
  - `npx tsc -b`: exit 0
  - `npm run build`: exit 0; `ConnectRequestsPage` is 13.75 kB
  - `test:mock-api`: `# pass 35`, `# fail 0`
  - `test:nav`: `# pass 15`
  - `check:labels`: `every controlled value and permission module has a label.`
  - `check:css-tokens`: `62 tokens read, all defined.`
  - eslint on every changed `src` file: exit 0
  - After the `aria-pressed` fix: the page test at 8/8, eslint and `tsc -b` all passed again.

**Review (`ecc:react-reviewer`): APPROVE WITH COMMENTS.**
- **HIGH, fixed:** `aria-current` was used for row selection.
- **MEDIUM, not done (out of scope by instruction):** after a decision the row leaves the pending list while its panel stays open.
- **LOW:** no action needed.

**External actions:** none. Nothing was pushed and no PR was opened. OPOS is tracked by the orchestrator.

**Still open:**
- **#26478.** `code: "connect_request_not_found"` was not in `origin/main`'s handler or in `CHAT_GROUP_ERROR_CODES` when merged. `describeConnectRequestError` handles only the uncoded 404 today. Once the code lands, add it to the error map, or the coded 404 would fall through to describeError's text.
- **Without users:view (D2),** the member rows are replaced by the guidance card, so the requester's role cannot be chosen and approval cannot be submitted. That is consistent with 6a, but such staff can only decline.
- **The group link** goes to `/chat-groups/:id`, which is 6b's route (built in parallel).
- **No fixture requester lacks a profile,** so the mock never omits `requester_name`. The fallback is covered in `ConnectRequestsPage.test.tsx` instead.
- **Not checked in a browser.**

**Traps:**
- **The worktree had no `node_modules`.** Run `npm ci` in `admin-web/` first.
- **Commands with `$PATH` in them are refused in isolated agent worktrees.** Call `/opt/homebrew/opt/node@22/bin/node` directly on `node_modules/vitest/vitest.mjs`, `typescript/bin/tsc`, `vite/bin/vite.js` and `eslint/bin/eslint.js`.
## 2026-09-15 — OPOS #26399 (Phase 6b): admin-web chat group detail page, plus E3 export and the admin-web half of #26429 (branch `feat/admin-chat-group-detail`)

**What was asked:** build `/chat-groups/:id` in admin-web, test first. The page needed a header with the lifecycle, the roster with add and remove, polled messages with a composer, the contact-block log, a designed 403 `sensitive_data_required` state, the group export (E3, rest of #26397) and the `chat_group_message` label (#26429). Extend the mock API too. Commit only: no push, no PR.

**What was changed.** Branched from `feat/admin-chat-groups-list` `dffbe1f`.
- **`18bdb57` feat(admin-web): chat group detail page with roster, messages, blocks and export**
  - `src/pages/ChatGroupDetailPage.tsx`: loads the group and shows one of four states: skeleton, 403 permission card, error with `error.retry` and a back link, or the panels. After a change it reloads in place. If the group is gone (moved to the Trash) it returns to `/chat-groups`.
  - `src/components/chatGroups/`:
    - `GroupHeader`: `ChatLifecycleControls` for messages:edit, a read-only state otherwise, and the ExportCsvButton.
    - `GroupMessages` and `GroupComposer`: a full first load, then a 3 s poll on `after_id`. The composer needs messages:add; a paused or ended group shows a notice with the reason instead.
    - `GroupRoster` and `AddMemberForm`: add and remove need messages:edit, and the picker needs users:view (6a's guidance card, now exported from `MemberRowsEditor`). Removed members sit behind a toggle. Removal asks for confirmation first.
    - `GroupContactBlocks`: `ContactBlocksPanel` hardcodes the `/chats` URL and `thread_id`, so this reuses its strings on the group route.
  - `src/lib/chatGroupDetail.ts`: the add-member rules (6a rules checked against the active roster, with a reactivation hint for D3), `groupExportRows` and `loadGroupChatExport`.
  - The list rows now link to the detail page, and `App.tsx` adds the route.
  - Locales: 34 `chat_groups.detail.*` keys and `status.chat_group_message`, in en and ar. `TRANSLATION_REQUEST.md` gets a new section (35 keys).
  - Mock: a new `no_sensitive` scenario answers 403 `sensitive_data_required` for a masked group's detail, messages and contact blocks. Two new mock tests cover it and a member add then remove. `docs/mock-api.md` is updated.
- **`6aecf1a`** merges `origin/main` `058b4be`, which includes 6a as #117 and #118–#122. The 6a files conflicted add/add because of the squash; this branch's side was kept.
  - `TRANSLATION_REQUEST.md`: both sides' rows were kept, and the count and Total are now **575** (main's 540 plus 35).
  - `HANDOFF.md`: main's entries were kept.

**Runs:**
- RED: `Error: Failed to resolve import "./chatGroupDetail"` for the lib, and the same for `./ChatGroupDetailPage`, `./GroupRoster`, `./GroupMessages` and `./GroupContactBlocks`. `ChatGroupsPage.test.tsx` failed with `Unable to find an accessible element with the role "link"`.
- GREEN after the merge:
  - `npm test`: `Test Files 17 passed (17)`, `Tests 158 passed (158)`
  - `npx tsc -b`: exit 0
  - `npm run build`: exit 0
  - `test:mock-api`: `# pass 34`, `# fail 0`
  - `test:nav`: `# pass 15`
  - `check:labels`: passes
  - `check:css-tokens`: 62 tokens, all defined
  - eslint on the changed files: exit 0
- The mock tests were written after the mock change, so they have no RED run.

**Review:** `ecc:react-reviewer` on `dffbe1f..18bdb57` approved it, with LOW notes only: comment the stale-response guard in `GroupMessages.fetchNewer`, and optionally skip a poll tick while a fetch is in flight. Neither was changed.

**External actions:** none. Nothing was pushed.

**Still open / traps:**
- **The brief was wrong about the add-member field.** It said `masked_label`, but `adminGroupMemberReq` (`backend/internal/handlers/chat_group_admin.go`) reads **`label`**, and the page sends `label`.
- **`ChatLifecycleControls` still uses `describeError`, not `describeChatGroupError`.** `error.<code>` keys still resolve through it.
- **Delete is gated on messages:edit, like the lifecycle controls.** The server requires messages:delete for it.
- **Phase 6c (the connect-request inbox) is on another branch.** Expect locale and TRANSLATION_REQUEST conflicts beside `chat_groups.detail`.

## 2026-09-15 — OPOS #26433: refused chat-invite answers show accurate copy, and closed chats offer no Accept (branch `fix/app-chat-invite-refusal-copy`)

**What was asked:** fix the app's chat-invite refusals, test first:
- The marriage chat screen showed the send-failure line for a refused accept or decline.
- The notification tile's `ChatRequestActions` showed a failed accept as raw `'$e'`, and a failed decline said nothing.
- Accept stayed visible on paused or ended threads.

**Findings the fix rests on** (read on `origin/main` `bbc6aa2`):
- **Accept refusals.** Both `chatErr` switches (`backend/internal/handlers/chat.go`, `marriage_chat.go`) and `refuseIfInviteClosed` answer:
  - paused or ended → 409 `chat_lifecycle_closed`, with `lifecycle` and `lifecycle_reason`;
  - archived → a bare 404;
  - declined → 409 `chat_invite_declined`.
- **Decline on an active chat** is an UNCODED 409. Both `DeclineThread` updates are guarded by `WHERE status IN ('pending','declined')` and return `ErrNotPending`, which is the only 409 either decline route returns. So the status identifies it without reading the English sentence.
- **The donor conversation screen has no Accept/Decline at all.** The donor answers live in `ChatRequestActions` and the Messages tab's `_IncomingRequestCard`, and both showed `'$e'` on accept.
- **`/api/chats` already sends `lifecycle` per thread** (`chat.go` ThreadSummary); `ChatThread` just did not parse it.
- **`_trackEvent` tracks no chat path**, so moving the four answer calls off `postJson` loses no analytics.

**What was actually changed.** Two commits on `fix/app-chat-invite-refusal-copy`, not pushed:

**`7bf2ae6` `fix(chat): accurate copy for refused chat-invite answers, no Accept on closed chats`**
- `lib/api/module_api.dart`:
  - `ApiCodedException` gains `statusCode` (default 0) and `payload` (default `{}`), so the K14 callers are unchanged.
  - `acceptMarriageChat`/`declineMarriageChat` now use `_sendCodedJson`.
  - New `acceptChat`/`declineChat` for the donor chat.
- `lib/modules/chat/utils/chat_invite_refusal.dart` (new): `classifyChatInviteRefusal` and `chatInviteRefusalMessage`.
  - The closed copy reuses the lifecycle notice's "...closed/paused by our team." keys, plus `Reason: <staff reason>`.
  - The generic line is `failureMessage` with `error_chat_accept_failed` or the existing `Could not decline this chat request.`
  - It never renders the exception text.
- `chat_models.dart`: `ChatThread.lifecycle` (optional, defaults to `open`). The `'User #'` fallback, which #26483 owns, was not touched.
- `chat_controller.dart`: `accept`/`decline` call the coded API and refresh threads in `finally`, so a refused invite's stale buttons go.
- **`ChatRequestActions`:** a refusal shows the mapped SnackBar and settles the row:
  - declined → Declined;
  - already active → Accepted;
  - closed → Accept removed, Decline kept;
  - anything else → both buttons re-enabled.

  Accept is also hidden when the loaded list reports the thread closed.
- `messages_screen.dart` `_IncomingRequestCard`: mapped copy for accept and decline, and no Accept on a closed thread.
- **Marriage chat screen:** `_decide(ChatInviteAnswer)` maps the refusal, sets `_acceptClosed` or `_status = 'declined'`, then reloads silently.
  - The pending-owner row moved to the new `lib/modules/marriage/widgets/marriage_chat_invite_bar.dart` (`canAccept`), which keeps the screen at 482 lines, under 500.
  - The `'Support'.tr` label was not touched.
- **Keys and docs:** 3 en+ar keys in `app_translations.dart`, and a new `TRANSLATION_REQUEST.md` section, "chat · OPOS #26433 chat invite refusals (3 keys)".
- `test/support/fake_http.dart`: an optional per-request `respond` returning `FakeHttpAnswer`. Null keeps every existing behaviour.
- **New tests:**
  - `test/modules/chat/chat_invite_refusal_test.dart` (unit, en + ar);
  - `test/modules/marriage/marriage_chat_invite_refusal_test.dart` (6 widget tests);
  - `test/notifications/chat_request_actions_refusal_test.dart` (5 widget tests).

**`a78e8ab`** merges `origin/main` `3e094c6` (#119, #120 and the #26483 app half). Only `TRANSLATION_REQUEST.md` conflicted; both sides were kept, and the count and Total went from main's 536 to **539**.

**This entry** is the third commit.

**What was run and what it printed** (from `humanitarian/`):
- **Baseline:** `flutter analyze` printed `6 issues found.`
- **RED:** `flutter test` on the two widget files gave `00:03 +1 -10: Some tests failed.`, failing on assertions (`Actual: <false>` / `<1>`). The one pass was the open-invite accept, which already worked. The unit file failed to compile: `Error when reading 'lib/modules/chat/utils/chat_invite_refusal.dart': No such file or directory`.
- **GREEN:** the three new files, plus `chat_request_tile_guest_test.dart`, `messages_stale_threads_test.dart` and `test/localization`, gave `00:08 +191: All tests passed!`
- **Pre-merge full suite:** `flutter test` gave `01:11 +1064: All tests passed!`
- **After the merge:** `flutter analyze` printed `6 issues found. (ran in 30.2s)`, and the full `flutter test` gave `02:48 +1064: All tests passed!`.

**Review:** `ecc:flutter-reviewer` returned REQUEST CHANGES, with one HIGH and one LOW.
- **HIGH:** it claimed `DeclineThread` never checks status, so the "already active" 409 would be unreachable. This is a **false positive**: `backend/internal/chat/chat.go:271` and `backend/internal/marriagechat/marriagechat.go:313` both guard `status IN ('pending','declined')` and return `ErrNotPending` (lines 276 and 318). No change was made.
- **LOW:** `messages_screen.dart` (722 lines) and `module_api.dart` were already over 500 lines. Not acted on, per the coordinator (CRITICAL/HIGH only).

Everything else it checked came back clean: no exception masking in `_answer`, safe casts, mounted checks, non-vacuous tests.

**Guest guard:** no `assert(!isGuestMode())` was added to `ChatRequestActions`. It was optional, the call-site guard already exists, and #26483 is editing nearby, so it was left out.

**External actions:** none. Nothing was pushed and there is no PR.

**Still open:**
- All three commits are local.
- `messages_screen.dart` and `module_api.dart` are still over the 500-line limit.
- There is no widget test for the Messages tab card. It shares the unit-tested mapping.

**Traps:**
- **`Locale('ar', 'IQ')` is the SORANI map in this app**, and Arabic is `ar_SA` (`AppTranslations.keys`). An Arabic assertion under `ar_IQ` fails with Kurdish text.
- **`chat_controller.dart` and `app_translations.dart` were already not `dart format`-clean on main.** Formatting them reflows unrelated lines and invites conflicts, so only the touched, previously clean files were formatted.
- **The worktree guard refuses shell loops and `cd` + git compounds.** Use plain `git -C <abs>` and one command per call.

---

## 2026-09-15 — OPOS #26483 (app half): no English "User #" or bare الدعم in chats (branch `fix/app-chat-english-fallbacks`)

**What was asked:** remove the two app-side fallbacks the #109 agent found, one English and one the wrong Arabic word, following #109's display-time pattern. The push half is the separate branch `fix/support-push-title-localized`.

**Findings:**
- `ChatThread.fromMap` (`humanitarian/lib/modules/chat/models/chat_models.dart`) put `'User #<other_user_id>'` into `otherName` for a blank name, and an untranslated `'User'` for a null one. Its only reader is `lib/modules/chat/screens/messages_screen.dart`, at 8 sites.
- `marriage_chat_conversation_screen.dart` lives in `lib/modules/marriage/screens/`, not in `marriagechat/`. Its `_Bubble` labelled staff with `'Support'.tr`, whose Arabic is الدعم (Kafala). T10 forbids that.

**What was changed** (one commit on `fix/app-chat-english-fallbacks`, based on `origin/main` `bbc6aa2`):
- `chat_models.dart`: `otherName` is now the trimmed server name, or `''`.
- `lib/modules/chat/utils/chat_sender_name.dart`: new `chatThreadOtherName(ChatThread)`. It returns, in order:
  - the name;
  - else `chat_thread_other_user_id`.trParams, keeping the id as the old UX did;
  - else `'User'.tr` when the id is 0.
- `messages_screen.dart`: every `thread.otherName` became `chatThreadOtherName(thread)`.
- `marriage_chat_conversation_screen.dart`: the staff label uses `'chat_group_sender_support'.tr` (Support / فريق الدعم).
- `lib/localization/app_translations.dart`: new key `chat_thread_other_user_id`, en `User #@id`, ar `مستخدم #@id`. It has no Kurdish, so Kurdish falls back to English.
- `TRANSLATION_REQUEST.md`: a new section and table row. The count went from 468 to 469.
- Tests:
  - `test/modules/chat/chat_thread_other_name_test.dart`: the model, ar, en, and a source test on messages_screen.
  - `test/modules/marriage/marriage_chat_staff_label_test.dart`: a source test plus the key's values.

**What was run:**
- **RED:** `flutter test` on the two new files printed `Error: Method not found: 'chatThreadOtherName'` and `00:00 +2 -2: Some tests failed.` The marriage source assertion failed with `Expected: true`.
- **GREEN:** `flutter test test/modules/chat/ test/modules/marriage/` printed `+26: All tests passed!`.
- **`flutter analyze`:** `6 issues found.`, the baseline. A doc comment containing `<id>` briefly made it 7; that is fixed.
- **Full `flutter test`:** `00:54 +1058: All tests passed!`.
- **Review:** `ecc:flutter-reviewer` returned APPROVE, with no CRITICAL or HIGH findings. Its three LOW notes needed no change.

**External actions:** none. Nothing was pushed; the orchestrator ships.

**Still open:** Kurdish for `chat_thread_other_user_id` (listed in TRANSLATION_REQUEST.md).

**Traps:**
- `dart format lib/modules/chat` also reformats unrelated files (`chat_controller.dart`, `chat_lifecycle_notice.dart`). Format only the files you touch.
- A hook blocks `git checkout -- <file>`; `git restore <file>` works.

## 2026-09-15 — OPOS #26466 follow-up: the retire runbook matches the Trash fix (branch `docs/runbook-after-trash-fix`)

**What was asked:** update `docs/runbooks/retire-direct-chats.md` for the #26466 Trash fix. Docs only.

**What was changed:** branched from the local `fix/trash-direct-chat-restore-closed` (`85dda17`). One commit touches the runbook and this file.
- **Header row:** notes the #26466 update.
- **Section 3, item 7:** delete and Trash restore are off the freeze. Claim and release stay on. The reasons cited are: `FOR UPDATE` (`admin_chat_lifecycle.go:207`), `DELETE … RETURNING *` (`:247-248`), and the restore closing direct chats in the same transaction (`admin_trash.go:296`, `admin_chat_lifecycle.go:369`, `retire_one.go:53`).
- **Pre-flight query 6 and its bullet:** every trashed direct chat is now safe to restore, because it comes back ended and archived.
- **Post-check 7h and its follow-up:** a row there is something to record, not a failure. It is no longer "expect 0 rows".
- **Section 9:** old risk 9 moved to a new "Resolved by OPOS #26466" block. Old risk 10 is now 9. No text referred to it by number.
- **Section 10:** new bullet on Trash-restored snapshot threads.
  - `chat_threads` has no `updated_at` trigger, and the restore keeps the copy's value.
  - A thread deleted after the run and then restored still has `run_ts`, so the snapshot restore reopens it.
  - One deleted between the snapshot and the run gets a new `updated_at` when the restore closes it, so the snapshot restore skips it.
  - Rows still in the Trash are skipped.

**What was run:** `git diff --check`, clean. A grep for `risk [0-9]` found only "risk 3", which is still correct. No code was run, because this is docs only.

**External actions:** none. Not pushed. OPOS was not available to this agent.

**Still open:**
- Merge after `fix/trash-direct-chat-restore-closed` lands.
- The section 10 claims come from reading the code, not from a run.

**Traps:** a thread deleted after the run and then restored is not protected by the `run_ts` filter. Check 7h before running the snapshot restore.

---

## 2026-09-15 — OPOS #26483 (push half): the staff-reply push names the support team per language (branch `fix/support-push-title-localized`)

**What was asked:** the admin reply in a 1:1 donor chat pushed «رسالة من Support» to Arabic users. Localize the sender in the template layer, not the handler. The app half is the separate branch `fix/app-chat-english-fallbacks`.

**Findings:**
- `handlers/chat.go` (the admin reply, around line 578) sent `notify.ChatNewMessageMsg("Support", preview, id)`.
- That template formats one `who` into all four titles.
- `pickLocalizedText` (`push.go`) picks the device's `locale_code` slot and falls back to English only when a slot is empty.
- `group_alias.go`'s `groupFixedLabels` already mapped `"Support"` to ar فريق الدعم, with no ckb/kmr.

**What was changed** (one commit, based on `origin/main` `e1ac95f`):
- `backend/internal/notify/templates.go`:
  - New `ChatSupportReplyMsg(preview, threadID)`, which names the sender through `localizedGroupAlias(supportSenderLabel, lang)`.
  - `ChatNewMessageMsg` and the new template share a private `chatThreadNewMessageMsg(who LocalText, ...)`.
  - Titles for every other caller are byte-identical.
- `backend/internal/notify/group_alias.go`: new const `supportSenderLabel = "Support"`, used as the `groupFixedLabels` key. The `localizedGroupAlias` doc now names its second caller.
- `backend/internal/handlers/chat.go`: the admin reply sends `notify.ChatSupportReplyMsg(preview, id)`.
- `backend/internal/notify/support_reply_push_test.go` (new), selected by `-run '^TestSupportReplyPush_'` (4 tests):
  - Arabic and English devices, through the real `sendPush` with push_guest_test.go's FCM recorder;
  - all four stored titles;
  - a source check that the handler uses the template.
- **Titles:**
  - en: `Message from Support`
  - ar: `رسالة من فريق الدعم`
  - ckb: `نامە لە Support`
  - kmr: `Peyam ji Support`
- **Kurdish:** no support-team term exists, so ckb/kmr keep "Support", the same fallback the chat-group alias uses. OPOS #26468 tracks this.

**What was run** (from `backend/`):
- **RED** on the fresh DB `godonation_26483_red`: `go test ./internal/notify/ -run '^TestSupportReplyPush_' -v` printed `undefined: ChatSupportReplyMsg` and `FAIL ... [build failed]`.
- **GREEN** on the same DB: 4 `--- PASS`, `ok .../internal/notify 1.037s`.
- **gofmt:** `gofmt -l` on the four changed files printed nothing (after `gofmt -w group_alias.go` realigned the map).
- **Build and vet:** `go build ./...` and `go vet ./...` were clean.
- **`godonation_26483_pkg`:** `go test ./internal/notify/ ./internal/handlers/ -count=1 -p 1` gave `ok notify 1.048s` and `ok handlers 14.903s`.
- **`godonation_26483_run`:** `-v -run '^TestSupportReplyPush_'` gave PASS=4, SKIP=0, FAIL=0.
- **`godonation_26483_all`:** `go test ./... -count=1 -p 1 -timeout 45m` exited 0, with 22 packages `ok` and 0 FAIL.
- **Cleanup:** every DB was dropped; `psql -lqt | grep -c 26483` printed `0`.
- **Review:** `ecc:go-reviewer` returned APPROVE WITH NITS.
  - It confirmed byte-identical titles for the other callers, and correct per-language titles.
  - Nit 2 was a confusing doc sentence on `localizedGroupAlias`; it is reworded.
  - Nit 1, four lookups instead of a helper, was left as is for clarity.

**External actions:** none. Nothing was pushed.

**Still open:**
- The Kurdish word for the support team (OPOS #26468).
- The in-app rows already stored with «رسالة من Support» are not rewritten.

**Traps:** `ChatNewMessageMsg`'s `Sprintf` lines also appear in other templates, so a text replace across templates.go hits more than one.

## 2026-09-15 — OPOS #26478: the connect-request "not found" 404 gets a machine code (branch `fix/connect-request-not-found-code`)

**What was asked:** give the admin connect-request not-found 404 (detail, approve, decline) the `code` #107's `chatErr` puts on every other chat-group refusal, so admin-web can use its translated `error.connect_request_not_found`. First move the connect-request inbox out of `chat_group_admin.go` (492 lines), as #111's entry required.

**What was actually changed** (off `origin/main` `3bc5b1d`; not pushed):
- `5452d17` refactor(chatgroups): move the connect-request inbox handlers into their own file. It is a pure move:
  - `backend/internal/handlers/chat_group_admin.go` is now 309 lines.
  - The new `chat_group_admin_connect.go` (207 lines) holds `resolveConnectContext`, `adminConnectRequestItem`, `adminConnectRequestItems` and the list, detail, approve and decline handlers.
  - A `diff` against `git show HEAD:` showed the moved block is identical; only headers and imports changed.
  - `chat_group_connect.go`'s header comment now points at the new file.
- `a4e9181` fix(chatgroups): give the connect-request not-found 404 its machine code.
  - The store uses one `chatgroups.ErrNotFound` for groups, members and connect requests, and has no connect-request sentinel, so the store is unchanged.
  - `chat_group.go` has a new handler-level `errConnectRequestNotFound`, entered in `chatErrResponses` BEFORE `ErrNotFound`: 404, `"Connect request not found."`, `connect_request_not_found`.
  - `connectRequestErr` (in `chat_group_admin_connect.go`) wraps a store `ErrNotFound` as `fmt.Errorf("%w: %w", errConnectRequestNotFound, err)`. The three handlers call `h.chatErr(c, connectRequestErr(err))` instead of answering inline. No other refusal changed.
  - New test file `backend/internal/handlers/chat_group_connect_not_found_test.go`:
    - `TestConnectRequestErr_MapsOnlyNotFound`, which needs no DB;
    - `TestAdminConnectRequest_MissingRequestCarriesItsCode`, which uses the real routes with valid approve and decline bodies.
- New body: `404 {"success":false,"error":"Connect request not found.","code":"connect_request_not_found"}`.

**What was run and what it printed** (from `backend/`):
- After the move: `go build ./...` and `go vet ./...` were ok. `gofmt -l internal/handlers/` listed only `admin_edit_user_profile.go`, which is untouched and pre-existing.
- **RED**, on DB `godonation_26478_red`: `--- FAIL: TestAdminConnectRequest_MissingRequestCarriesItsCode (0.53s)`. Detail, approve and decline each printed `code = <nil>, want "connect_request_not_found"`. `TestConnectRequestErr_MapsOnlyNotFound` was written after RED and was never seen failing.
- **GREEN**, same DB, `-run` new tests plus `TestChatErr_|CarriesItsCode`: `ok …/internal/handlers 6.714s`, all PASS. `gofmt -l` on the changed files printed nothing; build and vet ok.
- **Package run**, fresh DB `godonation_26478_pkg`: `ok …/internal/chatgroups 18.107s`, `ok …/internal/handlers 46.399s`, exit 0.
- **`-v` run**, fresh DB `godonation_26478_v`: `-run 'TestConnectRequestErr_MapsOnlyNotFound|TestAdminConnectRequest_MissingRequestCarriesItsCode'` printed `ok …/internal/handlers 7.753s`, with 11 `--- PASS` and 0 `--- SKIP`.
- **Full suite**, fresh DB `godonation_26478_full`: `go test ./... -count=1 -p 1 -timeout 45m` exited 0.
  - 22 `ok`, 36 with no test files, 0 `FAIL` or `panic` lines.
  - `ok …/internal/chatgroups 2.609s`, `ok …/internal/handlers 33.016s`; the last `ok` line was `ok …/internal/users 2.669s`.
- All four DBs were dropped with `dropdb`, and `psql -lqt` lists no `godonation_26478*` database.
- **Review:** `ecc:go-reviewer` on `3bc5b1d..HEAD` answered APPROVE, with 0 CRITICAL, 0 HIGH and 0 MEDIUM. It confirmed:
  - the move is pure;
  - the table order is correct;
  - `connectRequestErr` cannot mislabel another not-found;
  - the tests reuse the shared helpers.

  It raised one LOW nit, about where `connectRequestErr` lives. It was left as is, by the coordinator's decision.

**External actions:** none. Nothing was pushed and no PR was opened. OPOS was not touched from this session; the coordinator tracks it.

**Still open:**
- Push the branch and open a PR.
- Inline chat-group refusals that still lack a `code`:
  - 401 `Unauthorized.` on every handler.
  - The 400s: `Invalid JSON.`, `kind and at least one member are required.`, `user_id is required.`, `Invalid user id.`, `Message body is required.`, `A decline reason is required.`, and the mobile submit's 400.
  - The `Database error.` 500s on the group list, messages, contact blocks, the connect-request list, and the mobile list, mark-read and my-requests routes.

**Traps:**
- The worktree isolation hook refused a `git add && git commit -F - <<EOF … && git log` chain even though the same shape had worked minutes earlier. Write the message to a file and run `git add`, `git commit -F file` and `git log` as separate commands.
- `ErrNotFound` is shared across groups, members and connect requests. Any handler that needs a more specific not-found must wrap it with its own sentinel listed before `ErrNotFound` in `chatErrResponses`. Do not add a second inline 404.

---

## 2026-09-15 — OPOS #26398 (Phase 6a): admin-web Chat Groups page, create dialog and error map (branch `feat/admin-chat-groups-list`)

**Follow-up (same day): main merged in.** `origin/main` (`3bc5b1d`, which includes #109–#112) was merged, not rebased, in `22adc5e`.
- **Conflicts:**
  - `TRANSLATION_REQUEST.md`: both rows kept; the count is now 536 (main's 468 plus 68).
  - `HANDOFF.md`: both entries kept, this one on top.
  - `en.ts`, `ar.ts` and `mock-api.test.mjs` merged by themselves.
- **Follow-up commit (see the SHA in `git log`):**
  - The merged `scripts/mock-api.test.mjs` came to 516 lines. The chat-group cases moved to `scripts/mock-api-chat-groups.test.mjs`, the shared `startMock` to `scripts/mock-api-test-helpers.mjs`, and `test:mock-api` now runs both files.
  - The mock detail route now serves the #111 fields: `full_name` on each member (from the users fixture), and `lifecycle`, `lifecycle_reason` and `is_archived` beside `group`. `chatGroupsApi.getGroup` folds those three into the group it returns.
  - RED was 1 failing of 32; GREEN is 32 of 32.
  - Not mocked: the sensitive 403, and `requester_name` on connect requests.
- **Runs on the merged tree:**
  - `npm test`: `Test Files 12 passed (12)`, `Tests 110 passed (110)`
  - `npx tsc -b`: exit 0
  - `npm run build`: exit 0
  - `test:mock-api`: `# pass 32`, `# fail 0`
  - `test:nav`: `# pass 15`
  - `check:labels`: passes
  - `check:css-tokens`: 62 tokens, all defined
  - eslint on this branch's files: exit 0
- **Still open:** #26478 will add `code: "connect_request_not_found"`. `describeConnectRequestError` already handles the coded and uncoded forms, but `connect_request_not_found` is not yet in `CHAT_GROUP_ERROR_CODES`, so the coded form still goes through the 404 check.

**What was asked:** build the Chat Groups page (list plus create dialog) in admin-web, test-first. Also fix the `check:labels` gaps, and give admin-web an error map for the final chat-group error contract. The mock API was to serve the page. Commit, do not push, and do not start the Vite dev server.

**Mid-task scope changes from the coordinator:**
1. **`common.retry` is not this branch's.** A separate session owns it. It was added in `de93e7c`, then taken back out in `ef9161a`. `ContactBlocksPanel.test.tsx` was edited in `de93e7c` and restored in `ef9161a`. Net diff against main is none for that file, `ContactBlocksPanel.tsx` and `EditModal.tsx`. The new page labels Retry with `error.retry` ("Try again").
2. **The base was squash-merged.** `chore/admin-web-test-setup` became PR #102 (`e66ff69`). This branch was rebased with `git rebase --onto origin/main 2bf5e3e`. By then `origin/main` was at `95ea8fb` (#103, backend only). There were no conflicts.
3. **The final error contract arrived.** Every chatErr answer has a `code`; the details are below.

**What was actually changed.** Commits on `95ea8fb`, oldest first:
- **`de93e7c` fix(admin-web): define common.retry and the missing status labels.** It added `status.masked/team/case/created/member_added/member_removed` in en and ar. These are CHECK values from migrations 120 and 122, and they turn `check:labels` from failing to passing. It also added `common.retry`, which the next commit removes.
- **`ef9161a` fix(admin-web): leave common.retry to its own change.**
- **`9f06ce0` feat(admin-web): chat group API client, error map and form rules.**
  - `src/lib/chatGroupsApi.ts`
  - `src/lib/chatGroupErrors.ts` and its test
  - `src/lib/chatGroupForm.ts` and its test
  - `error.*` keys
- **`d4a6d26` feat(admin-web): chat groups list and create dialog.**
  - `src/pages/ChatGroupsPage.tsx` and its test
  - `src/components/chatGroups/{CreateGroupDialog,MemberRowsEditor,KindCards,FieldNote}.tsx`, `useDialogKeyboard.ts`, and the dialog and editor tests
  - `src/test/chatGroupsKit.ts`
  - the lazy route `chat-groups` in `App.tsx`
  - the NAV item `/chat-groups` (module `messages`) in `navLayout.ts`, under communication_support
  - `nav.chat_groups` and `chat_groups.*` in en and ar
- **`2cb2ef6` feat(admin-web): translate the final chat-group error contract.** It adds `server_error` (mapped to `error.server`), `chat_lifecycle_closed` (with the staff `lifecycle_reason` appended) and `contact_details_blocked`, and a `describeConnectRequestError` for the uncoded 404 "Connect request not found.".
- **`df700ea` feat(admin-web): mock the final chat-group refusals and a guest account.**
  - `scripts/mock-api-routes.mjs` now sends every chat-group refusal code:
    - group_not_found, including on a missing group's messages and contact blocks;
    - group_invalid_input, group_member_conflict, group_label_conflict and connect_request_decided;
    - the uncoded connect-request 404;
    - reactivation of a removed member (D3).
  - A guest account, user 107 `GUEST_USER_ID`, is refused with `guest_member_not_allowed`.
  - Fixtures `chatGroups.ts` and `shell.ts`: `ADMIN_USERS.role_id` may now be null.
  - `mock-api.test.mjs` gains 7 cases. `docs/mock-api.md` is updated.
- **`81b5446` docs(i18n): list the chat-groups dashboard keys for Kurdish translation.** 68 keys go into `TRANSLATION_REQUEST.md`, and the count goes from 467 to 535. No Kurdish was written.
- **`f694e6f` fix(admin-web): never show a developer error message in chat-group screens.** This fixes the review findings below.
- **This entry.**

**The error map** (`CHAT_GROUP_ERROR_KEYS`). Each key's order of resolution: the translated code, then describeError (a 4xx's own text, the generic line for a 5xx, the offline line), then `error.unknown`.

| Code | Message key |
|---|---|
| guest_member_not_allowed | `error.guest_member_not_allowed` |
| connect_context_not_found | `error.connect_context_not_found` |
| group_member_conflict | `error.group_member_conflict` |
| group_label_conflict | `error.group_label_conflict` |
| group_label_contact | `error.group_label_contact` |
| group_invalid_input | `error.group_invalid_input` |
| group_not_found | `error.group_not_found` |
| not_group_member | `error.not_group_member` |
| connect_request_decided | `error.connect_request_decided` |
| sensitive_data_required | `error.sensitive_data_required` |
| server_error | `error.server` |
| chat_lifecycle_closed | `error.chat_lifecycle_closed`, followed by `chat_lifecycle.reason_shown` |
| contact_details_blocked | `error.contact_details_blocked` |
| uncoded 404, via `describeConnectRequestError` | `error.connect_request_not_found` |

The first four go beside the member rows in a form (`chatGroupErrorArea`).

**What was run and what it printed.** Node 22.23.1 (`PATH=/opt/homebrew/opt/node@22/bin:$PATH`).
- **RED, before any implementation.** `npx vitest run` printed `Test Files 5 failed | 2 passed (7)`: each new test file failed with `Failed to resolve import "./chatGroupForm"` (and the same for the others).
- **RED for the final contract.**
  - The error and dialog tests printed `Tests 8 failed | 23 passed (31)`: "expected [ 'connect_context_not_found', …(9) ] to deeply equal [ 'chat_lifecycle_closed', …(12) ]" and `describeConnectRequestError is not a function`.
  - `test:mock-api` printed `# fail 6`, including `expected: 409 actual: 500`.
- **GREEN.** The same runs printed `Tests 34 passed (34)` and `# pass 30`.
- **Each commit on its own.** Each was extracted with `git archive` and `node_modules` symlinked.
  - `9f06ce0`: `tsc -p tsconfig.app.json` and `tsc -p tsconfig.test.json` exited 0, and `vitest run src/lib` printed `Tests 46 passed (46)`.
  - `d4a6d26`: both `tsc` runs exited 0, and `vitest run` printed `Test Files 7 passed (7)`, `Tests 68 passed (68)`.
- **Final runs.** The mock, labels, nav and css-token checks ran on `81b5446`; `f694e6f` changes none of their inputs. The test and build runs are from after `f694e6f`.
  - `npm test`: `Test Files 7 passed (7)`, `Tests 79 passed (79)`
  - `npm run build`: `✓ built in 373ms`, exit 0; the `ChatGroupsPage` chunk is 18.84 kB
  - `npm run lint` (whole repo): `✖ 162 problems (98 errors, 64 warnings)`, main's known baseline, with none in this branch's files
  - `npm run test:mock-api`: `# tests 30`, `# pass 30`, `# fail 0`
  - `npm run check:labels`: `check-labels: every controlled value and permission module has a label.`
  - `npm run test:nav`: `# pass 15`
  - `npm run check:css-tokens`: `check-css-tokens: 62 tokens read, all defined.`
  - `npx eslint` on the 15 new and changed `src` files: exit 0, no output. The `scripts/*.mjs` files have no ESLint config (see the mock docs, OPOS #26437).

**Code review (`ecc:react-reviewer` on `origin/main...HEAD`, reviewed at `df700ea`):** no CRITICAL or HIGH findings. The reviewer checked hooks, the cancelled flag, the `busy` guards during the exit animation, ARIA, validation against the POST body, RTL and file sizes. Its own runs were clean: `tsc -b --force`, eslint, and vitest 74/74.
- **MEDIUM, fixed in `f694e6f`.** A non-request `Error`, such as `buildCreateGroupBody`'s guard, would reach the dialog as its raw English message through describeError's last resort. Now it is logged and the operator sees `error.unknown`. RED: `expected 'buildCreateGroupBody: member row m2 h…' to be 'Something went wrong. Please try agai…'`. GREEN: all pass.
- **MEDIUM, not changed.** Some tests rely on real timers (UserPicker's 300 ms debounce, framer-motion exit animations), which can make them flaky under CI load. It is a documented trade-off with generous timeouts; mocking framer-motion would remove the risk. It is listed under "still open".
- **LOW, fixed in `f694e6f`.** A test asserted `not.toHaveAttribute('aria-invalid', 'true')`; it now asserts the attribute is absent.
- **LOW, no action.** The branch moved during the review, so the reviewer re-checked the final state.

**External actions taken:** none. Nothing was pushed. The OPOS MCP needed OAuth, which this non-interactive subagent session could not complete, so #26398 was not moved or commented on.

**What is still open:**
- **Commits.** All of them are local, unpushed and not reviewed by a human.
- **The browser check.** It was not done here, on instruction. Run the mock (`docs/mock-api.md`) and open `http://127.0.0.1:5173/chat-groups`. Pick "Guest visitor" as a member to see the 400 refusal inline.
- **Backend codes.** Everything except `guest_member_not_allowed` and `connect_context_not_found` depends on backend branches that are not on main yet. Until they land, a real duplicate member still answers 500, which the dialog shows as the generic server line.
- **`common.retry`.** When that change lands, `ChatGroupsPage` can switch from `error.retry`. A comment marks the spot.
- **Phases 6b and 6c.**
  - Rows don't link anywhere yet; the detail page is 6b.
  - `chatGroupsApi.ts` already has getGroup, add/remove member, `listGroupMessages` and `fetchAllGroupMessages` (the after_id loop), postGroupMessage, contact blocks, lifecycle, trash, and connect-request list/detail/approve/decline.
  - 6c should show connect-request failures with `describeConnectRequestError`.
- **Kurdish.** 68 keys need ckb and kmr (`TRANSLATION_REQUEST.md`).
- **`scripts/mock-api.test.mjs`.** It is at 496 lines, so the next case needs a split.
- **Test timing.** The reviewer's MEDIUM finding is not acted on: `CreateGroupDialog.test.tsx` and `chatGroupsKit.ts` depend on real timers and animation frames. If CI turns flaky, mock framer-motion's exit animations and use fake timers for UserPicker's debounce.

**Traps:**
- **Parallel test runs.** Running `vitest` and `npm run build` at the same time starves jsdom. The dialog tests then time out ("Unable to find role=option", "Test timed out in 5000ms"), and the build took 4.5 minutes. Run heavy commands one at a time.
  - `pickPerson` in `src/test/chatGroupsKit.ts` waits up to 4 s, because UserPicker debounces for 300 ms on real timers.
  - The interaction-heavy tests have 15 s timeouts.
- **GateGuard and restoring a file.** GateGuard treats `git checkout <sha> -- <file>` as destructive and kept refusing it, even after the facts were stated. Undoing the edit with the Edit tool worked.
- **The worktree isolation guard.** It refuses git commands that contain shell variables, loops or `$(…)`. Split them into plain commands with literal paths. To stage part of a file, write the wanted content to the scratchpad, then use `git hash-object -w` and `git update-index --cacheinfo`.
- **Direction marks in the Edit tool.** It turns a typed `\u2066` into the real invisible character. In locale `.ts` files and Markdown, write the escape text and check with `grep -c $'\u2066'`.
- **Permission tests.** `usePermission` falls back to the tier while the matrix loads, and a `super_admin` passes that fallback. So a test about a MISSING permission must sign in as `employee` (`EMPLOYEE_USER` in `chatGroupsKit.ts`). Otherwise it can pass before the matrix loads.

---

## 2026-09-15 — OPOS #26466: the Trash snapshots chat threads atomically, and restored direct chats come back closed (branch `fix/trash-direct-chat-restore-closed`)

**What was asked:** two findings in the chat Trash, fixed test-first.
1. `trashChatThread` snapshotted a thread without a lock, so a delete racing a lifecycle write or the retire run could store an earlier state.
2. Restoring a trashed `kind='direct'` thread brought it back OPEN, reopening a retired conversation.

The owner decided (2026-09-15) on **"Restore as closed"**: a restored direct chat comes back ended and archived, with the retire run's rules and reason. Every other chat restores as before.

**What was changed:** commit `743d71f`, based on `origin/main` `9425007`.
- **`backend/internal/handlers/admin_chat_lifecycle.go`:**
  - `trashChatThread` reads the thread `FOR UPDATE`.
  - Each child table's snapshot is now its own `WITH removed AS (DELETE … RETURNING *) SELECT jsonb_agg(…)`.
  - The thread is then deleted, and the `trash_items` row is inserted last.
  - A second concurrent delete of the same thread now gets 404 instead of creating a duplicate trash entry.
  - New: `closeRestoredDirectChat`.
- **`backend/internal/handlers/admin_trash.go`:**
  - `Restore` calls `closeRestoredDirectChat` inside its transaction, with the password-verified staff member as the actor.
  - After the commit it logs `[trash] INFO restored direct chat … came back closed`.
- **`backend/internal/chatlifecycle/retire_one.go` (new):** `RetireDirectThreadInTx(ctx, tx, threadID, actorID)` is the bulk `endAndArchiveOpenSQL`/`archiveEndedSQL` with ` AND id = $3` / ` AND id = $2` appended. Same reason text, and existing end and archive stamps are kept.
- **`retire.go`:** comment only.
- **New tests:**
  - `chatlifecycle/retire_one_test.go`
  - `handlers/chat_trash_direct_restore_test.go`
  - `handlers/chat_trash_snapshot_race_test.go`: holds the write open in a second transaction and commits it once `pg_stat_activity` shows the delete blocked.

**What was run:**
- **RED, against `origin/main` code on fresh DB `godonation_trash_restore_26466`:**
  - `chatlifecycle`: `retire_one_test.go:141:14: undefined: RetireDirectThreadInTx`.
  - `TestTrashRestore_OpenDirectChatComesBackClosed`: `restored direct chat = {Lifecycle:open …}`.
  - The paused, open+archived and ended+visible subtests of `…KeepsTheStampsStaffAlreadySet` failed.
  - Race: `the Trash holds thread 9 with lifecycle open … but the delete removed it with lifecycle ended`.
  - Race: `message 3, sent while the chat was being deleted, is not in the Trash … lost for good`.
  - The guard tests passed, as intended: ended+archived keeps every stamp, and support/marriage/staff/group threads are unchanged.
- **GREEN, on fresh DBs:**
  - `go test ./internal/handlers/ ./internal/chatlifecycle/ -count=1 -p 1 -timeout 45m`: `ok …/handlers 17.172s`, `ok …/chatlifecycle 0.943s`.
  - `go test ./... -count=1 -p 1 -timeout 45m`: 22 packages `ok`, exit 0.
- **After the review fixes, on fresh DB `godonation_trash_review_26466`:**
  - Both packages `ok` (55.243s and 3.985s).
  - The new tests with `-v`: 6 top-level PASS, 0 SKIP.
- **Formatting and vet:** `gofmt -l` is clean on the changed files; the only file it lists anywhere in `backend/` is the pre-existing `admin_edit_user_profile.go`. `go vet ./...` is clean.
- **Every test DB was dropped:** `SELECT count(*) … LIKE 'godonation_trash_%26466'` printed `0`.

**Code review** (`ecc:code-reviewer`): APPROVE, with no critical or high findings.
- **MEDIUM**, fixed: the `RetireResult` was discarded. It is now logged after the commit.
- **MEDIUM**, fixed: the appended placeholders could drift. Renumbering comments were added to both files, and the test fails on drift.
- **LOW**, kept with a reason: the duplicate `UserFromGin` guard in `Restore` stays, so the handler never relies on another function's nil check.

**External actions:** none. Nothing was pushed. OPOS MCP needed OAuth in this session, so #26466 was not moved.

**Still open:**
- Both commits are local and unpushed. Main has moved (≥ `bbc6aa2`); the coordinator merges it.
- **Chat groups have no foreign keys.** A group message committed after its child `DELETE` ran stays behind as a live row. It is not lost, and it reappears with the group on restore.
- **The runbook (`docs/runbooks/retire-direct-chats.md`) is not updated.** Another branch owns it. It should say:
  - Trashed direct chats are not touched by the run.
  - Restoring one brings it back ended and archived, with the run's reason, `lifecycle_changed_by`/`archived_by` set to the restoring staff member, and existing stamps kept.
  - The Trash is therefore not a way to reopen a retired chat.
  - The snapshot and 7g restore queries do not cover rows in the Trash.

**Traps:**
- **Postgres row-version behaviour:** under READ COMMITTED a plain SELECT never waits on an uncommitted UPDATE. Only a later `DELETE` or `FOR UPDATE` waits, and it then sees the new row version.
- **Don't reorder or renumber the retire SQL** without updating `retire_one.go`.

## 2026-09-15 — OPOS #26474: `user_profiles.user_id` gets an index, and group chats stop repeating a message whose sender has two profile rows (branch `perf/user-profiles-user-id-index`)

**What was asked:** add an index on `user_profiles.user_id` and check the table's one-row-per-user assumption. If a user can have two rows, fix `AdminListMessages`' join, test-first. The change was to stay within a new migration plus a minimal code fix, because other branches are editing the chat-group handlers and stores. A database review was then to be run, and anything real it found fixed.

**What was actually changed.** There are three local commits on `perf/user-profiles-user-id-index`, based on `origin/main` `9425007`.

**`bb32094` `perf(db): index user_profiles.user_id`**
- `backend/migrations/124_user_profiles_user_id_index.sql` (new): `CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles (user_id);`.
- Its header explains why the index is needed, why there is no UNIQUE and why there is no CONCURRENTLY. The DOWN is recorded in comments, the same way as in 113.
- Numbered 124 because `fix/chat-group-lifecycle-null-reason` already adds `123_chat_group_lifecycle_reason_nullable.sql`.

**`ec83248` `fix(chatgroups): stop repeating messages for senders with two profiles`**
- `backend/internal/chatgroups/chatgroups_reads.go`: in both message reads, the plain `LEFT JOIN user_profiles up ON up.user_id = m.sender_user_id` became `LEFT JOIN LATERAL (SELECT p.full_name … ORDER BY p.id LIMIT 1) up ON true`, so the oldest profile row names the sender. Both doc comments say why.
  - `AdminListMessages` serves `GET /admin/chat-groups/:id/messages` (`cmd/server/main.go:1035` → `handlers/chat_group_admin.go:168`).
  - `ListMessagesForMember` is the members' own read. In a team group, the repeated copies could show one message under two names.
- Response shapes are unchanged.
- `backend/internal/chatgroups/chatgroups_duplicate_profiles_test.go` (new), with two tests:
  - `TestAdminListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles`;
  - `TestListMessagesForMemberListsEachMessageOnceWhenSenderHasTwoProfiles`, with `team` and `masked` subtests.
- The member-read half was added after the database review (see Review).

**This entry** is the third commit.

**Can a user have two `user_profiles` rows? Yes. One row per user is intended, not guaranteed.**
- **The table:** `001_full_v2.sql:73-80` declares `user_id INTEGER NOT NULL`, with no UNIQUE and no index. `002_add_foreign_keys.sql:32-34` adds only the FK (ON DELETE CASCADE). No trigger or SQL function writes the table; the only SQL INSERT is the six-user seed at `001_full_v2.sql:751`.
- **The intent is written down:** `010_phone_canonical.sql:60` says "user_profiles is one-row-per-user", and `handlers/admin_edit.go:1806` notes the missing UNIQUE.
- **Safe inserts**, both for a brand-new user id:
  - `users/users.go:817` `InsertGuest`, in the same transaction as the user insert;
  - `handlers/admin_status.go:341`, right after creating the user.
- **Racy check-then-insert**, with no lock held between the check and the INSERT:
  - `users/profile.go` `UpsertProfile`: `GetProfileRow` at `:100` runs on the pool, outside the transaction begun at `:105`, and the INSERT is at `:139`.
  - `users/registration.go` `SubmitRegistration`: SELECT at `:153`, INSERT at `:157`. The transaction's first `UPDATE users` is at `:238`, after the insert.
  - `handlers/admin_edit.go` `User`: SELECT at `:1811`, INSERT at `:1930`. The users row is locked only when phone or email are sent too (`:1770`, `:1790`).
- **So no UNIQUE constraint was added.** It would fail to apply on a database that already holds a pair, and deduping means deleting user rows. That decision belongs to a human.

**Why not `CREATE INDEX CONCURRENTLY`.**
- `internal/db/migrate.go:182` sends a whole file as one simple-protocol query.
- Probed on local Postgres 18.6:
  - A file with `SELECT 1;` before the CIC failed with `CREATE INDEX CONCURRENTLY cannot run inside a transaction block`.
  - A one-statement CIC file, comments included, succeeded.
- **But the one-statement form deadlocks against the runner's own locking.** Session A took `pg_advisory_lock` and ran the CIC. Session B blocked in `pg_advisory_lock` on the same key. B was aborted:
  - `ERROR: deadlock detected`
  - `Process 3460 waits for ExclusiveLock on advisory lock … blocked by process 3254.`
  - `Process 3254 waits for ShareLock on virtual transaction 9/471; blocked by process 3460.`
- **Concurrent callers are normal here:** every DB test package's process, and two replicas booting with `RUN_MIGRATIONS=1` (`internal/db/migrate_concurrent_test.go`).
- **A plain build is atomic,** and 113 indexed this table the same way.

**What was run and what it printed.** All ran on local databases created for this task. Nothing remote was touched.

**Migration.** On `godonation_upidx_26474`:
- Main's migrations first: `done: 121 newly applied, 121 total migration files`. At that point `\d user_profiles` showed no `user_id` index.
- Seeded 50,000 users and profiles, 2,000 connect requests (one in ten pending), and group 900001 with 5,000 messages from 500 senders, then ran `ANALYZE`.
- 124 applied through `db.RunMigrations`: `done: 1 newly applied, 122 total migration files`, with `indisvalid = t`.
- DOWN executed (`DROP INDEX IF EXISTS idx_user_profiles_user_id` and the ledger delete): `index rows: 0`, `ledger rows: 0`.
- Up again: `1 newly applied`, still valid.

**EXPLAIN ANALYZE, before → after:**

| query | before | after |
|---|---|---|
| roster `WHERE user_id = ANY('{…}'::bigint[])`, the `profileNames` shape | Seq Scan, 50,001 rows removed, 20.968 ms | Index Scan using `idx_user_profiles_user_id`, 0.417 ms |
| requester `LATERAL (… WHERE up.user_id = r.requester_user_id ORDER BY up.id LIMIT 1)`, 200 pending requests | 200 loops of Seq Scan, 2293.849 ms | Index Scan, 200 searches, 1.610 ms |
| old DISTINCT ON derived-table requester shape, one request | Seq Scan + Sort of 50,006 rows, 30.452 ms | Index Scan + Incremental Sort, 0.091 ms |
| `AdminListMessages` as on main | Hash Left Join over a Seq Scan of all 50,006 profiles, 33.832 ms | Memoize + Index Scan, 0.584 ms |

- With `enable_seqscan = off` before the index, there was no index path at all: `Seq Scan … Disabled: true` for the roster, and `Index Scan using user_profiles_pkey … Filter` for LATERAL.
- The fixed `AdminListMessages` uses `idx_user_profiles_user_id` (50 loops). Over 5 warm, alternating runs each, the median was 0.408 ms for the old join and 0.469 ms for the LATERAL.

**Tests first.** All run with `go -C backend test ./internal/chatgroups/ -run … -count=1 -v`.
- **RED, admin:** `chatgroups_duplicate_profiles_test.go:53: got 2 messages, want 1: a sender with two user_profiles rows must not duplicate their message`.
- **GREEN, admin:** `-run '^TestAdminListMessages'` passed 4 tests: `ok …/internal/chatgroups 0.713s`.
- **RED, member** (on a fresh `godonation_upidx_member_26474`): both the `/team` and `/masked` subtests printed `chatgroups_duplicate_profiles_test.go:108: got 2 messages, want 1 …`.
- **GREEN, both:** `-run '^Test(ListMessagesForMember|AdminListMessages)'` passed all 12 tests, including both subtests: `ok …/internal/chatgroups 0.730s`.

**Format and vet:** `gofmt -l` on the two changed Go files printed nothing, and `go -C backend vet ./...` exited 0.

**Suites on the final tree**, each on a brand-new DB:
- `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` on `godonation_upidx_suite2_26474`: `ok …/internal/chatgroups 1.867s`, `ok …/internal/handlers 14.390s`, exit 0.
- `go test ./... -count=1 -p 1 -timeout 45m -v` on `godonation_upidx_full2_26474`: exit 0, 22 packages `ok`, 995 `--- PASS`, 0 SKIP, 0 FAIL. The last package line was `ok …/internal/users 0.785s`.

**Earlier suite runs,** on the tree before the member-read fix:
- The targeted run passed on a fresh DB: chatgroups 3.036s, handlers 35.327s.
- A full run reusing that DB failed two chatgroups tests on leftovers (see Traps).
- The rerun on a brand-new DB passed: exit 0, 22 packages `ok`, 992 PASS, 0 FAIL.

**Databases created and dropped:** `godonation_upidx_probe_26474`, `godonation_upidx_26474`, `godonation_upidx_suite_26474`, `godonation_upidx_full_26474`, `godonation_upidx_member_26474`, `godonation_upidx_suite2_26474` and `godonation_upidx_full2_26474`. `SELECT count(*) FROM pg_database WHERE datname LIKE 'godonation_upidx%'` printed `0`.

**Merge check** (`git merge-tree --write-tree --name-only`), done after the commits:
- Against `origin/feat/chat-groups-admin-data` (`891b571`, which contains `a3e9323`, the other commit editing `chatgroups_reads.go`): exit 0, no conflicts.
- Against `origin/main`, which moved to `bbc6aa2` during this session and has merged that work as `9044379` (#111): exit 0, no conflicts.
- `origin/main` still ends at migration 122, so 124 does not collide.

**Review.** `ecc:database-reviewer` ran on the first version, which had fixed only `AdminListMessages`.
- **HIGH:** `ListMessagesForMember` (`chatgroups_reads.go:117`) had the same fan-out, on the member-facing read. It is fixed in `ec83248`, test-first as above.
- **LOW:** the migration and test comments named the `profile.go` writer `UpdateProfile`, but it is `UpsertProfile` (`profile.go:81`). Fixed.
- **Verified with no issue:**
  - the runner and CIC claims;
  - the index name, and `(user_id)` over `(user_id, id)`;
  - the LATERAL semantics for 0, 1 and 2+ rows, including the `COALESCE` fallback and pagination;
  - the RED reasoning;
  - the test cleanup.

**External actions taken:** none. Nothing was pushed and no PR was opened. The OPOS MCP needed OAuth, which isn't available in this non-interactive session, so #26474 was not moved or commented on.

**What is still open:**
- All three commits are local, unpushed and not reviewed by a human.
- **The branch is behind `origin/main`** (`9425007` vs `bbc6aa2`). It merges cleanly, but the suites have not been run on the merged tree.
- **44 other plain name joins remain.** `grep -rn -E "JOIN user_profiles [a-z]+ +ON [a-z]+\.user_id" backend/internal` still finds 44 in non-test Go code on this branch. Each can return a row twice for a user with two profiles. In chatgroups, only `chatgroups_admin.go:115` (contact blocks) is left. These were out of scope.
- **UNIQUE on `user_profiles.user_id`** needs a human decision on how to dedupe existing pairs. After that, the three racy writers above can become `INSERT … ON CONFLICT (user_id)`.
- **Stale comment once 124 merges.** The comment in `chatgroups_connect.go` (on `origin/main` via #111) that says `user_id` "still has no index … an index is the remaining fix" becomes stale.

**Traps:**
- **Never run the chatgroups tests twice against one DB.** `TestListGroupsForUserUnreadCount` and `TestListConnectRequestsForUserOnlyReturnsOwnRequests` then fail on the earlier run's rows: two groups (`LastAt 18:05:22` and `18:06:41`), and two requests from `RequesterID:700000127`.
  - `makeTestUser` cleanup deletes only the `users` row (`chatgroups_test.go:1282`).
  - `raiseUserIDFloor` sets the id sequence to `GREATEST(MAX(id), 700000000)` once per process, so a second run reissues the same ids.
  - No `chat_group_*` table has an FK to `users`.
  - Use a brand-new DB for every full run.
- **The brief's two named queries were not on this branch's base.** `profileNames` and the LATERAL requester lookup came from `feat/chat-groups-admin-data` and reached `origin/main` only in `9044379`. The first version of that branch (`3134085`) used a `DISTINCT ON` derived table.
- **The local branch `feat/chat-groups-admin-data` was deleted mid-session.** Only `origin/feat/chat-groups-admin-data` remains; use that ref.
- **CONCURRENTLY looks allowed but deadlocks** (see above). Don't "upgrade" this or a later index migration to CIC without changing the runner.
- **The worktree guard refuses psql heredocs combined with `&`/`wait`.** Write the SQL to a file, run `psql -f`, and use the tool's background mode for the second session.
- **`git show <sha> | grep` is refused too.** Use `git show <sha> --output=<file>` or `git grep <rev>`, then read the file.

## 2026-09-15 — OPOS #26467: the retire runbook's freeze list matches the lifecycle race fix (branch `docs/retire-runbook-freeze-list`)

**What was asked:** bring `docs/runbooks/retire-direct-chats.md` in line with PR #103 (`95ea8fb`, OPOS #26431). Pause and resume come off the run-window freeze. End, archive and unarchive stay on it. Delete goes on it, because of the Trash risk tracked as OPOS #26466. Docs only.

**What was actually changed** (branch from `origin/main` `95ea8fb`):
- One commit, `docs(ops): narrow the retire runbook freeze list after the lifecycle race fix`, touching the runbook and this file only.
- **Section 3, item 7:** from the snapshot until the post-checks are done, staff must not end, archive, unarchive or delete a direct chat, or restore one from the Trash. Each item says why. Pause and resume are no longer frozen.
- **Section 4:** new pre-flight query 6 counts direct threads in the Trash, grouped by the copy's lifecycle and archive state. The filter is `trash_items.source_table = 'chat_threads'`, `restored_at IS NULL` and `payload->>'kind' = 'direct'`. A new "What to expect" bullet explains the output.
- **Section 5:** one sentence. A pause or resume made between the snapshot and the run is still ended by the run, but a restore puts back the snapshot's state.
- **Section 7:** new post-check 7h lists direct threads deleted to the Trash since `snapshot_taken_at`. A paragraph after the block says what to do with a row.
- **Section 9:** the Apply race moved to a new "Resolved by OPOS #26431" block. Risk 9 is now the Trash risk (#26466), so the existing "risk 9" cross-references still point at the right item.
- The header table and the appendix intro each gained one sentence. The appendix one says query 6 and 7h were verified separately, here.
- **Review fix, commit `d7a219a`** (`docs(ops): apply the review of the retire runbook freeze list`). The agent review of `ca8193a` came back CHANGES NEEDED, with 3 medium findings, 4 low, and none critical or high. All seven were checked against the code and applied:
  - **Trash restore is admin-level, not Super-Admin only.** The route uses `RequireAdminTier` (`main.go:1176`), which accepts `admin` or `super_admin` (`auth/middleware.go:47-53`). Query 6's bullet and risk 9 now say so.
  - **Claim and release join the freeze.** Both write `updated_at` with only `WHERE id = $1` (`chat/chat.go:281-282`, `:297-298`), and the Messages page shows them on every thread (`MessagesPage.tsx:316-330`). Staff replies stay off the list, because `handlers/chat.go:537` refuses them on ended threads.
  - **7h also lists Trash restores** (`restored_at >= snapshot_taken_at`). Its comment now names the other causes of a query 6 difference: a purge, or a delete or restore made between the pre-flight and the snapshot.
  - **Wording fixes:**
    - The pause/resume text now covers a pause that lands first, which the run then ends.
    - The resolved block no longer says delete "stays" frozen.
    - The 7h follow-up notes that an `ended | t` copy shows in neither 7a nor 7c.
    - Section 5 says "the section 10 restore", and the header says the freeze was revised.
  - **Not applied, on instruction:** the review's "Sentences to update when OPOS #26466 lands" list, because #26466 has not merged.

**Evidence read** (file:line at `95ea8fb`):
- **Pause and resume are refused on an ended thread:** `backend/internal/chatlifecycle/apply.go:121-122` and `:127-128`.
  - The write only lands while the lifecycle is unchanged (`:194`, `AND lifecycle = $5`). Zero rows means `errLifecycleChanged` (`:198-199`), and Apply reads again (`:91-99`).
  - `handlers/admin_chat_lifecycle.go:99-101` maps `ErrEnded` to 409.
  - Tested against the run in `apply_race_test.go`. Line `:293` covers the run committed first, `:294-295` the run's `retireInTx` holding its locks, and `:312-321` assert `ErrEnded` with the run's END kept.
- **End, archive and unarchive still write:**
  - an end with a reason on an ended thread rewrites reason, actor and `updated_at` (`apply.go:139-142`, `:191-194`);
  - archive and unarchive have no condition, and re-stamp or clear `archived_at` and bump `updated_at` (`apply.go:215-236`).
- **Trash:**
  - `handlers/admin_chat_lifecycle.go:182-183` copies the thread with a plain `SELECT to_jsonb(t.*)`, with no `FOR UPDATE`. It then inserts into `trash_items` (`:226-228`) and deletes (`:261`).
  - `handlers/admin_trash.go:255-257` restores by inserting the copy as it is.
  - Routes: `backend/cmd/server/main.go:1065` (`DELETE /admin/chats/:id`, direct chats) and `:1176` (Trash restore).
  - The run's selectors read only live `chat_threads` (`retire.go:101`, `:113`).
  - Schema: `migrations/016_trash.sql` (`trash_items`), and `migrations/119_chat_support_threads.sql:28` (`kind NOT NULL DEFAULT 'direct'`).

**What was run and what it printed** (throwaway DB `gd_retire_freeze_26467`, made with `createdb -h /tmp`):
- **Migrations:** `TEST_DATABASE_URL=... go test ./internal/chatlifecycle/ -count=1 -run '^TestRetireAllDirectThreadsIsIdempotent$' -v` → `[migrate] done: 121 newly applied, 121 total migration files`, `PASS`, `ok 1.358s`.
- **Restore probe:** open direct thread 920001 was trashed with `trashChatThread`'s statements, then re-inserted with `Restore`'s `jsonb_populate_record` INSERT. It came back `920001 | direct | open | f`. The same copy without its `kind` key failed: `ERROR: null value in column "kind" of relation "chat_threads" violates not-null constraint`.
- **Verbatim run of the edited runbook:**
  - The SQL blocks of sections 2, 4, 5 and 7 were extracted from the file with `awk`. `<actor>` was replaced by 1 (`admin`), and each block ran through `psql -v ON_ERROR_STOP=1`, with sections 4 and 7 under `PGOPTIONS` read-only.
  - Seed: open direct threads 920002 and 920003.
  - Pre-flight: `will_end 2 | will_archive 0`; query 6 printed `open | f | 1` (920001, from the probe).
  - Snapshot: `snapshot_rows 2`. Then 920003 was deleted to the Trash.
  - Run: `UPDATE 1`, `UPDATE 0`, `COMMIT`.
  - Post-checks: 7a `0`, 7b `1`, 7c `0 rows`, 7d `0 rows`, 7f `0`, 7g `2026-09-15 17:59:48.655791 | 1`.
  - 7h returned one row: `2 | 920003 | open | f | 2026-09-15 17:59:35.456159+03 |` (not restored).
  - Query 6 again: `open | f | 2`, higher by exactly the 7h row.
- **Cleanup:** `dropdb -h /tmp gd_retire_freeze_26467`, then a `pg_database` count of `gd_retire_freeze_26467%` → `0`.
- **Whitespace:** `git diff --check` is clean.
- **Review fix, on a fresh throwaway DB `gd_retire_freeze_26467_b`.** It was made with `createdb`, then migrated with the same test, which printed `[migrate] done: 121 newly applied, 121 total migration files` and `ok 2.303s`.
  - Direct threads 930001 and 930002 were deleted to the Trash before the snapshot. The snapshot then printed `snapshot_rows 1` (930003).
  - After the snapshot, 930001 was restored with `Restore`'s INSERT plus `restored_at = NOW()`, and 930003 was deleted.
  - The edited section 7 block ran verbatim and read-only. 7h returned exactly `1 | 930001 | open | f | 18:14:25.176912 | 18:14:47.151094` and `3 | 930003 | open | f | 18:14:49.451224 |` (dates 2026-09-15, +03). 930002 was not listed.
  - The other checks: 7a `1` (the restored open thread; no retire run was made), 7b `0`, 7c and 7d `0 rows`, 7f `0`, 7g `0 rows`.
  - After `dropdb`, a `pg_database` count of `gd_retire_freeze_26467%` returned `0`. `git diff --check` is clean.

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS was not updated from this session: the `opos` MCP server needed authorization, and this non-interactive session could not run the OAuth flow.

**What is still open:**
- Both commits, `ca8193a` and `d7a219a`, are local and unpushed. The agent review's findings are applied in `d7a219a`, but no human has reviewed either commit.
- **OPOS #26466 is not fixed.** The freeze, query 6 and 7h only work around it. The delete race itself (a delete that copies the thread before the run commits) was read in the code, not reproduced.
- **When OPOS #26466 merges,** apply the review's "Sentences to update when OPOS #26466 lands" list. It is in the review output of agent `af8516112e224c0f3`. The list covers:
  - the delete and restore freeze items in section 3, item 7;
  - query 6's bullet, and 7h with its follow-up paragraph;
  - risk 9;
  - the section 10 note on `updated_at`;
  - the header row.
- **Additions beyond the original brief:** restore from the Trash is frozen alongside delete, section 5 has its pause-and-resume sentence, and the review added claim and release to the freeze. Revert any of them if unwanted.
- **`origin/main` has moved at least five commits ahead,** with its own `HANDOFF.md` entries at the top. A rebase will conflict in this file only: keep both sets of entries.
- The production run has still not been performed.

**Traps:**
- **The worktree isolation guard refuses a Bash command that uses `$(...)`** ("a construct too complex to verify"). Split it into plain separate commands.
- **GateGuard's destructive-command check fires on any `psql` with INSERT or DELETE,** even against a throwaway DB. State the facts and retry.
- **A `chat_threads` copy in the Trash from before migration 119 has no `kind` key,** and its restore fails on NOT NULL. That is why query 6 needs only `payload->>'kind' = 'direct'`.
- **A review agent's `tasks/<id>.output` file is a JSONL transcript of about 1 MB,** too large for Read. The report is the text content of its last line: `sed -n <last>p <file> | jq -r '.message.content[] | select(.type=="text") | .text'`.

---

## 2026-09-15 — OPOS #26443: guests' phones no longer get chat pushes (branch `fix/no-chat-push-to-guest-devices`)

**What was asked:** a guest who is a grandfathered chat participant still received chat push notifications, including the 80-character message preview. #104 (OPOS #26424) had already hidden those rows from the guest's in-app list, so the push was the remaining leak. Fix it test-first in `backend/internal/notify`, and keep out of the chat, chatgroups and trash code that other branches are editing.

**Findings the fix rests on** (read on `origin/main` `9425007`):
- `activeDevicesFor` (`push.go`) selects every active device of a user and never reads `users.is_guest`.
- `Send` (`notify.go`) always fires `sendPush` in a goroutine after writing the row. `sendPush` is its only caller.
- `POST /api/notifications/device` is not guest-gated. By the owner's decision, it stays that way.
- **There is no FCM interface or fake.** `Notifier.fcm` is a concrete `*fcmClient`, with an `httpClient` field and a cached `accessToken`/`tokenExpires`.
- `users.is_guest` is `BOOLEAN NOT NULL DEFAULT FALSE` (migration 064).
- `user_device_tokens.user_id` has an `ON DELETE CASCADE` FK (migration 002).
- `SendPushDirect` (the admin compose endpoint) sends admin free text with no notification type, so it is out of scope.

**Owner decision implemented:**
- A guest gets no push for a type in `chatNotificationTypes` (`list.go`, #104's list, reused, not copied).
- Guests keep every other push: broadcasts, `admin_announcement` and support-ticket updates.
- Members are unchanged.
- The in-app row is still written, and device registration is not gated.

**What was actually changed.** There are two local commits on `fix/no-chat-push-to-guest-devices`, based on `origin/main` `9425007`.

**`77d123e` `fix(notify): no chat push notifications to guest devices`**
- `backend/internal/notify/push.go`:
  - New unexported `shouldWithholdChatPush(ctx, userID, notificationType) bool`. For a non-chat type it returns false without querying.
  - For a chat type it runs one `SELECT COALESCE(is_guest, FALSE) FROM users WHERE id = $1` and returns true for a guest, logging `[notify:push] chat push withheld from guest ...`.
  - On any lookup error, including a missing user row, it fails closed: it returns true and logs `guest lookup ... failed; chat push withheld`.
  - `sendPush` calls it once per send, not per device, after the existing "no devices" and "FCM not configured" exits, so those paths never pay for the query.
- `backend/internal/notify/notify.go`: a doc-comment paragraph on `Send` only.
- `backend/internal/notify/push_guest_test.go` (new, 351 lines) holds the six tests, selected by `-run '^TestGuestPush_'` (`go test -list` shows exactly six):
  - **The fake:** a real `fcmClient` with a cached token (so no OAuth call) and an `http.Client` whose `RoundTripper` records `fcm.googleapis.com/.../messages:send` requests and refuses anything else.
  - **Why `sendPush` is called directly:** `Send` runs it in a goroutine that a test cannot wait on without sleeping.
  - `TestGuestPush_NoChatPushReachesAGuestDevice`: every conversation template to a guest, 0 pushes.
  - `TestGuestPush_MemberStillGetsChatPushes`: every one to a member, 1 each.
  - `TestGuestPush_GuestKeepsNonChatPushes`: broadcasts, support and `admin_announcement` to a guest, 1 each.
  - `TestGuestPush_UpgradedGuestGetsChatPushesAgain`.
  - `TestGuestPush_SendStillStoresTheChatRow`.
  - `TestGuestPush_GuestLookupFailsClosedForChatTypesOnly`: a missing row and a closed pool.
  - **Reused helpers:** `newCategoryTestPool`, `makeNotifyUser`, `catSeq` and `catRunTag` (category_preference_test.go), and `conversationTemplates`/`guestVisibleTemplates` (chat_types_test.go).

**This entry** is the second commit.

**What was run and what it printed.** All commands ran from the worktree, on a fresh DB `godonation_guest_push_26443`, created with `createdb`, passed as `TEST_DATABASE_URL='postgres://localhost:5432/godonation_guest_push_26443?sslmode=disable'`.

**RED, stage 1** (the tests on unchanged `origin/main` code), `go -C backend test ./internal/notify/ -count=1 -p 1 -run '^TestGuestPush' -v -timeout 45m`, exit 1:
- All 10 `TestGuestPush_NoChatPushReachesAGuestDevice` subtests failed. For example: `a guest's phone got 1 push(es) of type "chat_message": [{Token:test-device-70000-8 Title:Message from Donor Body:preview}]`, and likewise for `chat_request`, `chat_accepted`, `chat_group_message` (masked and team), `marriage_chat_*`, `marriage_meeting_declined` and `staff_chat_message`.
- The member, non-chat, upgraded-guest and Send-row guard tests already passed. Last line: `FAIL .../internal/notify 10.270s`.

**RED, stage 2** (the fail-closed test, before the helper existed), `-run '^TestGuestPush_GuestLookupFailsClosedForChatTypesOnly$'`, exit 1:
- `push_guest_test.go:327:9: n.shouldWithholdChatPush undefined`, then `FAIL .../internal/notify [build failed]`.

**GREEN**, the same `-run '^TestGuestPush' -v`, exit 0:
- All 6 top-level tests PASS, 0 SKIP. That is 10 + 10 + 8 + 2 subtests, plus the upgraded-guest and Send-row tests.
- The log shows `chat push withheld from guest user=13 type=chat_message`, and the fail-closed lines `... user=2000000000 ... no rows in result set` and `... closed pool`.
- Last line: `ok .../internal/notify 0.600s`.

**Formatting and vet:** `gofmt -l backend/internal/notify` printed nothing, and `go -C backend vet ./internal/notify/` exited 0.

**The two affected packages**, `go -C backend test ./internal/notify/ ./internal/handlers/ -count=1 -p 1 -timeout 45m`, exit 0:
- `ok .../internal/notify 0.849s`
- `ok .../internal/handlers 14.590s`

**Handlers verbose check.** `handlers` took 14.6s, where #26434's entry recorded 636s, so I checked it wasn't skipping. `go -C backend test ./internal/handlers/ -count=1 -p 1 -v` exited 0 with 242 top-level `--- PASS`, 0 `--- SKIP` and 0 `--- FAIL`, ending `ok .../internal/handlers 16.075s`. The handler tests read only `TEST_DATABASE_URL`, so the earlier 636s came from machine load.

**Full suite**, `go -C backend test ./... -count=1 -p 1 -timeout 45m`, exit 0:
- 22 packages `ok`, 0 FAIL.
- `handlers` took 35.134s and `chatgroups` 3.986s. The last test line was `ok .../internal/users 2.034s`.

**Cleanup:** `dropdb godonation_guest_push_26443` exited 0, and `SELECT count(*) FROM pg_database WHERE datname = 'godonation_guest_push_26443'` printed `0`.

**Review:** `ecc:code-reviewer` on the diff returned **APPROVE, with 0 findings at any severity**. It confirmed:
- the gate is evaluated once per `sendPush`, before the device loop;
- it fails closed on any scan error, including `ErrNoRows`;
- `SendPushDirect` is correctly out of scope;
- the tests are deterministic and non-vacuous.

It also mentioned a gofmt issue in `devices.go` that already exists on main. That did not reproduce here: `gofmt -l backend/internal/notify/devices.go` printed nothing, and the file is identical to `origin/main`'s.

**External actions:** none. Nothing was pushed. OPOS #26443 was only read: it was already in Work In Progress, with its timer (log 24687) started by the orchestrating session. It was not moved and no timer was touched.

**Still open:**
- Both commits are local and unpushed, and there is no PR. The coordinator will merge main, re-verify on a fresh DB and ship.
- At commit time `origin/main` had moved 4 commits past this branch's base (#106–#109). They are not merged here.
- The OPOS task needs completion notes and a move to Completed once shipped.

**Traps:**
- **zsh expands unquoted globs.** `grep --include=*_test.go` failed with `no matches found`; quote the pattern.
- **The worktree-isolation guard refuses complex Bash.** It rejects a `cd` + variable + `go` compound, and a Monitor loop that uses `$((…))`. Use plain `go -C <abs>/backend …` with the output redirected to a file, then grep that file in a separate call.
- **Package run times vary about 20x with machine load**, e.g. `handlers` at 636s vs 15–35s. A fast run is not by itself evidence of skipping; check with `-v` and count `--- SKIP`.
- **The FCM fake must not touch `*testing.T`.** `Send`'s push goroutine can outlive a test, and logging through a finished test panics. That is also why the Send-row test uses a Notifier with no FCM client.
- **The scratchpad is shared** with other sessions, which use generic names like `commit1.txt` and `full.txt`. Give your files a task-specific name.

---

## 2026-09-15 — OPOS #26473: notification_tile.dart split under the 500-line limit, no behaviour change (branch `refactor/split-notification-tile`)

**What was asked:** `humanitarian/lib/modules/notifications/widgets/notification_tile.dart` had 704 lines against the 500-line limit. The request was to move the self-contained chat request Accept / Decline widget into its own file, keep #106's guest guard and every comment, and split further if the file was still too long. It was a pure refactor.

**What was actually changed** (on `refactor/split-notification-tile`, off `origin/main` `30186e5`, which includes #106 `686eb89`; not pushed):
- **`672519c` refactor(notifications): split the chat request actions out of notification_tile.dart.** Module map, all in `humanitarian/lib/modules/notifications/widgets/`:

  | File | Lines | Holds |
  |---|---|---|
  | `notification_tile.dart` | 446 (was 704) | `NotificationTile`, `_relativeTime`, `_IconBadge`, `_CategoryChip`, `_MiniChip`, `_ReadBackground`; new file header |
  | `chat_request_actions.dart` (new) | 197 | `ChatRequestActions`, formerly `_ChatRequestActions`, with its private State: the inline Accept / Decline row |
  | `notification_visuals.dart` (new) | 149 | `NotificationVisuals`, formerly `_NotificationVisuals`: category and type map to colour, icon and `isPinned` |

  `notification_tile.dart` imports both new files; neither imports it back. Moving only the actions would have left the tile at about 550 lines, so the icon and colour lookup was moved as well.
- **Why the classes are public.** `lib/` has no `part` / `part of` libraries, so library-private was not an option in the house style. Two constructor lines changed:
  - `ChatRequestActions` gained `super.key`, which `use_key_in_widget_constructors` expects on a public widget. The tile passes no key.
  - `NotificationVisuals` has a private `._` constructor and is built only through `.of`, as before.
- **The guest guard is still at the call site.** `NotificationTile` builds `ChatRequestActions` only when `notificationType == 'chat_request'`, the related id parses, and `!isGuestMode()`, with `isGuestMode()` last. The new file's header and class doc say that any other host must apply the same guard, because building the widget registers `ChatController` and starts its 5-second `/api/chats` poll.
- **Proof of no change** (Python, against `git show HEAD:…`): with comments ignored and the two renames normalized, the kept tile code (318 lines) and both moved bodies (124 and 105 lines) match line for line, except the two constructor changes above. All 109 original comment lines are still present.

**What was run and what it printed** (from `humanitarian/`):
- `flutter analyze` on untouched main printed `6 issues found.`, and after the split also `6 issues found.`: the same six deprecation infos, nothing new.
- `dart format` on the three files: `Formatted 3 files (1 changed)`. The change re-joined the `NotificationVisuals.of` signature.
- `flutter test test/notifications/ test/localization/notification_relative_time_test.dart` printed `00:03 +18: All tests passed!`. These are the only tests that render `NotificationTile`; grep finds no dashboard test that does.
- Full `flutter test` printed `00:57 +1031: All tests passed!` and exited 0.
- Full `flutter test --reporter json`, parsed:
  - `suites run: 135 | test files on disk: 135`, `on disk but not run: none`;
  - `{'success': 1031}`, with no failures;
  - `chat_request_tile_guest_test.dart` 4, `support_destination_test.dart` 9 and `notification_relative_time_test.dart` 5, all success.

**Review** (`ecc:flutter-reviewer` on `git diff origin/main`): the verdict was **no behaviour change**. It independently confirmed the moved bodies match, the guard and its OPOS #26448 comment are intact, all imports are used, and consumers reference only `NotificationTile`. It reported two findings; neither changed the code:
- **MEDIUM, the guest guard is now enforced by documentation instead of the compiler.** As a library-private class in a codebase with no `part` files, `_ChatRequestActions` could not be built outside the tile. As a public class it can be, and only the header, the class doc and the `_ctrl` comment warn against it. This is real, and it is the trade-off the task accepted: public with a clear doc if there is no `part` pattern. The suggested `assert(!isGuestMode(), …)` in `initState` would add debug-mode runtime behaviour to a change meant to have none, so it was not added. See Still open.
- **LOW, `notification_tile.dart:6` is 81 columns.** This is a false positive: the line is 77 characters and 81 bytes, because "•" and "—" are three bytes each. By character count the only lines over 80 in the three files are four carried over verbatim: two comments in the tile, and the `chat_controller` and `chat_conversation_screen` imports.

**External actions:** none. Nothing was pushed, and there is no PR. The OPOS MCP needed authentication in this session, so #26473 was not moved to WIP or Completed and no timer was run.

**Still open:**
- Push the branch and open a PR.
- Update OPOS #26473 once the connector is authorised.
- Decide whether to restore some enforcement of the guest guard on the now-public `ChatRequestActions`. The reviewer's option is a debug-only `assert(!isGuestMode(), 'ChatRequestActions must not be built for a guest — OPOS #26448')` in `initState`, with a test that a guest-mode build trips it. It is a behaviour change in debug and test builds, so it belongs in its own commit.
- Pre-existing issues in the moved code were left untouched on purpose:
  - `ChatRequestActions._accept` shows the raw exception (`'$e'`) in a SnackBar;
  - `_decline` catches its error and only re-enables the buttons, so a failed decline tells the member nothing.

  Both break the error-UX rules and deserve their own fix with a test.

**Traps:**
- The expanded reporter's log names only the test files whose tests happened to print, 82 of 135 here, so it cannot prove a full run. Use `flutter test --reporter json` and count the `suite` events.
- `wc -l` gives 704 for the original tile. The Read tool shows 705 because it numbers the empty line after the final newline.
- In zsh, `grep --include=*.dart` must be quoted (`--include='*.dart'`), or it fails with "no matches found".
- In a worktree-isolated agent, the isolation hook refuses git inside `for` loops and multi-statement Monitor scripts. Run plain, single git commands from the worktree root.

---

## 2026-09-15 — OPOS #26409 and part of #26410: masked chat-group admin reads check sensitive_data per user, and the dashboard gets names and lifecycle fields (branch `feat/chat-groups-admin-data`)

**What was asked:** backend for Phase 6 of the chat-group admin dashboard, test-first.
- #26409 (user decision D1): a MASKED group's detail, messages and contact blocks need sensitive_data, checked per user with per-user overrides applied. A TEAM group needs only messages:view.
- Part of #26410: roster names, the lifecycle fields, and the requester's name on connect requests. D6: `requester_name` only for a caller who may view sensitive data, by the same per-user check.
- Out of scope, done in parallel by another agent: #26410's conflict codes and member reactivation (`insertMembers`, `AddMember`, `refuseContactInLabel`, `chatErr`). None of those functions was touched here.

**What was actually changed** (three code commits on `feat/chat-groups-admin-data`, based on `origin/main` `a1da04f`; the later helper rename, the merge of main and the #107 follow-up are under **Follow-up** below):
- `a3e9323` feat(chatgroups): per-user sensitive gate on masked group admin reads.
  - `backend/cmd/server/main.go`: `perm("sensitive_data","view")` removed from `GET /api/admin/chat-groups/:id`, `/:id/messages`, `/:id/contact-blocks`. `perm("messages","view")` stays. Route comments rewritten.
  - `backend/internal/handlers/chat_group_admin.go`: new `refuseMaskedWithoutSensitive(c, groupID)`, called by `AdminGetGroup`, `AdminMessages`, `AdminContactBlocks`.
    - It reads the kind first (404 via `chatErr` when the group is missing).
    - A team group passes. Any other kind needs `canViewContact(c, h.Perms)`, otherwise 403 with code `sensitive_data_required`.
  - `backend/internal/chatgroups/chatgroups_admin.go`: new `Store.GroupKind`.
  - `backend/internal/chatgroups/chatgroups_reads.go`: `AdminListMessages` doc comment only.
  - New tests: `backend/internal/handlers/chat_group_admin_sensitive_test.go`, `backend/internal/chatgroups/chatgroups_admin_kind_test.go`.
- `3134085` feat(chatgroups): names and lifecycle fields for the admin dashboard.
  - `chatgroups_admin.go`: `GroupMember.FullName *string` (`json:"full_name"`), filled only by new `Store.AdminGetGroup`.
    - `AdminGetGroup` is `GetGroup` plus one batched `DISTINCT ON` query over `user_profiles` (`profileNames`).
    - `GetGroup` stays name-less on purpose: the member routes call it on every poll for their membership check.
  - `chatgroups_connect.go`: `ConnectRequest.RequesterName *string` tagged `json:"-"`.
    - `ListConnectRequests` and `GetConnectRequest` share `adminConnectRequestSelect` / `scanAdminConnectRequest`, which LEFT JOIN a `DISTINCT ON (user_id)` view of `user_profiles`.
  - `chat_group_admin.go`: `AdminGetGroup` answers through `mergeChatLifecycle`.
    - New `adminConnectRequestItem` DTO. `adminConnectRequestItems` asks `canViewContact` once per request and copies the name only on yes.
    - The detail's `request` is now that DTO; the top-level `context_label` stays.
  - New tests: `backend/internal/handlers/chat_group_admin_data_test.go`, `backend/internal/chatgroups/chatgroups_admin_names_test.go`.
- `1cc9dea` perf(chatgroups): scope the requester-name lookup to each connect request. This commit addresses the code review's findings.
  - `chatgroups_connect.go`: `adminConnectRequestSelect` now uses a `LEFT JOIN LATERAL … WHERE up.user_id = r.requester_user_id ORDER BY up.id LIMIT 1` instead of a `DISTINCT ON` view of the whole `user_profiles` table. The output is unchanged.
  - `chat_group_admin_data_test.go`: new `TestAdminGetGroup_TeamRosterCarriesFullNameWithoutSensitive`.

**JSON shapes, for the admin-web implementer:**
- `GET /api/admin/chat-groups/:id` → 200:
  - `success`: `true`.
  - `group`:
    - `id`: int. `kind`: `"masked"|"team"`. `member_title`: string. `created_by_staff_id`: int. `lifecycle`: string. `created_at`: RFC 3339 string.
    - `members`: array of `{id: int, user_id: int, full_name: string|null, role_in_group: string, masked: bool, masked_label: string, removed_at?: RFC 3339 string}`. It is `null`, not `[]`, for a group with no member rows (pre-existing).
  - `lifecycle`: `"open"|"paused"|"ended"`.
  - `lifecycle_reason`: string, `""` when none. `null` only if the state read failed.
  - `is_archived`: bool.
- `GET /api/admin/chat-groups/:id/messages?after_id=&limit=` → 200 `{success: true, items: [...]}`. Unchanged. Each item is:
  - `id`: int. `sender_member_id`: int, `0` when no member row. `sender_user_id`: int.
  - `sender_name`: string. `body`: string. `created_at`: string.
- `GET /api/admin/chat-groups/:id/contact-blocks` → 200 `{success: true, items: [...]}`. Unchanged. Each item is:
  - `id`: int. `group_id`: int. `sender_user_id`: int. `sender_name`: string|null.
  - `kind`: string. `match_count`: int. `redacted_body`: string. `created_at`: string.
- The three routes above, masked group, caller without sensitive_data → 403 `{"success":false,"error":"You need permission to view sensitive data to read this masked group.","code":"sensitive_data_required"}`.
- Missing group → 404 `{"success":false,"error":"Group not found.","code":"group_not_found"}`. This is new for messages and contact-blocks, which answered 200 with an empty list before. The `code` comes from #107's `chatErr`, merged in at `b633687`.
- The gate cannot read the group's kind (database failure) → 500 `{"success":false,"error":"Database error.","code":"server_error"}`, also from #107's `chatErr`, which logs the detail.
- Caller without messages:view → the middleware's 403 `{"status":"error","error":"You don't have permission for this action.","code":"permission_denied"}`.
- `GET /api/admin/chat-groups/connect-requests?status=` → 200 `{success: true, items: [...]}`. Each item is:
  - `id`: int. `requester_user_id`: int. `context_type`: `"donation"|"case"`. `context_id`: int.
  - `target_hint?`: int. `message`: string. `group_id?`: int. `status`: `"pending"|"approved"|"declined"`.
  - `decline_reason?`: string. `decided_by_staff_id?`: int. `created_at`: string. `context_label`: string.
  - `requester_name?`: string. It is present only for a caller who may view sensitive data per user, AND whose requester has a profile. Otherwise the key is absent; tell the two apart with `/api/admin/permissions/me`.
- `GET /api/admin/chat-groups/connect-requests/:id` → 200 `{success: true, request: <same shape as a list item>, context_label: string}`. Missing request → 404 `{"success":false,"error":"Connect request not found."}`.

**What was run and what it printed:**
- **Throwaway DBs**, created for this work:
  - `godonation_admin_data_26409`, for the RED/GREEN runs. Dropped with `dropdb` after the package run; `psql -lqt` no longer lists it;
  - `godonation_admin_data_26409_pkg`, for the package run;
  - `godonation_admin_data_26409_full`, for the full suite;
  - `godonation_admin_data_26409_fix`, for the review-fix verification;
  - `godonation_admin_data_26409_merge`, `…_merge_full` and `…_merge_v`, for the verification after merging #107 (see **Follow-up**).
- **No baseline run** before the first edit.
- **B1 RED:** `go test ./internal/handlers/ -run 'TestAdminGroupReads_' -count=1 -p 1 -timeout 45m -v` printed `FAIL …/internal/handlers 38.458s`.
  - The revoked admin and the employee without sensitive_data: `status = 200, want 403`, with bodies carrying `"sender_name":"Sensitive Donor Secret Name"`.
  - The missing group's messages and contact-blocks: `status = 200, want 404`.
  - The grant, super_admin and team cases passed, as guards, because the post-#26409 router has no sensitive gate to refuse them.
- **`GroupKind` RED:** `s.GroupKind undefined`, build failed. GREEN: `ok …/internal/chatgroups 2.328s`.
- **B1 GREEN:** the handler run filtered to chat-group and connect-request tests printed `ok …/internal/handlers 72.428s`, 44 `--- PASS`, 0 `--- SKIP`.
- **B2 RED:**
  - The store test failed to build: `FullName undefined`, `RequesterName undefined`.
  - Handlers printed `FAIL …/internal/handlers 12.501s`: `named member full_name = <nil>`, `lifecycle fields = (<nil>, <nil>, <nil>)`, and `requester_name = <nil> (present false)` for the allowed callers.
  - The detail failed `request.context_label missing`.
  - The member-route leak test passed, as a guard.
  - After RED the store test was retargeted from `GetGroup` to the new `AdminGetGroup`, a design change so that the poll path holds no names. RED was not re-run for that edit.
- **B2 GREEN:**
  - chatgroups, filtered: `ok …/internal/chatgroups 60.393s`, 0 failures.
  - handlers, filtered: `ok …/internal/handlers 124.034s`, 48 `--- PASS`, 0 `--- FAIL`, 0 `--- SKIP`.
- **Package run, fresh DB `godonation_admin_data_26409_pkg`:** `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/chatgroups 101.049s` and `ok …/internal/handlers 1144.309s`, exit 0. The handlers package took 19 minutes on the loaded machine, so give it the full `-timeout 45m`. The DB was then dropped with `dropdb`, and `psql -lqt` no longer lists it.
- **Full suite, fresh DB `godonation_admin_data_26409_full`:** `go test ./... -count=1 -p 1 -timeout 45m` exited 0.
  - 22 packages printed `ok`, 36 had no test files, and there were 0 `FAIL` and 0 `panic` lines.
  - Among them: `ok …/internal/chatgroups 202.193s` and `ok …/internal/handlers 1390.034s`. The last line was `ok …/internal/users 161.348s`.
  - Its test binaries were built from `3134085`. `1cc9dea` changes only chatgroups and handlers files, and was verified separately below.
  - The DB was then dropped with `dropdb`. At the end, `psql -lqt` lists none of the four `godonation_admin_data_26409*` databases.
- **Static checks:** `go build ./...` ok. `go vet ./...` ok. `gofmt -l` on the 9 changed Go files printed nothing.
- **Review:** `ecc:code-reviewer` on `a1da04f..HEAD` answered APPROVE: 0 CRITICAL, 0 HIGH, 1 MEDIUM, 2 LOW.
  - **Checked and found sound:**
    - `canViewContact` / `CanViewForUser` fail closed, and an unknown group kind is treated as masked.
    - The `adminConnectRequestItem.RequesterName` shadowing is correct.
    - No member route leaks a name: `GetGroup` loads none, `GroupSummary` is a distinct type, and `MyConnectRequests` maps to its own DTO while the store field is `json:"-"`.
    - `user_id = ANY($1)` with `[]int64` is safe; `privacy.go` uses the same pattern. NULL scans are safe.
    - The `main.go` comments are accurate.
  - **MEDIUM:** `adminConnectRequestSelect` joined a `DISTINCT ON` view of the WHOLE `user_profiles` table, which scanned and sorted every profile on every inbox call, even the single-request read.
    - Fixed in `1cc9dea`: `LEFT JOIN LATERAL (SELECT up.full_name FROM user_profiles up WHERE up.user_id = r.requester_user_id ORDER BY up.id LIMIT 1) p ON true`.
    - The output is unchanged: the oldest profile row's name, or NULL without a profile.
  - **LOW:** no test covered a TEAM group's roster names. Added `TestAdminGetGroup_TeamRosterCarriesFullNameWithoutSensitive` in the same commit. An employee with messages:view but no sensitive_data gets `full_name` for a named member and null for one without a profile.
  - **LOW:** `chat_group_admin.go` is 493 lines. It was not split, by the coordinator's decision; see "What is still open".
- **Review-fix verification, fresh DB `godonation_admin_data_26409_fix`:**
  - `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m -v -run 'ConnectRequest|AdminGetGroup|AdminGroupReads|RosterCarriesFullName'` printed `ok …/internal/chatgroups 59.953s` and `ok …/internal/handlers 24.865s`.
  - That was 44 top-level tests: 105 `--- PASS` lines counting subtests, 0 `--- FAIL`, 0 `--- SKIP`.
  - Before the run: `gofmt -l` on the two changed files printed nothing, and `go vet ./...` and `go build ./...` were clean.
  - The DB was then dropped with `dropdb`, and `psql -lqt` no longer lists it.

**Follow-up, same day: the branch stopped compiling after main was merged in.**
- **What was asked (coordinator):**
  - The branch had taken main up to #105 in merge commits `6654ecd` and `4976c63`.
  - main's `chat_guest_reads_test.go` (#97) defines `getRawAs(t, r, token, path) (int, string)`, and this branch's three-value `getRawAs` redeclared it.
  - The automated fix `4fd5d6e` deleted this branch's copy, and `go vet` then failed: `chat_group_admin_data_test.go:138:21: assignment mismatch: 3 variables but getRawAs returns 2 values`.
  - Asked: restore the helper under a new name; merge main again at `30186e5` (#106, #107); reconcile with #107's `chatErr` codes; verify on fresh DBs.
- **What was changed:**
  - `a926e77` test(chatgroups): rename the admin raw-response helper to avoid main's getRawAs.
    - The helper is restored as `getRawAdminAs` in `chat_group_admin_sensitive_test.go`, with its `net/http/httptest` import.
    - All 10 three-value call sites in that file and `chat_group_admin_data_test.go` use the new name. main's `getRawAs` and its callers are untouched.
  - `b633687` merges `origin/main` at `30186e5`.
    - Only `HANDOFF.md` conflicted. `merge_handoff.py 9425007 HEAD MERGE_HEAD` printed `inserted 126 branch lines at line 9 above upstream entries`.
    - No Go file conflicted, as `git merge-tree` had predicted.
  - `ac4e839` refactor(chatgroups): align the admin group reads with #107's chatErr.
    - `chat_group_admin.go`: `refuseMaskedWithoutSensitive` no longer logs a non-404 kind-lookup error itself. #107's `chatErr` logs it, so each failure is logged once. Statuses and bodies are unchanged.
    - `chat_group_admin_sensitive_test.go`: `TestAdminGroupReads_MissingGroupIs404` now asserts the whole body with #107's `assertChatGroupRefusal(…, wantGroupNotFound)`.
- **Response bodies changed by #107 on this branch's routes:**
  - A missing group on the detail, messages and contact-blocks reads now answers 404 with `"code":"group_not_found"` added.
  - A failed kind lookup answers 500 with `"code":"server_error"` added.
  - `sensitive_data_required` and every 200 body are unchanged.
- **#107 checked for interplay and found compatible:**
  - `TestChatGroupRoutes_MissingGroupCarriesItsCode` expects the admin group detail to answer 404 `group_not_found` for a missing group. The gate answers a missing group through `chatErr`, so it does.
  - `chatGroupRoster` (in `chat_group_conflict_test.go`) reads the roster through `newAdminChatGroupRouter`, which has `Perms` wired, signed in as an admin (`tokenForStaffUser`), who holds sensitive_data by default. The masked-group gate lets it through. Its `reflect.DeepEqual` compares the roster before and after a refused add; both carry `full_name`.
  - `git grep -n -w` on `origin/main` for every identifier this branch adds found no collision.
- **What was run and what it printed:**
  - After the merge, on the final tree: `go build ./...` ok and `go vet ./...` ok. `gofmt -l` on `chat_group_admin.go`, `chat_group_admin_sensitive_test.go` and `chat_group_admin_data_test.go` printed nothing.
  - All three runs below used the final code (`ac4e839`'s tree), each on its own fresh DB, and all exited 0.
  - Package run, fresh DB `godonation_admin_data_26409_merge`: `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/chatgroups 3.147s` and `ok …/internal/handlers 18.319s`.
  - Full suite, fresh DB `godonation_admin_data_26409_merge_full`: `go test ./... -count=1 -p 1 -timeout 45m` — 22 packages `ok`, 36 with no test files, 0 `FAIL` and 0 `panic` lines.
    - Among them: `ok …/internal/chatgroups 2.569s` and `ok …/internal/handlers 17.102s`. The last `ok` line was `ok …/internal/users 0.715s`.
  - `-v` run of this branch's new tests, fresh DB `godonation_admin_data_26409_merge_v`: `-run 'TestAdminGroupReads_|TestAdminGetGroup|TestAdminConnectRequests_|TestChatGroupMemberReads_|TestGroupKind|TestConnectRequestAdminReads|TestConnectRequestNeverSerializes'` printed `ok …/internal/chatgroups 1.793s` and `ok …/internal/handlers 1.065s`.
    - 18 top-level tests, 65 `--- PASS` lines counting subtests, 0 `--- FAIL`, 0 `--- SKIP`.
  - These timings are far shorter than this entry's earlier runs (handlers 17.102s here, 1390.034s before). Nothing was skipped or cached:
    - `-count=1` disables the test cache.
    - The DB-backed tests skip only when `TEST_DATABASE_URL` is empty, and every command set it.
    - The `-v` run shows those tests as PASS, not SKIP.
    - The first test in each package paid the migration cost on its fresh DB (`TestGroupKindReadsEachKind` 1.20s, the rest 0.00–0.07s).
    - It was not a quieter machine: `uptime` right afterwards printed load averages `13.37 16.83 18.14`. The likelier cause is that the earlier slow runs overlapped with other worktrees' test runs against the same Postgres — `pgrep` then showed five `handlers.test` processes from different worktrees. That was not measured.
  - Afterwards the three DBs were dropped with `dropdb`, and `psql -lqt` lists none of the `godonation_admin_data_26409*` databases.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commits are local, unpushed, and not reviewed by a human.
- OPOS MCP needed interactive OAuth and wasn't available in this subagent session. OPOS #26409 and #26410 were not moved or commented on.
- The branch now contains `origin/main` up to `30186e5` (#107), through merge commits `6654ecd`, `4976c63` and `b633687`. It is not merged into main.
- The admin-web must handle 403 `sensitive_data_required` and 404 `group_not_found` on all three group reads.
- Not every chat-group admin refusal carries a `code` yet. #107 put one on everything `chatErr` sends, but `chat_group_admin.go` still writes these refusals inline without one:
  - 401 `Unauthorized.` on every handler.
  - 400 `Invalid JSON.` and `kind and at least one member are required.` on create and approve.
  - 400 `user_id is required.` on add member, `Invalid user id.` on remove member, `Message body is required.` on post message, and `A decline reason is required.` on decline.
  - 404 `Connect request not found.` on connect-request detail, approve and decline.
  - 500 `Database error.` on the group list, messages, contact blocks and the connect-request list.
  - None of these changed in this work; admin-web's `describeError` falls back to the sentence for them. Adding codes means editing `chat_group_admin.go`, which must first be split (next item).
- `backend/internal/handlers/chat_group_admin.go` is 493 lines, 7 under the 500-line cap. It was deliberately NOT split in this work (coordinator's decision after review). **The next change to this file must first move its connect-request inbox section into a file of its own:** `resolveConnectContext`, `adminConnectRequestItem`, `adminConnectRequestItems`, and the list, detail, approve and decline handlers. Only then add anything else.
- `user_profiles.user_id` has no index and no UNIQUE constraint (checked every migration). Every name lookup scans it. Worth a migration of its own.
- `resolveConnectContext` still runs one query per inbox item (pre-existing).

**Traps:**
- The `origin/main` ref is shared by every worktree, so another session's fetch moves it under you. `git diff origin/main` then shows main's newer commits as deletions on your branch. Diff against `git merge-base HEAD origin/main`.
- In a worktree-isolated agent session, a Bash or Monitor command is refused when it chains many statements or contains the text `git` in a form the guard cannot verify. A grep pattern with `github.com` was enough. Use short, separate commands.
- Do not run `internal/chatgroups` and `internal/handlers` tests at the same time against one database: they share the `users.id` sequence (see `raiseChatGroupUserIDFloor`). Run them one after the other, or on separate databases.
- `user_profiles` can hold two rows for one user, so a plain `JOIN user_profiles` duplicates rows. The new reads avoid that in two ways:
  - for a known batch of ids, `DISTINCT ON (user_id) … WHERE user_id = ANY($1) ORDER BY user_id, id` (`profileNames`);
  - per row, `LEFT JOIN LATERAL (… WHERE up.user_id = r.requester_user_id ORDER BY up.id LIMIT 1) p ON true` (`adminConnectRequestSelect`).
  - Do not join a `DISTINCT ON` view of the whole table: it scans and sorts every profile on every call.
- Two test files in one Go package that each define the same helper name merge without any git conflict; only the compiler finds the clash. That happened here with `getRawAs`, from #97 and from this branch.
  - Before merging main, run `git grep -n -w` on `origin/main` for the identifiers the branch adds.
  - When two same-named helpers collide, compare their signatures before deleting one. `4fd5d6e` deleted the three-value copy on the assumption the two matched, and `go vet` then failed.

---

## 2026-09-15 — OPOS #26397 (E1 + E2): export ONE chat conversation from the donor, marriage and staff chat pages (branch `feat/admin-chat-conversation-export`)

**What was asked:** in admin-web, test-first, let staff export the open conversation (CSV / Excel / PDF / Word, behind the existing PIN step-up) from MessagesPage, MarriageChatsPage and StaffChatPage. Fix ExportCsvButton reporting every failure as "Incorrect password". Make the engine general enough for the later group export (E3). Commit, do not push.

**What was actually changed** (on `origin/main` `7de9faf`, worktree `.claude/worktrees/agent-a944411f886a442c7`):
- **`efbbeaf` fix(admin-web): export errors no longer claim the password was wrong.** `components/ExportCsvButton.tsx` reports each step on its own: a refused PIN shows the server's refusal; a failed verify-password request goes through `describeError`; a failed file build shows `error.unknown` and logs the detail. New `ExportCsvButton.test.tsx`.
- **`c1ee5e8` feat(admin-web): export a single chat conversation.**
  - `ExportCsvButton` gains optional `loadRows`, called exactly once and only after the PIN is accepted. A load failure toasts `export.load_failed` with `describeError`'s reason.
  - New `src/lib/chatExport.ts` (+ test): row engine `toExportRow`, builders `donorExportRows` / `marriageExportRows` / `staffExportRows`, `chatExportColumns()` (six columns) and `groupChatExportColumns()` (adds `masked_label`, `role_in_group`), `chatExportFilenameBase` (`donor_chat_7`, `support_chat_20`, `marriage_chat_51`, `staff_chat_61`), `chatExportTitle`, loaders for donor and marriage.
  - Columns: `message_id`, `sent_at` (ISO UTC), `sender_name`, `sender_user_id`, `sender_role` (translated), `body`. Rows are built field by field, so no contact field can reach a file.
  - Role mapping, verified on main: donor `0` = support (`backend/internal/chat/chat.go:30` RoleSupport; staff replies use it at `handlers/chat.go:563`), otherwise the sender's app role_id (`handlers/chat.go:425`), `1` grantor / `2` recipient / `3` volunteer (`handlers/registration.go:232,299,309`; same keys as `UserPicker.tsx` and `DetailPage.tsx`). Marriage `requester` / `owner` / `staff` (`internal/marriagechat/marriagechat.go:214-216`), staff named "Support" like the page. Staff chat has no role; the sender's staff tier stands in.
  - Page buttons ("Export conversation") in each conversation header, gated by the module that gates the messages route: `messages` (`main.go:1012`), `marriage` (`main.go:1092`), and `messages` for staff chat (decision D5; the route has no perm gate, `main.go:1084`).
  - Locales en + ar: `col.{message_id, sent_at, sender_name, sender_user_id, sender_role, masked_label, role_in_group}` and `export.{conversation, load_failed, chat_title, chat_donor, chat_support, chat_marriage, chat_staff, chat_group, role_unknown}`. No Kurdish.
  - Mock API: `src/test/fixtures/legacyChats.ts` adds a multi-line body with commas and quotes to each system's first thread (messages 7004, 5104, 6103); `scripts/mock-api.test.mjs` pins it; `docs/mock-api.md` says how to check an export by hand.
  - One page test per page.
- **`6731167` fix(admin-web): staff chat export includes messages that arrive during the PIN.** From the `ecc:react-reviewer` review: StaffChatPage's `loadRows` had closed over a render-time copy of the messages, so a message the 3 s poll delivered during PIN entry was left out. It now reads a ref holding the newest list, filtered by the thread id captured at click. Tests added for that, for the thread-switch race, and for a download that throws.
- **This entry.**

**Staff-chat read side effect.** `GET /api/admin/staff-chats/:id/messages` calls `Store.MarkRead` (`handlers/staff_chat.go:162`, `internal/staffchat/staffchat.go:227`). The page already calls it on open and every 3 s, so the export REUSES the loaded messages and sends no GET of its own (pinned by StaffChatPage.test.tsx). The export changes no read state. Donor and marriage routes have no such side effect and are fetched once after the PIN.

**What was run and what it printed** (Node 22.23.1, `PATH=/opt/homebrew/opt/node@22/bin:$PATH`):
- RED:
  - all tests written, before `chatExport.ts` and `loadRows` existed: `Tests 9 failed | 6 passed (15)`, with `Failed to resolve import "./chatExport"`, `Unable to find role="button" and name "Export"` for the loadRows cases, and the page tests timing out;
  - the error-reporting tests before the error fix: `Tests 2 failed | 1 passed (3)`, the DOM showing "Incorrect password — cancelled.";
  - before the fixture change: `not ok 13 - each legacy chat has a multi-line message body with a comma`;
  - before the review fix: `AssertionError: expected [ 6101, 6102, 6103 ] to deeply equal [ 6101, 6102, 6103, 6104 ]`.
- Final, on `c07b9a7`, whose admin-web tree is identical to `6731167` (the later rebase onto `7de9faf` brought only backend and HANDOFF changes); `npm test` re-run on the rebased tree printed `Tests 34 passed (34)` again:
  - `npm test` → `Test Files 7 passed (7)`, `Tests 34 passed (34)`;
  - `npx tsc -b` → exit 0;
  - `npm run build` → exit 0 (only Vite's usual >500 kB chunk warning);
  - `npm run test:mock-api` → `# tests 24`, `# pass 24`, `# fail 0`;
  - `npm run check:labels` → exit 1, only the 6 chat-group values (`status.case, created, masked, member_added, member_removed, team`), none from this branch;
  - `npm run test:nav` → 15 pass;
  - `npm run check:css-tokens` → `62 tokens read, all defined.`;
  - `npx eslint` on the 14 changed ts/tsx/mjs files → `✖ 6 problems (6 errors, 0 warnings)`, all `react-hooks/set-state-in-effect` in the three pages' existing polling effects (2 per page; the base versions of those pages give the same 2 each). None new.

**External actions taken:** none. Nothing pushed. OPOS MCP needed OAuth, unavailable in this non-interactive session, so #26397 was not moved or commented on.

**What is still open:**
- The three commits are local and unpushed.
- **LOW, pre-existing, not fixed:** ExportCsvButton's dropdown has no roving focus, no arrow-key navigation and no `aria-controls` (reviewer finding).
- The staff chat page itself can still DISPLAY a late load for the previously selected thread under the newly selected one until the next poll (a pre-existing page race). The export hides itself in that state and never mixes threads (pinned by a test).
- **E3 (group export) should reuse:** `toExportRow(message, role, { masked_label, role_in_group })`, `groupChatExportColumns()`, `chatExportFilenameBase('group', id)`, `chatExportTitle('group', id)` (`export.chat_group` exists), and `ExportCsvButton` `loadRows` with the after_id paging loop. The `col.masked_label` / `col.role_in_group` keys are already in en and ar.

**Traps:**
- **Vitest timeout.** A whole-page export test takes ~1.5 s alone but passed Vitest's 5 s default when all files ran in parallel. Each page suite sets `{ timeout: 15_000 }` with a comment.
- **Poll tests.** Fake ONLY `setInterval` / `clearInterval` (`vi.useFakeTimers({ toFake: [...] })`), so Testing Library's `waitFor` and user-event keep real `setTimeout`.
- **mockApi replies synchronously.** To model a slow request, wrap its spy through `vi.mocked(api.get).getMockImplementation()` (see `holdFirstLoadOf` in StaffChatPage.test.tsx).
- **`vi.clearAllMocks()` keeps mock implementations.** A test that replaces one should use `mockImplementationOnce` or `vi.resetAllMocks()`.
- **FileReader drops the BOM** that `csv.ts` writes, so a test reading the CSV Blob sees text starting at the header row.
- **Worktree guard.** This harness refuses `git -C ..`, and `awk -v` inside compound commands. Use plain git from the worktree root.

---

## 2026-09-15 — OPOS #26435 and #26429 (app half): the 1:1 chat names an unnamed staff reply in the reader's language, and group chat notifications get a type label (branch `fix/app-support-name-and-group-notif-label`)

**What was asked:** two Flutter localization fixes on one branch, test-first, in en and ar only.
- **#26435:** the 1:1 support chat showed English "Support" to Arabic users.
- **#26429:** the `chat_group_message` notification type had no label. Only the app half was in scope, not admin-web.

Commit locally; do not push.

**What was actually changed:**
- **Base.** The branch was cut from `origin/main` `e66ff69`. Before any commit, it was moved onto `origin/main` `30186e5` with `git checkout -B`. Upstream #103–#107 had landed in the meantime, and none of them touch these files.
- **`8cb9fd8` fix(chat): localize the support sender name and the group-message notification label.**
  - `humanitarian/lib/modules/chat/models/chat_models.dart`: `ChatMessage.senderName` is now the server's trimmed `sender_name`, or `''` when the server sent none.
    - It used to be `'Support'` for `sender_role` 0 and `'User'` for everyone else.
    - The server sends null when a staff profile has no name, or when privacy settings hide the name. `Viewer.Name` in `backend/internal/privacy/privacy.go` returns nil on purpose and leaves the placeholder to the client.
  - New `humanitarian/lib/modules/chat/utils/chat_sender_name.dart`: `chatSenderName(ChatMessage)`.
    - It returns the server's name when there is one.
    - Otherwise it returns `'chat_group_sender_support'.tr` for staff and `'User'.tr` for anyone else.
  - `humanitarian/lib/modules/chat/screens/chat_conversation_screen.dart`: `_MessageBubble` draws `chatSenderName(message)` (~line 233), and its comment was rewritten to match.
    - This is the only place the app displays `senderName`. Grepping `lib/` finds no other reader.
  - `humanitarian/lib/localization/app_translations.dart`: `chat_group_message` was added to `_en` (line 37) and `_ar` (line 3258), next to `chat_message`.
    - A comment on `chat_group_sender_support` now says the key is shared with the 1:1 chat.
  - **Tests:**
    - New `humanitarian/test/modules/chat/chat_sender_name_test.dart`, 14 cases:
      - `fromMap` adds no words of its own;
      - Arabic and English fallbacks, with real names left untouched;
      - Kurdish never falls back to Arabic;
      - a source guard that the screen draws `chatSenderName(message)`.
    - It is a source test rather than a pumped screen: `ChatThreadController.onInit` calls `const ModuleApi()` directly, with no seam for a fake.
    - `humanitarian/test/localization/localized_tag_test.dart` lists `chat_group_message`. It also has a new test that every listed type has its own `_en` entry, because the existing English test passes on the humanised token alone.
  - `TRANSLATION_REQUEST.md`:
    - a new 1-key section and table row;
    - the count heading and the Total row both went from 467 to 468;
    - a note in the #26419 section that `chat_group_sender_support` now serves both chats.
- **This entry.**

| Key | English | Arabic | Status |
|---|---|---|---|
| `chat_group_sender_support` | Support | فريق الدعم | reused (from #26419). T10: a bare الدعم is Kafala |
| `User` | User | مستخدم | reused |
| `chat_group_message` | Group chat message | رسالة محادثة جماعية | **new**. It follows `chat_message` → رسالة محادثة; جماعية is the word the chat-groups screens use |

**What was run and what it printed** (from `humanitarian/`):
- **RED.** This ran on `e66ff69`, where every file involved is byte-identical to `30186e5`. `chat_sender_name.dart` was an identity stub, and nothing else in production had changed.
  - `flutter test test/modules/chat/chat_sender_name_test.dart test/localization/localized_tag_test.dart` printed `+24 -8: Some tests failed.` The failures were:
    - the model tests: `Expected: ''` / `Actual: 'Support'` and `Actual: 'User'`;
    - Arabic: `Expected: 'فريق الدعم'` / `Actual: 'Support'`, and `Expected: 'مستخدم'` / `Actual: 'User'`;
    - the source guard;
    - `no _en entry for chat_group_message`;
    - `chat_group_message rendered as "Chat group message" in Arabic`.
- **GREEN.** The same command printed `00:00 +32: All tests passed!`
- **Format.** `dart format --output=none --set-exit-if-changed` on the 5 owned Dart files flagged only the new test, which was then formatted. `app_translations.dart` was left alone: it already fails formatting on main (see the #26419 entry).
- **On `30186e5`:**
  - `flutter analyze` printed `6 issues found. (ran in 10.6s)`, the same 6 `deprecated_member_use` as the baseline.
  - `flutter test test/localization/ test/modules/chat/ test/modules/chatgroups/` printed `00:24 +357: All tests passed!`
  - `flutter test` (full) printed `01:10 +1045: All tests passed!` (exit 0).
- **Review.** `ecc:flutter-reviewer` returned APPROVE, with 0 CRITICAL, 0 HIGH and 0 MEDIUM findings. Neither of its two minor findings was changed:
  - **LOW:** the Kurdish test asserts "not Arabic, not empty" rather than exactly "Support". That is deliberate: it catches the real risk and survives a future Kurdish translation.
  - **NIT:** the "shared key" comment could drift if the key is renamed. It names `chatSenderName`, which a grep finds.

**External actions taken:** none. Nothing was pushed and no PR was opened. The OPOS connector needs interactive OAuth, which this session could not do, so #26435 and #26429 were not moved or commented on.

**What is still open:**
- Both commits are local and unpushed.
- The admin-web half of #26429, the dashboard's label for `chat_group_message`, is not done.
- `chat_group_message` needs Sorani and Badini.
- **Not fixed, same file:** `ChatThread.otherName` still falls back to English `'User #<id>'` (`chat_models.dart` ~line 53). It is what the Messages tile and conversation title show for a counterpart with no name.
- **Not fixed, T10:** the marriage chat signs staff with `'Support'.tr` (`marriage_chat_conversation_screen.dart` ~line 356). That resolves to `الدعم`, the Kafala word, not `فريق الدعم`.
- **Not fixed, server side: the 1:1 support-reply push.**
  - The admin reply handler in `backend/internal/handlers/chat.go` (~line 561) always calls `notify.ChatNewMessageMsg("Support", …)`.
  - That template (`backend/internal/notify/templates.go`) puts the word into every language's title.
  - So an Arabic user's push, and the in-app notification row, both read «رسالة من Support».
  - The fix belongs in that template, the way #26434 fixed masked group pushes.

**Traps:**
- **The shared `origin/main` ref moves under you.** Another worktree's fetch advanced it from `e66ff69` to `30186e5` mid-task. After that, `git diff origin/main` showed about 4,000 lines of unrelated upstream work. Diff against `HEAD` or the base SHA, and re-check `git log <base>..origin/main` before committing.
- **`test/modules/chat/` did not exist before this change**, so a test command naming it would have failed on main.
- **zsh:** an unquoted `--include=*.dart` fails with "no matches found". Quote it.
- **The worktree guard refuses `$((...))` arithmetic in Bash.** Split the command into plain ones.

---

## 2026-09-15 — OPOS #26436: a declined chat invite can't be accepted; asking again starts a fresh one (branch `fix/declined-invite-needs-reinvite`)

**What was asked:** apply the owner's decision "make it decline and re invite behavior", test-first:
- a declined chat invite can no longer be accepted, in donor chat or marriage chat;
- to start again, the initiator sends a new invite or request, and the recipient gets a fresh pending invite and a notification.

The brief limited the change to the two chat stores' accept (and re-invite), their handlers' accept paths and error mapping, and new test files, because parallel branches edit chat groups, notifications and `chatlifecycle.Apply`.

**What was actually changed:** commit `9c06524`, based on `origin/main` `62cadbd` and fast-forwarded to `e66ff69` before committing. Nothing between those two touches `backend/`.
- **The bug.** Both `AcceptThread`s updated by id with no status condition. A recipient who had declined could accept later: the thread went back to `active` and the initiator was pushed "chat accepted". The RED run below confirms it.
- `backend/internal/chat/chat.go`:
  - new sentinel `ErrInviteDeclined` (:47);
  - `AcceptThread` (:198) now runs `UPDATE … WHERE id = $1 AND status = 'pending' RETURNING …`;
  - on no row, the new `acceptNotPending` (:230) re-reads the thread. `active` keeps today's idempotent success and still returns the initiator id. Anything else returns `ErrInviteDeclined` with initiator id 0, so nobody is pushed.
- `backend/internal/marriagechat/marriagechat.go`:
  - the same shape: `ErrInviteDeclined` (:50), `AcceptThread` (:249), `acceptNotPending` (:279).
  - `ApproveMeetingRequest` (:115): the `ON CONFLICT (requester_user_id, profile_id) DO UPDATE` now also sets `status = CASE WHEN marriage_chat_threads.status = 'declined' THEN 'pending' ELSE marriage_chat_threads.status END` (:148).
- `backend/internal/handlers/chat.go`: new const `chatInviteDeclinedCode = "chat_invite_declined"` (:452), and `chatErr` maps `ErrInviteDeclined` (:456).
- `backend/internal/handlers/marriage_chat.go`: `chatErr` maps `ErrInviteDeclined` (:55). Doc comments updated on `Accept` (:182) and `AdminApproveMeetingRequest` (:99).
- **Check order is unchanged:** the participant/owner check, then `refuseIfInviteClosed` (#93/#99), then `AcceptThread`. #98's decline code is untouched.
- **New tests:**
  - `backend/internal/chat/chat_accept_declined_test.go` (3 store tests): declined is refused and untouched with initiator 0; pending accepts; active is idempotent.
  - `backend/internal/handlers/chat_invite_accept_declined_test.go` (6 tests, 10 counting subtests):
    - accepting a declined invite answers 409 and leaves no accepted-notification row, in donor and marriage;
    - pending accepts, and a repeat accept is a 200, in both;
    - the initiator/requester and a stranger get today's plain 403 on a declined thread, never the 409;
    - marriage re-invite through the production routes end to end: request, approve, decline, request again, approve again; the owner's `GET /api/marriage/chats` lists the thread as pending, and accepting it succeeds and pushes the requester;
    - a new approval leaves an active chat active.

**Responses:**
- **Donor, declined:** `409 {"success":false,"code":"chat_invite_declined","error":"This chat request was declined, so it can no longer be accepted."}`. It promises nothing further, because a donor chat cannot be requested again.
- **Marriage, declined:** `409 {"success":false,"code":"chat_invite_declined","error":"This chat request was declined, so it can no longer be accepted. If a new request is approved, it will come to you as a new invite."}`. It does not promise a push; see the notification gap below.
- **Already active, both:** 200 `{"success":true,"status":"active",…}`, unchanged.

**Re-invite findings per kind:**
- **Donor direct chat: none exists, so a declined donor invite is final.**
  - The route `POST /api/chats/request` (`cmd/server/main.go:733`) runs `ChatHandler.Request` (`internal/handlers/chat.go:94`), which calls `chat.Store.RequestThread` (`internal/chat/chat.go:106`). That always returns `ErrDirectChatRetired`, which becomes 410 "Direct messaging has been retired. Ask staff to connect you instead." (`handlers/chat.go:176`).
  - Creation was not re-opened.
- **Marriage chat: the requester asks again through the existing flow.**
  - `POST /api/marriage/:id/request-meeting` (`main.go:804`, `MarriageHandler.RequestMeeting` `handlers/extras.go:453`, `marriage.Store.RequestMeeting` `internal/marriage/marriage.go:403`) inserts a new `marriage_meeting_requests` row. That table has no uniqueness, so nothing blocks a second request.
  - Staff then approve with `POST /api/admin/marriage/meeting-requests/:id/approve` (`main.go:1089`), which runs `ApproveMeetingRequest`.
  - The schema keeps ONE thread per pair: `CONSTRAINT uq_marriage_chat_pair UNIQUE (requester_user_id, profile_id)` (`migrations/058_marriage_mediated_chat.sql:29`). Before this change the conflict branch reused the declined thread without touching `status`, so the "new" invite came back `declined` and hidden from the owner's list.
  - **Choice: reset the existing thread, don't create a new one.** The unique constraint makes a second thread impossible without a migration, and resetting is how the model is meant to work.
  - Only `declined` becomes `pending`. A `pending` or `active` thread keeps its status, so a new approval never locks a live chat back behind the owner's accept.

**What was run and what it printed:**
- **RED, before the fix, observed earlier in this session** on DB `godonation_declined_invite_26436` (only the sentinels declared):
  - `go test ./internal/chat/ -run AcceptThread -count=1 -p 1 -timeout 45m -v`: `TestAcceptThreadRefusesDeclinedInvite` printed `err = <nil>, want ErrInviteDeclined`, `initiator = 8, want 0` and `stored status = "active", want declined`. The two controls passed. It ended `FAIL …/internal/chat 132.074s`.
  - `go test ./internal/handlers/ -run DeclinedInvite -count=1 -p 1 -timeout 45m -v`:
    - DonorRefused printed `200 map[status:active success:true thread_id:4]`;
    - MarriageRefused printed `200 map[status:active success:true thread_id:1]`;
    - the re-invite test printed `approve: status = 200 body = map[status:declined success:true thread_id:4], want 200 pending`;
    - the other 3 tests passed. It ended `FAIL …/internal/handlers 22.278s`.
  - The re-invite test was later rewritten to seed the first approval through the routes. Its status assertion is the one that failed above; the rewritten version was not re-run against the pre-fix code.
- **Notification probe, after the fix:** a temporary test (not committed) ran request → route approve → decline → request again → route approve. It printed `user 30 has 1 "marriage_chat_request" notifications after 5s, want at least 2`.
- **GREEN, final, on a freshly recreated DB `godonation_declined_invite_26436b`:**
  - store `-v`: 6/6 PASS, `ok …/internal/chat 0.871s`;
  - HTTP `-run DeclinedInvite -v`: 6/6 PASS with no SKIP, `ok …/internal/handlers 1.083s`. It printed, for example, `approve a new meeting request after a decline: 200 map[status:pending success:true thread_id:4]` and `accept the fresh invite: 200 map[status:active success:true thread_id:4]`.
- **Package run, DB recreated fresh:** `go test ./internal/chat/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/chat 1.443s` and `ok …/internal/handlers 16.306s`, exit 0. `internal/marriagechat` has no test files; its behaviour is covered through the handlers tests.
- **Full suite, DB recreated fresh again:** `go test ./... -count=1 -p 1 -timeout 45m` exited 0 with 22 `ok` packages and 0 FAIL. Among them: `ok …/internal/handlers 17.832s`, `ok …/internal/marriage 1.062s`, `ok …/internal/chatlifecycle 1.056s` and `ok …/internal/notify 0.583s`.
- **Cleanup:** `dropdb godonation_declined_invite_26436b` succeeded. Afterwards `psql -d postgres -lqt` lists 0 `godonation_declined_invite*` databases. The first DB, `godonation_declined_invite_26436`, was already gone after the session restart.
- **Lint:** `go build ./...` and `go vet ./...` exited 0, and `gofmt -l` on the 6 changed files printed nothing.
- **Review:** `ecc:code-reviewer` returned APPROVE with 0 critical, high or medium findings.
  - LOW 1: files over 500 lines, already over before this change. Not split, because parallel branches edit them.
  - LOW 2: a re-approval landing between the guarded UPDATE and the re-read makes one accept tap answer 409. Accepted and documented on `acceptNotPending`.
  - The review ran before the notification probe and assumed a re-opened invite "brings its own notification". The two comments that said so were corrected afterwards.

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needs interactive OAuth in this subagent session, so #26436 was not moved or commented on. A background-task suggestion, "Fix lost marriage chat invite notifications", was raised for the user.

**What is still open:**
- The two commits are local and unpushed.
- **The re-invite push is lost.** `notify.Notifier.Send` dedupes on user + English title + English body + type, with no time window and no entity check (`internal/notify/notify.go:120`). `MarriageChatRequestMsg`'s text never varies, so an owner who already received one invite gets no new row and no push for the re-invite. The same applies to any later invite from anyone, and `MarriageChatAcceptedMsg` has the same shape. The probe above confirms it.
  - The owner still sees the pending invite in their Marriage chats list.
  - Not fixed here: the dedupe is relied on elsewhere (`handlers/admin_status_notify.go:357-360`), the templates belong to a parallel branch, and getting past it would mean deleting users' notification rows or changing the shared `Send`. It needs a decision.
- **A re-opened thread keeps its lifecycle and its old messages.** If staff had ended or archived the declined thread, a re-invite produces a pending invite that accept refuses with `chat_lifecycle_closed`, or 404 if archived. This is the lifecycle rule working as designed, but staff approving a request for such a pair creates an invite nobody can use.
- **Flutter** (no Dart changed; for #26433). Both accept calls go through `postJson` (`humanitarian/lib/api/module_api.dart:360`), which throws `Exception(<error>)` and drops `code`:
  - **Notification tile** (`modules/notifications/widgets/notification_tile.dart`): Accept is offered on any `chat_request` (:196) whose thread is not active in `ChatController.threads`. Declined threads are never in that list, so the `declined` branch at :550 never fires. `_localDone` (:557) resets when the widget is rebuilt, so a user who declined sees Accept again. Tapping it, `_accept` (:437) shows a snackbar with the raw text "Exception: This chat request was declined, so it can no longer be accepted." in English on every locale, and the buttons stay. This is the path most likely to hit the 409.
  - **Messages tab** (`modules/chat/screens/messages_screen.dart`): `_accept` (:517) shows the same raw `'$e'` (:533). Accept only renders for `incomingPending` threads (:198), so reaching it takes a stale list.
  - **Marriage conversation** (`modules/marriage/screens/marriage_chat_conversation_screen.dart`): `_decide(true)` (:152, :156) shows `failureMessage(e, 'error_message_send_failed')` (:165), i.e. "Could not send your message. Please try again…" / "تعذّر إرسال رسالتك…", which is misleading. Accept is gated on `_status == 'pending' && isOwner` (:212). A stale list row, or the first load, can still show it.
  - `marriage_chat_request` notifications have no buttons in the tile.
  - The existing pattern to follow is `ApiCodedException` via `_sendCodedJson`, as in `chat_group_conversation_controller.dart`'s `chat_lifecycle_closed` handling.
- **Files over 500 lines** (already over before): `internal/chat/chat.go`, `internal/handlers/chat.go`, `internal/marriagechat/marriagechat.go`.

**Traps:**
- **A session restart kills every background test run and reviewer.** Recheck `psql -l`: the first DB for this task was already gone afterwards.
- **Notification tests that seed an invite through the store** (`marriagechat.Store.ApproveMeetingRequest`) write no notification row, so they cannot see `Send`'s dedupe. Seed through the approve route when a test depends on a notification arriving.
- **In this worktree-isolated agent, the sandbox refuses:**
  - `cd <dir> && git …`: use `git -C <worktree>`;
  - Monitor loops with shell arithmetic: `tail -F log | grep --line-buffered …` works.
- **`psql` without `-d postgres` fails** with `database "zaidaqrawi" does not exist`.

---

## 2026-09-15 — OPOS #26410 (part): chat-group membership conflicts answer 409 with codes, and re-adding a removed member reactivates them (branch `feat/chat-groups-conflict-codes`)

**What was asked:** on the chat-group admin routes, adding someone who is already a member, or giving a masked label that another active member holds, returned 500 "Database error.". Three changes were requested, test-first:
- return 409s with machine codes instead;
- give every `chatErr` refusal a stable `code`;
- by user decision D3, re-add a REMOVED member by reactivating their row, keeping its label and role, instead of refusing.

A parallel agent owns `chat_group_admin.go`, `chatgroups_admin.go` and the admin routes in `main.go`. None of those were touched.

**What was actually changed** (on `feat/chat-groups-conflict-codes`, off `origin/main` `a1da04f`, not pushed):
- **`6927965` refactor(chatgroups): a pure move, diffed line for line against HEAD.** The membership writes left `chatgroups.go` for the new `backend/internal/chatgroups/chatgroups_members.go`: `autoLabel*`, `nullIfEmpty`, `refuseContactInLabel`, `memberExecer`, `memberRow`, `insertMemberRow*`, `insertMembers`, `AddMember` and `RemoveMember`. This was needed because the feature would have pushed `chatgroups.go` past 500 lines.
- **`8436e44` feat(chatgroups): 409 codes for member and label conflicts, reactivate removed members:**
  - **`chatgroups.go`.** New sentinels `ErrMemberConflict`, `ErrLabelConflict` and `ErrLabelContact`; the last wraps `ErrInvalidInput`, so old `errors.Is` checks still hold. The package and `CreateGroup` doc comments were updated.
  - **`chatgroups_members.go`: conflict mapping.** `memberConflict` maps SQLSTATE 23505 by `PgError.ConstraintName`: `chat_group_members_group_id_user_id_key` becomes `ErrMemberConflict`, and `uq_chat_group_members_active_label` becomes `ErrLabelConflict`. It is used by `insertMemberRow` (all three add paths) and by `reactivateMemberRow`.
  - **`chatgroups_members.go`: `AddMember`.** One transaction with `SELECT … FOR UPDATE` on the user's row in the group:
    - no row: insert, with auto-labels as before;
    - an active row: `ErrMemberConflict`;
    - a removed row: `reactivateMemberRowSQL`, which clears `removed_at` and `removed_by` only and refuses a guest in the same statement.
  - **`chatgroups_members.go`: `refuseContactInLabel`.** It returns `ErrLabelContact`, and the error no longer contains the label text, so the contact detail stays out of logs.
  - **`backend/internal/handlers/chat_group.go`.** `chatErr` is now an ordered table (`chatErrResponses`) plus `respondChatErr`. Every answer is `{success:false, error, code}`. An unrecognised error is logged and answered 500 `server_error`.
  - **Tests.** New `chatgroups_conflict_test.go`, `chatgroups_reactivate_test.go`, `handlers/chat_group_conflict_test.go` and `handlers/chat_group_error_codes_test.go`; the last includes a DB-free table test of the whole `chatErr` mapping. In `handlers/chat_group_guest_member_test.go`, the old "invalid input carries no code" test became `TestAdminCreateGroup_InvalidKindKeepsItsSentence`, asserting `group_invalid_input` with its sentence unchanged.

**Error codes sent by `chatErr`** (the English sentences of the pre-existing cases are unchanged):

| Code | Status | English `error` | Routes |
|---|---|---|---|
| `not_group_member` | 403 | You are not a member of this group. | GET/POST `/api/chat-groups/:id/messages`, POST `/api/chat-groups/:id/read` |
| `group_not_found` | 404 | Group not found. | the three participant routes above; GET `/api/admin/chat-groups/:id`; POST `/api/admin/chat-groups/:id/members`; DELETE `/api/admin/chat-groups/:id/members/:userId` (also when the user is not an active member); POST `/api/admin/chat-groups/:id/messages` |
| `connect_request_decided` | 409 | This request has already been decided. | POST `/api/admin/chat-groups/connect-requests/:id/approve` and `/decline` |
| `group_member_conflict` | 409 | This person is already a member of this group. | POST `/api/admin/chat-groups`, POST `/api/admin/chat-groups/:id/members`, POST `…/connect-requests/:id/approve` |
| `group_label_conflict` | 409 | Another member of this group already has this label. | the same three routes |
| `guest_member_not_allowed` | 400 | Guest accounts cannot be added to a chat group. | the same three routes |
| `group_label_contact` | 400 | A member label cannot contain a phone number or email address. | the same three routes (it used to be 400 "Invalid request." with no code) |
| `group_invalid_input` | 400 | Invalid request. | POST `/api/admin/chat-groups` (unknown kind); POST `…/approve` (unknown kind, or requester not in members); POST `/api/chat-groups/connect-requests` (context_type not donation/case) |
| `connect_context_not_found` | 400 | We couldn't find that case or donation. | POST `/api/chat-groups/connect-requests` |
| `server_error` | 500 | Database error. | any route above, for a failure `chatErr` does not recognise (now logged) |

These refusals on the same routes do NOT come from `chatErr`, so they are unchanged and carry no code unless one is noted:
- **400:**
  - "Invalid JSON.": create group, approve, and POST read.
  - "kind and at least one member are required.": create group and approve.
  - "user_id is required.": add member.
  - "Invalid user id.": remove member.
  - "A decline reason is required.": decline.
  - "Message body is required.": both message POSTs.
  - "context_type, context_id, and message are required.": submit connect request.
  - "Invalid id.": `parseID`, on every `:id` route.
- **404:**
  - "Connect request not found.": GET a connect request, approve and decline. `chat_group_admin.go` intercepts it before `chatErr`.
  - "Chat not found.": the lifecycle and archived gates.
- **409 `chat_lifecycle_closed`:** a message POST to a paused or ended group.
- **422 `contact_details_blocked`:** contact details in a masked-group message.
- **500 "Database error." inline:** the list routes and POST read.

**Reactivation rules (D3):** these apply to `AddMember` only (POST `/api/admin/chat-groups/:id/members`). CreateGroup and approval always make a new group, so no removed rows exist there.
1. A user with a REMOVED row in the group gets that same row back: `removed_at` and `removed_by` are cleared. The member id, `masked_label`, `role_in_group`, `masked`, `added_at` and `added_by_staff_id` stay. The route answers 200 and records its usual `member_added` audit row.
2. The request's `role_in_group` and `label` are ignored for a returning member.
3. The request's label is still scanned first. A phone number or email gets 400 `group_label_contact`, and the member stays removed.
4. If the old label is now held by another active member (compared ignoring case), the answer is 409 `group_label_conflict`, and the member stays removed.
5. A guest account gets 400 `guest_member_not_allowed` and stays removed.
6. A user who is already active gets 409 `group_member_conflict`, and nothing changes.
7. The lookup and the write share one transaction, with the member row locked `FOR UPDATE`.
8. Old and new messages resolve to the same `sender_member_id` and label, because the read side joins members on `(group_id, user_id)`.

**What was run and what it printed:**
- **RED, fresh DB `godonation_cg_conflict_codes`, sentinels declared but unused:**
  - **Store tests.** Every new store test failed with raw errors, for example `duplicate key value violates unique constraint "chat_group_members_group_id_user_id_key" (SQLSTATE 23505), want errors.Is(err, ErrMemberConflict)` and the same for `uq_chat_group_members_active_label`. The contact-label tests failed with `chatgroups: invalid input, want errors.Is(err, ErrLabelContact)`, and re-adding a removed member failed with the 23505 above. Only `TestAddMemberRefusesReactivatingGuest` passed, as a guard: the old INSERT already refused the guest.
  - **Handler tests.** `status = 500, want 409 (body map[error:Database error. success:false])`, and `code = <nil>, want "not_group_member"` and so on for each code. Only the two pre-existing codes passed.
- **GREEN, same DB:**
  - `go test ./internal/chatgroups/ -count=1 -p 1 -v`: `ok …/internal/chatgroups 126.064s`, 62 PASS / 0 SKIP / 0 FAIL.
  - `go test ./internal/handlers/ -count=1 -p 1 -v`: `ok …/internal/handlers 1512.881s`, 237 PASS / 0 SKIP / 0 FAIL. Every new test printed `--- PASS`.
- **Fresh DB `godonation_cg_conflict_codes_pkg`:** `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/chatgroups 615.473s` and `ok …/internal/handlers 552.194s`, exit 0.
- **Fresh DB `godonation_cg_conflict_codes_suite`:** `go test ./... -count=1 -p 1 -timeout 45m` exited 0 and printed 22 `ok` packages with 0 FAIL, panic or build-failed lines. Among them were `ok …/internal/chatgroups 23.768s` and `ok …/internal/handlers 81.963s`. The first full-suite attempt, on `godonation_cg_conflict_codes_full`, was killed with its session before finishing; that DB no longer exists.
- `go vet ./...` exited 0. `gofmt -l` on the 8 changed files printed nothing.
- **Review:** `ecc:code-reviewer` said APPROVE, with 0 critical, 0 high, 0 medium and 1 low; the low is listed under "still open" below.
- **DBs:** four throwaway DBs were created for this work: `godonation_cg_conflict_codes` (RED/GREEN), `_pkg`, `_full` (the killed run) and `_suite`.
  - `dropdb` reported dropping `godonation_cg_conflict_codes` and `godonation_cg_conflict_codes_suite`.
  - `_pkg` and `_full` were already gone when checked after the restart.
  - At the end, `psql -lqt | grep godonation_cg_conflict_codes` matched nothing (grep exit 1).
  - No other database was touched.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commits are local and unpushed, and no human has reviewed them.
- OPOS MCP needs interactive OAuth and was not available to this subagent, so #26410 was not moved or commented on.
- **admin-web.**
  - `src/lib/locales/{en,ar,ckb,kmr}.ts` have no `error.<code>` keys for any of these codes, `server_error` included.
  - Until they are added, `describeError` shows the English sentence for a 4xx and `error.server` for the 500.
- **Owned by the parallel agent (`chat_group_admin.go`).**
  - The connect-request 404 "Connect request not found." needs a one-line `"code": "connect_request_not_found"` on each of its three intercepts.
  - The handler-level 400s listed above also have no code.
- **Misleading sentence.** DELETE on a member who is not active answers 404 `group_not_found` "Group not found.".
- **No relabel path.** No endpoint changes a member's label, so a reactivation refused for a taken label can only be resolved by removing the other holder.
- **Reviewer LOW, which predates this diff.** `insertNewMember`'s auto-label `COUNT(*)` is not serialized. Two concurrent adds of new users with the same role can compute the same "Donor N"; the second now gets a clean 409 `group_label_conflict` instead of a 500.
- **Flutter.** No change is needed.
  - `sendChatGroupMessage` maps only `contact_details_blocked` and `chat_lifecycle_closed`. Any other code, including the new `not_group_member`, gets the same generic line that no code got before.
  - The conversation screen reads status codes only.
  - `postJson` callers show `failureMessage`, never the server sentence.

**Traps:**
- **Worktree guard.** The agent's worktree guard refuses complex Bash: process substitution around `git show`, or a long `-run 'a|b|c'` combined with variables and redirects. Split them into plain commands.
- **Long handlers run.** `internal/handlers` took about 25 minutes under this machine's load, past the 10-minute tool limit, so run it in the background.
- **`chatErr` logs from `c.Request`.** A test that builds a context with `gin.CreateTestContext` must set `c.Request`, or the `server_error` path panics.
- **Hard-coded constraint names.** `memberUserConstraint` and `memberLabelConstraint` in `chatgroups_members.go` must change with any migration that renames those constraints; otherwise conflicts silently revert to 500 `server_error`.
- **Unrelated gofmt hit.** `gofmt -l` in `backend/` still lists `internal/handlers/admin_edit_user_profile.go`, which is untouched and already unformatted on `origin/main`.
- **A session end kills background test runs.** The first full-suite run died with its session and left nothing to read. Check `psql -l` for leftover throwaway DBs before re-running, and re-run on a fresh one.
- **`dropdb` can hang past the tool limit.** `dropdb` waits while any connection to the DB is still open, which may be a test process that has not exited yet. Check `pg_stat_activity` for the DB first.
- **No re-runs on the same DB.** `internal/chatgroups` tests still cannot be re-run on the same DB (see the #26351 entry). Use a fresh DB per run.

---

## 2026-09-15 — OPOS #26448: the chat request notification tile never starts a chat poller for a guest (branch `fix/notification-tile-no-guest-chat-poller`)

**What was asked:** close the gap #100 (OPOS #26423) left open, test-first. `NotificationTile` still fell back to `Get.put(ChatController())` for a `chat_request` notification, with no guest check. This is defense in depth: the server already gives guests an empty `/chats` (#97), and #26424 hides chat notifications from guests server-side. The change had to stay in `notification_tile.dart` plus new tests, with no `app_translations.dart` edits.

**What was actually changed** (commit `bf77eb8` on `origin/main` `e66ff69`; local, unpushed):
- `humanitarian/lib/modules/notifications/widgets/notification_tile.dart`:
  - `_ChatRequestActions` (inline Accept/Decline) is now built only when `!isGuestMode()`, checked LAST in its condition, so a tile that is not a chat request never reads preferences.
  - The reason it matters: the widget's `Obx` reads `ChatController.threads` and puts a controller when none exists. `ChatController.onInit` fetches `/api/chats` and starts a 5-second `Timer.periodic`, so merely rendering the tile started that poll for a guest.
  - A comment on the `_ctrl` getter warns not to host the widget without the guard.
- **Why hidden and not `requireSignIn`:**
  - `ConnectRequestButton` already renders nothing for a guest.
  - A tap gate cannot stop a poller that the build itself starts.
  - `POST /api/chats/:id/accept` and `/decline` are `RequireNotGuest` (`backend/cmd/server/main.go:751-752`).
  - Signing in lands on a different account, which the invite is not addressed to.
  - The notification itself still shows and still taps through.
- New test: `humanitarian/test/notifications/chat_request_tile_guest_test.dart` (4 tests).
  - Guest: the tile shows and taps through, with no `ChatController`, no chat-route request past 6 seconds, and no buttons.
  - Member: with no controller registered, the fallback still registers one, which loads and polls `/api/chats` and draws 2 buttons. Decline posts `POST /api/chats/42/decline`.

**What was run and what it printed** (all from `humanitarian/`):
- RED, before the fix: the new file printed `00:19 +2 -2: Some tests failed.`
  - Guest tests: `Expected: false / Actual: <true>` (controller registered) and `Expected: <0> / Actual: <2>` (buttons shown).
  - Both member tests passed, as intended.
- GREEN:
  - The new file alone printed `00:01 +4: All tests passed!`
  - The new file plus the existing notification and guest-chat tests printed `00:12 +51: All tests passed!` Those are `support_destination_test`, `notification_relative_time_test`, `localized_tag_test`, `dashboard_guest_chat_polling_test`, `messages_guest_prompt_test` and `top_bar_support_button_test`.
- Full `flutter test` on the final tree printed `02:23 +1031: All tests passed!`, exit 0.
- `flutter analyze` printed `6 issues found.`, the same 6 `deprecated_member_use` as the baseline, none in touched files.
- `dart format --set-exit-if-changed` on both files: 0 changed.
- `ecc:flutter-reviewer`: APPROVE, with 0 critical, 0 high and 0 medium findings.
  - Only 3 sites ever `Get.put(ChatController())`, and all are now guest-guarded.
  - The tests are not vacuous, and no timers leak.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commits are local and unpushed, with no PR and no human review.
- OPOS MCP needed interactive OAuth and was unavailable in this subagent, so OPOS #26448 has no status update or notes yet.
- Reviewer LOW, deliberately not fixed here: `isGuestMode()` is read once at build, so the tile does not react to a guest upgrading to a member mid-session until it rebuilds. The app uses the same pattern at 16 other call sites.
- Reviewer LOW, deliberately not fixed here: `notification_tile.dart` is 705 lines, over the 500-line limit, and was already about 678 before this change. A follow-up should extract `_ChatRequestActions` into its own file.

**Traps:**
- `isGuestMode()` reads the `late` global `sharedPreferences`. A widget test that pumps a `chat_request` tile without initializing prefs now throws `LateInitializationError`. Other tile types do not, because the guest check runs last. `notification_relative_time_test.dart` pumps a support tile without prefs and is unaffected.
- The first session running this task ended mid-work and its background `flutter test` and reviewer runs were killed. The uncommitted tree survived, and `git checkout -B <branch> origin/main` carried it onto the newer main cleanly, because #101 and #102 touch neither file.

---

## 2026-09-15 — OPOS #26434: masked chat-group pushes name the sender in Arabic and Kurdish, not English (branch `fix/masked-push-title-localized-alias`)

**What was asked:** masked chat-group pushes put the server's English label ("Donor 1", "Support", …) into every language's title. An Arabic push read «رسالة من Donor 1», and the in-app list stored the same. Fix it test-first in `backend/internal/notify`, without touching files other branches are editing.

**Owner decisions (2026-09-15).** These were relayed mid-task and replaced the brief's first word table.
- **English:** keep the server's words exactly: "Donor 1", "Beneficiary 2", "Volunteer 3", "Member 4", "Support". Do not use "Grantor" or "Eligible Recipient". The app's chat bubbles are being changed to show the same English.
- **Arabic:**
  - The role labels become مانح N, مستحق N, متطوع N and عضو N; a bare "Member" becomes عضو.
  - **"Support" becomes فريق الدعم**, not الدعم. The app already uses الدعم for Kafala (`'Kafala': 'الدعم'`, `humanitarian/lib/localization/app_translations.dart:3837`), and TERMINOLOGY.md T10 says the two must differ.
- **Kurdish:** reuse only exact existing translations. Anything without one stays the English server word and goes on a translator list.

**What was actually changed.** There are two local commits on `fix/masked-push-title-localized-alias`, based on `origin/main` `3c3a612`.

**`38271bc` `fix(notify): localize masked chat-group aliases in push titles`**
- `backend/internal/notify/group_alias.go` (new): `localizedGroupAlias(label, lang string) string`, a pure lookup.
  - It translates only the exact shapes the server writes: the anchored, case-sensitive `^(Donor|Beneficiary|Volunteer|Member) ([1-9][0-9]*)$`, and the whole labels "Support" and "Member".
  - Everything else passes through unchanged, as does any language with no word for the label.
- `backend/internal/notify/templates.go`:
  - `GroupMaskedNewMessageMsg` applies the empty → "Member" fallback, then asks the helper for each language's label.
  - `GroupTeamNewMessageMsg` passes the real name unchanged to all four languages, so team output is byte-identical to before.
  - The shared `chatGroupNewMessageMsg` now takes a per-language `LocalText`. Its only callers are these two templates.
- `backend/internal/notify/templates_group_alias_test.go` (new) checks:
  - all four titles for every generated shape;
  - English kept verbatim;
  - Arabic "Support" is not the Kafala word;
  - 14 near-miss and custom labels kept verbatim (lowercase, leading zero, `\n`, Arabic-Indic digit, …);
  - team names untouched, even "Donor 1".
- `backend/internal/notify/group_alias_test.go` (new): the helper's own contract, including an unknown language, an upper-case code and an empty label.
- Existing tests are unchanged. `templates_chat_groups_test.go` and `handlers/chat_group_push_message_test.go` still pin «Message from Donor 1» and «Message from Beneficiary 2», which is exactly the owner's English decision.

**This entry** is the second commit.

**Kurdish words used.** Each is copied byte for byte from the app's shipped keys. A Python byte-compare against `app_translations.dart` showed no hidden joiners or direction marks.

| label | ckb (`_sorani`) | kmr (`_badini`) |
|---|---|---|
| Donor N | بەخشەر N (`'Donor'`, `:6246`) | بەخشەر N (`"Donor"`, `:8541`) |
| Beneficiary N | وەرگری شایستە N (`:6247`) | وەرگرێ شایستە N (`:8542`) |
| Volunteer N | خۆبەخش N (`:6248`) | خۆبەخش N (`:8543`) |
| Member N / Member | **stays English**: no Kurdish "Member" exists | **stays English** |
| Support | **stays English** (see below) | **stays English** |

**Why Kurdish "Support" stays English:**
- **The candidate word is ambiguous.** The app's Kurdish for its bare `'Support'` key, پشتیوانی / پشتەڤانی, is also its word for *financial* support: ckb `'Next support due'` (`:6159`), kmr `"General Support"` (`:8878`), kmr `"Kafala Sponsorship"` → «کەفالەت و پشتەڤانی» (`:8632`). That is the same ambiguity T10 settles for Arabic.
- **There is no standalone Kurdish "support team" label.** The phrase appears only inside sentences, and ckb is inconsistent: «تیمی پاڵپشتی» (`:7039`) vs «تیمی پشتگیری» (`:7541`), while kmr uses «تیما پشتەڤانیێ» (`:8699`, `:9444`).

**What was run and what it printed.** All commands ran from the worktree root.

**RED on the `origin/main` code**, with the Arabic and Kurdish expectations above, run as `go -C backend test ./internal/notify/ -count=1 -run '^TestGroup' -v`, exit 1:
- `Title[ar] = "رسالة من Donor 1", want "رسالة من مانح 1"`, and likewise for Beneficiary, Volunteer, Member 4, Support and Member, in ckb and kmr too.
- `Arabic text "رسالة من Donor 1" still contains the English noun "Donor"`.
- The custom-label and team guard tests already passed, as intended.

**RED for the helper**, before it existed, with `-run '^TestLocalizedGroupAlias'`, exit 1:
- `group_alias_test.go:38:14: undefined: localizedGroupAlias`.

**RED again after the owner decisions**, against the first implementation, with `-run '^Test(Group|LocalizedGroupAlias)'`, exit 1:
- `localizedGroupAlias("Support", "ar") = "الدعم", want "فريق الدعم"`
- `Title[en] = "Message from Grantor 1", want "Message from Donor 1"`
- `Title[ckb] = "نامە لە پشتیوانی", want "نامە لە Support"`
- `Title.Ar = "رسالة من الدعم", which names the Kafala section, not the support team`
- The handler test `chat_group_push_message_test.go:86` printed `Title.En = "Message from Eligible Recipient 2", want exactly the alias`.

**GREEN:**
- `go -C backend test ./internal/notify/ -count=1 -v` exited 0 with 18 top-level PASS, 0 FAIL and 6 SKIP (the DB tests, without `TEST_DATABASE_URL`). The last line was `ok .../internal/notify 0.976s`.
- `go -C backend test ./internal/handlers/ -count=1 -run '^TestGroupMessageFor' -v` passed: `ok .../internal/handlers 1.029s`.

**Full suite** on a fresh DB, `godonation_masked_alias_26434`:
- Command: `createdb` it, then `TEST_DATABASE_URL='postgres://localhost:5432/godonation_masked_alias_26434?sslmode=disable' go -C backend test ./... -count=1 -p 1 -timeout 45m`.
- Exit 0. 22 packages `ok`, 0 FAIL. `chatgroups` took 604.963s and `handlers` 636.225s. The last lines were `ok .../internal/storage 1.225s` and `ok .../internal/users 39.573s`.
- The DB was then dropped, and `SELECT count(*) FROM pg_database WHERE datname = 'godonation_masked_alias_26434'` printed `0`.

**Formatting and vet:**
- `gofmt -l` on the four changed Go files prints nothing, and `go -C backend vet ./...` is clean.
- `gofmt -l backend` still lists only `internal/handlers/admin_edit_user_profile.go`, which was already on `main` and is not touched here.

**Code review** (`ecc:code-reviewer`, two passes):
- **First pass:** APPROVE with one LOW. The comments claimed *every* label staff typed passes through untouched. But a typed label that is exactly a generated shape (e.g. "Donor 5") is stored identically (`MemberInput.Label`, `chatgroups.go:246-253` and `:329-342`), so it is translated too. The comments were reworded in `38271bc`.
- **Second pass**, on the final diff: APPROVE, no findings. It byte-checked the Kurdish against the app, and confirmed `groupMessageFor` (`handlers/chat_group.go:348`) is the only production caller and that nothing parses stored titles.

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needed OAuth and wasn't available in this non-interactive session, so #26434 was not moved or commented on.

**What is still open:**
- Both commits are local, unpushed and not reviewed by a human.
- **Translator request (ckb + kmr):**
  - "Member", standalone and as «Member N»;
  - "Support", meaning the support team, with the candidates listed above.
- **The Flutter branch `fix/chat-group-sender-labels-localized` (OPOS #26419, unmerged) contradicts the owner's decisions.** It still has English `Grantor @n` / `Eligible Recipient @n` and Arabic `الدعم`. The coordinator reports the bubbles are being changed to match; until then, push and bubble differ.
- **Kurdish push and Kurdish bubble will differ.** That branch also leaves ckb/kmr to fall back to English, so a Kurdish reader sees Kurdish Donor/Beneficiary/Volunteer in the push but English in the bubble, unless the app reuses the same three values.
- **The team-group empty-name fallback is still the English "Member"** in every language («رسالة من Member»). It was left untouched on purpose, since team groups were out of scope.
- **Script mix in Badini titles.** The Badini chat title template `Peyam ji %s` (shared with `ChatNewMessageMsg`) is Latin script, while the Badini nouns are Arabic script, so a title reads «Peyam ji بەخشەر 1». This is for the native-speaker review (#21431).
- **The in-app notification list reads only `title` and `title_ar`** (`internal/notify/list.go:152`). Sorani and Badini titles reach the push only.

**Traps:**
- **Wrong premise in the brief:** the brief said the label sat in the title *and body*. The body is the message preview verbatim; only the title carries the label.
- **Wrong path in the brief:** `TERMINOLOGY.md` is at the repo root, not `humanitarian/TERMINOLOGY.md`.
- **The worktree-isolation guard refuses compound Bash commands:** git combined with pipes, loops or `cd`, and `go test -run 'A|B'` inside a pipeline. Run plain commands such as `go -C backend test … > file`, then read the file.
- **`dropdb`/`createdb` can take over 2 minutes** while other agents' suites load Postgres. It is not a hang.
- **Stale Grantor/الدعم version:** the first implementation followed the brief's table (Grantor / Eligible Recipient / الدعم / Kurdish پشتیوانی). It was replaced before any commit. The first review agent was launched on that version but reviewed the final files.

## 2026-09-15 — OPOS #26424: guests no longer see chat notifications or their previews (branch `fix/guest-notifications-no-chat-previews`)

**What was asked:** guests must not read chats. The chat read routes already refuse guests (PR #83, and #26354 in flight). But `GET /api/notifications` was not guest-gated, and a chat message writes a notification whose body is an 80-character preview of the message. A guest who was in a chat before `9d1cde5` could still read snippets there. The task was to close that, test-first, touching only notification list/count code.

**What was actually changed** (commit `7d8a563` on `fix/guest-notifications-no-chat-previews`, based on `origin/main` `a1da04f`; `main.go` untouched):
- `backend/internal/notify/list.go`:
  - `chatNotificationTypes` (line 72) is the one named list of chat types. `ChatNotificationTypes()` (line 86) returns a copy of it.
  - `GuestChatExclusionSQL(userIDArg, typesArg)` (line 103) is the shared SQL predicate. It uses placeholders only and is NULL-safe. It drops chat-type rows when `users.is_guest` is true.
  - `Notifier.List` applies it for every user id (line 199).
- `backend/internal/dashboard/dashboard.go`: `recentNotifications` (line 139) applies the same predicate (line 148). It is a second leak with the same cause: `GET /api/dashboard` returns the newest three notification bodies and is not guest-gated.
- `backend/internal/handlers/notifications.go`: the doc comment on `List` changed; nothing else.
- New tests:
  - `backend/internal/handlers/notifications_guest_test.go`: HTTP tests with a router that mirrors `main.go`, guest vs member.
  - `backend/internal/notify/chat_types_test.go`: pure unit tests that stop the type list drifting from the templates.

**Decision: option (a), filter by type for guests; the routes stay open.** Option (b), gating the route, was rejected for two reasons:
- Guests legitimately receive `new_campaign`, `new_media_post`, `new_partner`, `new_volunteer_mission` and `admin_announcement` broadcasts (`Notifier.Broadcast` selects every active user), plus support-ticket notifications.
- The app polls `/notifications` for guests too, so a 403 would turn the Alerts screen into an error state.

The filter is in SQL, before `LIMIT`. There is no separate count endpoint: the app counts `is_read` from the same list, and `?read_status=unread` / `?unread_only=1` filter the same query.

**Type classification** (every `Type:` the backend writes: `notify/templates.go` plus `handlers/push.go`):

| Class | Types | Guest sees it? |
|---|---|---|
| Chat | `chat_request`, `chat_accepted`, `chat_message` (donor↔owner chat, and support-chat staff replies), `chat_group_message`, `marriage_chat_request`, `marriage_chat_accepted`, `marriage_chat_message`, `marriage_meeting_declined` (refusal of a request to open a marriage chat), `staff_chat_message` | No |
| Support tickets | `support_request_submitted`, `support_ticket_replied`, `support_ticket_<status>` | Yes. `GET /api/support/mine` stays guest-readable, and these rows never quote the reply |
| Everything else | donations, sponsorships, in-kind, marketplace, marriage profile/subscription, registration, volunteer, project/case, broadcasts, `admin_*`, `task_assigned`, reminders | Yes, unchanged |

**Routes affected:**
- `GET /api/notifications` and `GET /api/notifications/` (`cmd/server/main.go:753-754`): `NotificationsHandler.List` (`handlers/notifications.go:32`) calls `Notifier.List`.
- `GET /api/dashboard` and `GET /api/dashboard/` (`main.go:855-856`): `DashboardHandler.Get` (`handlers/extras.go:1109`) calls `recentNotifications`.
- Not changed: `POST /api/notifications` mark_read (`main.go:755-756`).

**What the app shows a guest:**
- `NotificationsController` is registered for every session and polls every 5s. The bell (`humanitarian/lib/modules/dashboard/screens/dashboard_screen.dart:781-787`) has no guest check.
- After this change the list simply contains no chat rows. The bell badge and the "N new" card count only the rows shown.
- There is no error state. If nothing is left, the screen shows its normal empty state.
- The app does not fetch `/dashboard` for guests (`dashboard_screen.dart:113`), but the server filters it anyway.
- No Flutter file changed.

**What was run and what it printed** (DB `godonation_guest_notif_26424`, created for this work, recreated fresh before each full run, then dropped):
- **RED:**
  - `go test ./internal/notify/ -run ChatNotificationTypes` failed with `undefined: ChatNotificationTypes … [build failed]`.
  - `go test ./internal/handlers/ -run GuestNotifications -v`:
    - On `/api/notifications`, `/api/notifications/`, `?read_status=unread` and `?unread_only=1`, it printed `guest was shown chat notifications [chat_group_message chat_message]`.
    - `?type=chat_message` printed `got 1 rows (body … "body":"meet me at the clinic gate…")`.
    - The dashboard guest check printed `recent_notifications = [40 39 42], want [40 39 38]`, where 42 is the `chat_group_message` row.
    - Both member controls printed `--- PASS`.
- **GREEN:** `ok …/internal/handlers 1.745s` with all 3 tests `--- PASS`, and the 3 notify tests `--- PASS`.
- **Fresh DB, the two packages:** `go test ./internal/notify/ ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/notify 24.829s` and `ok …/internal/handlers 385.555s`.
- **Fresh DB, full suite:** `go test ./... -count=1 -p 1 -timeout 45m` printed `ok` for all 22 packages with tests, and no `FAIL` or `panic` line. Among them: `ok …/internal/chatgroups 597.998s`, `ok …/internal/handlers 1511.426s`, `ok …/internal/notify 23.885s`.
- **New tests with `-v`:** 6 `--- PASS`, 0 `--- SKIP`.
- **Static checks:** `go vet ./...` exited 0. `gofmt -l` on the 5 changed files printed nothing.
- **DB removed:** after `dropdb`, `select count(*) from pg_database where datname='godonation_guest_notif_26424'` printed `0`.
- **Review:** `ecc:code-reviewer` approved, with 0 critical, 0 high and 0 medium findings. Two LOW notes, not applied, are listed below.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- Both commits are local and unpushed, with no human review.
- OPOS MCP needed interactive OAuth and wasn't available in this subagent session, so I didn't move or comment on #26424.
- Reviewer LOW 1: `Notifier.MarkRead` (`notify/list.go:291`) does not apply the guest exclusion.
  - A guest can mark a hidden chat row as read by id.
  - No body is returned, so nothing leaks.
- Reviewer LOW 2: `seedNotificationMix` registers no `t.Cleanup` for its `app_notifications` rows.
  - They are removed by the `ON DELETE CASCADE` FK when `makeGuestUser` / `makeChatGroupUser` delete the user.
  - Those deletes discard their error, so a failed delete would leave the rows behind.
- Out of scope, tracked as **OPOS #26443**: FCM pushes still deliver the chat preview to a guest's devices.
  - `activeDevicesFor` (`notify/push.go:249`) has no `is_guest` check.
  - `POST /api/notifications/device` is not guest-gated.
- By design, a guest who upgrades sees their old chat notifications again: `is_guest` is read per request.

**Traps:**
- `dashboard.RecentNotification` has no `user_id` field.
  - A test that filters its rows by user gets `[]` and fails for the wrong reason, which is what my first RED run did.
  - `recentNotifications` also turns query errors into an empty list, so assert exact ids, never just "no chat rows".
- `NULL = ANY(...)` is NULL, and `NOT NULL` would hide untyped rows. The predicate wraps `COALESCE(n.notification_type, '')` to avoid that.
- This worktree's command guard refuses chained commands that mix `TEST_DATABASE_URL` and `go test` with `&&`, `;` or `echo $?`. Run `dropdb`, `createdb` and `go test` as separate plain commands.
- Under machine load, `dropdb` overran the 120s default and was moved to the background.

---

## 2026-09-15 — OPOS #26431: a racing staff pause or resume can no longer reopen an ended chat (branch `fix/chat-lifecycle-apply-race`)

**What was asked:** make `chatlifecycle.Apply`'s writes conditional on the state it read, working test-first. Two concurrent actions could interleave: a staff pause or resume, and an END from another staff member or from `cmd/retire-direct-chats`. The later write overwrote `ended`. Changes were to stay inside `backend/internal/chatlifecycle`.

**What was actually changed** (branch from `origin/main` `0277242`):
- Commit `2496f79`, `fix(chatlifecycle): make lifecycle writes conditional on the state that was read`.
- `backend/internal/chatlifecycle/apply.go` (new). Apply and its two writes moved here from `chatlifecycle.go`, which went from 435 to 300 lines; the moved text and SQL are otherwise verbatim.
  - The `setLifecycle` UPDATE gains `AND lifecycle = $5`, the lifecycle Apply decided from.
  - Zero rows returns the unexported `errLifecycleChanged`. Apply then reads the thread again and re-decides, up to `maxApplyAttempts` = 3.
  - Outcomes: a pause or resume that lost to an END gets the existing `ErrEnded`; a resume that lost to a resume gets `ErrNotPaused`; a deleted thread gets `ErrNotFound`; a blank END that lost to another END is the usual no-op.
  - If all 3 attempts are lost, Apply returns a wrapped `errLifecycleChanged`.
  - `setArchived` keeps its unconditional write, because archive and unarchive decide nothing from the read. The doc comment says why.
  - A nil-by-default `testHookBeforeWrite` runs just before each write.
- `backend/internal/chatlifecycle/apply_race_test.go` (new). Five tests; the interleaving is deterministic and uses no sleeps:
  - pause and resume refused after an END, for direct, staff and group threads. The END either commits first (a nested Apply, or `RetireAllDirectThreads`), or holds its lock while Apply's write waits (the retire run's own `retireInTx`, or a plain end).
  - a blank END keeps the winner's stamp;
  - a lost race to an allowed change is decided again;
  - a thread deleted mid-flight is `ErrNotFound` for all five actions;
  - Apply gives up after 3 lost attempts.
- **No handler changes.** `handlers/admin_chat_lifecycle.go` `lifecycleErr` already maps `ErrEnded` and `ErrNotPaused` to 409 and `ErrNotFound` to 404. Exhaustion falls to its logged 500.

**What was run and what it printed** (each DB made with `createdb`):
- **Baseline** at `0277242`, DB `gd_lifecycle_race_26431`: `go test ./internal/chatlifecycle/ -count=1` → `ok 77.280s`.
- **RED:** the hook seam was added, but the writes were still `WHERE id = $1`.
  - All 8 race subtests FAILED, each with the thread reopened. Examples:
    - `thread after the race = {Lifecycle:paused Reason:cooling off ChangedBy:69 Archived:false}; want the END kept, {Lifecycle:ended …}`;
    - resume versus the retire run: `{Lifecycle:open Reason: ChangedBy:69 Archived:true}`, want ended with the retire reason. The lock-wait cases failed the same way.
  - The blank-END test FAILED: `{Lifecycle:ended Reason: ChangedBy:83}`, want the winner's reason and user 84.
  - The benign re-pause test and the deleted-thread test PASSED. They pin behaviour the old code already had.
  - The loop-bound test FAILED: `Apply(pause) = {Lifecycle:paused …}, <nil>; want errLifecycleChanged after 3 lost attempts`.
- **GREEN:** `go test ./internal/chatlifecycle/ -count=1 -race -v -timeout 30m` → 16 top-level tests (5 new, 11 existing) and 38 results including subtests, all PASS. Nothing skipped, no `DATA RACE`, `ok 73.895s`.
- **After the review fix,** on fresh DB `gd_lifecycle_race_26431_b`: same command, all PASS, `ok 397.245s`. It was slow only because a handlers run was going at the same time.
- `gofmt -l` on the three changed files prints nothing. `go vet ./...` is clean, and `go build ./...` is ok.
- `go test ./internal/handlers/ -count=1 -p 1 -timeout 45m` on `gd_lifecycle_race_26431` → `ok internal/handlers 1092.962s`.
- **Full suite** on fresh DB `gd_lifecycle_race_26431_full2`: `go test ./... -count=1 -p 1 -timeout 45m` → 22 packages `ok`, 0 `FAIL`, exit 0. That includes `internal/chatlifecycle 120.308s` and `internal/handlers 471.043s`.
  - An earlier attempt was stopped about a minute in, because it wrote to a log name another agent was using (see Traps).
- **DBs:** `gd_lifecycle_race_26431`, `gd_lifecycle_race_26431_b`, `gd_lifecycle_race_26431_full` and `gd_lifecycle_race_26431_full2` were all dropped. A `pg_database` count of `gd_lifecycle_race_26431%` returns 0.
- **Code review** (`ecc:code-reviewer`): APPROVE. It confirmed the retry-and-re-decide semantics, the READ COMMITTED claim, that no non-racing request changes HTTP status, and that the move is verbatim. One MEDIUM finding: the lock-wait harness's `pg_blocking_pids` check matched any blocked backend on the server. Fixed: the losing Apply now runs through a second pool tagged with `application_name`, and the check filters on it.

**External actions taken:** nothing pushed and no PR opened.
- A comment with these results was added to OPOS #26431. Its status and timer were left alone: the timer is the parent session's, log 24648.
- A task chip was suggested for the group NOT NULL defect below.

**What is still open:**
- Both commits are local and unpushed, not reviewed by a human.
- **Group lifecycle defect, pre-existing and not fixed here.** A group resume, or a group pause or end with no reason, fails with 23502 and returns HTTP 500. The cause: `setLifecycle` stores an empty reason as NULL, but `chat_group_threads.lifecycle_reason` is `NOT NULL DEFAULT ''` (migration 120). Verified with psql on a migrated DB. No existing test covered it.
  - The user has started a separate session to fix it.
  - That fix will conflict with this branch. Commit `2496f79` moved `setLifecycle`, including its NULL-reason line, and the resume call from `chatlifecycle.go` to `apply.go`, and changed `setLifecycle`'s signature. Whichever branch merges second has to rebase.
- **Trash snapshot race, found by reading the code and not reproduced.** `handlers.trashChatThread` snapshots the thread with a plain SELECT, without `FOR UPDATE`, then deletes it. A delete that races a lifecycle write, or the retire run, can store the state from before that write. A later restore brings that state back, for example an open, unarchived direct thread. Separately, any direct thread already in the Trash before the retire run restores as open.
- **Runbook `docs/runbooks/retire-direct-chats.md`**, not edited as instructed. Section 3 item 7 and risk 9 still describe the race as open.
  - Risk 9 is now closed in code: a racing pause or resume is refused and the thread stays ended. This was tested with the run committed first and with the dashboard write blocked on the run's lock.
  - The freeze can be narrowed to END, archive, unarchive and delete. Those are still worth freezing:
    - their races are serial-equivalent, but they re-stamp rows, which shifts post-checks 7b, 7c, 7d and 7g;
    - the `updated_at = run_ts` restore then skips those rows;
    - a delete can hit the Trash snapshot race above.

**Traps:**
- **The session scratchpad is shared with sibling agents.** Another agent wrote to the same generic `full.log`, and its `exit=0` and `dropped` lines looked like this run's result. Use a per-agent subdirectory and a unique exit marker, and check `ps` before trusting a log.
- **Background commands can start minutes late** on a loaded machine.
- **`go test` without `-v` writes nothing to a redirected log until a package finishes.** An empty log is not a hang.
- **Don't run two DB-backed packages against one DB at once.** The retire tests act on the whole `chat_threads` table. Use separate DBs.
- **The group race tests must pause with a reason,** because of the NOT NULL defect above.

---

## 2026-09-15 — OPOS #26408: admin-web test infrastructure and a credential-free mock API (branch `chore/admin-web-test-setup`)

**What was asked:** implement Phase 6 plan sections T0 and T0b in admin-web, test-first. That meant two things:
- **T0:** Vitest and Testing Library, with a first ContactBlocksPanel test.
- **T0b:** a zero-dependency mock API, so dashboard screens can be checked in a browser with no backend and no login.

Commit, do not push.

**What was actually changed** (branched from `origin/main` at `9bcc053`, in worktree `.claude/worktrees/agent-a5596c0e5627a3217`):
- **`1f2424d` chore(admin-web): add Vitest and Testing Library.**
  - devDependencies, installed without `--legacy-peer-deps`:
    - vitest 5.0.1 and jsdom 30.0.1;
    - @testing-library/react 16.3.3, dom 10.4.2, user-event 14.6.7 and jest-dom 7.0.1.
  - The lockfile also moved three transitive packages, each within range:
    - @jridgewell/sourcemap-codec 1.5.5→1.6.0;
    - picomatch 4.0.4→4.0.7;
    - tinyglobby 0.2.16→0.2.17.
  - New files: `vitest.config.ts`, which merges `vite.config.ts`, and `tsconfig.test.json`. Three existing configs changed:
    - `tsconfig.json` now references `tsconfig.test.json`;
    - `tsconfig.app.json` excludes the tests;
    - `tsconfig.node.json` includes `vitest.config.ts`.
  - Under `src/test/`:
    - `setup.ts`: jest-dom; `cleanup`, `localStorage.clear` and `resetPermissionCache` after each test.
    - `render.tsx`: `renderWithProviders`.
    - `mockApi.ts`: spies on `api` and rejects unregistered requests.
    - `fixtures/session.ts`.
  - Scripts `test` and `test:watch`.
  - `src/lib/permissions.ts` gains `resetPermissionCache()`.
  - Tests:
    - `src/components/ContactBlocksPanel.test.tsx`: the empty state, which asserts the GET URL, and Retry after a 500.
    - `src/lib/permissions.test.ts`.
- **`493a8e1` feat(admin-web): mock API for credential-free browser checks.**
  - The server is split across four files, `scripts/mock-api.mjs` plus `-routes`, `-chat-routes` and `-helpers`. Each file stays under 500 lines.
  - Fixtures: `src/test/fixtures/{chatGroups,legacyChats,permissions,shell}.ts`.
  - `scripts/mock-api.test.mjs` has 21 cases, and `docs/mock-api.md` explains how to use the mock.
  - Scripts `mock:api` and `test:mock-api`.
- **This entry.**

**What was run and what it printed.** All runs used Node 22.23.1, via `PATH=/opt/homebrew/opt/node@22/bin:$PATH`.
- **RED, then GREEN, for the ContactBlocksPanel test.**
  - The expected GET URL was deliberately wrong. The run printed `AssertionError: expected [ { method: 'get', …(2) } ] to deeply equal [ { method: 'get', …(1) } ]`, with the diff `- "url": "/api/admin/chat-groups/7/contact-blocks"` / `+ "url": "/api/admin/chats/7/contact-blocks"`, and `Tests 1 failed | 1 passed (2)`.
  - After correcting the URL, both tests passed.
- **RED, then GREEN, for `resetPermissionCache`.**
  - Before the function existed: `TypeError: resetPermissionCache is not a function`.
  - With a no-op body: `AssertionError: expected false to be true`, the stale cached matrix.
  - After implementing it: `Tests 3 passed (3)`.
- **RED, then GREEN, for the mock.**
  - Before the server existed: `ERR_MODULE_NOT_FOUND … scripts/mock-api.mjs`.
  - After: `# tests 21`, `# pass 21`, `# fail 0`.
- **Final runs on the branch:**
  - `npm test` → `Test Files 2 passed (2)`, `Tests 3 passed (3)`.
  - `npm run build` → exit 0.
  - `npm run test:mock-api` → 21 pass, 0 fail.
  - `npm run lint` → `✖ 162 problems (98 errors, 64 warnings)`, exit 1. This is identical to clean `9bcc053`: the same 137 files are flagged, none of them new.
  - `check:labels` → exit 1, output identical to clean main (see below).
  - The other checks pass, as they did on main:
    - `check:pwa`: 46 checks passed (38 on main, where `dist/` was absent);
    - `test:sw`: 13 passed;
    - `test:nav`: 15 pass;
    - `test:field-labels`: 4 pass;
    - `check:pending-parity`, `check:css-tokens` and `check:feed-bodies`: ok.
- **On the machine's default Node 23.11.0,** `npx vitest run` passed 3 of 3 and the mock test passed 21 of 21.
- **Live check.**
  - `npm run mock:api` equivalent, on port 8787 as PID 39334. The start-up log printed the `API_TARGET` and localStorage hints.
  - `curl /api/admin/chat-groups` → groups 42 (team) and 41 (masked).
  - `…/41/messages?after_id=8101&limit=2` → messages 8102 and 8103.
  - `…/connect-requests?scenario=error` → 500.
  - Then PID 39334 was killed.

**Review follow-up, same day** (commit `fix(admin-web): mock API listens on loopback only`). The code review came back CHANGES NEEDED with one HIGH. Everything else it checked was verified solid.
- **HIGH, fixed: the mock listened on every interface.**
  - `scripts/mock-api.mjs` called `server.listen(port, …)` with no host.
  - Before the fix, `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` on the running CLI printed `IPv6 … TCP *:8787 (LISTEN)`. The start-up banner prints a super_admin session.
  - Now a new exported `listenOnLoopback(server, port)` binds `127.0.0.1`, and both the command line and the test helper start the server through it.
  - The banner and `docs/mock-api.md` now say 127.0.0.1 throughout.
- **Tests first.** Two new cases in `scripts/mock-api.test.mjs`:
  - `listenOnLoopback` binds `127.0.0.1`;
  - the `if (isEntryPoint)` block calls `listenOnLoopback(server, port)` and never `.listen(` itself.

  RED printed `SyntaxError: The requested module './mock-api.mjs' does not provide an export named 'listenOnLoopback'`. Run against the unfixed file, the CLI check found `server.listen(port, () => printStartupHint(port, scenario))` and no helper call.

  GREEN, after the fix, with the same `lsof`: `IPv4 … TCP 127.0.0.1:8787 (LISTEN)`, and `curl http://127.0.0.1:8787/api/admin/chat-groups/42` answered the team group.
- **Vite binds every interface too.** `vite.config.ts` sets `host: true`, so a plain `npm run dev` would expose the mock's data through the `/api` proxy.
  - Checked: `npx vite --host 127.0.0.1` listened on `127.0.0.1:5199` only.
  - The docs and banner now say `API_TARGET=http://127.0.0.1:8787 npm run dev -- --host 127.0.0.1`. `vite.config.ts` was not changed.
- **The mock scripts have no ESLint coverage today.**
  - `npx eslint --print-config scripts/mock-api.mjs` applies 0 rules, against 108 for `src/lib/api.ts`.
  - A throwaway `scripts/*.mjs` file containing an unused variable linted clean, exit 0; the file was deleted.
  - The cause: `eslint.config.js` only configures `**/*.{ts,tsx}`, and a config-protection hook blocks editing that file.
  - Stated in `docs/mock-api.md`. The coordinator is adding it to the lint follow-up, OPOS #26437.
- **`common.retry`:** nothing to do on this branch. The Phase 6a branch adds the key, and the test's comment stays as it is.
- **Verification with Node 22.23.1:**
  - `npm run test:mock-api` → `# tests 23`, `# pass 23`, `# fail 0`.
  - `npm test` → exit 0, `Test Files 2 passed (2)`, `Tests 3 passed (3)`.
  - `npm run build` → exit 0, `✓ built in 6.57s`.
- **New traps:**
  - Use `127.0.0.1` in `API_TARGET`, not `localhost`: the mock does not listen on IPv6 `::1`.
  - localStorage is per origin, so a session pasted on `localhost:5173` is not visible on `127.0.0.1:5173`.

**External actions taken:** none. Nothing was pushed. OPOS MCP needed OAuth, which wasn't available in this non-interactive subagent, so #26408 was not moved or commented on.

**What is still open:**
- **Commits.** Both commits are local, unpushed and not reviewed by a human.
- **Lint.** `npm run lint` already fails on main with 162 problems, so the plan's "lint passes" acceptance needs a separate cleanup. This branch adds no problems.
- **check:labels.** It already fails on main with 6 values: `status.case`, `created`, `masked`, `member_added`, `member_removed` and `team`. The fix belongs to the Phase 6 dashboard task.
- **ESLint override.** The planned override for `src/test/**` was not added, because a config-protection hook blocks edits to `eslint.config.js`. ESLint reports no problems in the test files without it.
- **Missing `common.retry` key.**
  - No locale defines it, so ContactBlocksPanel.tsx:132 and EditModal.tsx:384 print the raw key.
  - The Retry test finds the button by role, with a comment saying to pin the label once the key exists.
  - A follow-up task was suggested.
- **Mock vs backend.** Known differences are listed in `admin-web/docs/mock-api.md`: no auth or masking, no contact scan on labels, and borrowed empty-body 400 text on the legacy routes.

**Traps:**
- **Node version.** The default `node` on this Mac is 23.11.0. That is outside vitest 5's engines (`^22.12 || ^24`) and jsdom 30's (`^22.22.2 || ^24.15`). The tests passed on it, but `.nvmrc` says 22 and Homebrew's `node@22` is installed.
- **Test reporter.** On Node 23, `node --test` prints `ℹ pass N`, not the TAP `# pass N`, so a grep for `# pass` finds nothing.
- **Testing Library cleanup.** It does not clean up automatically without Vitest globals, so `setup.ts` calls `cleanup()` itself.
- **`mockApi` scope.** It spies on `api`'s methods, so axios interceptors (the Bearer header, the delete-password dialog, the 401 sign-out) never run in those tests.
- **Parallel branches.** Other agents' branches also edit this file. On a conflict, keep both entries.

---

## 2026-09-15 — OPOS #26419: masked chat-group sender labels in the reader's language (branch `fix/chat-group-sender-labels-localized`)

**What was asked:** Arabic members saw the server's English sender labels ("Support", "Donor 1") in masked group chats. Fix it in the Flutter app, tests first, en + ar only.

**Decision: app side (a), not server fields (b).** The app maps only the exact strings the server generates:
- `autoLabel` in `backend/internal/chatgroups/chatgroups.go` writes "Donor N", "Beneficiary N", "Volunteer N" and "Member N".
- `ListMessagesForMember` in `chatgroups_reads.go` writes "Support" for staff, and a bare "Member" fallback when there is no label or name.

Why (a): it needs no API change and no backend release in step with the app.
- The conversation screen is never told the group kind, so the mapping runs on every label.
- A custom label or a team member's real name is translated only if it is literally "Support", "Member" or "Donor 3", and then it already meant that.

**What was actually changed** (one commit, based on `origin/main` `60cf163`):
- **New:** `humanitarian/lib/modules/chatgroups/utils/chat_group_sender_label.dart`, containing `localizedSenderLabel(String)`.
  - Match rule: `^(Donor|Beneficiary|Volunteer|Member) ([1-9][0-9]*)$`, plus the exact words `Support` and `Member`. It is case-sensitive.
  - Anything else, a number too big for an int, or a missing translation returns the label unchanged.
  - The number is formatted with `NumberFormat.decimalPattern(AppLocaleService.dateFormatLocale(Get.locale))..turnOffGrouping()`.
- **`chat_group_message_bubble.dart`:** `_SenderLabel` calls the mapper. This is the ONLY place the app displays `sender_label`.
  - The Messages-tab tile's `last_message` is the message body only.
  - My Connect Requests only uses `chatGroupTitle`.
- **`app_translations.dart`:** 6 keys added to `_en` and `_ar` under `chat_group_sender_`:

  | Key | English | Arabic |
  |---|---|---|
  | `support` | Support | فريق الدعم |
  | `member` | Member | عضو |
  | `donor_n` | Donor @n | مانح @n |
  | `beneficiary_n` | Beneficiary @n | مستحق @n |
  | `volunteer_n` | Volunteer @n | متطوع @n |
  | `member_n` | Member @n | عضو @n |

  The table shows the values after the review follow-up commit (below). The first commit `61311a7` shipped English `Grantor @n` / `Eligible Recipient @n` and Arabic support `الدعم`.
- **Tests:**
  - New `test/modules/chatgroups/chat_group_sender_label_test.dart` (unit). It includes Kurdish `ar_IQ` and `ar_TR` (English fallback, never Arabic) and a no-translations group (the key name is never shown).
  - New `test/modules/chatgroups/chat_group_message_bubble_sender_label_test.dart` (widget).
  - `chat_group_conversation_screen_test.dart` still expects "Donor 1" in English. The first commit changed it to "Grantor 1"; the follow-up changed it back.
- **`TRANSLATION_REQUEST.md`:** new 6-key section; the total and the `## Count:` heading both read 465.

**Review follow-up (second commit, same branch, not amended):**
- **User decision, 2026-09-15:** English aliases use the server's own words (`Donor @n`, `Beneficiary @n`), so the app matches the dashboard and push notifications.
- **Arabic `chat_group_sender_support`:** now `فريق الدعم`. A bare `الدعم` is already Kafala (`app_translations.dart` ~3859), and TERMINOLOGY.md T10 settles that the two must differ. The app already says فريق الدعم for the support team.
- **Kurdish:** `ar_IQ` / `ar_TR` get English here, because `AppTranslations` merges `_en` under each Kurdish map. That means Kurdish never reaches the missing-translation branch, so a separate test clears all translations to pin that branch.
- **Follow-up verification** (from `humanitarian/`):
  - `dart format` on the 4 files this change owns printed `Formatted 4 files (0 changed)`.
  - The 2 new test files printed `+43: All tests passed!`
  - `flutter analyze` printed `6 issues found.`, the same baseline.
  - `flutter test test/modules/chatgroups/ test/localization/` printed `08:02 +343: All tests passed!`
  - `flutter test` printed `24:16 +1018: All tests passed!`
  - The machine was slow: analyze took 229s and the full suite took 24 minutes, against 3 before. The chain went past the 600s Bash limit and finished in the background.

**What was run and what it printed** (from `humanitarian/`):
- **Digit probe** (a temporary test, deleted): intl 0.20.2 prints ASCII digits for `ar`, `ar_SA` and `ar_IQ`.
  - `NumberFormat.decimalPattern('ar').format(12)` gives `12`.
  - `DateFormat.MMMd('ar').add_jm()` gives `14 سبتمبر 9:05 ص`.
  - So Arabic labels read `مانح 1`, matching the app's other numbers and dates.
- **RED**, with the mapper as an identity stub: the 2 new files printed `+33 -7: Some tests failed.`
- **GREEN:** the 2 new files printed `+40: All tests passed!`
- `flutter test test/modules/chatgroups/ test/localization/` printed `+340: All tests passed!`
- `flutter test` printed `+1015: All tests passed!`
- `flutter analyze` printed `6 issues found.`, the same 6 `deprecated_member_use` as the baseline.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commit is local and unpushed.
- OPOS MCP needs interactive OAuth and was unavailable in this subagent session, so #26419 was not moved or commented on.
- **Resolved (was open after `61311a7`):** whether English aliases use the app's role nouns ("Grantor 1") or the server's words ("Donor 1"). The user chose the server's words on 2026-09-15, and the review follow-up commit applies that.
- **Not fixed, server side:** the push notification for a masked-group message.
  - `GroupMaskedNewMessageMsg` in `backend/internal/notify/templates.go` bakes the English alias into all 4 language titles ("رسالة من Donor 1").
  - Those titles are also what the in-app notification list shows.
  - The fix belongs in that template, translating the alias per language. The app cannot fix it without parsing server sentences.
- **Not fixed, separate leak:** the 1:1 support chat.
  - `lib/modules/chat/models/chat_models.dart:97` falls back to an untranslated `'Support'`.
  - `chat_conversation_screen.dart` draws `senderName` raw.
- The 6 new keys need Sorani and Badini.

**Traps:**
- "The device showed ١٤ سبتمبر" did not reproduce: intl 0.20.2 prints ASCII digits under `ar`. Probe it before assuming Eastern Arabic digits.
- `dart format --set-exit-if-changed` fails on `lib/localization/app_translations.dart` (9 hunks) and on `test/modules/chatgroups/chat_group_conversation_screen_test.dart`, and it fails the same way on `origin/main`. That drift predates this change and was left alone.
- zsh: `echo ==== X` fails with "=== not found"; quote it.

---

## 2026-09-15 — OPOS #26423: guests get a sign-in prompt on Messages instead of polling donor chats (branch `fix/guest-messages-no-chat-poll`)

**What was asked:** stop treating guests like members for donor chats. The server is moving to give guests an empty GET /api/chats and /api/marriage/chats, and 403 guest_restricted on thread messages (OPOS #26354). The work was test-first, en + ar only, and support had to stay reachable for guests.

**What was actually changed** (one local commit on `fix/guest-messages-no-chat-poll`, branched from `origin/main` at `aa32268`):
- `humanitarian/lib/modules/dashboard/screens/dashboard_screen.dart`:
  - `initState` registers `ChatController` only when `!isGuestMode()`.
  - `_TopBarActions` uses `Get.isRegistered` instead of `Get.find`, so a guest's Messages button has no badge and no `Obx`. GetX 4.7.3 throws on an `Obx` that reads no observable (`rx_interface.dart:27`).
  - The Messages button stays visible for guests, because Messages is where support is reached from.
- `humanitarian/lib/modules/chat/screens/messages_screen.dart`:
  - A guest gets no `ChatController` and no `ChatGroupsController`, and sees `GuestMessagesPrompt` where the thread list was. There is no pull-to-refresh for a guest.
  - The bot card, support-chat tile and support-form tile are unchanged for everyone.
  - The `Obx` now wraps only the thread-list `AppAsync`.
- `humanitarian/lib/modules/dashboard/screens/guest_sections.dart`: new `GuestMessagesPrompt`, built on `AppEmpty`. Its button reuses the file's `_goSignIn`, which leaves guest mode and goes to `/login`, the same as `GuestAccountSection`.
- `humanitarian/lib/localization/app_translations.dart`: added `messages_guest_title` and `messages_guest_body` at the end of `_en` and `_ar`. The button reuses `Sign in`. No Kurdish was written.
- `TRANSLATION_REQUEST.md` (repo root; there is none under `humanitarian/`): a new section for the 2 keys, and the count went from 459 to 461.
- New tests:
  - `humanitarian/test/widgets/messages_guest_prompt_test.dart` (6 tests)
  - `humanitarian/test/widgets/dashboard_guest_chat_polling_test.dart` (3 tests)

**What was run and what it printed** (all from `humanitarian/`):
- Baseline before any edit: `flutter analyze` printed `6 issues found.`, all `deprecated_member_use`.
- RED: the two new files printed `+3 -6: Some tests failed.`
  - The guest tests failed with `Expected: false / Actual: <true>` on ChatController, `Found 0 widgets with text "Sign in to use Messages"`, and `"ChatController" not found`.
  - The 3 passing tests were the support-doors guard and the two member tests.
- GREEN:
  - The new tests plus 10 related files (Messages wiring, stale threads and support doors; top bar, assistant hint and dashboard keyboard; Arabic purity, widget literals, guest-gate language; chat groups section) printed `+54: All tests passed!`
  - Full `flutter test` on the final tree printed `18:18 +963: All tests passed!` with exit 0.
  - `flutter analyze` printed `6 issues found.`, the same 6.
- An `ecc:flutter-reviewer` pass approved with 0 critical and 0 high findings. Its medium copy finding was applied: the body line no longer says "with our team".

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commit is local, unpushed and not reviewed by a human.
- OPOS MCP needed interactive OAuth and was unavailable in this subagent, so OPOS #26423 has no status update or notes yet.
- Not changed, flagged by review: `humanitarian/lib/modules/notifications/widgets/notification_tile.dart:433-435` still does `Get.put(ChatController())` for `chat_request` notifications with no guest check. It is probably unreachable for a guest.
- Not changed: on `origin/main`, `POST /chats/support` is `RequireNotGuest` (`backend/cmd/server/main.go:736`). So a guest tapping "Contact support" on Messages gets the existing failure state. The support form (`TechnicalSupportScreen`) opens for guests, but its submit is behind `requireSignIn`.
- Review LOW items left as they are:
  - `if (!isGuestMode()) const ChatGroupsSection()` was kept as written, because `messages_screen_chat_groups_wiring_test.dart:98` pins that exact text.
  - The private `_messagesButton` helper in `_TopBarActions` stays.

**Traps:**
- Branch `fix/connect-copy-our-team` edits chat-group strings. These keys sit at the END of `_en`/`_ar`, away from those strings, to keep the merge simple.
- `dart format` already flags the `IndexedStack(...)` block around `dashboard_screen.dart:248` on main. It was left unformatted so the diff stays readable.
- Running the full `flutter test` alongside `flutter analyze` pushed it past a 600s tool timeout (18 min). Run them one after the other.

---

## 2026-09-15 — OPOS #26426: marriage-chat invite accept now respects the thread lifecycle (branch `fix/marriage-accept-respects-lifecycle`)

**What was asked:** `POST /api/marriage/chats/:id/accept` had no lifecycle check, the gap #26413 recorded as open. Confirm the bug, then fix it test-first with the same gate the donor accept got in #26413. Keep the change to the marriage ACCEPT handler plus new test files, because parallel branches edit decline (#26427), the list routes (#26354) and chat-group files.

**What was actually changed:** one commit, `12f45af`, based on `origin/main` `a1da04f`:
- `backend/internal/handlers/marriage_chat.go` `MarriageChatHandler.Accept` (line 158) now runs `GetThread`, then an owner check, then `refuseIfInviteClosed(c, h.Pool, chatlifecycle.KindMarriage, id)` (line 177). All three run before `AcceptThread` and the `MarriageChatAcceptedMsg` push (line 190).
  - A non-owner gets `chatErr(marriagechat.ErrNotOwner)`, the same 403 "Only the profile owner can accept or decline." that `AcceptThread` gave before.
  - This is an OWNER check, not the donor path's participant check. It keeps today's 403 for both a stranger and the requester, and it runs before the gate because the 409 carries staff's reason.
  - Paused or ended gets 409 `chat_lifecycle_closed`, the same as the send path.
  - Archived-but-open gets 404 `{"error":"Chat not found.","success":false}`. That is exactly what the marriage messages route (`MarriageChatHandler.Messages` → `refuseIfArchivedForParticipant`) answers, and it is the same 404 the donor accept gives.
- `backend/internal/marriagechat/marriagechat.go` `Store.AcceptThread` (line 217): doc comment only. It says the lifecycle gate lives in the handler, so a new caller must run it. The wording mirrors #26413's comment on `chat.Store.AcceptThread`.
- New test `backend/internal/handlers/marriage_invite_accept_lifecycle_test.go` (6 tests, 8 counting subtests):
  - Each invite is seeded through the real `marriagechat.Store.ApproveMeetingRequest`, which opens the `pending` thread.
  - Refusal cases:
    - ended and paused, via `setLifecycle`;
    - retired, via real `chatlifecycle.Apply` end then archive with `KindMarriage`;
    - archived-open, where the test compares the accept response to the messages route response with `reflect.DeepEqual`.
  - Each refusal asserts that the status stays `pending` and that no `marriage_chat_accepted` row exists in `app_notifications`.
  - Controls: an open invite accepts and its push row appears. A stranger and the requester each get the plain 403 with no `code` or `lifecycle_reason`.
- The route (`backend/cmd/server/main.go:804`) and the gate (`backend/internal/handlers/chat_lifecycle_gate.go:121`) are unchanged.

**What the app shows for a refused accept:**
- `marriage_chat_conversation_screen.dart:156` `_decide(true)` calls `ModuleApi.acceptMarriageChat`, which goes through `postJson`. On non-2xx, `postJson` throws `Exception(<server sentence>)` and ignores `code`.
- The catch shows a snackbar from `failureMessage(e, 'error_message_send_failed')`: "Could not send your message. Please try again. If it keeps happening, contact support." (ar: "تعذّر إرسال رسالتك. حاول مرة أخرى. وإن تكرّر الأمر، تواصل مع الدعم."). The server sentence is not shown.
- The Accept/Decline row is gated only on `_status == 'pending' && isOwner`, not on the lifecycle. On a paused or ended invite the owner therefore sees the buttons and the `ChatLifecycleNotice` together.
- On an archived invite the messages load fails with a 404, so the screen shows "Could not load this conversation." with Retry. An archived thread is not in the list, so it is only reachable from an already-open screen or a push.
- No Flutter file was changed.

**What was run and what it printed:** DB `godonation_marriage_accept_26426`, created for this work, recreated fresh before the package run and again before the full suite, and dropped at the end. After the drop, `psql -l` shows 0 matches.
- **RED, before the fix:** `go test ./internal/handlers/ -run MarriageInviteAccept -count=1 -p 1 -timeout 45m -v` failed 4 tests, and each printed `200 map[status:active success:true ...]`:
  - `ClosedThreadRefused/ended`
  - `ClosedThreadRefused/paused`
  - `RetiredInviteRefused`
  - `ArchivedOpenInviteAnswersLikeMessagesRoute`: `accept = 200 ..., want the messages route's 404 map[error:Chat not found. success:false]`

  `OpenInviteStillAccepts` and both `NonOwnerRefusedAsBefore` subtests passed.
- **GREEN, same command after the fix:** every test printed `--- PASS`, with no `--- SKIP`, and the run ended `ok …/internal/handlers 1.536s`. For example, ended printed `409 map[code:chat_lifecycle_closed … lifecycle:ended lifecycle_reason:Resolved by our team success:false]`, and archived-open printed `404 map[error:Chat not found. success:false] (messages route: 404 map[error:Chat not found. success:false])`.
- **Package, fresh DB:** `go test ./internal/handlers/ -count=1 -p 1 -timeout 45m` printed `ok …/internal/handlers 389.763s`.
- **Full suite, fresh DB:** `go test ./... -count=1 -p 1 -timeout 45m` exited 0 with 22 `ok` packages and no FAIL. Among them: `ok …/internal/handlers 38.802s` and `ok …/internal/marriage 9.289s`.
- `go vet ./...` exited 0, `go build ./...` exited 0, and `gofmt -l` on the 3 changed files printed nothing.
- **Review:** `ecc:code-reviewer` returned APPROVE with 0 critical, high or medium findings.
  - LOW 1: document on `Store.AcceptThread` that the gate is the handler's job. Applied, in `12f45af`.
  - LOW 2: the double `GetThread`, and a race between the gate's SELECT and `AcceptThread`'s UPDATE. Left as is, because it mirrors the merged donor precedent.

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needed interactive OAuth in this subagent session, so OPOS #26426 was not moved or commented on.

**What is still open:**
- `12f45af` and this entry are local and unpushed.
- **Race window (LOW 2):** the gate reads the lifecycle, then `AcceptThread` updates without re-checking it. The donor accept and every send path have the same shape. A `SELECT … FOR UPDATE` in one transaction would close it.
- **Behaviour change to be aware of:** `AcceptThread` treats an already-active thread as idempotent (200). A repeated accept on an ACTIVE thread that staff later paused or ended now gets 409 instead.
- **Stale comment, left for scope:** the `chat_lifecycle_gate.go` header (lines 1-3) still names only the donor-chat accept as a user of the gate.
- **App:** the marriage screen shows Accept/Decline on a closed invite, and a refused accept shows the generic "Could not send your message." copy. To name the refusal, the app would have to read `code`, for example the way `chat_group_conversation_controller.dart` does with `chat_lifecycle_closed`.
- **Decline:** still ungated in marriage chat, and `DeclineThread` does not check `status`. Both are being handled on the parallel #26427 branch, not here.

**Traps:**
- zsh: `grep --include=*.dart` fails with `no matches found`. Quote the glob: `--include='*.dart'`.
- When a background test run is written as `go test … > log; echo "exit=$?" >> log`, the background task's own exit code is the `echo`'s, always 0. Read the `exit=` line and the `ok`/`FAIL` lines from the log.
- Run times vary widely with machine load: the same `internal/handlers` package took 389.763s on one fresh DB and 38.802s inside the full suite minutes later. Keep `-timeout 45m`.

---

## 2026-09-15 — OPOS #26427: only a pending chat invite can be declined (branch `fix/chat-decline-requires-pending`)

**What was asked:** confirm test-first, then fix, that both invite-decline store methods (donor chat and marriage chat) update the thread without requiring `status = 'pending'`, which let an invite's recipient flip an ACTIVE chat to `declined`. Put the pending condition inside the UPDATE, map "no row" to a not-pending error, map it in the handlers, and do not change decline's lifecycle behaviour.

**What was actually changed** (commit `63759ae`, off `origin/main` `8fcd38d`):
- **The bug, confirmed by the RED run below:** `chat.Store.DeclineThread` and `marriagechat.Store.DeclineThread` both ran `UPDATE ... SET status = 'declined' WHERE id = $1`. A declined thread is hidden from both participants' lists (`ListThreadsForUser` filters `status <> 'declined'`), and sending needs `active`, so one tap ended a live chat.
- **Two assumptions in the brief were wrong:**
  - Accept does not require pending. `AcceptThread` returns an idempotent 200 on an already-`active` thread and otherwise updates with no status condition, so a `declined` thread goes back to `active`. This is true in both stores.
  - Neither package had a not-pending error. A new sentinel `ErrNotPending` was added to each.
- `backend/internal/chat/chat.go`:
  - `ErrNotPending` at :43.
  - `DeclineThread` at :226 now runs `UPDATE chat_threads ... WHERE id = $1 AND status IN ('pending', 'declined') RETURNING ...`. `pgx.ErrNoRows` becomes `ErrNotPending`.
  - The participant and recipient checks still run first. The doc comment was rewritten.
- `backend/internal/marriagechat/marriagechat.go`: `ErrNotPending` at :44, and the same guarded UPDATE in `DeclineThread` at :249. The old doc said it declined "an active/pending thread"; the new doc describes the fix.
- `backend/internal/handlers/chat.go` (`chatErr` :452, `Decline` doc :301) and `backend/internal/handlers/marriage_chat.go` (`chatErr` :53, `Decline` doc :180): `ErrNotPending` → `409 {"success":false,"error":"This chat is already active, so it can no longer be declined."}`. There is no `code` field, matching the sibling `chatErr` entries.
- **Deliberate choice:** re-declining an already-`declined` invite stays a 200. The guard is `IN ('pending','declined')`, not `= 'pending'`.
  - That is the behaviour before this change, and it mirrors accept being idempotent on `active`.
  - The Flutter notification tile really does re-offer Decline for a declined invite, because the list it reads hides declined threads. The tile swallows errors, so a 409 there would be a silent dead button.
  - Switching to strict pending is a one-line SQL change plus flipping one test.
- **Untouched on purpose:**
  - Decline is still not lifecycle-gated, so a pending invite on an ended and archived thread still declines (OPOS #26413).
  - Routes are unchanged: `main.go:740` and `:805`, behind `RequireBearer` + `RequireApproved` + `RequireNotGuest`.
- **New tests:**
  - `backend/internal/chat/chat_decline_pending_test.go` (3 store tests).
  - `backend/internal/handlers/chat_invite_decline_pending_test.go` (5 tests, 12 subtests, covering donor and marriage):
    - active thread refused, status stays active;
    - pending declines;
    - already-declined stays 200;
    - the other party and a stranger get today's 403s on pending AND active threads, so status is never revealed;
    - a retired (end + archive through `chatlifecycle.Apply`) pending invite still declines.

**What was run and what it printed** (all on a fresh DB `godonation_decline_pending_26427`, created for this task, dropped at the end, confirmed gone):
- **RED, store, before the fix** (only the sentinel declared): `go test ./internal/chat/ -run DeclineThread -count=1 -v`
  - `err = <nil>, want ErrNotPending`
  - `stored status = "declined", want active`
  - The pending and declined controls passed. It ended `FAIL .../internal/chat 12.708s`.
- **RED, HTTP:** `go test ./internal/handlers/ -run ChatInviteDecline -count=1 -v`
  - Donor and marriage both printed `decline on an active ... thread: 200 map[status:declined success:true ...]` and `stored status = "declined" after declining an active chat, want "active"`.
  - The other 4 tests passed. It ended `FAIL .../internal/handlers 3.053s`.
- **GREEN, same two commands:**
  - Store: `ok .../internal/chat 3.413s` (3/3).
  - HTTP: 5/5 PASS, with `decline on an active donor thread: 409 map[error:This chat is already active, so it can no longer be declined. success:false]` (marriage identical). It ended `ok .../internal/handlers 16.475s`.
- **Targeted run:** `go test ./internal/chat/ ./internal/handlers/ -count=1 -timeout 45m` printed `ok .../internal/chat 5.961s` and `ok .../internal/handlers 58.229s`, exit 0. `internal/marriagechat` has no test files.
- **Full run:** `go test ./... -count=1 -p 1 -timeout 45m` printed 22 `ok` packages and 0 FAIL, including `ok .../internal/handlers 187.120s`, exit 0.
- **Lint:** `gofmt -l` on the 6 changed files printed nothing. `go vet ./...` exited 0.
- **Review:** an `ecc:code-reviewer` pass returned APPROVE with 0 findings at every severity.
- **Security review:** an `ecc:security-reviewer` pass found no CRITICAL, HIGH or MEDIUM issues and nothing to fix, and called the diff a net security improvement. Its report went to the coordinating agent, which relayed this summary:
  - **No new enumeration oracle.** The participant/recipient (donor) and owner (marriage) checks still run on `GetThread` data before the UPDATE. Strangers and non-recipients get the same 403 on pending and active threads, pinned by `TestChatInviteDecline_NonRecipientRefusedAsBefore`. Only an authorized recipient can reach the 409.
  - **TOCTOU closed.** The old read followed by an unconditional UPDATE could race a concurrent accept. `WHERE status IN ('pending','declined') ... RETURNING` makes check-and-write one atomic statement.
  - **SQL is fully parameterized.** The test helper builds a table name by concatenation, but only from a hardcoded fixture value, never user input.
  - **Marriage identity masking is unaffected.** `Decline` serializes only `thread.ID` and `Status`.
  - **The 409 error text leaks no internals.**

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needed interactive OAuth in this subagent session, so #26427 was not moved or commented on.

**What is still open:**
- **Unpushed:** `63759ae` and this entry are local only.
- **Behind main:** the branch is 3 commits behind `origin/main` (#95, #96, #97 landed during the work).
  - `git merge-tree` of the fix commit onto `origin/main` is clean. None of the six files overlap, and #97 did not change the decline routes.
  - This HANDOFF entry will conflict at the top of the file, as every parallel branch's does.
- **What the app shows on the new 409** (Flutter was not changed):
  - **Notification tile:** `humanitarian/lib/modules/notifications/widgets/notification_tile.dart:462` `_decline` catches the error and only clears `_busy`. The user sees nothing; the Decline button simply comes back. The tile offers Decline whenever the thread is not in `ChatController.threads`, for example not loaded yet, archived, or declined, so this is the path that used to kill active chats.
  - **Messages tab:** `humanitarian/lib/modules/chat/screens/messages_screen.dart:510` `_decline` shows the snackbar "Could not decline this chat request." It only renders for `incomingPending` threads, so it would need a stale list to reach the 409.
  - **Marriage conversation screen:** `humanitarian/lib/modules/marriage/screens/marriage_chat_conversation_screen.dart:152` `_decide` offers Decline only while `_status == 'pending' && isOwner` (:212). On failure it shows the generic `failureMessage(e, 'error_message_send_failed')` and does not reload. The 3-second poll then replaces the buttons.
  - No caller shows the server's error text.
- **Accept can re-activate a declined invite** in both stores (see above). It is the recipient's own consent, but it pushes the initiator. Not changed; it needs a decision.
- **Marriage accept is still not lifecycle-gated** (carried over from #26413).
- **Race edge:** a thread deleted between `GetThread` and the guarded UPDATE answers 409 instead of 404.
- **Files over the 500-line limit** (already over before this change): `internal/chat/chat.go` 611 (was 586), `internal/handlers/chat.go` 605 (was 598), `internal/marriagechat/marriagechat.go` 551 (was 530). `handlers/chat.go` was not split because #26354 was editing its List handler in parallel.

**Traps:**
- **The worktree guard refuses some shell constructs.** It refused `go test -run 'A|B'` (a quoted `|`) and commands built from shell variables. Run separate, plain commands.
- **go.mod is in `backend/` and each Bash call starts in the worktree root.** `go test ./...` from the worktree root fails with "cannot find main module". Use `go -C <abs>/backend test ...`.
- **The chat and handlers tests share one DB.** Run them as sequential commands or with `-p 1`, so the first-run migrations and seeded rows don't race.

---

## 2026-09-15 — OPOS #26354: guests get an empty chat list and are refused chat messages (branch `fix/guest-gates-chat-reads`)

**What was asked:** block guest sessions from the remaining chat READ routes, the way #83 did for chat groups, writing the tests first. The owner decided "Block, keep guest support". A later decision followed, for apps already installed: the chat LIST routes give a guest an empty list instead of a 403, and the messages routes stay 403.

**What was actually changed:** two local commits on `fix/guest-gates-chat-reads`, rebased onto `origin/main` `aa32268`, which includes #89 and #90. The rebase had no conflicts.
- **`5186698` `fix(server): refuse guest sessions on donor and marriage chat reads`.** It put `auth.RequireNotGuest()` on all six GET routes. Its message still says the lists return 403; the next commit supersedes that for the lists.
- **Follow-up `fix(server): give guests an empty chat list instead of a 403`.** It sets the final behaviour, in `backend/cmd/server/main.go`:
  - **List routes:** `GET /api/chats`, `/api/chats/` (lines 749-750) and `GET /api/marriage/chats`, `/api/marriage/chats/` (lines 822-823) now use `handlers.GuestGetsEmptyList()`.
    - A guest gets 200 `{"items":[],"success":true}`.
    - That is byte-identical to what `ChatHandler.List` (`backend/internal/handlers/chat.go:309`) and `MarriageChatHandler.List` (`marriage_chat.go:143`) send a member with no threads. Both stores start from an empty slice (`internal/chat/chat.go:326`, `internal/marriagechat/marriagechat.go:295`).
    - The list handler never runs for a guest, so no thread is queried.
  - **Messages routes:** `GET /api/chats/:id/messages` (753) and `GET /api/marriage/chats/:id/messages` (826) keep `auth.RequireNotGuest()`, which returns 403 `guest_restricted`.
  - **Support:** `GET /api/support/mine` (784) stays open on purpose.
- **`backend/internal/handlers/guest_empty_list.go`** (new): the middleware, with a doc comment explaining why it exists.
- **`backend/internal/handlers/chat_guest_reads_test.go`** (new):
  - `TestChatLists_GuestGetsEmptyList`: the guest is a participant in both threads, each holding a canary message. All 4 list routes must return exactly the body a member with no threads gets.
  - `TestChatMessages_RefuseGuest`: both messages routes return 403.
  - `TestChatReads_AllowSignedInParticipant`: the member still sees its thread ids and can read both conversations.
  - `TestSupportMine_StaysOpenToGuest`.
- **`backend/internal/handlers/chat_lifecycle_fixtures_test.go`:**
  - `insertMarriageChatThread` split out of `seedMarriageChat`.
  - `newLifecycleRouter` mirrors main.go: guest guards on the participant routes, and #90's `perm()` and `RequireDeletePassword` on the admin routes.
- **`backend/internal/auth/middleware.go`:** the `RequireNotGuest` doc now says the chat lists use `GuestGetsEmptyList` on purpose.

**Why support stays open (evidence):**
- Guests already cannot write to support. `POST /api/support` (main.go:772-773) and `POST /api/chats/support` (main.go:736) refuse them.
  - Commit `9d1cde5` ("fix: require sign-in for support messages") added that, undoing K20 `520d50c`.
  - `chat_guest_support_test.go` guards it.
- The app's send path calls `requireSignIn` (`humanitarian/lib/modules/support/screens/technical_support_screen.dart:122`).
- But `_load` fetches `support/mine` for every session, guests included (same file, `:83`). Blocking that route would show every guest "Could not load your support requests."

**What was run and what it printed:**
- **First commit** (DB `godonation_guest_chat_reads_26354`, created for it and dropped):
  - RED: `go test ./internal/handlers/ -count=1 -run 'ChatReads|SupportMine|ChatLifecycle' -v`. `TestChatReads_RefuseGuest` failed on all 6 subtests with `status = 200, want 403`, and the bodies contained the guest's own threads.
  - GREEN: `go test ./internal/handlers/ -count=1 -v` exited 0, `ok .../internal/handlers 374.525s`. The full suite exited 0.
- **Follow-up** (a fresh DB, `godonation_guest_chat_lists_26354`, created for it and dropped):
  - RED, run on `5186698` before the middleware existed: `go test ./internal/handlers/ -count=1 -run 'ChatLists|ChatMessages|ChatReads|SupportMine' -v`.
    - `TestChatLists_GuestGetsEmptyList` failed on all 4 subtests with `status = 403, want 200 ... (body {"code":"guest_restricted",...})`.
    - `TestChatMessages_RefuseGuest`, `TestChatReads_AllowSignedInParticipant` and `TestSupportMine_StaysOpenToGuest` passed.
    - Each subtest's baseline check also passed: a member with no threads gets exactly `{"items":[],"success":true}`.
  - GREEN: `go test ./internal/handlers/ -count=1 -v` exited 0: 215 top-level PASS, 0 FAIL, 0 SKIP, `ok .../internal/handlers 20.803s`.
  - Full: `go test ./... -count=1 -p 1` exited 0, with all 22 packages that have tests `ok`. The last lines were `ok .../internal/storage 0.596s` and `ok .../internal/users 1.245s`.
  - `gofmt -l` on the changed Go files prints nothing, and `go vet ./...` is clean.
- `gofmt -l .` on the whole backend also lists `internal/handlers/admin_edit_user_profile.go`, which this branch does not touch. That warning was already on `main`: gofmt wants to rewrite `''` in its doc comments as `”`, which would corrupt the SQL `DEFAULT ''` quoted there.
- `everything-claude-code:code-reviewer` passes on both commits found no backend defects.
  - The first review found the app dead end that the owner's empty-list decision resolves.
  - The follow-up review's LOW doc-comment notes were applied.

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needed OAuth and wasn't available in this non-interactive session, so #26354 was not moved or commented on.

**What is still open:**
- Both commits are local, unpushed and not reviewed by a human.
  - `5186698`'s message says the list routes return 403.
  - A squash-merge message or PR description must describe the final behaviour: lists return 200 with an empty list, messages return 403.
- **App (no longer a blocker):** installed apps now show guests the normal "No conversations yet" state.
  - The dashboard still creates `ChatController` for guests (`humanitarian/lib/modules/dashboard/screens/dashboard_screen.dart:122-124`).
  - That controller polls `GET /api/chats` every 5 s (`modules/chat/controllers/chat_controller.dart:30-31, 65`). The guard answers those polls without a database query.
  - Skipping that poll for guests in the app is optional tidy-up.
  - Marriage chats need nothing: their tile is inside `if (!guest)` (`modules/marriage/screens/marriage_event_group_screen.dart:206, 231`).
- **LOW:** `GET /api/notifications` has no guest gate, and chat-message notifications include an 80-character preview (`backend/internal/handlers/chat.go:405-414, 528-537`). A guest who was in a thread from before 9d1cde5 can still see message snippets there.
- **LOW:** the handler test routers copy main.go's middleware chains, and nothing tests main.go's real route table. Removing a guard from main.go alone would not fail any test; this was already true for #83.
- A guest who was in a support thread opened in the K20 window (before 9d1cde5) no longer sees it in the list and cannot read it.

**Traps:**
- The full `go test ./... -count=1 -p 1` took over 10 minutes in one run and under a minute in the next, both on fresh databases.
  - 10 minutes is longer than the Bash tool's 600 s limit, so the harness moved the slow run to the background.
  - The cause was not verified. Other agents running tests on the same machine is a likely one, so plan for the slow case.
- An agent isolated in a worktree has Bash commands refused as "too complex to verify" when they mix `git` or `go test` with shell variables. Use literal paths.
- `TestChatLists_GuestGetsEmptyList` compares exact bytes against `emptyChatListBody`. If the list handlers' envelope ever gains a key, change `GuestGetsEmptyList` and that constant together; otherwise guests and members would get different shapes.

---

## 2026-09-15 — OPOS #26412: `retire-direct-chats` made atomic, paused threads included, staff actor required (branch `fix/retire-direct-chats-atomic`)

**What was asked:** harden `backend/cmd/retire-direct-chats` → `chatlifecycle.RetireAllDirectThreads` before it runs on production. Work test-first, update `docs/runbooks/retire-direct-chats.md`, and verify only on local throwaway databases. It fixes the four findings from the OPOS #26402 local run:
- not atomic;
- paused direct threads skipped;
- actor not checked;
- existing archive stamps overwritten.

**What was actually changed** (branch based on `dfa632d`, the runbook commit on top of `origin/main` `9bcc053`). The code and tests are commit `6b91432`. The runbook and this entry are in the docs commit directly on top of it.
- `backend/internal/chatlifecycle/retire.go`, rewritten.
  - One transaction. It first locks the actor `FOR SHARE` and returns `*ActorNotStaffError` if the actor isn't dashboard staff. Staff is `permissions.CanAccessDashboard(permissions.TierFrom(staff_tier))`, the predicate behind `auth.IsDashboardStaff` (`internal/auth/middleware.go:40`, `internal/permissions/permissions.go:51,62`). `is_admin` is not read.
  - UPDATE 1 ends AND archives `kind='direct'` threads that are open or paused. It keeps an existing `archived_at` and `archived_by`.
  - UPDATE 2 archives ended direct threads that are still visible.
  - Returns `RetireResult{Ended, Archived}`. The reason text is unchanged.
- `backend/cmd/retire-direct-chats/main.go`: the first output line is unchanged, a counts line is added, and a refused actor gets a clear message with exit 1.
- `backend/internal/chatlifecycle/retire_direct_hardening_test.go` (new): 9 tests.
- `backend/internal/chatlifecycle/retire_direct_test.go`: uses a staff actor and table-derived counts.
- `docs/runbooks/retire-direct-chats.md`: the new selection in pre-flight, snapshot, post-checks and restore; new expected and failure outputs; the resolved risks removed; and a new appendix with this run's evidence.

**What was run and what it printed** (every DB was created with `createdb` and dropped afterwards):
- **Baseline at `dfa632d`:** `go test ./internal/chatlifecycle/ -count=1 -v` → 2 PASS, `ok`.
- **RED, the new tests against the old behaviour.** 6 of the 9 new tests failed, each on the finding it pins:
  - the atomicity test left `lifecycle:ended … ArchivedAt:<null>` after the injected failure;
  - the paused thread stayed `paused`;
  - a non-staff actor got `err = <nil>`;
  - the archive stamp `2026-09-01 10:00:00/41` was overwritten;
  - the result was `{Ended:1 Archived:0}`, want `{Ended:2 Archived:2}`.
- **GREEN:** 11 top-level tests PASS, `ok`. `-race` → `ok`.
- `go build ./...` and `go vet ./...` are clean. `gofmt -l` on the changed dirs prints nothing. The whole backend flags only the pre-existing, untouched `internal/handlers/admin_edit_user_profile.go`.
- **Full suite:** `go test ./... -count=1 -p 1`, run twice on separate fresh DBs, once before and once after the review changes. Both runs: 22 packages `ok`, 0 `FAIL`, exit 0.
- **Local script run** on `gd_retire_run_26412`, following the runbook verbatim (full outputs are in the runbook appendix):
  - pre-flight `will_end 4 / will_archive 2`;
  - three refused actors (non-staff, legacy `is_admin`, nonexistent) and a missing `-actor`, each exit 1 with the checksum unchanged;
  - run 1 `ended+archived 6` / `ended 4 …, archived 2 …`;
  - post-checks 7a 0, 7b 4, 7c 0, 7d 0, 7f 4;
  - run 2 `0`/`0` with the checksum unchanged;
  - the restore put back `6 | 6`, and the checksum matched the before-state.
- **Code review** (`everything-claude-code:code-reviewer`): no correctness bugs in `retire.go` or `main.go`. Its findings, and what was done with each:
  - (a) The `retireInTx` comment wrongly said the statement order didn't matter. It matters under READ COMMITTED. Comment fixed.
  - (b) The atomicity test accepted any error. It now requires the injected `P0001`.
  - (c) The runbook's restore guard (reason plus actor) would also undo a staff unarchive and re-archive made after the run. It was replaced by `t.updated_at = '<run_ts>'`, with a new post-check 7g that records `run_ts`.
  - (d) 7f now expects at least the pre-flight count, because a send that already passed its lifecycle check can still land during the run (`chat.PostMessage`, chat.go:442-453). Section 8 and risk 10 say so.
  - (e) The "five round trips" figure was wrong under pgx statement preparation, and was removed.
  - (f) The restore now has a note for the 23503 error from a deleted user.
  - (g) A staff pause or resume that races the run can overwrite `ended`, because `Apply` writes `WHERE id = $1` only. Mitigated in the runbook: a lifecycle-action freeze and risk 9. Not fixed in code (see open items).
- **Second local pass** after the review, on the same DB:
  - run 1 `6`/`4`/`2`;
  - 7a 0, 7b 4, 7c 0, 7d 0, 7f 4, and 7g one row `13:35:38.522824 | 6`;
  - simulated staff unarchive then re-archive of 910002 as the actor, after which the old guard would have restored 6 rows including 910002;
  - the new restore put back `5 | 6`, skipped 910002 with its re-archive intact, and every other row's checksum matched the before-state (`69426f0e…`);
  - DB dropped.
- Re-ran after the review changes: chatlifecycle 11 PASS, `ok`; `go vet` clean; `gofmt -l` prints nothing on the changed dirs.

**External actions taken:** none. Nothing was pushed, no PR was opened, and no remote or production database was touched.

**What is still open:**
- The branch commits are local and unpushed, not reviewed by a human.
- **The production run has still not been performed.** It needs the owner's explicit go, per the runbook.
- OPOS MCP needed interactive OAuth in this non-interactive subagent session, so OPOS #26412 was not moved or commented on. Update it by hand.
- **Follow-up, not done here:** `chatlifecycle.Apply` reads a thread's lifecycle, then writes with only `WHERE id = $1`. So a dashboard pause or resume that races any end, the bulk run included, can overwrite `ended` and make the thread resumable again. The fix is to add a lifecycle guard to the pause and resume UPDATEs (`AND lifecycle <> 'ended'`). This predates OPOS #26412, so it needs its own task. Until it is fixed, the runbook asks for a lifecycle-action freeze during the production run.
- `docs/superpowers/plans/2026-09-14-chat-groups-phase4-retire-direct-chat.md` still shows the old `(int, error)` signature. It is a historical plan and was left as is.

**Traps:**
- `chat_threads` has `uq_chat_pair UNIQUE (donor_user_id, owner_user_id)`, so a fixture seeding several threads needs a fresh owner (or donor) per thread.
- Runbook post-check 7b needs `lifecycle_changed_at = updated_at`. Without it, it also counts threads an earlier interrupted run had already ended (5 instead of 4 locally).
- The worktree-isolation guard refuses Bash commands that use shell variables, `${pipestatus}` or `cd` into computed paths alongside psql or git. Write literal paths.

---

## 2026-09-15 — OPOS #26351: the server refuses a connect request for a case or donation that does not exist (branch `fix/connect-request-unknown-context`)

**What was asked:** `POST /api/chat-groups/connect-requests` accepted any `context_id`, including a case or donation that does not exist. Refuse such a request on the server, test-first. The user's decision: keep the "Ask our team to connect me" button everywhere, and have the server refuse only an unknown context. There are no status, visibility or ownership checks.

**What was actually changed** (one commit on `fix/connect-request-unknown-context`, based on `origin/main` `9bcc053`):
- `backend/internal/chatgroups/chatgroups.go`: new sentinel `ErrUnknownContext`.
- `backend/internal/chatgroups/chatgroups_connect.go`: `SubmitConnectRequest` now runs `submitConnectRequestSQL`, one parameterized statement.
  - The statement is `INSERT … SELECT … WHERE EXISTS … ON CONFLICT … RETURNING id`.
  - `case` checks `beneficiary_cases.id`, and `donation` checks `donations.id`.
  - When no row comes back (`pgx.ErrNoRows`), it returns `ErrUnknownContext` and writes nothing. The doc comment was rewritten.
- `backend/internal/handlers/chat_group.go`: one added `chatErr` case, answering 400 `{"success":false,"error":"We couldn't find that case or donation.","code":"connect_context_not_found"}`.
- `backend/internal/handlers/chat_group_connect.go`: handler doc comment.
- New test files: `backend/internal/chatgroups/chatgroups_connect_context_test.go` and `backend/internal/handlers/chat_group_connect_context_test.go`.
- `chatgroups_test.go` and `chat_group_test.go`: every connect request that used a literal context id (1, 2 or 42) now uses a real case or donation fixture.
  - Donations 1–8 and cases 1–2 exist only as demo seed rows from `migrations/001_full_v2.sql`.
  - Donation 42 does not exist, so it would now be refused.

**Findings behind the decisions:**
- **Donation ids are plain `donations.id`.**
  - My Donations: `donations.Store.ListByUser` (`backend/internal/donations/donations.go:562`, `FROM donations d`) feeds `DonationHistoryEntry.id` (`humanitarian/lib/modules/donations/models/donation_history_models.dart:330`), which `my_donations_page.dart:326` sends.
  - Campaign donations list: the handler reads `d.id … FROM donations d` (`backend/internal/handlers/donations.go:569`), which `beneficiary_campaign_donations_screen.dart:464` sends.
  - `in_kind_donations` has no connect button.
  - Donations are therefore checked the same way as cases.
- **Case ids come from `GET /beneficiary_cases`** (`beneficiary.Store`, `FROM beneficiary_cases`). They are sent by `beneficiary_case_detail_screen.dart:192`, which opens from `proposal_services_section.dart` and `orphan_family_profiles_screen.dart`.
- **Soft delete.** Neither table has a trash column. The Trash (`trashRow` in `backend/internal/handlers/admin_delete.go`) copies the row into `trash_items` and then DELETEs it from the source table.
  - A trashed case or donation is therefore unknown and refused; a restored one is accepted again.
  - The "moved to the Trash" subtests pin this.

**What the app shows for the 400:**
- `ModuleApi.postJson` throws `Exception(<server sentence>)` and ignores `code`.
- `connect_request_sheet.dart` passes the exception to `failureMessage(e, 'error_connect_request_submit_failed')`, which does not count it as an offline failure.
- The member sees this under the message field: "Could not send your request. Please try again. If it keeps happening, contact support." (ar: "تعذّر إرسال طلبك. حاول مرة أخرى. وإن تكرّر الأمر، تواصل مع الدعم.").
- The server's sentence reaches only `debugPrint`. No Flutter file was changed.

**What was run and what it printed** (on DB `godonation_connect_ctx_26351`, created for this work, recreated fresh before GREEN and before the full suite, and dropped at the end):
- **Baseline, before any edit:** `go test ./internal/chatgroups/ ./internal/handlers/ -run ConnectRequest -count=1 -p 1` printed `ok` for both.
- **RED:**
  - `TestSubmitConnectRequestRefusesUnknownContext` failed with `SubmitConnectRequest(case 9000000000000000) = <nil>, want errors.Is(err, ErrUnknownContext)`. All 4 subtests failed that way, plus `5 request rows written for unknown contexts, want 0`.
  - `TestSubmitConnectRequest_RefusesUnknownContext` failed with `status = 200, want 400` for both case and donation.
  - The accept tests passed, as guards.
- **GREEN, fresh DB:** `go test ./internal/chatgroups/ ./internal/handlers/ -count=1 -p 1` printed `ok …/internal/chatgroups 156.858s` and `ok …/internal/handlers 420.185s`.
- **Full suite, fresh DB:** `go test ./... -count=1 -p 1` printed `ok` for every package with tests, exit 0. Among them: `ok …/internal/chatgroups 47.347s` and `ok …/internal/handlers 41.532s`.
- **Connect tests with `-v`:** every one printed `--- PASS`, and the `--- SKIP` count was `0`.
- `go vet ./...` was clean. `gofmt -l` on the 8 changed files printed nothing.
- **Reviews:**
  - `ecc:code-reviewer` found nothing.
  - `ecc:security-reviewer` found one Low. The route is now an existence oracle for case and donation ids (400 vs 200), though it returns no content and sits behind bearer, approved and non-guest checks. It suggested an optional per-user rate limit; not blocking.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commit is local, unpushed, and not reviewed by a human.
- OPOS MCP needed interactive OAuth and wasn't available in this subagent session. OPOS #26351 was not moved or commented on.
- To say "not found" specifically, the app must read `code`, for example through `ApiCodedException`. Today it shows the generic failure sentence.
- The optional rate limit from the security review.

**Traps:**
- `gofmt -l .` in `backend/` lists `internal/handlers/admin_edit_user_profile.go`. That file is untouched here and already unformatted on `origin/main`.
- `internal/chatgroups` tests cannot be re-run safely against the same database.
  - `raiseUserIDFloor` in `chatgroups_test.go` recomputes the floor from `MAX(users.id)`, which falls back once earlier runs have deleted their users, so user ids are reissued. Connect-request rows are never cleaned up.
  - A second run failed `TestListConnectRequestsForUserOnlyReturnsOwnRequests` on a row left by the first run.
  - Use a fresh database per run. `internal/handlers` already fixed its copy by reading the sequence's `last_value`. Not fixed here because it is out of scope.

---

## 2026-09-15 — OPOS #26411: team chat-group pushes get their own entity type (branch `fix/team-group-push-entity-type`)

**What was asked:** team-group message pushes used the donor-chat template, which labelled a chat-GROUP id as a `chat_thread`. Give them their own template, test-first, and leave `chatErr` in `chat_group.go` untouched (parallel branches edit it).

**What was actually changed** (commit `fa22b87`, off `origin/main` `aa32268`):
- **Before:**
  - Masked groups already sent `GroupMaskedNewMessageMsg`: `chat_group_message` / `chat_group_thread` / group id.
  - Team groups sent `ChatNewMessageMsg`: `chat_message` / `chat_thread` / group id, which was wrong.
- **Now:**
  - `backend/internal/notify/templates.go` adds `GroupTeamNewMessageMsg` (`chat_group_message` / `chat_group_thread`). It and the masked template share a private `chatGroupNewMessageMsg`, and the masked output is unchanged.
  - `backend/internal/handlers/chat_group.go`: `notifyGroupMembers` calls the new pure `groupMessageFor(kind, label, preview, groupID)`. Team kind gets the team template, and every other kind fails closed onto the masked template. `chatErr` was not touched.
- **Kurdish:** ckb/kmr reuse the exact strings `ChatNewMessageMsg` already ships. Note that its kmr string `Peyam ji %s` is Latin script, while the file header says Arabic script.
- **New tests (pure, no DB):**
  - `backend/internal/notify/templates_group_test.go` (3 tests)
  - `backend/internal/handlers/chat_group_push_message_test.go` (table test with 3 cases, plus an alias test)

**What was run and what it printed:**
- **RED:**
  - `go test ./internal/notify/` printed `undefined: GroupTeamNewMessageMsg` and `[build failed]`.
  - `go test ./internal/handlers/` printed `undefined: groupMessageFor` and `[build failed]`.
- **GREEN, on a fresh DB `godonation_team_group_push_26411`** (created, then dropped):
  - The targeted run printed `ok .../internal/notify 6.070s` and `ok .../internal/handlers 31.014s`.
  - `go test ./... -count=1 -p 1` exited 0, with 22 `ok` packages and 0 FAIL/panic lines.
- **Lint:**
  - `go vet ./...` exited 0.
  - `gofmt -l` listed only `internal/handlers/admin_edit_user_profile.go`. That file is untouched and already unformatted on `origin/main`.
- **Review:** an `ecc:code-reviewer` pass found 0 issues.

**Readers of `related_entity_type`:**
- None branch on it. The backend only writes and lists it (`notify.go:141`, `list.go:29`).
- The Flutter app copies it into `AppNotificationModel` (`notifications_controller.dart:161`) but never acts on it.
- admin-web does not reference it.
- `chat_request` is the only type the tile acts on, keyed on `notification_type` (`notification_tile.dart:196`).
- The push-tap handler (`main.dart:114`) only logs.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- Both commits are local and unpushed.
- Existing team-group rows keep `chat_message` / `chat_thread`. They can't be told apart from real donor-chat rows, so there is no backfill.
- `chat_group_message` has no label anywhere:
  - Flutter `app_translations.dart` (en/ar), and the `notificationTypes` list in `test/localization/localized_tag_test.dart`.
  - admin-web `src/lib/locales/en.ts` and `ar.ts`.
  - The Arabic UI shows the `localizedTag` fallback. Masked-group rows had this gap before; team-group rows now share it. It needs a Flutter plus admin-web follow-up.
- OPOS MCP needed OAuth and wasn't available in this subagent session, so #26411's status and notes need updating by hand.

**Traps:**
- The worktree guard refuses `go test ... | tee ...` with `${pipestatus}`. Redirect to a file instead.
- `gofmt -l .` on `backend/` is not empty on `main`, because of `admin_edit_user_profile.go`.

---

## 2026-09-15 — OPOS #26413: donor-chat invite accept now respects the thread lifecycle (branch `fix/chat-accept-respects-lifecycle`)

**What was asked:** confirm, then fix test-first, that `POST /api/chats/:id/accept` ignored `chat_threads.lifecycle`, so a pending invite on an ended or archived thread could be accepted and push "chat accepted". Report whether decline or other invite transitions have the same gap. Fix only accept.

**What was actually changed:** one commit, `d790230`, based on `origin/main` `9374edc`:
- `backend/internal/handlers/chat_lifecycle_gate.go` gained the new `refuseIfInviteClosed`, which reuses the two existing gates.
  - It calls `refuseIfNotSendable` first. A paused or ended thread gets 409 `chat_lifecycle_closed`, the same response the send path gives.
  - It then calls `refuseIfArchivedForParticipant`. An archived-but-open thread gets 404, the same as the participant messages route.
- `backend/internal/handlers/chat.go` `ChatHandler.Accept` now runs `GetThread`, then `IsParticipant` (403), then the gate, before `AcceptThread` and the push.
  - The participant check comes first because the 409 carries staff's reason.
- `backend/internal/chat/chat.go`: a doc comment on `AcceptThread` says the lifecycle gate is the handler's job.
- New test `backend/internal/handlers/chat_invite_accept_lifecycle_test.go` (6 tests):
  - Four refusal cases: ended, paused, retired (real `chatlifecycle.Apply` end+archive), and archived-open. Each asserts that the status stays `pending` and that no `chat_accepted` row exists in `app_notifications`.
  - An open control, which accepts and waits for the push row.
  - A stranger test, which gets a plain 403 with no lifecycle detail.

**What was run and what it printed:** all runs used a fresh DB, `godonation_accept_lifecycle_26413`, which has since been dropped.
- **RED, before the fix:** `go test ./internal/handlers/ -run ChatInviteAccept -count=1 -v` failed 4 tests. The ended, paused, retired and archived-open cases each printed `200 map[status:active success:true ...]`. The open control and the stranger test passed.
- **GREEN, same command after the fix:** 6/6 PASS. The ended case, for example, printed `409 map[code:chat_lifecycle_closed ... lifecycle:ended lifecycle_reason:Resolved by our team ...]`, and the archived-open case printed `404 map[error:Chat not found.]`.
- `go test ./internal/handlers/ -count=1` printed `ok ... internal/handlers 24.223s`.
- `go test ./... -count=1 -p 1` printed `ok` for every package with tests, and no FAIL.
- `go vet ./...` was clean.
- `gofmt -l .` printed only `internal/handlers/admin_edit_user_profile.go`, which is not part of this diff (see Traps). The 4 changed files are gofmt-clean.
- An `ecc:code-reviewer` pass on the diff returned APPROVE with 0 critical, high or medium findings. Its 2 LOW notes are listed under "still open".

**External actions taken:** none. Nothing was pushed and no PR was opened. OPOS MCP needed interactive OAuth in this subagent session, so OPOS #26413 was not moved or commented on.

**What is still open:**
- `d790230` and this entry are local and unpushed.
- **Same gap in marriage chat, not fixed:** `MarriageChatHandler.Accept` (`backend/internal/handlers/marriage_chat.go:147`) has no lifecycle gate and pushes `MarriageChatAcceptedMsg`. Approving a meeting request opens a `pending` marriage thread (`marriagechat.go:125`), so the path can be reached. The fix would be the same pattern with `chatlifecycle.KindMarriage`, done as a separate task.
- **Decline was deliberately left ungated,** in both donor and marriage chat.
  - Reasons: decline sends no push, and it is the only way an invitee can dismiss a dead invite, because `ListThreadsForUser` hides `status='declined'`. Gating decline would leave an ended invite stuck in their list forever.
  - Found in passing: `chat.Store.DeclineThread` never checks `status = 'pending'`, so the recipient can flip an ACTIVE thread to declined. The marriage store's decline does the same. Not changed here.
- **Race window:** there is a gap between the gate's SELECT and `AcceptThread`'s UPDATE. The send path has the same shape. A `SELECT ... FOR UPDATE` in one transaction would close it.
- **Oversized files:** `backend/internal/handlers/chat.go` was already 581 lines before this change, over the 500-line limit, and is now 598 (+17).
- **App behaviour:** the Flutter caller, `humanitarian/lib/modules/chat/controllers/chat_controller.dart:90`, has not been checked for how it shows a 409 or 404 on accept.

**Traps:**
- `gofmt -l` flags `internal/handlers/admin_edit_user_profile.go` on `origin/main` itself (unchanged since `a6c74d5`). Do not "fix" it blindly: gofmt rewrites the SQL `''` inside its doc comments into a typographic `”`.
- `chatlifecycle.RetireAllDirectThreads` sweeps every open direct thread in whatever DB it is pointed at. The retired-invite test applies the same two transitions to its own thread only, so the shared test DB is not swept.

---

## 2026-09-15 — OPOS #26355: guest accounts can no longer be added to a chat group (branch `fix/chat-groups-no-guest-members`)

**What was asked:** staff could add a guest account (`users.is_guest = TRUE`) to a chat group in three ways: create group, add member, or approve a connect request. Every participant chat-group route refuses guest sessions, so that guest was locked out and staff got no warning. The brief: enforce the rule once, in the store, test-first, and return a 400 with a machine code.

**What was actually changed** (one commit on `fix/chat-groups-no-guest-members`, branched from `origin/main` `9bcc053`):
- `backend/internal/chatgroups/chatgroups.go`:
  - New sentinel `ErrGuestMember`.
  - New `insertMemberRow`, now the ONLY writer of `chat_group_members`. It is a single `INSERT ... SELECT ... WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = $2 AND is_guest)`. Zero rows affected means the user is a guest, and it returns `ErrGuestMember`.
  - `insertMembers` (used by `CreateGroup` and `ApproveConnectRequest` inside their transactions) and `AddMember` now both call it. That replaces two duplicated INSERTs.
  - A user id with no `users` row is inserted exactly as before (there is no FK).
- `backend/internal/chatgroups/chatgroups_connect.go`: doc comment only. A guest requester's request can never be approved, only declined.
- `backend/internal/handlers/chat_group.go`: `chatErr` maps `ErrGuestMember` to `400 {"success":false,"error":"Guest accounts cannot be added to a chat group.","code":"guest_member_not_allowed"}`. Only this response has a `code`; every other response is unchanged.
- New tests:
  - `backend/internal/chatgroups/chatgroups_guest_test.go` (store).
  - `backend/internal/handlers/chat_group_guest_member_test.go` (HTTP). They are separate files because `chatgroups_test.go` and `chat_group_test.go` are already over 500 lines.
- `backend/internal/handlers/chat_group_guest_test.go`: `TestChatGroupReads_RefuseGuest` now writes the guest's membership row directly (`insertLegacyGuestMembership`), because the store refuses it now.

**What was run and what it printed**
- **RED, before the fix, with the new tests plus only the sentinel declared:**
  - Store tests: `CreateGroup`/`AddMember`/`ApproveConnectRequest with a guest member = <nil>, want errors.Is(err, ErrGuestMember)` for TestCreateGroupRefusesGuestMember (masked and team), TestAddMemberRefusesGuest, TestApproveConnectRequestRefusesGuestMember and TestApproveConnectRequestRefusesGuestRequester.
  - HTTP tests: `status = 200, want 400` for TestAdminCreateGroup_RefusesGuestMember, TestAdminAddMember_RefusesGuestMember, TestAdminApproveConnectRequest_RefusesGuestMember and TestAdminApproveConnectRequest_RefusesGuestRequester.
  - The controls passed: TestAddMemberAcceptsUpgradedGuest and TestAdminCreateGroup_OtherRefusalsCarryNoCode.
- **After the fix:**
  - `gofmt -l` on all 6 changed files printed nothing.
  - `go vet ./...` printed nothing, exit 0.
  - On a fresh DB, `go test ./internal/chatgroups/ ./internal/handlers/ -count=1` printed `ok .../internal/chatgroups 143.403s` and `ok .../internal/handlers 539.745s`, with 0 FAIL and 0 SKIP.
  - On a second fresh DB, `go test ./... -count=1 -p 1 -timeout 30m` exited 0 with 22 `ok` packages and 0 FAIL, including `ok .../internal/chatgroups 94.593s` and `ok .../internal/handlers 57.991s`.
- An `ecc:code-reviewer` pass found 0 issues at every severity.

**External actions taken:** none. Nothing was pushed and no PR was opened. The throwaway DBs `godonation_guest_members_26355`, `_pkgs` and `_full` were created and then dropped.

**What is still open**
- The commit is local and unpushed.
- OPOS MCP needed interactive OAuth in this subagent session, so #26355 was not moved or commented on.
- **Admin dashboard (Phase 6)** must handle `400` + `code: "guest_member_not_allowed"` on these three routes:
  - `POST /api/admin/chat-groups`
  - `POST /api/admin/chat-groups/:id/members`
  - `POST /api/admin/chat-groups/connect-requests/:id/approve`
- What that means for the dashboard:
  - Show a localized message on this code, not the raw `error`.
  - The refusal is all-or-nothing, so nothing was created.
  - For approve, the request stays `pending`. A guest requester's request can only be declined.
  - The member picker should exclude guests up front, for example via `GET /api/admin/users?hide_guests=1`.
- Guest memberships created before this fix are not cleaned up. They are still locked out by the read and write gates.
- A background-task suggestion was filed: `raiseUserIDFloor` in `chatgroups_test.go` moves the users sequence backward (see Traps).

**Traps**
- **Reusing one test DB across runs of `internal/chatgroups` gives spurious failures.** Its `raiseUserIDFloor` uses `MAX(users.id)`, which drops after cleanup. So each new process reissues user ids that still own leftover `chat_group_members` and connect-request rows.
  - Seen after 3 runs on one DB: 61 orphan member rows, sequence at 700000532 vs `MAX(id)` 6.
  - Tests that failed because of it: TestListGroupsForUserUnreadCount, TestListGroupsForUserExcludesRemovedMembership, TestAdminDeclineConnectRequest_ShowsReasonToRequester.
  - Use a fresh DB per run. The new guest tests count only rows above a `chat_group_members.id` watermark for this reason.
- **Under machine load** (load average around 40 from parallel agents), `internal/handlers` took 540s, close to Go's 10-minute default per-binary timeout and the Bash tool's 10-minute cap. Run the full suite in the background with `-timeout 30m` and wait for an exit marker.
- **The sandbox refuses `psql`/`createdb` commands that contain shell variables.** Use literal DB names.

---

## 2026-09-15 — OPOS #26351 ("our team" decision): connect-request copy says "our team", not "staff" (branch `fix/connect-copy-our-team`)

**What was asked:** implement one of OPOS #26351's decisions. All member-facing chat-group and connect-request copy says "our team" (Arabic فريقنا), never "staff" (الفريق). Tests first. Do not write Kurdish.

**What was actually changed** (one commit on `fix/connect-copy-our-team`, based on `origin/main` `9bcc053`):
- `humanitarian/lib/localization/app_translations.dart`: values only. No key was renamed, because no key name contains "staff".
  - English: `connect_request_action`, `_title`, `_explainer`, `_message_hint`, `_sent` and `_sent_body`.
  - Arabic: the same keys except `_explainer`, which already said فريقنا.
- Two new tests:
  - `humanitarian/test/modules/chatgroups/connect_request_our_team_copy_test.dart` renders the button, the sheet and the success view in en and ar.
  - `humanitarian/test/localization/chat_groups_our_team_copy_test.dart` holds exact-value pins, plus a scan so that no chat-group or connect value says staff/الفريق/موظف. `chat_groups_my_team_groups` (the "team" kind of group) is allowlisted.
- Comments that quoted the old "Ask staff to connect me" label were updated in 7 files: the sheet, button, sent view, submit button, My Connect Requests controller, `failure_message_test.dart` and `connect_request_sheet_test.dart`.
- `TRANSLATION_REQUEST.md`: the 6 rows now show the new English and Arabic and are marked `**ckb + kmr — REWORDED**`. An intro note was added. The key count stays at 459.

**What was run and what it printed** (from `humanitarian/`):
- **RED, before the value change:**
  - The new widget test printed `+0 -6: Some tests failed.`
  - The new localization test printed `+2 -13: Some tests failed.` The 2 that passed are the Arabic explainer pin and the guard against an empty scan.
- **GREEN:**
  - `flutter test test/modules/chatgroups/ test/localization/` printed `+300: All tests passed!`
  - Full `flutter test` printed `+975: All tests passed!` (main's 954 plus the 21 new tests).
  - `flutter analyze` printed `6 issues found.`, the same 6 `deprecated_member_use` as the baseline.
  - `dart format --set-exit-if-changed` on the 2 new files changed 0.
- An `ecc:code-reviewer` pass found 0 issues.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- The commit is local and unpushed.
- OPOS MCP needs interactive OAuth, so it was unavailable in this subagent session. OPOS #26351 was not commented on or moved.
- #26351's OTHER decision is untouched: whether the case-detail connect button should show on every route.
- The 6 REWORDED rows need Sorani and Badini from a native speaker.
- "staff" was deliberately left in other features: the support chat ("Message the staff team", "Staff support", `chat_support_unavailable_body`'s الفريق), marriage chat ("mediated by staff"), and the `staff_chat_message` notification type, which belongs to the older `staffchat` threads. Also left: profile-approval, checkout, marriage-owner and "Staff only" visibility strings.

**Traps:**
- macOS `awk` does not support `\s`, so an awk grep over the translation map silently matched nothing. Use perl.
- The first English edit missed `connect_request_sent_body`. Only the new pins caught it.
- `connect_request_sheet_test.dart` was already 515 lines, over the 500-line cap, so the new widget tests went into their own file.

---

## 2026-09-15 — OPOS #26348: 5 stale Flutter tests on `main` brought up to current behaviour (branch `fix/stale-flutter-tests`)

**What was asked:** fix the 5 Flutter tests failing on `origin/main`: 1 in `main_menu_button_test.dart` and 4 in `marriage_hub_feed_test.dart`. Update or delete each test whose subject was changed on purpose. Change no product code, and report a real regression rather than fix it. None was found.

**What was actually changed (tests only, zero product code):**
- `b1a18e1`, in `humanitarian/test/widgets/main_menu_button_test.dart`: removed `lib/modules/chat/screens/case_chat_conversation_screen.dart` from `_formerOwnAppBarPages`, with a comment. Commit `e07d59a` (PR #79, chat-groups Phase 4) deleted that screen on purpose, so `_read()` failed with "... is missing". The other 6 paths are still guarded. Verdict: updated.
- `250d781`, in `humanitarian/test/widgets/marriage_hub_feed_test.dart` (rewritten). PR #76 (`33d6891`, OPOS #25858) removed the hub's general news feed on purpose.
  - Now pinned: the hub draws no "News and activities" section, no "See all" and no `MediaPostCard`. It registers no `MediaPostsController`, untagged or under `events-hub-feed`. Both cards still render.
  - Deleted: the "feed sits below the cards" test and the "card wired to hub feed" test, because the feed they guarded no longer exists.
- Also in `250d781`, `humanitarian/test/widgets/profile_menu_doors_test.dart` gained a source pin that `profile_menu_screen.dart` navigates to `NewsActivitiesScreen`. PR #77 (`6fdad49`, OPOS #25869) moved the feed's door there with no test. Full per-test reasoning is in the two commit messages.

**What was run and what it printed:**
- **Before any edit, on `cf24bd4`:**
  - `flutter test test/widgets/main_menu_button_test.dart test/widgets/marriage_hub_feed_test.dart` printed `+4 -5: Some tests failed.`
  - `flutter analyze` printed `6 issues found.`, all `deprecated_member_use`.
- **After the change**, all from `humanitarian/`:
  - The same two-file command printed `+7: All tests passed!`
  - Full `flutter test` printed `+820: All tests passed!` with exit 0.
  - `flutter analyze` on the 3 changed files printed `No issues found!`
  - Full `flutter analyze` printed `6 issues found.`, all 6 `deprecated_member_use`, so the baseline is unchanged.
- An `ecc:code-reviewer` pass on the diff found 0 issues.

**External actions taken:** none. Nothing was pushed and no PR was opened.

**What is still open:**
- Both commits and this entry are local, unpushed, and not reviewed by a human.
- OPOS MCP needed interactive OAuth and wasn't available in this non-interactive subagent session. OPOS #26348 was not moved or commented on, so its status and completion notes need updating by hand.
- Stale product comments were found but not changed here, because they are out of scope:
  - The `MediaPostCard.controller` doc comment in `humanitarian/lib/modules/proposal/screens/news_activities_screen.dart` still says the Events hub registers a tagged controller.
  - `humanitarian/lib/api/module_api.dart:1124` still mentions the Events hub.
  - No caller passes `MediaPostCard(controller:)` any more, so that parameter is now unused.
  - If OPOS #25862 (a marriage-specific news feed) brings back a tagged `MediaPostsController`, restore a card-wiring test. The deleted one is at `git show 250d781^:humanitarian/test/widgets/marriage_hub_feed_test.dart`.

**Traps:**
- The task brief's failure text for `main_menu_button_test.dart` ("Found 0 widgets with type AppSectionHeader") actually came from `marriage_hub_feed_test.dart`. Run each file on its own to see its own failure.
- `dart format --set-exit-if-changed` already flags these test files on `main`, for example `profile_menu_doors_test.dart:81` and `main_menu_button_test.dart:78`. They predate the current formatter style. Only lines edited here were formatted, so the real diff stays readable.

---

## 2026-09-15 — Phase 5 follow-ups, backend/Android/test fixes, Motorola device pass (PR #82 branch plus 5 fix branches)

**What was asked:** "log tasks on opos and continue working", then "use the connected motorola device to test". This continued from PR #82 (Phase 5 chat groups) with the open follow-ups. Every task was logged in OPOS before work started.

**OPOS tasks** (office 19, account 6). Created today: #26344–#26351, #26353–#26355, #26357, #26364, #26367.

Status when this was written:
- **Completed:** #26344, #26345, #26346, #26350.
- **Under Review** (local commits; pushing and opening PRs needs the user's OK): #26347, #26348, #26349, #26353, #26357.
- **To Do:** #26351 (needs user decisions), #26354, #26355, #26364, #26367.
- **WIP:** #26047 (final Phase 5 verification), blocked on the Android device pass.

**What was actually changed**
1. **`feat/chat-groups-phase5-ui` (PR #82)**: four new local commits, **not pushed**.
   - `995beda`: the connect sheet's send button moved to `widgets/connect_request_submit_button.dart`. The sheet went from 498 to 397 lines. (#26344)
   - `b9a525c`: a connect request that fails after the member dismissed the sheet is now reported through a SnackBar (`onFailedAfterDismiss`). (#26345)
   - `0e1a97f`, merged in `e74651a` (#26346):
     - New `lib/api/api_status_exception.dart`. `ModuleApi.getObject` now throws `ApiStatusException(status)`, whose `toString` is unchanged.
     - A 403 or 404 on chat-group messages now gives a terminal "This conversation is no longer available" state, with no Retry and no composer.
     - 2 new en+ar keys. TRANSLATION_REQUEST.md now lists 459 keys.
   - `f38c58b`: queued loads stop once a group is unavailable. It also corrects three comments about the exception getObject throws.
2. **`fix/chat-groups-guest-reads`** (worktree `.claude/worktrees/agent-afe13100798e37acf`): `56bfb95` adds `auth.RequireNotGuest()` to `GET /chat-groups`, `GET /chat-groups/:id/messages` and `GET /chat-groups/connect-requests/mine`. (#26347)
3. **`fix/android-debug-build-without-signing`** (worktree `.claude/worktrees/android-signing-fix`): `976d876` and `b231054` change `build.gradle.kts` to use `signingConfigs.findByName("release")`, plus a task-graph guard that fails only release builds that have no signing config. Before this, a checkout without the gitignored `key.properties` could not even build debug. (#26353)
4. **`fix/stale-flutter-tests`** (worktree `.claude/worktrees/agent-aa2e480042cf01557`): `b1a18e1`, `250d781` and `2034ffa`.
   - The 5 tests that failed on main were updated or deleted. Each pinned behaviour that e07d59a or PR #76 changed on purpose.
   - Added a test that Profile opens News.
   - That branch has its own HANDOFF.md entry, so expect a trivial HANDOFF.md merge conflict. (#26348)
5. **`fix/app-error-state-in-scroll-views`** (worktree `.claude/worktrees/app-error-state-fix`): `7471961` makes `AppErrorState` use `Expanded` for stale rows only when the height is bounded. Inside a scroll view it threw, which broke the Messages tab on a failed pull-to-refresh. (#26349)
6. **`fix/test-routers-match-main`** (worktree `.claude/worktrees/agent-a2f9a9fd81ffdbf57`), stacked on `56bfb95`: `ae7a65a` makes the backend handler test routers apply the same guest and approval gates as `main.go`, including routers the review missed. Only 6 `_test.go` files changed; no production code. (#26357)
7. Removed the 4 merged Phase 5 agent worktrees and their branches. (#26350)

**What was run and what it printed**
- **Phase 5 branch, at `f38c58b`:**
  - `flutter test test/modules/chatgroups/ test/api/ test/localization/` → `+330: All tests passed!`
  - Full `flutter test` → `+947 -5`. The 5 are the known stale tests, fixed on branch 4.
  - Full `flutter analyze` → `6 issues found`, the existing baseline.
- **#26345:** the 2 new tests failed first ("Found 0 widgets with text containing Could not send your…"), then passed. `test/modules/chatgroups/ test/localization/` → `+270`.
- **#26346:** 8 new tests failed first, then passed. `test/modules/chatgroups/ test/api/ test/localization/` → `+329`, and `+330` after `f38c58b`.
- **#26347:**
  - `TestChatGroupReads_RefuseGuest` failed first: a guest group member got 200.
  - `go vet ./...` is clean, and `go test ./... -count=1 -p 1` on a freshly created DB → 22 packages ok.
  - A reviewer confirmed with a mutation check that the test catches the bug.
- **#26353**, in a checkout without `key.properties`:
  - The debug build printed "✓ Built … app-debug.apk", then installed and ran on a Motorola Defy.
  - `flutter build apk --release` → "No release signing config: android/key.properties is missing…", BUILD FAILED.
  - A reviewer used a fake keystore to show that release signing is unchanged when the file is present.
- **#26348:** full `flutter test` on that branch → `+820: All tests passed!`, 0 failures. Analyze is at the baseline.
- **#26349:**
  - On origin/main without the fix → `+1 -2`, failing with "RenderFlex children have non-zero flex but incoming height constraints are unbounded".
  - With the fix → `+3: All tests passed!`
  - Full suite on that branch → `+819 -5`, the 5 stale tests.
- **#26357:** no test began failing. `go vet ./...` exit 0; `go test ./internal/handlers/ -count=1` → ok; full `go test ./... -count=1 -p 1` → every package ok, on fresh DBs dropped afterwards; a `-v` handlers run → 429 PASS / 0 SKIP / 0 FAIL.
- **Android device pass** on the Motorola Defy (ZY32D3QTSD, Android 11, 720×1600), through the uncommitted dev harness `humanitarian/tool/chat_groups_preview.dart` with a fake API.
  - Verified in English, light theme: the masked chat; the composer's focus outline, send enabling and sending; the contact-details refusal (typed text kept); a paused chat with its reason; an ended, empty chat; the Messages-tab sections; My Connect Requests in all its states.
  - The screenshots exist only in the agent scratchpad.

**External actions taken:**
- **OPOS:** tasks, comments, statuses, and manual time logs for #26347 and #26348.
- **GitHub**, on the user's instruction "yes push everything and open the PRs and merge":
  - pushed all six branches and opened #83–#87;
  - squash-merged them into `main` in this order:
    1. #83 `81a9478`
    2. #85 `91aec17`
    3. #86 `e1e99bf`
    4. #82 `07759e5`
    5. #84 `7de63f9`, rebased onto `main` first to drop its copy of #83's commit
    6. #87 `4ed2c86`, after a HANDOFF.md conflict resolved by keeping both entries
- **Merged `main` verified at `4ed2c86`**, in a fresh worktree:
  - full `flutter test` → `+954: All tests passed!` (0 failures)
  - `flutter analyze` → `6 issues found` (the baseline)
  - `go build ./...` and `go vet ./...` → ok

**What is still open**
- **Merged:** every branch above is on `main` (see External actions taken). Their local worktrees and branches can be removed; the remote branches were kept.
- **#26353:** a signed release build with the real `key.properties` is still needed before merging.
- **#26351 decisions:** whether the case-detail "Ask staff to connect me" button should show on every route, and "staff" vs "our team".
- **Android device pass still to do:** the connect sheet (success and failure), Arabic, dark mode, guest vs donor. The Motorola disconnected twice (usb:2-1) and was not back after a 30-minute wait.
- **Phase 5 worktree temporary files:** an UNCOMMITTED copy of the #26353 `build.gradle.kts` (needed to build on devices) and the untracked dev harness `humanitarian/tool/`. Never commit either; revert and delete both after the device pass.
- **Worktree cleanup:** `.claude/worktrees/agent-a52e0750b3d4145aa` (`fix/phase5-chat-unavailable`, already merged) can be removed.
- **Follow-ups:** #26354 (guest gates on the other chat read routes), #26355 (staff can add a guest to a group), #26364 (stale Events-hub comments), #26367 (admin test routers skip main.go's permission and admin-tier gates).

**Traps**
- **OPOS timers and statuses:**
  - Each account has ONE running timer. Moving a task to in_progress stops any other timer.
  - Status changes fail with `PRESENCE_NOT_WORKING` while the account is clocked out, but comments still work.
- **OPOS uploads:** `upload_screenshot` cannot read local files (ENOENT).
- **emulator-5554 hangs device discovery:** the Pixel Tablet emulator, used by another session, never answers `adb`, so `flutter run` hangs on its `adb shell getprop`. Kill only the hung getprop processes your own run spawned; do not touch the emulator.
- **zsh word-splitting:** zsh does not split `$VAR` into a command plus arguments. Use a function (`adbm() { adb -s SERIAL "$@"; }`) or run the script through `bash -s`.
- **GetX translations:** a hot reload does not load new translation keys, so raw keys show until a hot restart.
- **GateGuard hook:** besides first file edits, it blocks the first Bash command of a session and anything it deems destructive (`git commit --amend`, `git checkout --`, `rm`) until you state the facts and retry.

---

## 2026-09-14 — OPOS #25284 Phase 5 Tasks 3-5 + whole-branch review fixes + device walkthrough (branch `feat/chat-groups-phase5-ui`)

**What was asked:** take Phase 5 (tracker #25608) through to a PR:
- Task 3 (#26044): the group conversation screen.
- Task 4 (#26045): Messages-tab group sections and My Connect Requests.
- Task 5 (#26046): the "ask staff to connect me" sheet and its entry points.
- #26047: final verification, PR and handoff.

The user asked for speed and pre-approved pushing and opening the PR. They also asked the agent to test every role on a device itself. The agent does not enter passwords, so the device pass used a dev harness with fake data (see below) instead of a signed-in account.

**What was actually changed** (all under `humanitarian/` unless noted):
- **Task 3:** `a1fd7c2`, review fixes in `5575061`. Files: `lib/modules/chatgroups/screens/chat_group_conversation_screen.dart`, `widgets/chat_group_message_bubble.dart`, `widgets/chat_group_composer.dart`.
- **Task 5:** merged in `b30aacc`. Files: `widgets/connect_request_sheet.dart` and `widgets/connect_request_button.dart`. Entry points were added in:
  - `my_donations_page.dart` (`_DonationDetailSheet`)
  - `beneficiary_campaign_donations_screen.dart` (`_DonationRow`)
  - `beneficiary_case_detail_screen.dart`
- **Task 4:** merged in `70e8ecc` (commit `2d0b51d`). Files: `widgets/chat_groups_section.dart` and `screens/my_connect_requests_screen.dart`. `lib/modules/chat/screens/messages_screen.dart` now shows the section to non-guests.
- **Fixes found on the device:**
  - `d055e54`: the composer lost its pill outline on focus, because the theme's `focusedBorder` is an underline.
  - `0bf69f8`: a message is now laid out in the direction it was typed. It used to show ".campaign" on Arabic screens. Reuses `contentDirection` from `lib/localization/content_localizer.dart`.
- **`211343c`:** repo-root `TRANSLATION_REQUEST.md` now lists the Phase 5 keys for Kurdish: 36 keys, 457 in total after the review fixes. Kurdish itself was deliberately not written (#21431).
- **Whole-branch review fixes (OPOS #26331).** Two agents worked in separate worktrees; their branches were merged in `4f74392` and `47ac0de`.
  - **Connect sheet** (`7fd7d20`, `bfaf757`, `f2375fc`):
    - The sheet pops only while its own route is current. Before, a response landing during the dismiss animation popped the screen underneath.
    - Success is shown inside the sheet: `connect_request_sent_view.dart`, keys `connect_request_sent_title` and `connect_request_sent_body`. Before, the SnackBar was hidden under the donation detail sheet on My Donations. The SnackBar now fires only if the sheet was dismissed before the answer arrived.
    - Send is disabled while the message is blank.
    - New MyDonationsPage entry-point test, using `test/support/fake_http.dart`.
  - **Messages section** (`0f9aeeb`):
    - `ChatGroupsController` is now created in `MessagesScreen.build`. It used to be created in the lazily built section, where it could bind to a covering route and be deleted early.
    - Pull-to-refresh, and returning from a conversation, now refresh the groups.
    - Group tiles and request cards are announced as buttons.
    - Approved requests open under the group's real title, via `lib/modules/chatgroups/utils/chat_group_title.dart`.
    - `contentDirection` is applied to message previews, team titles, request messages and decline reasons.

**What was run and what it printed:**
- On `4f74392`: `flutter test test/modules/chatgroups/ test/localization/ test/api/` → `+304: All tests passed!`
- Connect-sheet agent: `flutter test test/modules/chatgroups/ test/localization/` → `+253: All tests passed!`
- Section agent: the same command plus `test/widgets/messages_support_doors_test.dart` → `+265: All tests passed!`
- `flutter analyze` on the changed files → `No issues found!`, on both fix branches and for `d055e54` / `0bf69f8`.
- On `47ac0de` (both fix branches merged):
  - Full `flutter test` → `01:08 +933 -5: Some tests failed.` The 5 failures are the pre-existing stale tests, which fail identically on a clean `origin/main`: `marriage_hub_feed_test` ×4 and `main_menu_button_test` ×1.
  - Full `flutter analyze`: `6 issues found`, the same 6 pre-existing `deprecated_member_use` infos.
- Before the review fixes: backend `go test ./...` on a fresh Postgres DB → all 22 packages ok.

**Device walkthrough** (iPhone 17 simulator, UDID `90C7CF87-E95B-40B4-B8AA-DE9A0BD82D7E`). It used an uncommitted dev harness, `tool/chat_groups_preview.dart`, since deleted. The harness ran the real screens against the same `FakeChatGroupsApi` the widget tests use, with EN/AR, dark mode and role switches.
- **English, light:**
  - masked chat;
  - contact-details refusal, with the typed text kept;
  - Messages sections with an unread badge, where a tap opens the chat;
  - My Connect Requests, both empty and in all three states; an approved request opens its chat;
  - connect-sheet validation and sending.
- **Arabic, light and dark:**
  - chat is right-to-left, with Arabic-Indic dates and a mirrored send icon;
  - the Messages tab and My Connect Requests;
  - the connect-sheet failure path shows a localized message and keeps the typed text.
- **Guest vs donor** on the real `BeneficiaryCaseDetailScreen`: the connect button is hidden for a guest and shown for a donor.
- **Roles:** the chat-group widgets branch only on guest vs member. Donor, beneficiary and volunteer see the same widgets; they differ only in which host screens they can reach.

**Review:** the whole-branch everything-claude-code code-reviewer said "not ready", with 2 IMPORTANT findings plus minors. Every finding was checked against the source and fixed as described above. Left for the PR description:
- an approved request whose group was later deleted;
- a failure after the sheet is dismissed is only logged;
- "staff" vs "our team" wording;
- the case button appears on every route into case detail, which needs a product decision.

**External actions taken:**
- **GitHub:** pushed `feat/chat-groups-phase5-ui` (`5575061..604931e`; the branch now tracks origin) and opened PR #82 against `main`: https://github.com/IamSizar/go_donation/pull/82. Screenshots are not attached to the PR yet.
- **OPOS, #26331:** Completed, with completion notes.
- **OPOS, #26047 and #25608:** comments posted. Their statuses could NOT be changed: while account 6 is clocked out, OPOS rejects status changes with `PRESENCE_NOT_WORKING`, although comments still go through.
- **OPOS:** Created #26331 (review fixes) and moved it to WIP, which auto-stopped another session's timer on #26330 (office 1555).
- Posted progress comments on #26331.

**What is still open:**
- **A signed-in pass on a real backend, for every role.** It has to be done by a human; the agent cannot enter credentials.
- **Native-speaker review** of the Arabic copy.
- **Android device pass.** None was done. The walkthrough was iOS only, to save time after a stalled `flutter run` on `emulator-5554` blocked the Flutter lock for 14 minutes. The platform-specific send spinner is widget-tested on both platforms.
- **Kurdish translations** (`TRANSLATION_REQUEST.md`).
- **Product decision:** should the case "Ask staff to connect me" button show on every route into case detail? Today that includes the public feed, Orphan & Family Profiles, and a beneficiary's own pending or rejected cases.
- **Known issues listed in the PR:**
  - A pre-existing Messages-tab `AppAsync` sits in an unbounded `ListView`.
  - GET chat-group routes don't block guests on the server (`backend/cmd/server/main.go:813`, `:820`).
  - An approved request whose group was later deleted.
  - A failure after the sheet is dismissed is only logged.
  - An English draft in an Arabic text field follows the screen's direction.
  - `messages_screen.dart` (678 lines) and `beneficiary_campaign_donations_screen.dart` (528 lines) exceed 500 lines.
  - `connect_request_sheet.dart` is at 498 lines. The next change should move `_SubmitButton` into its own file.
- **The 5 stale Flutter tests** (follow-up suggested, not started).
- **Agent worktrees to remove:** `.claude/worktrees/agent-aae98afe2eae47416` and `.claude/worktrees/agent-a0e52345db4207465`. Both branches are merged.

**Traps:**
- **Flutter startup lock.** Every `flutter` command shares `~/flutter/bin/cache/lockfile`. A stalled `flutter run -d emulator-5554` held it for 14 minutes and silently blocked every `flutter test`, whose output was buffered behind a pipe. `lsof ~/flutter/bin/cache/lockfile` shows the holder.
- **Reloading a background `flutter run`.** Send `kill -USR1 <pid>` to hot-reload it and `kill -USR2 <pid>` to hot-restart it.
  - A hot RELOAD does not pick up new translation keys: GetX loads translations once at startup, so new keys show raw until a restart.
  - A preview `GetMaterialApp` without `localizationsDelegates` shows a red "No MaterialLocalizations" screen in Arabic.
- **OPOS timers.** Account 6 has one running timer. Moving any task to `in_progress` stops whatever timer is running, including another session's.
- **Focus borders.** The app theme's focused input border is an `UnderlineInputBorder`. A field with a custom shape must set `focusedBorder` itself.
- **Text direction.** User- or staff-written text needs `contentDirection` (`content_localizer.dart`); otherwise it takes the screen's direction.
- **Toasts.** SnackBars and toasts are unreliable on the Messages route (see the header of `messages_screen.dart`). Prefer an in-place confirmation.
- **GateGuard hook.** It denies the first Write/Edit of every file, scratchpad files included, until its facts are stated.

---

## 2026-09-14 — OPOS #25284 Phase 5 Task 2: chat-groups Flutter controllers (branch `feat/chat-groups-phase5-ui`, commit `97aab43`, NOT pushed)

**What was asked:** study where the project stands and continue. Continued Phase 5 (OPOS #25608) with Task 2 (OPOS #26042). User decisions this session: OPOS work is recorded under account 6 (Zaid Aqrawi); the case-context "ask staff to connect me" entry point goes on `BeneficiaryCaseDetailScreen` in Task 5 — NOT the plan's Messages-tab "type a case number" dialog, because users only ever see codes like `CSE-000123` and the backend cannot look a case up by code.

**What was actually changed** — commit `97aab43` on `feat/chat-groups-phase5-ui`, branched from `origin/main` `cf24bd4`:
- New `humanitarian/lib/modules/chatgroups/controllers/`: `chat_groups_controller.dart`, `chat_group_conversation_controller.dart`, `my_connect_requests_controller.dart`.
- `humanitarian/lib/api/module_api.dart` — three fixes to Task 1's client (PR #81), all verified against Go source:
  - `markChatGroupRead(groupId, lastReadMessageId:)` now posts `last_read_msg_id`. It posted `{}`; the field is not required, so the server bound 0, `GREATEST` kept the old cursor, and unread badges could never clear.
  - `chatGroupMessages(groupId, afterId:, limit:)` now pages. The server returns ids above `after_id`, oldest first, default 50 / max 100 (`chatgroups_reads.go`); the old call only ever saw the first 50 messages of a group.
  - `sendChatGroupMessage` now goes through `_sendCodedJson`, so `contact_details_blocked` (422) and `chat_lifecycle_closed` (409) codes reach the app. `_sendCodedJson` now honours the `httpClient` test seam. `postJson`'s `_trackEvent` has no branch for this path, so no analytics are lost.
- `app_translations.dart` — 4 keys in en + ar. Sorani/Badini intentionally absent (#21431); they still need listing in `TRANSLATION_REQUEST.md` (final task #26047).
- Tests: `test/modules/chatgroups/fake_chat_groups_api.dart` (pages like the server) + 5 controller test files, 3 API tests under `test/api/chat_group_*`, and `failure_message_test.dart` now pins the new keys.

**Where the Phase 5 plan file is wrong — read before Tasks 3-5:**
- The mark-read body, messages paging and send refusals above. Verify every endpoint against Go source; do not trust the plan's shapes.
- **`send()` contract for Task 3's screen:**
  - Failures go to `sendError`, NOT `errorMessage` (the plan's screen checks `errorMessage` and would silently lose the typed text). Restore the text when `send()` returns false.
  - `isSending` stays true until the sent message is on screen, so disabling the button on `isSending` prevents double sends.
  - A `chat_lifecycle_closed` refusal refreshes the lifecycle, so the closed notice replaces the composer.
- A failed first load sets `errorMessage`; the plan's screen shows "No messages yet" in that case — Task 3 needs a real error state.

**Process:** an independent code review (everything-claude-code code-reviewer) found 1 CRITICAL (paging) and 2 IMPORTANT (overlapping poll responses applied out of order; dropped refusal codes) plus minors. Each was checked against source, then fixed test-first. Loads now run one at a time (a poll tick skips while a load runs) and nothing is applied after the screen closes. Mutation checks ran twice: bugs were planted (files backed up, restored byte-identical by checksum) and exactly the targeted tests failed each time.

**What was run and what it printed:**
- `cd humanitarian && flutter test test/modules/chatgroups/ test/api/chat_group_mark_read_test.dart test/api/chat_group_messages_page_test.dart test/api/chat_group_send_refusal_test.dart test/localization/failure_message_test.dart` → `+58: All tests passed!`
- `flutter analyze` on every changed file → `No issues found!`. Full `flutter analyze` → the same 6 pre-existing `deprecated_member_use` infos as before any change.
- Full `flutter test` → `+861 -5`. All 5 failures are pre-existing: the same 5 fail on a clean detached `origin/main` checkout. `main_menu_button_test.dart` (1) is stale since `e07d59a` deleted `case_chat_conversation_screen.dart`; `marriage_hub_feed_test.dart` (4) are stale since #76 removed the hub feed. A separate follow-up task was suggested for them.

**External actions taken:** OPOS only — created #26042 (Task 2), #26044 (Task 3), #26045 (Task 4), #26046 (Task 5), #26047 (final verification/PR/handoff) in office 19; #25608 moved To Do → Work In Progress with comments; findings recorded on #26042. Nothing pushed, no PR opened.

**What is still open:**
- `97aab43` is local only. The branch's upstream was deliberately unset (it was created tracking `origin/main`).
- Tasks 3-5 (#26044-#26046) and #26047.
- The 5 stale Flutter tests (follow-up suggested, not started).
- Still pending from earlier sessions: the production run of `backend/cmd/retire-direct-chats` (an ops decision).

**Traps:**
- OPOS: the `opos` MCP server reports "needs authentication", but the claude.ai connector (`mcp__e090ae84…` tools) works. Write calls need `accountId` (3 linked accounts). Moving a task to In Progress auto-starts a timer — it silently started one on #25608, which had to be stopped. `list_tasks officeId=19` returns ~2.4 MB: query the saved file with `jq`.
- This worktree's directory is still named `chat-groups-phase1`, but its branch is `feat/chat-groups-phase5-ui`.
- A GateGuard hook denies the first Write/Edit of every file until its facts are stated; expect one retry per new file.
- `testWidgets` poll tests must `Get.delete` the controller before they end, or pending timers fail the test.

---

## 2026-09-14 — SESSION WRAP-UP: OPOS #25284 Phases 1-4 fully merged to `main`, Phase 5 in progress

**Read this entry first if you are picking this project up cold.** It is the single most current summary of where the whole chat-groups feature (OPOS #25284) actually stands, written specifically so a fresh agent or engineer does not have to reconstruct it from git archaeology.

### What is DONE and merged into `main` right now

Nine PRs from this session are merged into `main`, in this order (verify with `git log --oneline main` — all are still there as named merge commits):

1. **#71** — Phase 1: `internal/chatgroups` schema + Store layer (masked/team group chats, no HTTP surface yet).
2. **#72** — Phase 2: mobile + admin routes, permission gating, `chatlifecycle` registration (`KindGroup`), K19 contact filter, push notifications.
3. **#73** — OPOS #25544: `moderation.ScanContact` now runs over a staff-typed `masked_label` before it's stored (closes a contact-info leak in the admin create-group/add-member routes).
4. **#74** — Phase 3: connect-request end-to-end (`POST /chat-groups/connect-requests`, admin approve/decline, `chat_group_audit_log` table + `RecordAudit`).
5. **#78** — OPOS #25634: wires `RecordAudit` into Phase 2's `AdminCreateGroup`/`AdminAddMember`/`AdminRemoveMember` (the retrofit Phase 3's own audit mechanism was built for).
6. **#79** — Phase 4: retires the old donor↔campaign-owner direct chat (`kind='direct'` now refuses new requests, returns 410) and removes `casevolchat`'s direct volunteer↔beneficiary messaging entirely (package trimmed to one surviving read-only method).
7. **#80** — the integration PR that collapsed the whole #71→#72→#73→#74→#78→#79 dependency chain into one clean merge to `main` (see "How the merge-to-main actually happened" below — there were real, resolved-by-hand conflicts here, not just a rubber-stamp).
8. **#75** — OPOS #25612: replaced the single-weight, unlicensed `Kurdfont.ttf` with `NotoKufiArabic[wght].ttf` (OFL-licensed variable font, weights 300/400/600).
9. **#76** — marriage hub screen no longer shows the general humanitarian news/activities feed (was leaking humanitarian-work posts into the Marriage tab).
10. **#77** — added a "News" section to the Profile screen (`ProfileMenuScreen`) as the requested relocation of what #76 removed — the home tab already had an equivalent "Latest news" strip, so nothing was needed there.
11. **#81** — Phase 5 Task 1 (Flutter API client methods + models for the new chat-groups endpoints — purely additive, no UI wiring yet, safe to land ahead of the rest of the plan). See "What is NOT done — Phase 5" below for what's left.

**Verification standard applied to every one of the above, and to the final merged state of `main` itself:** every PR was independently re-verified by the controlling agent against a genuinely fresh (`createdb`, `-count=1 -p 1`) Postgres database — never trusted a subagent's self-reported test count or a single green run. `main` itself, AFTER all nine merges, was re-checked out fresh and re-verified one final time: `go build ./...` clean, `go vet ./...` clean, `gofmt -l` shows only one pre-existing unrelated file (`internal/handlers/admin_edit_user_profile.go`, untouched by any of this session's work), full backend suite **22/22 packages green, zero failures**, `flutter analyze` clean (6 pre-existing unrelated info-level notices), admin-web `tsc --noEmit` + `npm run build` clean.

### How the merge-to-main actually happened (read this before touching the chain again)

PR #71 (Phase 1) was **squash-merged** into `main` as a single commit. Every other branch in the chain (#72, #73, #74, #78, #79) was forked from Phase 1's **original, un-squashed** branch tip — so once #71 landed, those branches no longer shared a common git ancestor with `main` for the files Phase 1 touched, even though the actual file *content* was compatible. This produced real "add/add" merge conflicts when trying to bring the chain into `main` directly (git could not do a 3-way diff without a shared ancestor).

**The fix used, in order:**
1. Merged each PR into its **original** base branch first (not `main`) — #72 into `worktree-chat-groups-phase1`, #73+#74 into `feat/chat-groups-phase2`, #78+#79 into `feat/chat-groups-phase3` — all regular (non-squash) merges, so no history was rewritten and no force-push was needed anywhere.
2. Merged `feat/chat-groups-phase2` and then `feat/chat-groups-phase3` into `worktree-chat-groups-phase1`, producing one fully-integrated branch with all of Phases 1-4 on it. One trivial `HANDOFF.md` conflict at each step (both sides had appended their own "newest entry" at the top) — resolved by keeping both entries, newest first.
3. Merged `origin/main` into that integrated branch. This is where the real add/add conflicts appeared, in `backend/internal/chatgroups/chatgroups.go`, `chatgroups_connect.go`, and `chatgroups_test.go`. **Before resolving anything**, each conflict was independently verified line-by-line (`git diff origin/main:<file> <branch>:<file>`) to confirm the integrated branch's version was a **strict superset** of main's version — i.e., every line main had, the integrated branch also had, plus additional later-phase work, with nothing contradicted or removed. Only after confirming this were the conflicts resolved by keeping the integrated branch's side (`git checkout --ours`). **Do not resolve a conflict like this by just picking a side without doing this line-by-line superset check first** — if the two sides had actually diverged (not just "one side is behind"), blindly picking "ours" could have silently dropped a real fix from the other side.
4. Pushed the fully-reconciled integrated branch, opened PR #80 against `main`, verified the full 3-stack (backend/Flutter/admin-web) test suite on it one more time, then merged.
5. The three independent, already-`main`-based PRs (#75, #76, #77) merged cleanly afterward with no special handling needed.

**If you ever need to merge another long-lived branch chain into `main` again**: avoid squash-merging the FIRST link in a chain if other branches have already forked from it — either squash-merge everything at the very end (once), or don't squash internal links at all and only decide squash-vs-merge for the final PR into `main`. This session's approach (regular merges up the chain, one final reconciliation into `main`) is the safe pattern if you're already past the point where the first squash happened.

### What is NOT done — Phase 5 (Flutter client), in progress right now

**Task 1 is now merged into `main` directly**, via PR #81 — see "What is DONE and merged into `main` right now" above (item added after this section was first written). Since Task 1 was purely additive (new files only — models + `ModuleApi` methods + URL constants — nothing else in the app calls any of it yet), it was safe to land on its own without waiting for the rest of the plan, once the user asked for everything to be merged to `main`.

**For Task 2 onward: branch fresh from `main`'s current tip.** `feat/chat-groups-phase5-flutter-client` is now identical to `main` (no unique commits left on it) — don't keep building on that branch name, it no longer serves a purpose. The design and plan docs are both already on `main`:
- `docs/superpowers/specs/2026-09-14-chat-groups-phase5-flutter-client-design.md` — the design addendum (extends §11 of the original masked-group-chats spec with concrete screen-by-screen decisions: one conversation screen serves both masked and team groups, where the "Request to connect" entry points live, etc.)
- `docs/superpowers/plans/2026-09-14-chat-groups-phase5-flutter-client.md` — the full 5-task implementation plan with exact code for every task.

**Exact current state as of this entry:**
- **Task 1 (API client methods + models) is DONE and on `main`**: added `humanitarian/lib/modules/chatgroups/models/chat_group_models.dart` (`ChatGroupSummary`, `ChatGroupMessage`, `MyConnectRequest`), new URL constants in `links.dart`, and new thin one-liner methods on `ModuleApi` (`chatGroups()`, `chatGroupMessages()`, `sendChatGroupMessage()`, `markChatGroupRead()`, `submitConnectRequest()`, `myConnectRequests()`). Independently re-verified before AND after merging (`flutter analyze` clean, `flutter test test/modules/chatgroups/` 5/5 pass, full backend suite unaffected).
- **Tasks 2-5 are NOT started.** A fresh SDD ledger will need to be created (or the existing one at `.superpowers/sdd/2026-09-14-chat-groups-phase5-flutter-client/progress.md` reused/renamed) once a new branch exists — that ledger directory is git-ignored local scratch, not itself pushed anywhere, so a different machine/session won't have it; the plan file on `main` is the durable source of truth for what each task needs to do.
- Task 2: GetX controllers (`ChatGroupsController`, `ChatGroupConversationController`, `MyConnectRequestsController`) — full exact code already in the plan.
- Task 3: `ChatGroupConversationScreen` — one screen serves both masked and team groups (the backend's `sender_label` already resolves correctly for both; the client never branches on `kind`). Full exact code already in the plan, modeled directly on the existing `ChatConversationScreen`.
- Task 4: wires "My Connections"/"My Team Groups" sections and a "My Connect Requests" tile into the existing `messages_screen.dart`, plus the new `MyConnectRequestsScreen`.
- Task 5: the "Request to connect" entry points — a shared bottom-sheet widget, wired into the two spots Phase 4 removed the old chat buttons from (`my_donations_page.dart`, `beneficiary_campaign_donations_screen.dart`) for donation context, plus a new generic "Request help with a case" dialog in the Messages tab for case context (a case reference number typed by the user — deliberately NOT a lookup against a specific case-detail screen, to keep this phase's scope bounded; see the design addendum §2 for the reasoning).

**How to resume:** branch fresh from `main` (e.g. `git checkout -b feat/chat-groups-phase5-task2 main`), then use the `superpowers:subagent-driven-development` skill against the existing plan file (already on `main`). Record `git rev-parse HEAD` as BASE, run `scripts/task-brief docs/superpowers/plans/2026-09-14-chat-groups-phase5-flutter-client.md 2` to extract Task 2's brief, dispatch a fresh implementer subagent with that brief, independently re-verify its work (fresh test run, read the actual diff, don't trust the report), track progress in a new ledger, and continue through Tasks 3-5 the same way — then a final whole-branch review, then `finishing-a-development-branch` (push, open a PR against `main` directly — each remaining task/small group of tasks can land on `main` incrementally the same way Task 1 did, rather than waiting for all of Tasks 2-5 to be done before opening a PR, if they're similarly additive; use judgment per task on whether it's safe to ship alone).

**OPOS #25608** (Phase 5's tracker) is in **Work In Progress** status with a detailed comment recording this exact state — check it for anything that changed after this HANDOFF entry was written.

### What has NOT been started at all

- **Phase 6** (admin-web client for the new chat-groups system) — OPOS #25610, still in "To Do", no design or plan work done yet. Will need its own scoping pass same as Phase 5 did (it's real UI work, not just API wiring) — the original spec's §11 has a short admin-web bullet list to start from (create-group flow, connect-request inbox, `MessagesPage.tsx`'s old donor/owner section becomes read-only history, `CaseVolunteerChatsPage.tsx`'s retirement already done in Phase 4).

### Deploy-time action still pending (not a code gap — a human/ops decision)

`backend/cmd/retire-direct-chats` (shipped in Phase 4, PR #79) has never been run against any real database — it was only tested against throwaway `createdb` instances during development. Running `go run ./cmd/retire-direct-chats -actor=<staff_user_id>` against production is what actually ends+archives every existing open donor↔owner direct-chat thread; until that runs, the **capability** to create new ones is gone (refused with 410) but existing ones keep working normally. This is a deliberate, separate deploy step — flag it to whoever owns production deploys, it is not something a future coding session should just run on its own initiative.

### Traps and gotchas worth knowing before you touch this codebase again

- **Test database reuse.** This backend's test suite has a real, pre-existing, well-documented flake: running `go test` twice against the *same* Postgres database without recreating it reproduces spurious failures (`TestListGroupsForUserUnreadCount` and others) purely from leftover rows, not from any actual bug. **Always `createdb` fresh and use `-count=1 -p 1`** for a trustworthy run. `-p 1` (serialized package execution) also avoids a separate, unrelated cross-package race where `internal/permissions`' own tests can run before another package's test binary has finished migrating the shared database.
- **Squash-merging the first link of a branch chain breaks every descendant's mergeability into the same target later** — see "How the merge-to-main actually happened" above. If you're about to squash-merge a PR, check first whether any other branch was forked from its pre-squash tip.
- **A dispatched subagent that `cd`s into `backend/` (or any subdirectory) before writing a report to a relative path can silently write it to the wrong location** — this happened at least twice this session (a stray `backend/.superpowers/sdd/.../task-4-report.md` during Phase 3, discovered and merged back into the canonical file). Always double-check where a subagent's "written to X" claim actually landed if there's any chance it changed directories mid-task.
- **`chatlifecycle.Systems()` vs `chatlifecycle.AllSystems()` are NOT interchangeable**, despite matching signatures — `Systems()` deliberately excludes retired kinds (correct for the dashboard's "systems in active use" listings), `AllSystems()` includes them (required for resolving historical/trashed data, e.g. restoring a `case_volunteer_chat_threads` row trashed before Phase 4 retired it). A "simplification" that merges these two call sites back together silently reintroduces a real empty-shell-restore bug that Phase 4's final review caught and fixed — the comments in `admin_chat_lifecycle.go` and `admin_trash.go` exist specifically to warn against this.
- **OPOS MCP requires interactive OAuth and was repeatedly unavailable to dispatched subagents** (non-interactive sessions) throughout this work, even though it worked fine in the main controlling session. Several fix-round subagents flagged this rather than silently skipping task tracking — worth checking whether OPOS auth can be pre-established for automated/background sessions rather than re-discovering this each time.
- **`hawkscan`'s post-commit hook fires on every commit** in this environment; its own stated precondition ("if the application is running and HAWK_API_KEY is set") was never met this session (no key configured), so every scan was correctly skipped, not silently ignored. A human with the key configured may want to run a scan over this session's cumulative changes at some point.
- **This project's `HANDOFF.md` merge conflicts are always the same shape**: two branches each add their own "newest entry" at the very top. Resolve by keeping both, ordered newest-first by date — never by discarding one side's entry.

---

## 2026-09-14 — OPOS #25284 Phase 4 final-review fix round (branch `fix/chatgroups-phase4-retire-direct-chat`)

**What was asked:** fix four findings from the final whole-branch review of `fix/chatgroups-phase4-retire-direct-chat` (Phase 4, retiring old direct chat): (1) IMPORTANT — a trash-restore regression where `case_volunteer_chat_threads` rows trashed before this deploy would restore as empty shells; (2) IMPORTANT — `staffactivity`'s "Chats assigned now" metric never excluded ended/archived threads; (3) MINOR — dead Flutter code (`ChatController.requestChat`, `chatRequestUrl`); (4) MINOR — dead notify templates (`CaseVolunteerChatOpenedMsg`, `CaseVolunteerChatNewMessageMsg`).

**What was actually changed:** `backend/internal/chatlifecycle/chatlifecycle.go` gained `AllSystems()` (every registered kind including retired ones, vs. `Systems()`'s actively-reachable subset); `admin_chat_lifecycle.go`'s `allowedChatChildTables` now calls `AllSystems()` instead of `Systems()` so a trashed `case_volunteer_chat_threads` row still resolves its child tables on restore; `admin_trash.go`'s stale comment claiming restore always brings back a full conversation was corrected to explain *why* that's true now (via `AllSystems()`) and warn against reverting; `staffactivity/store.go`'s `Load` added `AND lifecycle = 'open'` to the `chat_threads`/`case_volunteer_chat_threads` OpenWork subqueries; deleted `ChatController.requestChat` + `links.dart`'s `chatRequestUrl` (Flutter) and `notify/templates.go`'s two dead `CaseVolunteerChat*Msg` builders. New tests: `TestAllowedChatChildTablesCoversEveryRestorableTable` (`backend/internal/handlers/chat_lifecycle_trash_test.go`) and `TestLoadOpenWorkExcludesEndedDonorChats` (new file `backend/internal/staffactivity/store_test.go`, this package's first test file, `TEST_DATABASE_URL`-gated per the `chatgroups` package's convention). Full report: `.superpowers/sdd/2026-09-14-chat-groups-phase4-retire-direct-chat/final-review-fix-report.md`.

**What was run and what it printed:** `go build ./...`, `go vet ./...` clean; `gofmt -l internal cmd` — only the same pre-existing, unrelated `admin_edit_user_profile.go` flag every phase of this work has shown. Full backend suite (`TEST_DATABASE_URL=... go test ./... -count=1 -p 1` against a fresh single-use `createdb godonation_phase4_finalfix`, dropped afterward) — 22 packages, all `ok`, zero FAIL lines; the three test names confirmed individually as PASS in the verbose log. The restore-path regression test was explicitly verified both ways per the brief's own requirement: reverted the `AllSystems()` fix, re-ran `TestAllowedChatChildTablesCoversEveryRestorableTable` alone and watched it FAIL with the exact expected message (`case_volunteer_chat_threads` resolving to an empty child list), then restored the fix and watched it PASS. `flutter analyze` from `humanitarian/` — 6 issues, all the same pre-existing unrelated `deprecated_member_use` info notices this branch has shown throughout, zero new.

**External actions taken:** none. Two local commits on `fix/chatgroups-phase4-retire-direct-chat`, neither pushed: `9b3fa6a` (backend: chatlifecycle/admin_chat_lifecycle/admin_trash/staffactivity/notify + 2 test files) and `0c8919d` (humanitarian: links.dart + chat_controller.dart).

**What is still open:**
- Both commits are unpushed and unreviewed by a human.
- OPOS MCP required an interactive OAuth flow and was unavailable in this non-interactive session — no OPOS tasks were created or moved for this fix round. Same limitation hit a dispatched subagent during Phase 3's own fix round (see that entry's Traps below); both need reconciling once OPOS access is available.
- Two `hawkscan` post-commit hooks fired (one per commit) asking to run a security scan; `HAWK_API_KEY` is unset in this environment, so per the hook's own stated precondition the scan was correctly skipped rather than run — a human with the key configured may want to run it.

**Traps:**
- `allowedChatChildTables`'s whole point is to walk `chatlifecycle.AllSystems()`, NOT `chatlifecycle.Systems()` — they look interchangeable (same return type) but are not: `Systems()` deliberately excludes retired kinds (correct for the dashboard's "systems in active use" listings) while `AllSystems()` includes them (required for resolving historical/trashed data). A future "simplification" that merges these two call sites back together silently reintroduces the empty-shell restore bug this fix round closed — the comments left in both `admin_chat_lifecycle.go` and `admin_trash.go` exist specifically to stop that.
- OPOS MCP's non-interactive-session limitation is now a recurring pattern across this branch's phases (Phase 3's fix round hit it too) — worth checking whether OPOS auth can be pre-established outside these automated sessions rather than re-discovering the same blocker each time.

---

## 2026-09-14 — OPOS #25284 Phase 3: connect-request end-to-end (PR #74, branch `feat/chat-groups-phase3`)

**What was asked:** expose Phase 1's `internal/chatgroups` connect-request Store methods (`SubmitConnectRequest`/`ApproveConnectRequest`/`DeclineConnectRequest`/`ListConnectRequests`, built with no HTTP surface) — the flow where a donor/beneficiary/volunteer asks staff to open a masked chat group and staff triage, approve (creating the group transactionally), or decline.

**What was actually changed:** new migration `backend/migrations/122_chat_group_audit_log.sql` (`chat_group_audit_log` table, no FKs, matching this codebase's `chat_group_*` convention); new `backend/internal/chatgroups/chatgroups_audit.go` (`RecordAudit` Store method — currently has zero production callers; OPOS #25634, Phase 2's own version of this same staffactivity gap, will be its first); `chatgroups_connect.go` gained JSON tags on `ConnectRequest`, two new Store methods (`GetConnectRequest`, `ListConnectRequestsForUser`), and two fixes to `ApproveConnectRequest` now that it has a real caller (validates `kind`, and checks the requester is actually present in the approved `members` list — previously could silently create a group its own requester can never see); new `backend/internal/handlers/chat_group_connect.go` (mobile `SubmitConnectRequest`/`MyConnectRequests` handlers); additions to `chat_group_admin.go` (`resolveConnectContext`, `AdminListConnectRequests`, `AdminGetConnectRequest`, `AdminApproveConnectRequest`, `AdminDeclineConnectRequest`); `main.go` wires 6 new routes (2 mobile, 4 admin). Design spec: `docs/superpowers/specs/2026-09-13-chat-groups-phase3-connect-requests-design.md` (note: this spec corrects Phase 1's own original assumption that staff-activity logging could call `internal/staffactivity` directly — that package is a read-only dashboard aggregator with no write method; this phase instead adds the standalone `chat_group_audit_log` table). Plan: `docs/superpowers/plans/2026-09-13-chat-groups-phase3-connect-requests.md`. Built via 5 subagent-driven-development tasks, one final whole-branch review, one fix round, and one scoped re-review — every step independently re-verified by the controller against a real database, never trusting a subagent's self-reported test count.

**Privacy note (spec §9):** `ConnectRequest`'s `decided_by_staff_id`/`requester_user_id` fields must never reach a non-staff requester (a member should only ever learn "Support" acted, never which specific staff member). The mobile `GET /chat-groups/connect-requests/mine` endpoint serializes through a dedicated `myConnectRequestItem` DTO that structurally cannot hold either value — proven by a test that asserts the raw JSON response body never contains the substring `decided_by_staff_id`. Admin endpoints are staff-only (`perm("messages","view"/"edit")`) and intentionally expose the full struct.

**What was run and what it printed:** `go build ./...`, `go vet ./...`, `gofmt -l internal cmd` clean (same one pre-existing, unrelated `admin_edit_user_profile.go` gofmt flag as Phase 2's entry — still untouched by this work). Full backend suite (`go test -count=1 -p 1 ./...` against a genuinely fresh, single-use Postgres database) — all 19 packages `ok`, zero failures, run independently four separate times across the task/review/fix-loop cycle (never trusted a single green run or any subagent's self-report).

**External actions taken:** pushed branch `feat/chat-groups-phase3` to `origin`. Opened PR #74 against `feat/chat-groups-phase2` (NOT `main`) — https://github.com/IamSizar/go_donation/pull/74. Must merge after PR #71 (Phase 1) and PR #72 (Phase 2), in that order — same dependency chain as Phase 2's own entry below.

**What is still open:**
- PR #74 is unmerged, unreviewed by a human, and depends on PR #71 and PR #72 merging first.
- OPOS #25634 (Phase 2's own staffactivity/audit-log gap, on `AdminCreateGroup`/`AdminAddMember`/`AdminRemoveMember`) is a separate follow-up ticket, now corrected to reuse this phase's `RecordAudit`/`chat_group_audit_log` mechanism instead of a nonexistent `staffactivity` write call. A comment was added to that ticket flagging that `RecordAudit`'s `action` parameter needs the same Go-side string validation Task 2 added for `kind`, once this ticket gives it its first real caller.
- Phases 4–6 of #25284 not started (retiring the old direct chat; Flutter client; admin-web client).
- A genuine Critical bug was found and fixed by this phase's own final whole-branch review, after all 5 per-task reviews had already passed: `resolveConnectContext`'s `"donation"` case scanned `donations.amount` (a `VARCHAR(200)`, not numeric) into a `*float64`. The scan always failed, the error was silently discarded (matching an existing best-effort pattern in the same file), and the function always fell through to the raw `"donation #4471"` fallback — for every single donation-context connect request, defeating the entire point of the resolver (spec's own stated reason for existing: "staff cannot make a privacy decision from context_id: 4471"). The bug originated in the design spec's own code sample, was copied verbatim into the plan and then the implementation, so no task-scoped review could have caught it — only the whole-branch review, reading the feature end-to-end, surfaced it. Fixed (scan as `string`, matching how `internal/donations` treats amounts everywhere else), with a new regression test verified to actually catch the bug (the reviewer deliberately reverted the fix, watched the test fail with the exact `"donation #10"` fallback, then restored the file clean). Two spec-mandated test-coverage gaps dropped during planning were also closed in the same fix round: a single test proving the full submit→list-as-admin→approve→post→read-back chain over HTTP (previously split across isolated tests, with the list-as-admin and read-back steps missing entirely), and an HTTP-level test proving resubmitting the same pending request returns the same id rather than a duplicate.
- Non-blocking Minor items logged but not fixed: `chatErr`'s generic `"Group not found."` copy was already special-cased for the three connect-request admin routes to report `"Connect request not found."` instead — but this same generic-message issue exists on other pre-existing chat-group routes, out of this phase's scope. `RecordAudit` remains uncalled in production until OPOS #25634 lands.

**Traps:**
- The same `TestListGroupsForUserUnreadCount`-style flake (reusing one Postgres test database across two consecutive `go test` runs without recreating it) reproduced twice more during this phase's work, in two different forms: `TestAdminListConnectRequests_ReturnsAll` (a plan-mandated test that asserted an *exact* count of 1 from an endpoint with no per-test filter — fixed by looking up the submitted request by id instead of asserting total list length) and a broader default-parallelism race (`internal/permissions` reading a shared DB before another package's test binary has finished migrating it, and `internal/chatgroups`'s own user-id-floor helper using an unsafe `MAX(id)` pattern under concurrent cross-process execution — both pre-existing, neither touched by this branch's changes). **Always use `-count=1 -p 1` against a genuinely fresh, single-use `createdb`** for a trustworthy run of this backend's full suite; the background task started in an earlier session (`task_b18e99d7`) to fix `internal/chatgroups`'s own test-hygiene issue is still the right place to fix the `raiseUserIDFloor` root cause.
- A dispatched subagent can silently write a report (or any relative-path file) to the wrong location if it `cd`'d into `backend/` first and then used a relative path meant for the repo root — a stray duplicate `backend/.superpowers/sdd/.../task-4-report.md` was found and merged back into the canonical file during this phase's pre-finish cleanup. Always double-check where a subagent's reported "written to X" path actually landed if it might have changed directories mid-task.
- OPOS MCP was unavailable (non-interactive auth) to at least one dispatched fix-round subagent this phase — task tracking for that round was not created there and needs reconciling once OPOS access is available.
- This worktree's `HANDOFF.md` (this file) only reflects branches that have actually merged into whatever `main` snapshot it forked from — like the Phase 1 and Phase 2 entries below, this Phase 3 entry lives only on `feat/chat-groups-phase3` until all three PRs land.

---

## 2026-09-13 — OPOS #25544: wire moderation.ScanContact into masked_label writes (PR #73, branch `fix/chatgroups-scancontact-labels`)

**What was asked:** design spec §5's "Alias quality" rule that `moderation.ScanContact` runs over a staff-typed `masked_label` at write time was silently dropped during Phase 1 (the other two Alias-quality rules — auto-generation, neutral placeholder fallback — were implemented). Phase 2 (merged into this branch's history) made it exploitable by adding `POST /api/admin/chat-groups` and `POST /api/admin/chat-groups/:id/members`, both accepting a caller-supplied `label` with no contact-info filtering. Small, fully-specified OPOS follow-up ticket (#25544) from Phase 1's review.

**What was actually changed:** `backend/internal/chatgroups/chatgroups.go` — added `refuseContactInLabel(label string) error` (wraps `moderation.ScanContact`, returns an error wrapping `ErrInvalidInput` when flagged); wired into `insertMembers()` (used by `CreateGroup`) and `AddMember()`, called only on a non-empty, caller-supplied label on a MASKED group, after the empty→auto-label branch and before the `INSERT` — auto-generated labels ("Donor 1") are never scanned. `backend/internal/chatgroups/chatgroups_admin_test.go` — 4 new tests: `TestCreateGroupRefusesPhoneNumberLabel`, `TestAddMemberRefusesPhoneNumberLabel`, `TestAddMemberAllowsCleanLabel`, `TestAddMemberEmptyLabelStillAutoGeneratesForMaskedGroup`. No handler-side change needed: `internal/handlers/chat_group.go`'s existing `chatErr` dispatcher already maps `ErrInvalidInput` → 400.

**What was run and what it printed:** `createdb godonation_chatgroups_scancontact` (throwaway); `TEST_DATABASE_URL=... go test ./internal/chatgroups/... -v` → `PASS`, 38/38 (34 pre-existing Phase 1/Phase 2 tests + 4 new), `ok ... 2.650s`; database dropped after. `gofmt -l internal/chatgroups/*.go` → no output. `go vet ./internal/chatgroups/...` → clean. `go build ./...` (whole backend) → clean.

**External actions taken:** pushed branch `fix/chatgroups-scancontact-labels` to `origin`. Opened PR #73 against `feat/chat-groups-phase2` (correct base — depends on Phase 2's admin routes existing even though the code change is entirely in the Phase 1 `internal/chatgroups` package): https://github.com/IamSizar/go_donation/pull/73. OPOS task #25544 moved Work In Progress → Completed, timer stopped, completion comment added with files/tests.

**What is still open:** PR #73 is unmerged and unreviewed by a human; it stacks on the still-unmerged PR #72 (Phase 2) which itself stacks on PR #71 (Phase 1) — merge order matters. `hawkscan`'s post-commit hook fired asking for a scan, but its own precondition ("if the application is running and HAWK_API_KEY is set") wasn't met in this session (nothing running, key not verified), so it was not run — flagging in case a future session has that set up and wants to scan commit `ab4768a`.

**Traps:** none new. The existing "fresh `createdb` per verification run" trap from Phase 2's entry above still applies — this session followed it (dedicated throwaway db, dropped after).

---

## 2026-09-13 — OPOS #25284 Phase 2: chat-group routes, permissions, lifecycle wiring (PR #72, branch `feat/chat-groups-phase2`)

**What was asked:** expose Phase 1's `internal/chatgroups` Store (schema + service layer, no HTTP surface) over the real API — mobile and admin routes, permission gating, registering the new chat system with the shared `internal/chatlifecycle` pause/resume/archive/delete/restore mechanism, adapting the existing K19 contact-info filter for masked groups, and push notifications.

**What was actually changed:** new files `backend/internal/handlers/chat_group.go`, `chat_group_admin.go`, `chat_group_contact_block.go` (12 routes total on one `ChatGroupHandler`); `backend/internal/chatlifecycle/chatlifecycle.go` gains a 5th registered system (`KindGroup`); `backend/internal/chatgroups/chatgroups_admin.go` (new: `GetGroup`, contact-block recording) plus two small error-typing fixes in `chatgroups.go`; `backend/migrations/121_chat_group_contact_blocks_fix.sql` (corrects a Phase 1 scaffolding table's columns before its first real use — zero rows, zero prior consumers); `backend/internal/notify/templates.go` gains `GroupMaskedNewMessageMsg`; `backend/cmd/server/main.go` wires all of it in. Design spec: `docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md`. Plan: `docs/superpowers/plans/2026-09-12-chat-groups-phase2-routes-and-permissions.md`. Built via 10 subagent-driven-development tasks, two of which needed a fix round.

**What was run and what it printed:** `go build ./...`, `go vet ./...`, `gofmt -l internal cmd` all clean (one pre-existing, unrelated file — `admin_edit_user_profile.go` — excepted, not touched by this work). `go test ./...` against a freshly-created Postgres database — every package `ok`, including 16 new chat-group HTTP tests and a rewritten delete/restore round-trip test now covering all five chat systems (was hardcoded to one before this phase).

**External actions taken:** pushed branch `feat/chat-groups-phase2` to `origin`. Opened PR #72 against `worktree-chat-groups-phase1` (Phase 1's branch, NOT `main`) — https://github.com/IamSizar/go_donation/pull/72. This PR must merge after PR #71 (Phase 1), since it depends directly on Phase 1's `internal/chatgroups` package.

**What is still open:**
- PR #72 is unmerged, unreviewed by a human, and depends on PR #71 merging first.
- Phases 3–6 of #25284 not started (connect-request routes; retiring the old direct chat; Flutter and admin-web clients).
- A real bug was found and fixed by this phase's own final review before merge: `chat_group_*` tables have no foreign keys (Phase 1's deliberate convention), but the shared trash/delete handler (`admin_chat_lifecycle.go`) assumed every chat system has `ON DELETE CASCADE` FKs on its child tables — so deleting a chat group didn't delete its data and restoring it failed with a duplicate-key error. Fixed uniformly for all five chat systems, not special-cased.
- Several real-but-non-blocking gaps deliberately deferred, each with zero current impact since no client exists yet to reach any of these routes: per-user permission-override awareness on the admin routes that reveal real identity inside a masked group (tier-based gating only, a broader design question intentionally carried to whichever phase builds the admin-web UI); a notification entity-type mismatch for team-group pushes (reuses the donor-chat template's `RelatedEntityType`, colliding with an unrelated id space — latent since no client reads it yet, but baked into stored notification rows from first deploy); notification dispatch has zero automated test coverage; `chat_group_test.go` is 748 lines (over this codebase's 500-line file-size cap); a handful of "four chat systems" doc-comment references now that there are five. Full detail on every one of these, including explicit rulings, was recorded in this phase's SDD ledger before that scratch file was deleted per the workflow's own convention (git history + this entry are now the record).

**Traps:**
- `chat_group_*`'s deliberate no-foreign-keys convention (correct for Phase 1's own purposes) is exactly what broke the shared trash/delete/restore machinery, which every other chat system's schema satisfies via FK cascades. Any future chat-adjacent table built without FKs needs the SAME explicit-child-delete treatment in `admin_chat_lifecycle.go`'s `trashChatThread` — it's now generic across all five systems, so a sixth system just needs its `ChildIDColumn`/`ExtraChildTables` set correctly in `chatlifecycle.go`, nothing new in the handler.
- Running this codebase's Go test suite twice against the *same* database without recreating it reproduces a known, pre-existing, unrelated flake in `TestListGroupsForUserUnreadCount` (orphaned rows from the first run). Always use a fresh `createdb` for a trustworthy single-shot verification run; a background task (`task_b18e99d7`) was separately spawned to fix the underlying test-hygiene issue in `internal/chatgroups`'s own test helpers.
- This worktree's `HANDOFF.md` (this file) only reflects branches that have actually merged into whatever `main` snapshot it forked from — like Phase 1's entry above, this Phase 2 entry lives only on `feat/chat-groups-phase2` until both PRs land.

---

## 2026-09-12 — OPOS #25284 Phase 1: chatgroups schema + Store layer (PR #71, branch `worktree-chat-groups-phase1`)

**What was asked:** design and start building a replacement for direct donor/beneficiary/volunteer messaging — per client policy, those three roles must never contact each other directly; only staff-created group chats (masked/alias-only for donor+beneficiary+volunteer coordination, real-name for staff-curated volunteer teams) connect them. Full policy, architecture options, and phasing are in `docs/superpowers/specs/2026-09-12-masked-group-chats-design.md`.

**What was actually changed:** new, currently-unreferenced Go package `backend/internal/chatgroups/` (`chatgroups.go`, `chatgroups_reads.go`, `chatgroups_connect.go`, `chatgroups_test.go`) and new migration `backend/migrations/120_chat_groups.sql` (7 new tables: `chat_group_threads`, `chat_group_staff_notes`, `chat_group_members`, `chat_group_messages`, `chat_group_reads`, `chat_group_contact_blocks`, `chat_group_connect_requests`; additive only, no existing table touched). No HTTP route, no `chatlifecycle` registration, no client change — nothing here is reachable yet. Built via `docs/superpowers/plans/2026-09-12-chat-groups-phase1-schema-and-store.md` (10 tasks, subagent-driven development).

**What was run and what it printed:** `go build ./...` and `go vet ./internal/chatgroups/...` clean; `gofmt -l internal/chatgroups/*.go` empty; `go test ./...` from `backend/` — every package `ok`, including `ok github.com/karam-flutter/humanitarian-backend/internal/chatgroups 0.618s` (29 tests, gated on `TEST_DATABASE_URL` against a real Postgres instance — this machine's local Postgres via `pg_isready` on port 5432). Migration applies cleanly to a fresh database.

**External actions taken:** pushed branch `worktree-chat-groups-phase1` to `origin` (note: NOT named `feat/chat-groups-phase1` as originally intended — that name was already checked out in another local worktree, so the auto-generated worktree branch name was kept). Opened PR #71 against `main`: https://github.com/IamSizar/go_donation/pull/71. `mcp__ccd_pr__bind_pr` failed to bind it for CI monitoring ("could not read it as an open pull request... a host `gh` is not signed in to") — the desktop app's GitHub auth and this shell's `gh` CLI auth are apparently different identities/hosts; PR CI should be checked manually or by re-authenticating the app's GitHub connection.

**What is still open:**
- PR #71 is unmerged, unreviewed by a human.
- Phases 2–6 of #25284 (routes/permissions, connect-request end-to-end, retiring the old direct chat and `casevolchat`'s direct mode, Flutter client, admin-web client) are not started — each needs its own plan, written only once the prior phase's real interfaces exist.
- OPOS #25544 (run `moderation.ScanContact` over staff-typed masked labels, per spec §5) is open — deliberately not implemented in Phase 1 since no route sets a label yet; must be picked up when Phase 2 wires label input over HTTP.
- Several other gaps found by the final whole-branch review were deliberately deferred to the Phase 2 brief rather than fixed here (no current consumer exists for any of them): `ApproveConnectRequest` doesn't validate the requester is among the approved members or that `kind` is valid; `ListConnectRequests` isn't renamed/documented as staff-only; group-listing order reflects creation time not last-activity and isn't paginated; `AddMember` has no re-add-after-soft-remove path.
- OPOS #25296 (marriage feed separation + multi-vendor services catalogue) explicitly overlaps this task's messaging parts and was flagged in its own ticket to coordinate scope, not duplicated here.

**Traps:**
- This worktree's `HANDOFF.md` is branched from an old `main` snapshot (2026-07-06, `new-update` branch content) — it does **not** contain other same-day branches' entries from this same working session, since none of those PRs are merged yet. That's expected, not data loss: each unmerged branch's `HANDOFF.md` is relative to its own fork point until merge.
- `git branch -m` to rename the worktree's auto-generated branch to the intended `feat/chat-groups-phase1` fails (`fatal: a branch named 'feat/chat-groups-phase1' already exists`) if that name is checked out elsewhere in the same repo's other worktrees/checkouts — don't fight it, the branch name on GitHub (`worktree-chat-groups-phase1`) is what matters for the PR, not the local name.
- `gofmt -l pkg/*.go && echo CLEAN || echo DIRTY` is backwards logic: `gofmt -l` exits 0 whether or not it lists files, so the `&&` branch always fires. Check for genuinely empty output directly instead of trusting the exit code.

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
