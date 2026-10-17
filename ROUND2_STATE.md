# ROUND 2 — STATE FILE (read this first after any chat compaction / new agent)

Last updated: 2026-10-16

## SCOPE (owner gave the proposal 2026-10-17)
`ORIGINAL_SCOPE.md` + `ORIGINAL_PROPOSAL.pdf`. Rule: not in scope → mark **➕ Addition**, put aside, come back later.
Now ➕ Addition: #2 #5 #10 #11 #12 #14 #44 #45 #48 #66 #72 #73 #83, the «general user» part of #35 + #37 #38, and the extras of #59 #60 #61.
Owner also said (2026-10-16): NO payment/donation changes for now → #47–55 reverted; #54 bug documented only. #67 (wallet hole) is payment-related → ASK before touching; note the app wallet itself is not in the proposal.

## FINAL DELIVERABLE (owner, 2026-10-17)
When all points are done: give the owner **the same notes file the client sent** (`~/Downloads/الملاحظات.pdf`, 20 pages, same order/numbering) back with, for EACH point, how it was fixed + the screenshots (or ➕ Addition / ⏳ with the reason). Build it from ROUND2_REPORT.md; also tell him each point's fix in chat with screenshots.

## EXTRA requests from the owner during round 2 (not numbered points; include in the final file)
- **Default language = Arabic** (2026-10-17). Found: with no saved choice the app followed the phone and skipped English to the NEXT language in the phone's list (Kurdish on an English+Kurdish Iraqi phone). Fixed in `locale_service.dart` (`loadLocale` returns Arabic on first launch; user's choice always wins). Test: `test/localization/default_language_test.dart`. Screenshot: `round2_screens/extra/default-arabic.png`.

- **City Guide map squashed + «API KEY REQUIRED»** (owner screenshot, 2026-10-17). Found: (1) the map was an `Expanded` taking only the space left under the profile banner, header, search, button and chips, so with the banner showing it shrank to a ~100pt strip; (2) CartoDB now answers every tile with an "API KEY REQUIRED" image (confirmed with curl), so the basemap was that watermark. Fixed in `community_services_section.dart` (page scrolls, map min height 440 / 60% of screen) and tiles → OpenStreetMap in both maps (`community_detail_screen.dart` too); attribution «© OpenStreetMap». NOTE: OSM's free tiles suit modest use; at scale use a keyed provider (one URL to change). Not verified with the banner present (it did not reappear on the test account). Screenshots: `round2_screens/extra/city-guide-map-before.png`, `city-guide-map-fixed.png`. Related: #88.

## What this is
Client (Zaid / Tawazzn charity app) sent `~/Downloads/الملاحظات.pdf` (20 pages) on 2026-10-16.
All 91 points are numbered in `CLIENT_NOTES_ROUND2.md` (same order as the PDF), each tagged
[F] fix / [A] addition / [Q] question. That file is the master list + per-point fix log.
This file = rules, decisions, progress, what's next.

## WORKFLOW (FINAL, owner 2026-10-16 evening) — supersedes the two notes below
Go through CLIENT_NOTES_ROUND2.md in order and fix EVERY [F]/[Q] point myself, one by one, no waiting.
Additions [A] → ⏳ Waiting (until owner gives the scope). Everything goes into **ROUND2_REPORT.md**:
each point with ✅ / ⏳ / ❌, how it was fixed, screenshots below, notes. Helper:
`python3 round2_screens/setpoint.py N body.md` replaces point N's section. Commit each fix on
branch `round2-fixes` (NOT pushed, NOT deployed).
**OPOS per point (owner):** create the task BEFORE touching it → in_progress while working → done when finished.
Done so far: #2 ⏳, #3 ✅, #4 ✅ (96172), #20–23 ✅ (96177), #24 ✅ (96178), #25–26 ✅ (96180), #27–28 ✅ (96182), #29–33 ✅ (96181), #16–19 ✅ (96184: guest home/city guide/support chat+tickets opened; server GuestSupportThreadOnly), #56–57 + #6/#58 ✅ (96190), #59–61 answered (partly ⏳), #7 ✅ (96196), #8 + #86 ✅ (96197: Noto Sans Arabic app+dashboard, zero tracking), #34 ✅ #35 partly ✅ (general user ⏳) #36 ✅ #37 ⏳ #38 ⏳ (96183), #13 ✅ (already there), #15 ❌ (not reproducible locally), #39–43 ✅ (97611: count tiles = read filter, centred clear button, linked dropdowns, newest first, «تحديد الكل كمقروء»), #46 ✅ (97612: brand wheel + ticket coupon with 3D flip, Arabic wheel labels fixed).
NEXT TODO (in order): #47–55, #62–65, #67–71, #74–85, #87–91, then #1 summary.
Local server must run with OTP_DEMO_ENABLED=1 (scratchpad run-server.sh); demo code 123456.
Found+fixed on the way: static splash never navigated for logged-in users (scheduleFrame).
Pre-existing failing app tests (not ours): translating_widget_literals, featured_campaign_card_size, marriage_hub_events_grid ×2. Backend guest tests run with TEST_DATABASE_URL=postgres://localhost/r2test.
Noted for later: city-guide map «API KEY REQUIRED» watermark (CartoDB) — check live; sign-up screen shows a dev toggle «طريقة الإرسال واتساب / رسالة نصية · رمز تجريبي» (check #17/#19 time); raw English server errors shown in app («Demo OTP mode is disabled.») → #17.

## (old) WORKFLOW CHANGED 2026-10-16
Owner reads CLIENT_NOTES_ROUND2.md himself and sends ONE part at a time in chat. For each part:
find the issue → fix it → reply SHORT: **Found:** / **Fixed:** + screenshot. Nothing else — no tables,
no option lists, no asking which next. Owner 2026-10-16: keep rule 8 — user-friendly, easy to use and
understand, AND professional-looking. Then wait for the next part. Don't start points on my own.

## Owner rules (Momen) — do not break
1. One point at a time, in PDF order: fix → verify in the REAL running app/dashboard → send a
   real screenshot → STOP and wait for "ok go next point".
2. Never skip or forget a point. Every point stays in the list until it's ✅ / decided.
3. **Additions ([A]) are deferred to the very end.** At the end, do an addition ONLY if it is in
   the original proposal/scope we gave the client. Not in the proposal → we don't do it at all.
4. The original proposal is NOT on this Mac (searched 2026-10-16: repo, Downloads, Documents,
   Spotlight). Ask owner for it before starting the additions phase (maybe Gmail / Zaid).
5. Report each fix with **Found:** / **Fixed:** headings.
6. Save each point's "how it was fixed" into `CLIENT_NOTES_ROUND2.md` → "How each point was fixed".
8. **Professional + simple, nothing that looks AI-made.** Client complained the app feels AI-made because
   it is cluttered and repetitive. Every text we touch: short, formal Arabic, said once. No explanation
   paragraphs, no duplicate buttons/links, no emoji, no chatty hints. When fixing a point, also remove
   clutter on that same screen — but don't redesign beyond the point.
7. OPOS: office **19 "-129- Charity App"**, account **momen 1758**. Create task BEFORE work
   (in_progress), done only after owner approves. Title format: `R2 #N — …`.

## Technical must-knows (from round 1, see CLIENT_MEETING_HANDOFF.md for full detail)
- Real repo: `~/Documents/projects/go_donation` (GitHub IamSizar/go_donation). `tawazon/` is a mirror — don't touch.
- Verified 2026-10-16: local main == GitHub main (8e5d634), clean tree.
- Dashboard dev server (`.claude/launch.json` → go-donation-admin-web, port 5195) proxies to
  **PRODUCTION** backend → read-only browsing only. Backend changes → scratch DB recipe in handoff.
- App = Flutter in `humanitarian/`; dashboard = `admin-web/`; backend = Go `backend/`.

## Progress
| # | Type | Status | OPOS | Note |
|---|---|---|---|---|
| 4 | Q | ❓ answered, waiting owner OK | 96172 | All 5 controls work on group rooms. Khotba chat lacks add/remove member (guardian) → addition. 3 small clutter fixes proposed (double status text, English aliases, double confirm). Screens round2_screens/04 |
| 3 | Q | ✅ owner OK 2026-10-16 | 96169 | Exists: /chat-groups (team + masked) and khotba via طلبات الفعاليات → موافقة. Missing: add guardian to khotba chat. Screens in round2_screens/03 |
| 2 | A | 🅰 deferred — owner sent it 10-16, answered with screens round2_screens/02 | 96168 (backlog) | Investigated: (a) only per-mission volunteer check-in/out exists (لوحة المتطوعين, تسجيلات المهام), no daily attendance/leave, nothing for staff; (b) only volunteer signups per mission, no beneficiary/participant list per campaign; (c) إيصالات المساعدات exists (dashboard, admin-only, photos, no signature, no app upload). Missing parts = additions → end, only if in proposal. |

## Local test setup (reuse for every point — NEVER use production)
- Scratch DB `r2scratch` (local Postgres). Backend binary built to the session scratchpad, run with
  `RUN_MIGRATIONS=1 MIGRATIONS_DIR=./migrations DATABASE_URL=postgres://localhost/r2scratch?sslmode=disable HTTP_PORT=8095 APP_ENV=dev` (no SMS/email/push keys → nothing external sent).
- Test accounts: `go run ./cmd/seed-test-users -confirm` (prints the table: test_sa super admin, test_d donor, test_b beneficiary, test_v1/v2 volunteers, test_g guest…; password in that output).
- Dashboard against it: launch config `go-donation-admin-scratch` (port 5196). Sign in test_sa. Switch language to العربية for screenshots.
- App: Flutter `humanitarian/` runs on simulator "tawazzn-r2" (iPhone 16 Pro, **iOS 26.4** — iOS 27 crashes the app
  at launch: no UIScene adoption). Started with `flutter run -d <id> --dart-define=API_BASE_URL=http://localhost:8095/api/`
  with stdin from a FIFO held open by `sleep`; hot reload = `printf r > fifo`. (`flutter build ios --simulator` fails:
  Flutter.framework arch check — use flutter run.) App test logins: phone + password from seed-test-users table.
- Dashboard login shortcut: in the tab run JS fetch('/api/auth/admin/login') and put access_token + account into
  sessionStorage keys humanitarian.admin.token / humanitarian.admin.user.
- Screenshots saved per point in `go_donation/round2_screens/NN/` (git-ignored).

## Next
- Next point to work: **#1** is an umbrella (covered by #47–#55) → #3 ✅. Waiting for owner to send the next part (new workflow). #4's 3 proposed clutter fixes NOT done — only if owner sends them (room control buttons: pause, archive, delete, kick, add member).
- Deferred additions list (do last, proposal-gated): add-guardian-to-khotba-chat (from #4), 2, 5, 10, 11, 12, 14, 44, 45, 66, 72, 73, 83.
  Re-check while fixing: some [Q] points may turn into [A] if the feature is missing (3, 4, 60, 61, 80).
