# Start here — handoff to the next agent

> Written 2026-09-22 by an outgoing Claude Code session, at Zaid's request, so the
> next agent (human or AI) knows exactly what this project is and exactly what to
> do next without re-deriving it. Read this file top to bottom before touching
> code. It is a snapshot, not a duplicate of `HANDOFF.md` — that file is the full
> running log (6,500+ lines, newest entry first) and is the place to check for
> detail on anything summarized here.

## 1. What this project is

**BalanceNex** (also called **Tawazon** in older docs — see §7, "the naming
mess"). A donations and community platform. Three deployables in one repo:

| Path | Stack | Deployed to |
|---|---|---|
| `backend/` | Go (Gin) + PostgreSQL | Railway |
| `admin-web/` | React + TypeScript + Vite | Railway (staff dashboard) |
| `humanitarian/` | Flutter (iOS + Android) | App Store / Play Store |

Full run/build/test instructions are in [`README.md`](README.md) — read that
next; it is accurate and short. The one-line versions:

```bash
# backend
cd backend && cp .env.example .env  # set DATABASE_URL, then:
go run ./cmd/server

# admin dashboard
cd admin-web && npm install && npm run dev

# mobile app
cd humanitarian && flutter pub get && flutter run
```

**Testing traps that will burn you** (all detailed in `README.md` and
`HANDOFF.md`, repeated here because they are the single most common way to
waste an hour on this repo):

- `cd backend && go test ./...` silently skips 171 of 282 tests (needs
  `TEST_DATABASE_URL`; use `./scripts/test-with-db.sh` instead — it starts a
  throwaway Postgres in Docker). Give it an **empty** database; each package
  migrates itself.
- `cd admin-web && npx tsc --noEmit` type-checks **nothing** (root tsconfig has
  `"files": []`). Use `npm run build`.
- `flutter test` draws every glyph as a full-em square (the Ahem font). Any
  test that measures Arabic/Kurdish text width is meaningless unless it loads
  the real font first — see `humanitarian/test/widgets/
  donation_badge_title_squeeze_test.dart` for the pattern
  (`FontLoader('NotoKufiArabic')` from `assets/fonts/NotoKufiArabic-Variable.ttf`).
- Building the Flutter app for the iOS simulator can fail with `Xcode build
  failed due to concurrent builds ... database is locked` if a previous
  `flutter run`/`flutter build` is still holding Xcode's DerivedData lock —
  `pkill` the stale `xcodebuild`/`flutter_tools.snapshot run` process first.
- Kurdish is stored under Arabic locale codes: `ar_IQ` = Sorani, `ar_TR` =
  Badini (`humanitarian/lib/localization/app_translations.dart`). **Never
  invent Kurdish strings** — a wrong key falls back to English on purpose;
  Badini is a machine-drafted best-effort awaiting a native speaker.
- No secrets in the repo, ever, including test files — `backend/.env.example`
  lists keys with no values.

## 2. Where the code actually lives (read this before pushing anything)

There are now **two remotes**. This matters:

| Remote | URL | What it is |
|---|---|---|
| `origin` | `https://github.com/IamSizar/go_donation` | **The real, active repo.** PRs #150 and #151 (see §4) are open here. This is where CI, branch protection, and the existing PR history live. Keep working against this one unless Zaid says otherwise. |
| `tawazon` | `https://github.com/easytechnologycompany/tawazon` | **A private mirror**, created 2026-09-22, for handing this project off. All 176 local branches and full history were pushed here in one shot. It has no PRs, no CI, no branch protection — it is a snapshot, not (yet) a place to develop against. |

If the next agent's job is to keep shipping fixes on the live product, **use
`origin`**, exactly as the last three fixes did (branch off `main`, PR against
`IamSizar/go_donation`). If Zaid has since told you `tawazon` is now the
primary repo, disregard this and confirm with him which remote is canonical
before opening more PRs — this file cannot know that.

**176 local branches were pushed to `tawazon`, almost all of them clutter:**
most are `worktree-agent-<hash>` branches left behind by past parallel-agent
runs, plus a long tail of merged `fix/*`/`feat/*` branches from completed work
(see `HANDOFF.md` for which). Don't assume an old branch is live work in
progress — check its last commit date and whether it is already merged into
`main` before reviving it.

## 3. Uncommitted work sitting in the working tree — READ THIS

**The new `tawazon` mirror does NOT contain this**, because it was never
committed. If you clone `tawazon` fresh, you will not see it. It only exists
in this checkout's working tree (`/Users/zaidaqrawi/Documents/Projects/go_donation`)
as of 2026-09-22.

As of this writing, `main`'s working tree has uncommitted edits from a
2026-09-16 session (documented in `HANDOFF.md` under that date) plus a couple
of newer additions from later work:

```
 M admin-web/src/components/UserProfileSections.tsx
 M admin-web/src/lib/needsAction.ts
 M backend/internal/handlers/admin_detail_user_profile.go
 M backend/internal/handlers/admin_status_notify.go
 M backend/internal/handlers/pending_counts.go
 M backend/internal/handlers/registration.go
 M backend/internal/notify/templates.go
 M backend/internal/notify/templates_sponsorship_test.go
 M backend/internal/users/profile.go
 M backend/internal/users/registration.go
 M backend/internal/users/users.go
 M humanitarian/lib/core/phone_format.dart
 M humanitarian/lib/modules/auth/screens/login.dart
 M humanitarian/lib/modules/auth/screens/registration_form.dart
?? admin-web/src/components/UserProfileSections.test.tsx
?? backend/internal/handlers/admin_detail_user_profile_canonical_test.go
?? backend/internal/handlers/admin_status_notify_sponsorship_lang_test.go
?? backend/internal/handlers/pending_counts_marketplace_test.go
?? backend/internal/notify/templates_sponsorship_localized_name_test.go
?? backend/internal/users/profile_canonical_row_test.go
?? backend/internal/users/registration_phone_test.go
?? humanitarian/test/core/phone_validation_test.dart
?? humanitarian/test/widgets/registration_phone_validation_test.dart
```

This work looks like it addresses client items **A3** ("a sponsorship approval
must name the project") and **A4** ("a new account must notify the dashboard")
— see §5. **Nobody has verified it builds, passes tests, or is finished.**
Before doing anything else with it: read the 2026-09-16 `HANDOFF.md` entries
for context, run the test suites, decide whether to finish it, discard it, or
hand it back to whoever started it.

## 4. Open pull requests (both against `origin`, i.e. `IamSizar/go_donation`)

| PR | Branch | Status | What it fixes |
|---|---|---|---|
| [#150](https://github.com/IamSizar/go_donation/pull/150) | `fix/campaign-title-squeezed-by-pill` | Open, mergeable, CI not checked by me | Campaign detail screen: a 100%-funded campaign's title wrapped one syllable per line because it shared a `Row` with the funding pill. |
| [#151](https://github.com/IamSizar/go_donation/pull/151) | `fix/donation-card-title-squeezed-by-badge` | Open, mergeable, CI not checked by me | Same root cause, found by audit, on the Contribute tab: the campaign list card and the selected-campaign card. |

**Neither has been merged.** Both were verified with widget tests (RED before
the fix, GREEN after) and eyeballed on an iPhone 16 simulator — **neither was
checked on Android**, which is where the original bug report (a screenshot
from Zaid) came from. That is the single most important gap to close before
merging: **open a 100%-funded campaign, in Arabic, with an enlarged system
font, on an actual Android device or emulator**, for both PRs.

Both PRs also touch `HANDOFF.md` at the same insertion point, so merging both
will produce a **trivial merge conflict there** — keep both entries when you
resolve it.

## 5. What to work on next, in order

1. **Verify PRs #150 and #151 on Android**, then merge them (or fix whatever
   Android turns up).
2. **Decide what to do with the uncommitted working-tree changes** (§3) —
   finish, test, and commit them, or discard them. They are not safe to just
   leave sitting there indefinitely; the risk of losing them (or of someone
   else's future `git checkout` clobbering them) grows the longer they sit.
3. **A latent, unproven layout risk**: `humanitarian/lib/modules/sponsorship/
   screens/beneficiary_entitlements_screen.dart:210`, `_StatusChip`. The same
   audit that found #151's bug estimated (but did not reproduce on the real
   widget) that a long Sorani status label at 2.0x text scale could leave the
   title as little as ~30px. Reproduce it properly (real font, real widget,
   real device text scale) before deciding whether it needs the same `Wrap`
   fix as #150/#151.
4. **~45 other places in `humanitarian/lib` matched the same scanner pattern**
   (a title in an `Expanded`/`Flexible` sharing a `Row` with something else
   that can hold text) and were judged safe **by reading the code, not by
   measuring it**. See the OPOS task #28157 comment (§6) for the exact list.
   If you have spare cycles and care about this class of bug, pick a few and
   actually measure them the way #151's test does.
5. **The client feedback backlog is almost entirely unverified.**
   `docs/client-feedback-2026-09.md` tracks 27 items from the client (A1–F3,
   in Arabic and English); as of this writing **only 2 are marked DONE**
   (A2, and a chat-policy conformance item), the rest say `UNVERIFIED`. That
   file's own instructions are clear: don't mark anything done without
   `file:line` evidence. This is the highest-value place to spend time if the
   goal is client satisfaction rather than code quality.
6. **OPOS bookkeeping is incomplete for `main`'s standing uncommitted work**
   (§3) — no task exists for it yet. Create one in office 19 if you pick it up.

## 6. OPOS (task tracking)

Everything in this session was tracked in **OPOS office 19, "-129- Charity
App"**, workspace 3, as user **Zaid Aqrawi (userId 6)** — the connector has 3
linked accounts (`momen`, `Nipel`, `Zaid Aqrawi`); always pick `accountId: 6`
for this project unless told otherwise.

| Task | Status | What it is |
|---|---|---|
| #28156 | Under Review | Retroactive record of PR #150's fix. Held in review because Android is unverified. |
| #28157 | Completed | The audit that found #151's bug. Full method, measurements, and the "judged safe but unverified" list are in its comment — read it before re-doing this work. |
| #28166 | Under Review | Retroactive record of PR #151's fix, including the failed first attempt (see its comment) and why it was abandoned. Held in review for the same reason as #28156. |

The `opos` MCP server needs re-authorizing at the start of each new session —
if it reports "unavailable" or "needs auth," try `whoami` before concluding
it's actually down; that message has been wrong before.

## 7. The naming mess (so it doesn't cost you an hour)

`README.md` calls the product **BalanceNex**. The header of `HANDOFF.md` still
says "Tawazon / BalanceNex" and is dated July even though its entries run
through September. Migration/backend code, Play/App Store listings, and the
new mirror repo (`tawazon`, per Zaid's explicit naming choice for this
handoff) all use one name or the other inconsistently. **Nobody has
reconciled this.** Don't assume one name is "the real one" without asking; ask
Zaid before renaming anything user-facing.

## 8. Everything else you need is already written down

- **`HANDOFF.md`** — the full chronological log, one entry per unit of work,
  newest first. Every fix in this file (and every fix before it) has an entry
  there with root cause, files touched, exact verification commands and
  output, and traps. Read the relevant date range before touching adjacent
  code.
- **`RAILWAY.md`**, **`DEPLOYMENT_NOTES.md`** — deploy topology and current
  hosting notes.
- **`TERMINOLOGY.md`** — naming conventions used in code and copy.
- **`docs/`** — chat-policy conformance audit, client feedback (§5), runbooks,
  testing docs.

If something in this file turns out to be stale by the time you read it —
branches merged, PRs closed, OPOS tasks moved — trust the live state (git,
GitHub, OPOS) over this document, exactly as this document told you to trust
live state over anything older than it.
