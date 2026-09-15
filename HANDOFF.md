# Tawazon / BalanceNex — Project Handoff & Full Audit

> **Purpose:** Everything a new engineer (or a new Claude session) needs to pick up this project and continue. Read this top-to-bottom before touching code.
>
> **Generated:** 2026-07-06 · **Branch pushed:** `new-update` · **Latest commit:** `5360d68`

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
