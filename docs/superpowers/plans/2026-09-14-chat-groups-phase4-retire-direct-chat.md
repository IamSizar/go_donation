# OPOS #25284 Phase 4 — Retire Old Direct Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shut down the donor↔campaign-owner direct chat (`internal/chat`, `kind='direct'`) and retire `casevolchat`'s direct volunteer↔beneficiary messaging entirely, now that masked group chats (Phases 1–3, already merged into this branch's history) are the only sanctioned way these roles connect.

**Architecture:** No new packages. Backend: gate `chat.Store.RequestThread` to always refuse, run a one-off bulk `end`+`archive` over every existing open `kind='direct'` thread via the existing `chatlifecycle.Apply`, trim `casevolchat` down to the one read-only method `admin_delete.go`'s guard still needs, delete its HTTP handlers/routes, and drop `KindCase` from `chatlifecycle.Systems()`. Flutter: delete the donor/owner chat entry points and all casevolchat UI. Admin-web: delete the casevolchat oversight page and its nav entry.

**Tech Stack:** Go/Gin/pgx (backend), Flutter/GetX (mobile), React/TypeScript/Vite (admin-web).

## Global Constraints

- `kind='support'` (donor/volunteer/beneficiary↔staff 1:1 chat, `chat.Store.RequestSupportThread`) is explicitly UNAFFECTED — every task must leave it working exactly as today. Never touch `RequestSupportThread`, `SupportThread` handler, or `/chats/support` route.
- `marriagechat` (the marriage module's masked relay) is explicitly UNAFFECTED — do not touch anything under `internal/marriagechat` or `humanitarian/lib/modules/marriage/`.
- No migration of old `chat_threads` (`kind='direct'`) content into `chatgroups` — old threads become historical records only, still visible to staff via the existing `ListAllThreads`/admin `/admin/chats` routes (unchanged).
- No destructive `DROP TABLE` migration anywhere in this plan. `case_volunteer_chat_threads`/`case_volunteer_chat_messages` keep their existing rows; only the application code that creates/reads/writes NEW rows through them is removed (except the one read-only guard in `admin_delete.go`, which stays working).
- The branch `fix/messaging-channels-reachable` (unmerged, on `origin`) touches exactly the entry points Task 4 deletes. Per the design spec's own coordination note and the user's explicit decision this session: that branch is **dropped, not merged**. No task in this plan touches that branch; this is a note for whoever manages branches later, not an action item.
- This branch (`fix/chatgroups-phase4-retire-direct-chat`, forked from `feat/chat-groups-phase3`'s tip) already has Phase 1–3's `chatgroups` package, including `SubmitConnectRequest` accepting `context_type='case'` — confirmed already correct in `backend/internal/chatgroups/chatgroups_connect.go:53-56`. No changes needed there; this plan's Task 3 is what makes `case` the ONLY way to start case-volunteer coordination, by removing the old direct path.
- Design spec: `docs/superpowers/specs/2026-09-12-masked-group-chats-design.md` §7 (retirement policy) and §13 point 4 (phasing). Read before starting if anything below is unclear — do not guess past it.

---

### Task 1: Refuse new `kind='direct'` thread creation

**Files:**
- Modify: `backend/internal/chat/chat.go`
- Modify: `backend/internal/handlers/chat.go`
- Test: `backend/internal/chat/chat_test.go` (or wherever this package's existing tests live — check first)

**Interfaces:**
- Consumes: nothing new.
- Produces: `chat.ErrDirectChatRetired` (new sentinel) — Task 2 and any later task do NOT need this, it's used only by the one call site this task changes.

- [ ] **Step 1: Write the failing test**

Find this package's existing test file (likely `backend/internal/chat/chat_test.go` — check with `ls backend/internal/chat/*_test.go`; if none exists, create one following the `TEST_DATABASE_URL`-gated pattern used throughout this codebase, e.g. `backend/internal/chatgroups/chatgroups_test.go`'s `newTestPool` helper as a model). Add:

```go
func TestRequestThreadRefusesNewDirectChat(t *testing.T) {
	pool := newTestPool(t) // use this package's existing test-pool helper
	s := New(pool)
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")

	_, _, _, err := s.RequestThread(context.Background(), donor, owner, nil, donor)
	if !errors.Is(err, ErrDirectChatRetired) {
		t.Fatalf("err = %v, want ErrDirectChatRetired", err)
	}

	var count int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM chat_threads WHERE donor_user_id = $1 AND owner_user_id = $2`,
		donor, owner).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected no row inserted, got %d", count)
	}
}
```

Adjust `makeTestUser`/`newTestPool` to whatever this package's actual existing test helpers are named — read the existing test file (or `internal/chatgroups/chatgroups_test.go` as a model of this codebase's `TEST_DATABASE_URL`-gated pattern) before writing this, do not invent helper names.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' go test ./internal/chat/ -run TestRequestThreadRefusesNewDirectChat -v
```
Expected: FAIL — compile error, `ErrDirectChatRetired` undefined.

- [ ] **Step 3: Add the sentinel and the guard**

In `backend/internal/chat/chat.go`, add to the existing `var (...)` sentinel block (around line 33-39):

```go
var (
	ErrNotFound          = errors.New("thread not found")
	ErrNotParty          = errors.New("you are not a participant in this chat")
	ErrNotRecipient      = errors.New("only the invited party can accept or decline")
	ErrNotActive         = errors.New("this chat is not active yet")
	ErrAlreadyClaimed    = errors.New("this chat is already claimed by another staff member")
	ErrDirectChatRetired = errors.New("direct donor-owner chat has been retired; use a staff-mediated connect request instead")
)
```

Then change `RequestThread`'s signature line (currently `func (s *Store) RequestThread(ctx context.Context, donorID, ownerID int64, campaignID *int64, initiatorID int64) (Thread, int64, bool, error) {`) so the VERY FIRST line of the function body is:

```go
func (s *Store) RequestThread(ctx context.Context, donorID, ownerID int64, campaignID *int64, initiatorID int64) (Thread, int64, bool, error) {
	var t Thread
	return t, 0, false, ErrDirectChatRetired
}
```

Delete everything else that was in the function body (the transaction, the SELECT/INSERT/UPDATE logic) — it is now unreachable. `RequestSupportThread` (a separate function, further down the file) is untouched.

- [ ] **Step 4: Run test to verify it passes**

```bash
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' go test ./internal/chat/ -run TestRequestThreadRefusesNewDirectChat -v
```
Expected: PASS.

- [ ] **Step 5: Update the HTTP handler to map the new error to a clean response**

In `backend/internal/handlers/chat.go`, `Request` (around line 94-177), change the error-handling block:

```go
	thread, recipient, isNew, err := h.Store.RequestThread(c.Request.Context(), donorID, ownerID, campaignID, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
```
to:
```go
	thread, recipient, isNew, err := h.Store.RequestThread(c.Request.Context(), donorID, ownerID, campaignID, user.UserID)
	if err != nil {
		if errors.Is(err, chat.ErrDirectChatRetired) {
			c.JSON(http.StatusGone, gin.H{"success": false, "error": "Direct messaging has been retired. Ask staff to connect you instead."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
```
Add `"errors"` to this file's imports if not already present (check first — this file likely already imports it for other error checks; grep `errors\.` in the file before adding a duplicate import).

Also, since the function now always returns this error and everything below it (the `isNew` notification block, response JSON) is unreachable in practice, LEAVE that dead code in place for this task — do not restructure the handler further; a later cleanup is out of scope here. The important behavior (no new thread created, clean error) is what Step 3 and this step deliver.

- [ ] **Step 6: Add an HTTP-level test**

In `backend/internal/handlers/chat_test.go` (check this file exists first; it should, given other chat routes are already tested there), add:

```go
func TestChatRequest_RefusesNewDirectChat(t *testing.T) {
	pool := newChatTestPool(t) // use this file's existing test-pool helper name
	r, _ := newChatRouter(pool) // use this file's existing router-helper name
	donor := makeChatTestUser(t, pool, "Donor")
	owner := makeChatTestUser(t, pool, "Owner")
	campaignID := makeChatTestCampaign(t, pool, owner)
	token := tokenForChatTestUser(t, pool, donor)

	code, body := postAs(t, r, token, "/api/chats/request", map[string]any{
		"donor_user_id": donor,
		"campaign_id":   campaignID,
	})
	if code != http.StatusGone {
		t.Fatalf("status = %d, want 410 (body %v)", code, body)
	}
}
```
Read `backend/internal/handlers/chat_test.go` first and adjust every helper name (`newChatTestPool`, `newChatRouter`, `makeChatTestUser`, `makeChatTestCampaign`, `tokenForChatTestUser`, `postAs`) to whatever actually exists in that file or a shared test-helpers file in the same package — do not invent names; this package already has extensive existing tests for `/chats/*` routes to model this on.

- [ ] **Step 7: Run both new tests, then the whole package, then commit**

```bash
cd backend
createdb godonation_phase4_task1_verify
TEST_DATABASE_URL='postgres://localhost:5432/godonation_phase4_task1_verify?sslmode=disable' go test ./internal/chat/... ./internal/handlers/... -count=1 -v 2>&1 | tail -100
dropdb godonation_phase4_task1_verify
```
Expected: `TestRequestThreadRefusesNewDirectChat` and `TestChatRequest_RefusesNewDirectChat` PASS, zero FAIL lines package-wide. Also run `go build ./...`, `go vet ./...`, `gofmt -l internal/chat internal/handlers`.

```bash
git add internal/chat/chat.go internal/chat/*_test.go internal/handlers/chat.go internal/handlers/chat_test.go
git commit -m "feat(chat): refuse new direct donor-owner chat requests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Bulk end+archive every existing open `kind='direct'` thread

**Files:**
- Create: `backend/cmd/retire-direct-chats/main.go` (a one-off ops binary, matching this codebase's `cmd/` convention — check `backend/cmd/` for an existing similar one-off script to model the `package main` boilerplate and DB-connection setup on, e.g. how `cmd/server/main.go` reads its DB DSN from env)
- Test: `backend/internal/chatlifecycle/retire_direct_test.go` — tests the underlying bulk-transition LOGIC as an importable function, not the `cmd/` binary itself (Go doesn't unit-test `package main` binaries directly; put the real logic in a small exported function `chatlifecycle` or a new tiny package `backend/internal/chatlifecycle/retire.go` can hold, and have `cmd/retire-direct-chats/main.go` just call it)

**Interfaces:**
- Consumes: `chatlifecycle.Apply(ctx, pool, chatlifecycle.KindDonor, threadID, chatlifecycle.ActionEnd, reason, actorID)` and the same with `chatlifecycle.ActionArchive` — both already exist, confirmed in `backend/internal/chatlifecycle/chatlifecycle.go`.
- Produces: `chatlifecycle.RetireAllDirectThreads(ctx context.Context, pool *pgxpool.Pool, actorID int64) (int, error)` — returns the count of threads transitioned, for the `cmd/` binary to print. Nothing later in this plan consumes this function.

**Design decision (already made — do not re-litigate):** sweep every `chat_threads` row `WHERE kind = 'direct' AND lifecycle = 'open'`, regardless of `status` (pending/active/declined all default to `lifecycle='open'` per migration 118 — confirmed in Phase 4's research). This uniformly closes every non-ended direct thread rather than leaving pending/declined ones in a half-open state. `actorID` is a caller-supplied placeholder (this is an ops script, not a request-driven action) — the `cmd/` binary takes it as a required CLI flag/arg (a real staff/admin user id) so `lifecycle_changed_by` is a valid, attributable value, never a hardcoded `0` or `-1`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/chatlifecycle/retire_direct_test.go`:

```go
package chatlifecycle

import (
	"context"
	"testing"
)

func TestRetireAllDirectThreadsEndsAndArchivesOpenDirectThreads(t *testing.T) {
	pool := newTestPool(t) // this package's existing TEST_DATABASE_URL-gated helper — check chatlifecycle's existing tests for the exact name
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")

	var directID, supportID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $2, 'active', $1, 'direct') RETURNING id`, donor, owner).Scan(&directID); err != nil {
		t.Fatalf("insert direct: %v", err)
	}
	if err := pool.QueryRow(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $1, 'active', $1, 'support') RETURNING id`, donor).Scan(&supportID); err != nil {
		t.Fatalf("insert support: %v", err)
	}

	count, err := RetireAllDirectThreads(ctx, pool, staff)
	if err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	if count != 1 {
		t.Fatalf("count = %d, want 1 (only the direct thread)", count)
	}

	var directLifecycle string
	var directArchivedAt *string
	if err := pool.QueryRow(ctx, `SELECT lifecycle, archived_at::text FROM chat_threads WHERE id = $1`, directID).
		Scan(&directLifecycle, &directArchivedAt); err != nil {
		t.Fatalf("query direct: %v", err)
	}
	if directLifecycle != "ended" || directArchivedAt == nil {
		t.Fatalf("direct thread = lifecycle=%q archived_at=%v, want ended + archived", directLifecycle, directArchivedAt)
	}

	var supportLifecycle string
	if err := pool.QueryRow(ctx, `SELECT lifecycle FROM chat_threads WHERE id = $1`, supportID).Scan(&supportLifecycle); err != nil {
		t.Fatalf("query support: %v", err)
	}
	if supportLifecycle != "open" {
		t.Fatalf("support thread lifecycle = %q, want unchanged (open)", supportLifecycle)
	}
}

func TestRetireAllDirectThreadsIsIdempotent(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")
	if _, err := pool.Exec(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $2, 'active', $1, 'direct')`, donor, owner); err != nil {
		t.Fatalf("insert: %v", err)
	}

	if _, err := RetireAllDirectThreads(ctx, pool, staff); err != nil {
		t.Fatalf("first run: %v", err)
	}
	count, err := RetireAllDirectThreads(ctx, pool, staff)
	if err != nil {
		t.Fatalf("second run: %v", err)
	}
	if count != 0 {
		t.Fatalf("second run count = %d, want 0 (already ended+archived, lifecycle != 'open')", count)
	}
}
```
Check `chatlifecycle`'s existing test file(s) for the actual `newTestPool`/`makeTestUser` helper names before using them — adjust to match.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' go test ./internal/chatlifecycle/ -run TestRetireAllDirectThreads -v
```
Expected: FAIL — `RetireAllDirectThreads` undefined.

- [ ] **Step 3: Implement `RetireAllDirectThreads`**

Create `backend/internal/chatlifecycle/retire.go`:

```go
package chatlifecycle

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// RetireAllDirectThreads transitions every currently-open kind='direct'
// chat_threads row through end then archive, in one pass. Idempotent: a
// thread already ended (lifecycle != 'open') is skipped on a re-run, so this
// is safe to run more than once. Part of OPOS #25284 Phase 4's retirement of
// the old donor<->owner direct chat — kind='support' rows are never selected
// here and are left untouched.
func RetireAllDirectThreads(ctx context.Context, pool *pgxpool.Pool, actorID int64) (int, error) {
	rows, err := pool.Query(ctx, `SELECT id FROM chat_threads WHERE kind = 'direct' AND lifecycle = 'open'`)
	if err != nil {
		return 0, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	const reason = "OPOS #25284 Phase 4 — direct donor-owner chat retired"
	for _, id := range ids {
		if _, err := Apply(ctx, pool, KindDonor, id, ActionEnd, reason, actorID); err != nil {
			return 0, err
		}
		if _, err := Apply(ctx, pool, KindDonor, id, ActionArchive, reason, actorID); err != nil {
			return 0, err
		}
	}
	return len(ids), nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' go test ./internal/chatlifecycle/ -run TestRetireAllDirectThreads -v
```
Expected: both new tests PASS.

- [ ] **Step 5: Write the one-off `cmd/` binary**

First run `ls backend/cmd/` to see this codebase's actual existing one-off-script convention (there should be at least one non-`server` binary under `cmd/` — model this file's DB-connection bootstrap on whatever pattern it uses, likely reading `DATABASE_URL` from the environment via the same helper `cmd/server/main.go` uses). Create `backend/cmd/retire-direct-chats/main.go`:

```go
// Command retire-direct-chats is a one-off ops script for OPOS #25284 Phase 4:
// ends and archives every existing open kind='direct' chat_threads row, now
// that new direct-chat creation is refused server-side (see
// internal/chat.Store.RequestThread). Safe to re-run — already-ended threads
// are skipped. Usage:
//
//	go run ./cmd/retire-direct-chats -actor=<staff_user_id>
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

func main() {
	actor := flag.Int64("actor", 0, "staff/admin user id to attribute this bulk action to (required)")
	flag.Parse()
	if *actor <= 0 {
		log.Fatal("retire-direct-chats: -actor=<staff_user_id> is required")
	}

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("retire-direct-chats: DATABASE_URL is required")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatalf("retire-direct-chats: connect: %v", err)
	}
	defer pool.Close()

	count, err := chatlifecycle.RetireAllDirectThreads(context.Background(), pool, *actor)
	if err != nil {
		log.Fatalf("retire-direct-chats: %v", err)
	}
	fmt.Printf("retire-direct-chats: ended+archived %d thread(s)\n", count)
}
```
Check the exact env var name `cmd/server/main.go` reads for its Postgres DSN (it may not be literally `DATABASE_URL` — grep `os.Getenv` in `cmd/server/main.go` and use the SAME name here, so this script connects to the same database with the same configuration convention).

- [ ] **Step 6: Verify it builds, run the full test suite, commit**

```bash
cd backend
go build ./...
go vet ./...
gofmt -l internal/chatlifecycle cmd/retire-direct-chats
createdb godonation_phase4_task2_verify
TEST_DATABASE_URL='postgres://localhost:5432/godonation_phase4_task2_verify?sslmode=disable' go test ./internal/chatlifecycle/... -count=1 -v 2>&1 | tail -60
dropdb godonation_phase4_task2_verify
```
Expected: build clean, both new tests PASS, zero FAIL lines.

```bash
git add internal/chatlifecycle/retire.go internal/chatlifecycle/retire_direct_test.go cmd/retire-direct-chats/main.go
git commit -m "feat(chatlifecycle): add RetireAllDirectThreads + one-off retirement script

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

**Note for the controller (not a task step):** running this script against the real production database is a deploy-time action, out of scope for this plan (which only ships the capability) — do not run `go run ./cmd/retire-direct-chats` against any real data; the tests above are the only execution of this logic in this plan.

---

### Task 3: Retire `casevolchat` — remove its HTTP surface, routes, and every creation call site

**Files:**
- Modify: `backend/internal/casevolchat/casevolchat.go` — trim to `Store`, `New`, `MessageCountForSignup` only; delete every other method (`EnsureThreadForSignup`, `GetThread`, `ClaimThread`, `ReleaseThread`, `ListThreadsForUser`, `ListMessagesForViewer`, `ListMessages`, `PostMessage`, `MarkRead`, `ListAllThreads`, `AdminListMessages`) and their supporting types (`Thread`, `ThreadView`, `Message`, `AdminThreadView` — check which of these `MessageCountForSignup`'s own signature and imports still need; keep only what's referenced).
- Delete: `backend/internal/handlers/case_volunteer_chat.go` (the whole file — `List`, `Messages`, `PostMessage`, `AdminList`, `AdminMessages`, `AdminPostMessage`, `AdminClaim`, `AdminRelease`, and the `CaseVolunteerChatHandler` type all go).
- Modify: `backend/internal/handlers/admin_status.go` — delete the free function `ensureCaseVolChat` (currently at line 1184-~1200) and its two call sites (currently at lines 1179 and 1259).
- Modify: `backend/internal/handlers/volunteer_checkin.go` — delete the two `ensureCaseVolChat(...)` call sites (currently lines 83 and 138), and the now-unused `CaseVolChat *casevolchat.Store` field (line 28) + its constructor parameter (`NewVolunteerCheckinHandler`, line 32-33) + the `casevolchat` import (line 10). Every call site that constructs a `VolunteerCheckinHandler` (check `main.go`) must drop the now-removed argument.
- Modify: `backend/cmd/server/main.go` — delete: the 8 `case-chats`/`admin/case-chats` route registrations (currently lines ~813-816 mobile, ~1054-1055 lifecycle/delete, ~1076-1080 admin CRUD — re-confirm exact current line numbers before editing, this file has shifted since the research pass), the `caseVolChatH` handler construction, and update every caller that currently passes `caseVolChatStore`/`caseVolChatH` as an argument to another handler's constructor (`NewVolunteerCheckinHandler`, `NewAdminStatusHandler`) to match those handlers' now-changed signatures from the two bullets above. `caseVolChatStore := casevolchat.New(pool)` itself STAYS (still needed to construct `AdminStatusHandler` for `MessageCountForSignup`'s use via `admin_delete.go` — check whether `admin_delete.go` constructs its own `casevolchat.New(h.Pool)` inline (per the Phase 4 research: `casevolchat.New(h.Pool).MessageCountForSignup(...)` at `admin_delete.go:521` constructs its own instance inline, not via a shared field) — if so, `main.go`'s top-level `caseVolChatStore` variable may become entirely unused once `NewAdminStatusHandler`/`NewVolunteerCheckinHandler` no longer take it; delete the variable too if `go build` flags it unused).
- Modify: `backend/internal/chatlifecycle/chatlifecycle.go` — remove `KindCase` from the `Systems()` slice (line ~185: `return []System{systems[KindDonor], systems[KindMarriage], systems[KindStaff], systems[KindCase], systems[KindGroup]}` → drop `systems[KindCase]`). Leave the `KindCase` constant and its `systems[KindCase]` map entry defined (harmless if unused, and `admin_delete.go`'s historical data may still reference `case_volunteer_chat_threads` conceptually) — only `Systems()`'s returned slice changes, since that's the actively-iterated registry (per spec §8).
- Modify: `backend/internal/handlers/chat_lifecycle_fixtures_test.go`, `backend/internal/handlers/chat_lifecycle_test.go`, `backend/internal/handlers/chat_lifecycle_trash_test.go` — these three files enumerate `chatlifecycle.Kind` values by name (confirmed present by Phase 4's research, per spec §8's own callout); read each one, find every place it builds/asserts against a `KindCase` fixture as part of an "all systems" loop, and remove that fixture — but do NOT remove `KindCase`-specific assertions if a test is deliberately testing `case_volunteer_chat_threads` lifecycle behavior UNRELATED to whether it's in `Systems()` (read carefully before deleting; if genuinely unsure whether a specific assertion is safe to remove, leave it and flag it in your report rather than guessing).
- Modify: `backend/internal/handlers/admin_signup_delete_chat_guard_test.go` — this test presumably exercises `admin_delete.go`'s `MessageCountForSignup` guard; read it and confirm it still compiles/passes against the trimmed `casevolchat.go` (it should, since `MessageCountForSignup` itself is unchanged) — fix only if it breaks.
- Do NOT modify: `backend/internal/deleteguard/deleteguard.go` — its SQL block counting `case_volunteer_chat_messages`/`case_volunteer_chat_threads` (line ~108-114) queries the TABLES directly, not the Go package, and those tables still exist with their historical rows (per this plan's Global Constraints — no DROP TABLE), so this code stays valid and correct. Leave it untouched; do not attempt to add chat-groups awareness here either — that gap is a separate, pre-existing, out-of-scope item per spec §8.

**Interfaces:**
- Consumes: `chatlifecycle.Systems()` (Task-independent, already exists).
- Produces: nothing new — this task only removes.

- [ ] **Step 1: Read every file listed above in full before changing anything**

This task is almost entirely deletion across many files with real cross-file dependencies (confirmed by Phase 4's research: `admin_status.go` and `volunteer_checkin.go` both call into `casevolchat` for side-effect thread creation on signup/check-in status changes, and `admin_delete.go` depends on the one method that must survive). Read `backend/internal/casevolchat/casevolchat.go`, `backend/internal/handlers/case_volunteer_chat.go`, `backend/internal/handlers/admin_status.go` (search `casevolchat`/`CaseVolChat`/`ensureCaseVolChat`), `backend/internal/handlers/volunteer_checkin.go`, `backend/internal/handlers/admin_delete.go` (search `casevolchat`), `backend/cmd/server/main.go` (search `casevolchat`/`caseVolChat`), and `backend/internal/chatlifecycle/chatlifecycle.go` in full before editing any of them — do not work from this brief's line-number citations alone, they were captured during research and may have shifted.

- [ ] **Step 2: Trim `casevolchat.go`**

Delete every method except `New` and `MessageCountForSignup`, and every type not needed by the code that remains. Verify with `grep -n "func\|^type" backend/internal/casevolchat/casevolchat.go` after trimming that only `Store`, `New`, and `MessageCountForSignup` (plus whatever unexported helper types/queries `MessageCountForSignup` itself needs) remain.

- [ ] **Step 3: Delete `case_volunteer_chat.go` and its routes**

Delete `backend/internal/handlers/case_volunteer_chat.go` entirely. In `main.go`, delete every route registration this file's handlers were wired to (the mobile `case-chats` group and the admin `case-chats`/`case-chats/:id/claim`/`release`/`lifecycle` group — the lifecycle+delete routes at `perm("volunteers",...)` using `chatLifecycleH.Apply(chatlifecycle.KindCase)`/`chatLifecycleH.Delete(chatlifecycle.KindCase)` should also be deleted here, since there's no more UI/handler surface driving them and `KindCase` is leaving `Systems()` in Step 6 below).

- [ ] **Step 4: Remove the `ensureCaseVolChat` call sites**

In `admin_status.go`: delete the `ensureCaseVolChat` free function and both its call sites. In `volunteer_checkin.go`: delete both call sites, the `CaseVolChat` field, the constructor parameter, and the now-unused `casevolchat` import.

- [ ] **Step 5: Fix every constructor call site in `main.go`**

`NewAdminStatusHandler` and `NewVolunteerCheckinHandler` no longer take a `*casevolchat.Store` argument — update their call sites in `main.go` to match the new signatures. Run `go build ./...` repeatedly as you go; the compiler will find every remaining call site that needs updating faster than a manual search.

- [ ] **Step 6: Drop `KindCase` from `Systems()`**

In `chatlifecycle.go`, change the `Systems()` return line to drop `systems[KindCase]`, leaving the constant and map entry defined but unreferenced by the active registry.

- [ ] **Step 7: Fix the three lifecycle test files**

Read `chat_lifecycle_fixtures_test.go`, `chat_lifecycle_test.go`, `chat_lifecycle_trash_test.go` and remove any `KindCase` fixture/assertion that exists only because it was iterating "all systems" — per the file-list note above, leave anything testing case-chat-specific behavior unrelated to `Systems()` membership, and flag genuine uncertainty in your report rather than guessing.

- [ ] **Step 8: Full build, vet, format, and test run**

```bash
cd backend
go build ./...
go vet ./...
gofmt -l internal/casevolchat internal/handlers internal/chatlifecycle cmd
createdb godonation_phase4_task3_verify
TEST_DATABASE_URL='postgres://localhost:5432/godonation_phase4_task3_verify?sslmode=disable' go test ./... -count=1 -p 1 2>&1 | tail -100
dropdb godonation_phase4_task3_verify
```
Expected: build clean, zero FAIL lines across the ENTIRE backend (not just the touched packages — this task removes cross-package wiring, so a full-suite run is required to catch any missed reference). Use `-p 1` (serialized) per this codebase's documented shared-test-DB flake mode.

- [ ] **Step 9: Commit**

```bash
git add internal/casevolchat/casevolchat.go internal/handlers/admin_status.go internal/handlers/volunteer_checkin.go internal/chatlifecycle/chatlifecycle.go cmd/server/main.go internal/handlers/chat_lifecycle_fixtures_test.go internal/handlers/chat_lifecycle_test.go internal/handlers/chat_lifecycle_trash_test.go
git rm internal/handlers/case_volunteer_chat.go
git commit -m "feat(casevolchat): retire direct volunteer-beneficiary messaging entirely

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(Adjust the exact file list to whatever you actually touched, including `internal/handlers/case_volunteer_chat_test.go` if such a file exists and needs deleting too — check for it in Step 1.)

---

### Task 4: Flutter — remove donor/owner direct-chat entry points and all casevolchat UI

**Files:**
- Modify: `humanitarian/lib/modules/chat/chat_actions.dart` — delete `ChatActions.startChat` entirely (keep `startSupportChat` untouched).
- Modify: `humanitarian/lib/modules/donations/screens/my_donations_page.dart` — delete `_chatWithOwner` and the "Chat with campaign owner" `FilledButton.icon` (and the `canChat` variable if nothing else in this file uses it — check first) that calls it.
- Modify: `humanitarian/lib/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart` — delete `_suggestChat`, the `InkWell(onTap: canChat ? () => _suggestChat(context) : null, ...)` wiring, and the `canChat` computation (check first whether `canChat` or the row's other properties are used elsewhere in this file before deleting more than the chat-specific wiring).
- Delete: `humanitarian/lib/modules/chat/screens/case_chat_conversation_screen.dart` (the whole file).
- Modify: `humanitarian/lib/modules/chat/screens/messages_screen.dart` — delete `_CaseChatsSection` and `_CaseChatTile` (both private widgets in this file) and whatever renders `_CaseChatsSection` in the main screen body.
- Modify: `humanitarian/lib/api/module_api.dart` — delete `caseChats()`, `caseChatMessages(int threadId)`, `sendCaseChatMessage(int threadId, String body)`.
- Modify: `humanitarian/lib/api/links.dart` — delete the `caseChatsUrl` constant.
- Modify: `humanitarian/lib/localization/app_translations.dart` — search for `case_chats_label` and any other case-chat-specific keys (grep `case_chat` case-insensitively across this file) and remove them from all 4 locale blocks — but ONLY keys that become genuinely unused after the above deletions; grep the rest of `lib/` first to confirm no other screen still references a given key before removing it.

**Interfaces:**
- Consumes: nothing from earlier tasks (this is a pure client-side removal; the backend routes it called are already gone per Task 3, so these Flutter call sites would 404 if left in place — that's exactly why they're being removed here, not because of any Dart-level type dependency on Task 3).
- Produces: nothing — no later task needs anything from this one.

- [ ] **Step 1: Read every file listed above in full before changing anything**

Same caution as Task 3 — these are UI files with real internal references between the pieces you're deleting and pieces that stay (e.g. `_chatWithOwner`'s surrounding `_DonationDetailSheet` widget has other, unrelated buttons that must be left intact).

- [ ] **Step 2: Delete `ChatActions.startChat`**

In `chat_actions.dart`, delete the entire `startChat` static method (confirmed by Phase 4's research to have no internal branch that isn't donor/owner-specific — the whole function goes). `startSupportChat` stays completely unchanged.

- [ ] **Step 3: Remove the "Chat with campaign owner" entry point**

In `my_donations_page.dart`, delete `_chatWithOwner` and its calling button. If `canChat` (currently `item.campaignId != null && item.id != null`) is used ONLY to gate this button, delete it too; if the surrounding widget uses it for anything else, leave it and just remove the button + method.

- [ ] **Step 4: Remove the donor-suggestion entry point**

In `beneficiary_campaign_donations_screen.dart`, delete `_suggestChat` and its `InkWell` wiring. If the row becomes non-interactive as a result (no other `onTap` on that widget), that's expected — this whole row's interactivity WAS the chat entry point per the research; do not invent a replacement interaction.

- [ ] **Step 5: Delete the casevolchat conversation screen**

`git rm humanitarian/lib/modules/chat/screens/case_chat_conversation_screen.dart` — nothing else in the plan needs this file.

- [ ] **Step 6: Remove the case-chats section from the Messages tab**

In `messages_screen.dart`, delete `_CaseChatsSection`, `_CaseChatTile`, and wherever the main screen widget currently renders `_CaseChatsSection` in its build method (a `ListView`/`Column` entry — remove that entry, not the whole surrounding list, since other message-channel sections — masked groups, support, marriage — stay).

- [ ] **Step 7: Remove the API client methods and URL constant**

Delete `caseChats()`, `caseChatMessages`, `sendCaseChatMessage` from `module_api.dart`, and `caseChatsUrl` from `links.dart`.

- [ ] **Step 8: Clean up now-orphaned localization keys**

Grep `case_chat` (case-insensitive) across `app_translations.dart` AND the rest of `lib/` (to confirm no remaining reference) before deleting each match from all 4 locale blocks — matching this project's translation-completeness convention (never leave a stray, unused-but-present key is fine to leave actually; the risk here is the OPPOSITE — don't delete a key still referenced elsewhere by mistake, so the "check the rest of lib/ first" step is the one that matters, not leaving orphaned keys, which is harmless).

- [ ] **Step 9: Analyze and verify**

```bash
cd humanitarian
flutter pub get
flutter analyze
```
Expected: clean (or only the same pre-existing, unrelated info-level notices already present on this branch before this task — compare against a `flutter analyze` run on the branch tip before this task's changes if anything new shows up, to distinguish a real regression from noise).

- [ ] **Step 10: Commit**

```bash
git add lib/modules/chat/chat_actions.dart lib/modules/donations/screens/my_donations_page.dart lib/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart lib/modules/chat/screens/messages_screen.dart lib/api/module_api.dart lib/api/links.dart lib/localization/app_translations.dart
git rm lib/modules/chat/screens/case_chat_conversation_screen.dart
git commit -m "feat(chat): remove donor-owner direct chat and casevolchat UI entry points

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(Run this from `humanitarian/` or adjust paths to be relative to the repo root, matching how other commits in this session's history were staged — check with `git status` first.)

---

### Task 5: Admin-web — remove the casevolchat oversight page and its nav entry

**Files:**
- Delete: `admin-web/src/pages/CaseVolunteerChatsPage.tsx`
- Modify: `admin-web/src/lib/navLayout.ts` — remove the `/case-volunteer-chats` nav item (`{ to: '/case-volunteer-chats', tKey: 'nav.case_volunteer_chats', module: 'volunteers' }`) and its reference in the grouping array (both locations confirmed present by Phase 4's research — search `case-volunteer-chats` in this file to find both).
- Modify: `admin-web/src/App.tsx` (or wherever this project's route table lives — check `App.tsx` first, following this project's existing lazy-route convention per this project's CMS-clone pattern) — remove the route entry for `CaseVolunteerChatsPage`.
- Modify: locale files under `admin-web/src/lib/locales/` (`en.ts`, `ar.ts`, `ckb.ts`, `kmr.ts` or however this project's admin-web locale files are actually named — check first) — remove the now-orphaned `nav.case_volunteer_chats` key from each, after confirming (grep) nothing else references it.
- Leave `admin-web/src/pages/MessagesPage.tsx` untouched — it already handles `kind='direct'` as one of its two modes and naturally becomes a read-only historical view once the backend stops creating new direct threads (Task 1) and archives the old ones (Task 2); no code change needed there per this plan's Global Constraints.

**Interfaces:**
- Consumes: nothing from earlier tasks (admin-web is a separate app from the Go backend and Flutter mobile app; this task only needs Task 3's backend routes to already be gone so the deleted page isn't calling dead endpoints — sequence this task after Task 3, not before).
- Produces: nothing.

- [ ] **Step 1: Read `navLayout.ts`, `App.tsx`, and the locale files in full before editing**

- [ ] **Step 2: Delete the page**

`git rm admin-web/src/pages/CaseVolunteerChatsPage.tsx`

- [ ] **Step 3: Remove the nav entry and route**

Delete both `case-volunteer-chats` references in `navLayout.ts`, and the corresponding route registration in `App.tsx`.

- [ ] **Step 4: Remove the orphaned locale key**

Grep `case_volunteer_chats` across all of `admin-web/src/` to confirm no remaining reference, then delete the key from every locale file.

- [ ] **Step 5: Build and typecheck**

```bash
cd admin-web
npm install
npx tsc --noEmit
npm run build
```
Expected: clean, per this project's standard admin-web gate.

- [ ] **Step 6: Commit**

```bash
git add src/lib/navLayout.ts src/App.tsx src/lib/locales/
git rm src/pages/CaseVolunteerChatsPage.tsx
git commit -m "feat(admin-web): remove case-volunteer-chats oversight page

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Explicitly out of scope

- Running `cmd/retire-direct-chats` against any real/production database — this plan ships the capability, not the deploy action.
- `deleteguard.go`'s pre-existing gap (missing chat-groups awareness) — a separate, already-flagged checklist item per spec §8, unrelated to this phase's retirement work.
- Phases 5-6 of OPOS #25284 (Flutter and admin-web clients for the NEW `chatgroups` system) — separate plans.
- Merging or touching the `fix/messaging-channels-reachable` branch in any way.
