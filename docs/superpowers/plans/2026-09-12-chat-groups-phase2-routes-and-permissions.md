# Chat Groups Phase 2 — Routes, Permissions, Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Phase 1's `internal/chatgroups` Store over HTTP — mobile and admin routes, permission gates, `chatlifecycle` registration, contact-info filtering, and push notifications — with zero client-visible change to any existing chat surface.

**Architecture:** Follow `internal/handlers/chat.go`'s existing shape exactly: one `ChatGroupHandler` struct (split mobile/admin across two files from the start, since a single-file version of an equivalent handler is already over this codebase's 500-line cap), a `chatErr` dispatcher over `chatgroups`'s sentinel errors, routes registered in `cmd/server/main.go` on the existing `authed`/`admin` groups, and `chatlifecycle.KindGroup` added to the existing generic lifecycle/trash machinery.

**Tech Stack:** Go, Gin, pgx/pgxpool, Postgres. No new dependencies.

**Depends on (read, do not re-derive):** `backend/internal/chatgroups/{chatgroups.go,chatgroups_reads.go,chatgroups_connect.go}` (Phase 1, PR #71) and `backend/migrations/120_chat_groups.sql`.

## Global Constraints

- No foreign-key constraints in new/changed `chat_group_*` schema — matches migration 120's own stated convention; existence is validated in the Store.
- Every mobile write route requires `auth.RequireNotGuest()` in addition to the `authed` group's `RequireBearer`+`RequireApproved`, matching every existing mobile chat route.
- Every admin route requires `auth.RequireAdmin(tokenStore)` (the `admin` group's own middleware) plus `perm("messages", <action>)`; the one admin route that reveals real identities inside a masked group (`AdminMessages`) additionally requires `perm("sensitive_data", "view")`.
- JSON envelope is always `gin.H{"success": bool, ...}`, matching every existing handler in this package.
- Error mapping is `errors.Is` against typed sentinels via a `chatErr` dispatcher — never string-matching an error's text.
- `GroupMessage` (masked, non-staff) and `AdminGroupMessage` (staff-only, real identity) must never be reachable from the wrong route — this is Phase 1's core guarantee and Phase 2 must not create a new path around it.
- File-size discipline: split by responsibility (mobile vs. admin vs. contact-filter) the same way Phase 1 split `chatgroups.go`/`chatgroups_reads.go`/`chatgroups_connect.go`.
- Full spec: `docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md`.

---

### Task 1: Register `chatlifecycle.KindGroup`, and fix the hardcoded `thread_id` trash column

**Files:**
- Modify: `backend/internal/chatlifecycle/chatlifecycle.go`
- Modify: `backend/internal/handlers/admin_chat_lifecycle.go`
- Modify: `backend/internal/handlers/chat_lifecycle_fixtures_test.go`
- Modify: `backend/internal/handlers/chat_lifecycle_test.go`
- Test: same two `_test.go` files above (this task extends existing generic, table-driven tests rather than adding new ones)

**Interfaces:**
- Consumes: nothing from later tasks.
- Produces: `chatlifecycle.KindGroup`, usable by `chatLifecycleH.Apply(chatlifecycle.KindGroup)` / `.Delete(chatlifecycle.KindGroup)` in Task 9's route registration. `chatlifecycle.System` gains a `ChildIDColumn string` field, defaulting to `"thread_id"` for every existing system.

This task has two parts. Part A is the registration itself. Part B is a real bug this plan's research found: `admin_chat_lifecycle.go`'s trash-snapshot query hardcodes the child-table foreign key column name as `thread_id`, but every `chat_group_*` child table uses `group_id`. Registering `KindGroup` without fixing this would make `DELETE /admin/chat-groups/:id` crash with `column "thread_id" does not exist` the moment a group has any messages. Fix both in the same task since the fix is what makes the registration actually safe to ship.

- [ ] **Step 1: Add `ChildIDColumn` to `chatlifecycle.System` and the four existing entries**

In `backend/internal/chatlifecycle/chatlifecycle.go`, change the `System` struct (currently around line 92-108):

```go
// System describes one chat system's tables. Every string in here is a
// compile-time literal — see the note on Kind.
type System struct {
	// Kind is the URL-facing name of this system.
	Kind Kind
	// ThreadTable holds the thread rows carrying the lifecycle columns.
	ThreadTable string
	// MessageTable and ReadTable are the FK children that would be silently
	// cascaded away by a delete. They are snapshotted alongside the thread so
	// a restore brings back a conversation rather than an empty shell — see
	// TrashThreadWithChildren.
	MessageTable string
	ReadTable    string
	// ExtraChildTables are further cascade children to preserve. Only the
	// donor chat has one today (the K19 blocked-contact supervision log).
	ExtraChildTables []string
	// ChildIDColumn is the foreign-key column name every child table (message,
	// read, and extra tables) uses to reference ThreadTable's id. Every system
	// through chat groups used "thread_id"; chat groups uses "group_id"
	// instead, so this is a per-system value rather than a hardcoded literal
	// in the trash/restore snapshot query.
	ChildIDColumn string
}
```

Then update every entry in the `systems` map to set `ChildIDColumn: "thread_id"` explicitly (do not rely on a zero-value default reading as "thread_id" — write it out, so a future reader sees the value rather than inferring it from an empty string):

```go
var systems = map[Kind]System{
	KindDonor: {
		Kind:          KindDonor,
		ThreadTable:   "chat_threads",
		MessageTable:  "chat_messages",
		ReadTable:     "chat_reads",
		ExtraChildTables: []string{"chat_contact_blocks"},
		ChildIDColumn: "thread_id",
	},
	KindMarriage: {
		Kind:          KindMarriage,
		ThreadTable:   "marriage_chat_threads",
		MessageTable:  "marriage_chat_messages",
		ReadTable:     "marriage_chat_reads",
		ChildIDColumn: "thread_id",
	},
	KindStaff: {
		Kind:          KindStaff,
		ThreadTable:   "staff_chat_threads",
		MessageTable:  "staff_chat_messages",
		ReadTable:     "staff_chat_reads",
		ChildIDColumn: "thread_id",
	},
	KindCase: {
		Kind:          KindCase,
		ThreadTable:   "case_volunteer_chat_threads",
		MessageTable:  "case_volunteer_chat_messages",
		ReadTable:     "case_volunteer_chat_reads",
		ChildIDColumn: "thread_id",
	},
	KindGroup: {
		Kind:          KindGroup,
		ThreadTable:   "chat_group_threads",
		MessageTable:  "chat_group_messages",
		ReadTable:     "chat_group_reads",
		ExtraChildTables: []string{"chat_group_contact_blocks", "chat_group_staff_notes"},
		ChildIDColumn: "group_id",
	},
}
```

Add the constant next to the other four, in the existing `const ( KindDonor Kind = "donor" ... )` block:

```go
	KindGroup Kind = "group" // chat_group_threads (120)
```

And update `Systems()` (currently `return []System{systems[KindDonor], systems[KindMarriage], systems[KindStaff], systems[KindCase]}`) to include the fifth:

```go
func Systems() []System {
	// Fixed order so a test or a UI listing is stable rather than map-random.
	return []System{systems[KindDonor], systems[KindMarriage], systems[KindStaff], systems[KindCase], systems[KindGroup]}
}
```

- [ ] **Step 2: Fix the hardcoded `thread_id` in `trashChatThread`**

In `backend/internal/handlers/admin_chat_lifecycle.go`, find (around line 200):

```go
		if err := tx.QueryRow(ctx,
			"SELECT COALESCE(jsonb_agg(to_jsonb(x.*)), '[]'::jsonb) FROM "+child+" x WHERE x.thread_id = $1",
			id).Scan(&rows); err != nil {
```

Change to use the system's own column:

```go
		if err := tx.QueryRow(ctx,
			"SELECT COALESCE(jsonb_agg(to_jsonb(x.*)), '[]'::jsonb) FROM "+child+" x WHERE x."+sys.ChildIDColumn+" = $1",
			id).Scan(&rows); err != nil {
```

`restoreChatChildren` needs no change — it already re-inserts whole rows via `jsonb_populate_recordset` without referencing the FK column by name (confirmed by reading the function in full: it only ever names `sourceTable`/`table`, never a column).

- [ ] **Step 3: Extend the existing generic lifecycle fixture to seed a chat-group thread**

In `backend/internal/handlers/chat_lifecycle_fixtures_test.go`, add a new seeding function alongside `seedDonorChat`/`seedStaffChat`/`seedMarriageChat`/`seedCaseChat` (same file, same pattern — a `chatFixture` value naming the thread/message tables, a sender, and a send path):

```go
func seedGroupChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	ctx := context.Background()
	member := makeLifecycleUser(t, pool, "user")
	staff := makeLifecycleUser(t, pool, "employee")
	var id, memberRowID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_group_threads (kind, created_by_staff_id) VALUES ('masked', $1) RETURNING id`,
		staff).Scan(&id); err != nil {
		t.Fatalf("insert chat group thread: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
		 VALUES ($1, $2, 'donor', true, 'Donor 1', $3) RETURNING id`,
		id, member, staff).Scan(&memberRowID); err != nil {
		t.Fatalf("insert chat group member: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_contact_blocks WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_reads WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_messages WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'chat_group_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
	return chatFixture{chatlifecycle.KindGroup, "chat_group_threads", "chat_group_messages", id, member,
		fmt.Sprintf("/api/chat-groups/%d/messages", id)}
}
```

Add it to `allFixtures`:

```go
func allFixtures(t *testing.T, pool *pgxpool.Pool) []chatFixture {
	return []chatFixture{
		seedDonorChat(t, pool),
		seedMarriageChat(t, pool),
		seedStaffChat(t, pool),
		seedCaseChat(t, pool),
		seedGroupChat(t, pool),
	}
}
```

This one addition automatically extends every existing table-driven test in `chat_lifecycle_test.go` (`TestChatLifecycle_PausedThreadRefusesMessage`, `EndedThreadRefusesMessage`, `OpenThreadStillWorks`, `ResumeRestoresAPausedChat`, `EndedChatCannotBeResumed`, `EndKeepsTheHistory`) to cover chat groups — that is the entire point of `chatlifecycle` being one implementation shared by every system. **This step cannot pass yet** — `allFixtures`'s new `SendPath` (`POST /api/chat-groups/:id/messages`) does not exist as a route until Task 9. Leave `seedGroupChat` and the `allFixtures` addition in this commit (Task 1 is the natural home for the chatlifecycle-side change), but do not run the full lifecycle suite expecting it to pass yet — Task 9 is where `newLifecycleRouter` gains the chat-group routes and this becomes runnable. Note this explicitly in the task's commit message and completion report so the task reviewer does not treat a currently-failing `go test ./internal/handlers/ -run ChatLifecycle` as a regression in *this* task.

- [ ] **Step 4: Register the chat-group routes in the test router and extend the participant-cannot-moderate map**

Also in `chat_lifecycle_fixtures_test.go`'s `newLifecycleRouter`, add (once `ChatGroupHandler` exists — see Task 9; until then, skip this step and come back to it as part of Task 9's own checklist, which references this exact addition):

```go
	admin.POST("/admin/chat-groups/:id/lifecycle", lifeH.Apply(chatlifecycle.KindGroup))
	admin.DELETE("/admin/chat-groups/:id", lifeH.Delete(chatlifecycle.KindGroup))
```

And in `chat_lifecycle_test.go`'s `TestChatLifecycle_ParticipantCannotModerate` (around line 337), add to its `Kind → admin URL pattern` map:

```go
	chatlifecycle.KindGroup: "/api/admin/chat-groups/%d",
```

**Defer both edits in this step to Task 9** (they need `ChatGroupHandler`/its routes to exist and compile) — Task 1 only needs Steps 1-3 to be complete and committed on its own. State this explicitly in Task 1's completion report so nobody looks for these two edits in Task 1's diff.

- [ ] **Step 5: Run the chatlifecycle-adjacent tests that don't depend on chat-group routes**

```bash
cd backend
go build ./...
go vet ./internal/chatlifecycle/... ./internal/handlers/...
go test ./internal/chatlifecycle/... -v
```

`internal/chatlifecycle` has no test file of its own (confirmed: only `internal/handlers/chat_lifecycle_*_test.go` reference it), so the `go test ./internal/chatlifecycle/...` run will report `[no test files]` — that is expected, not a gap; the package's behavior is exercised through the handler-level tests, which this task does not yet make runnable end-to-end (see Step 3).

Run the full `internal/handlers` suite too, expecting the existing four-system lifecycle tests to still pass (they must — this task changed no behavior for the four existing kinds) and the new chat-group subtests inside `TestChatLifecycle_*` to fail with a 404 (no route yet), which is the expected, documented state until Task 9:

```bash
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run TestChatLifecycle -v
```

- [ ] **Step 6: Commit**

```bash
git add internal/chatlifecycle/chatlifecycle.go internal/handlers/admin_chat_lifecycle.go internal/handlers/chat_lifecycle_fixtures_test.go internal/handlers/chat_lifecycle_test.go
git commit -m "feat(chatlifecycle): register KindGroup, fix hardcoded thread_id trash column

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Fix `chat_group_contact_blocks`'s schema

**Files:**
- Create: `backend/migrations/121_chat_group_contact_blocks_fix.sql`
- Test: run the migration against a scratch database (no Go test file — this task is schema-only)

**Interfaces:**
- Consumes: nothing.
- Produces: `chat_group_contact_blocks(id, group_id, sender_user_id, kind, match_count, redacted_body, created_at)` — the exact shape Task 3's `RecordContactBlock`/`ListContactBlocks` methods assume.

Phase 1's migration 120 created `chat_group_contact_blocks` with columns (`message_id BIGINT NOT NULL`, `blocked_user_id`, `reason VARCHAR(64)`) that do not fit this codebase's own "refuse before storing" K19 model (see `chat_contact_block.go`'s doc comment: a blocked message is never stored, so it can never have a `message_id`). The table has zero rows and zero code references anywhere (confirmed: `grep -rn "chat_group_contact_blocks" backend/` outside the migration file itself returns nothing) — it is Phase 1 scaffolding whose shape did not match its own stated purpose, corrected here before its first real use. `internal/chat/contactblocks.go`'s existing `chat_contact_blocks` table is the proven-correct shape to copy.

- [ ] **Step 1: Write the migration**

```sql
-- 121_chat_group_contact_blocks_fix.sql
-- Migration 120 created chat_group_contact_blocks with a shape that does not
-- fit this codebase's "refuse before storing" contact-info filter (see
-- internal/handlers/chat_contact_block.go): a blocked message is never
-- inserted into chat_group_messages, so a NOT NULL message_id could never be
-- populated. The table has no rows and no code references it yet (created in
-- Phase 1 purely as scaffolding "so a later phase needs no migration" — this
-- IS that later phase), so it is safe to drop and recreate with the shape
-- that actually matches chat_contact_blocks, the proven-correct precedent
-- this mirrors.
DROP TABLE IF EXISTS chat_group_contact_blocks;

CREATE TABLE IF NOT EXISTS chat_group_contact_blocks (
  id             BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  group_id       BIGINT    NOT NULL,
  -- Who tried. Never a staff member — the filter does not run on staff (see
  -- internal/handlers/chat_group_contact_block.go).
  sender_user_id INTEGER   NOT NULL,
  -- What was found: 'phone' | 'email' | 'both'. CHECKed in the database, same
  -- as chat_contact_blocks, so a future writer cannot invent a fourth value.
  kind           VARCHAR(8) NOT NULL CHECK (kind IN ('phone', 'email', 'both')),
  match_count    INTEGER   NOT NULL DEFAULT 1 CHECK (match_count > 0),
  redacted_body  TEXT      NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Mirrors idx_chat_contact_blocks_thread's rationale: staff open one group's
-- history ("what has been tried here?"). No sender-scoped index yet since no
-- query needs one (chat_contact_blocks' sender index exists because that
-- table also serves a cross-thread "this sender keeps trying" report that
-- chat groups has no equivalent of yet).
CREATE INDEX IF NOT EXISTS idx_chat_group_contact_blocks_group
  ON chat_group_contact_blocks (group_id, created_at DESC);
```

- [ ] **Step 2: Apply it to a scratch database and verify the shape**

```bash
cd backend
createdb godonation_migration_121_check
TEST_DATABASE_URL='postgres://localhost:5432/godonation_migration_121_check?sslmode=disable' \
  go test ./internal/chatgroups/ -run TestNewStoreConnects -v
psql postgres://localhost:5432/godonation_migration_121_check -c '\d chat_group_contact_blocks'
dropdb godonation_migration_121_check
```

Expected: `\d` shows exactly `id, group_id, sender_user_id, kind, match_count, redacted_body, created_at` with the `kind` CHECK constraint listed, and the test run applies migration 121 with no error (it runs the full migration set as a side effect of connecting).

- [ ] **Step 3: Commit**

```bash
git add migrations/121_chat_group_contact_blocks_fix.sql
git commit -m "fix(chatgroups): correct chat_group_contact_blocks to match the refuse-before-store model

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `chatgroups` Store additions — `GetGroup`, contact-block recording, two error-typing fixes

**Files:**
- Create: `backend/internal/chatgroups/chatgroups_admin.go`
- Modify: `backend/internal/chatgroups/chatgroups.go` (two small error-typing fixes)
- Test: `backend/internal/chatgroups/chatgroups_admin_test.go` (new file)

**Interfaces:**
- Consumes: `chat_group_contact_blocks`'s corrected shape from Task 2.
- Produces:
  - `type GroupMember struct { ID, UserID int64; RoleInGroup string; Masked bool; MaskedLabel string; RemovedAt *time.Time }` (JSON-tagged)
  - `type GroupDetail struct { Group; Members []GroupMember }` (JSON-tagged; `Group` itself gains JSON tags in this task)
  - `func (s *Store) GetGroup(ctx context.Context, groupID int64) (GroupDetail, error)`
  - `type GroupContactBlock struct { ID, GroupID, SenderUserID int64; SenderName *string; Kind string; MatchCount int; RedactedBody string; CreatedAt time.Time }` (JSON-tagged)
  - `func (s *Store) RecordContactBlock(ctx context.Context, groupID, senderUserID int64, kind string, matchCount int, redactedBody string) error`
  - `func (s *Store) ListContactBlocks(ctx context.Context, groupID int64) ([]GroupContactBlock, error)`
  - `CreateGroup`'s invalid-`kind` branch now returns `%w`-wrapped `ErrInvalidInput` instead of a bare `errors.New`.
  - `AddMember`'s group-lookup now maps `pgx.ErrNoRows` to `%w`-wrapped `ErrNotFound` instead of a bare wrapped pgx error.

These four additions/fixes are the minimum the HTTP handlers in Tasks 5-8 need: `GetGroup` for the group-detail admin route, the notification sender-label lookup, and the contact-filter's group-kind check; `RecordContactBlock`/`ListContactBlocks` for the contact-filter's supervision log and its admin read route; the two error-typing fixes so `AdminCreateGroup`/`AdminAddMember` can use `chatErr`'s `errors.Is` dispatch instead of string-matching an error message (the final Phase 1 review flagged both as gaps to close "whenever a real caller needs it" — this is that caller).

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/chatgroups/chatgroups_admin_test.go`:

```go
package chatgroups

import (
	"context"
	"errors"
	"testing"
)

func TestGetGroupReturnsThreadAndMembers(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	detail, err := s.GetGroup(context.Background(), groupID)
	if err != nil {
		t.Fatalf("get group: %v", err)
	}
	if detail.ID != groupID || detail.Kind != KindMasked {
		t.Fatalf("detail = %+v, want ID=%d Kind=masked", detail, groupID)
	}
	if len(detail.Members) != 1 {
		t.Fatalf("got %d members, want 1", len(detail.Members))
	}
	if detail.Members[0].UserID != donor || detail.Members[0].MaskedLabel == "" {
		t.Fatalf("member = %+v, want UserID=%d with a non-empty label", detail.Members[0], donor)
	}
}

func TestGetGroupReturnsErrNotFoundForUnknownGroup(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)

	_, err := s.GetGroup(context.Background(), 999999999)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}

func TestRecordAndListContactBlocks(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	if err := s.RecordContactBlock(context.Background(), groupID, donor, "phone", 1, "call me on •••"); err != nil {
		t.Fatalf("record contact block: %v", err)
	}

	blocks, err := s.ListContactBlocks(context.Background(), groupID)
	if err != nil {
		t.Fatalf("list contact blocks: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks, want 1", len(blocks))
	}
	if blocks[0].Kind != "phone" || blocks[0].MatchCount != 1 {
		t.Fatalf("block = %+v, want Kind=phone MatchCount=1", blocks[0])
	}
	if blocks[0].RedactedBody == "" {
		t.Fatal("RedactedBody was empty")
	}
}

func TestCreateGroupInvalidKindReturnsErrInvalidInput(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	_, err := s.CreateGroup(context.Background(), Kind("bogus"), "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("err = %v, want ErrInvalidInput", err)
	}
}

func TestAddMemberToUnknownGroupReturnsErrNotFound(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	err := s.AddMember(context.Background(), 999999999, MemberInput{UserID: donor, RoleInGroup: "donor"}, staff)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/chatgroups/ -run 'TestGetGroup|TestRecordAndListContactBlocks|TestCreateGroupInvalidKind|TestAddMemberToUnknownGroup' -v
```

Expected: compile failure (`GetGroup`, `RecordContactBlock`, `ListContactBlocks` undefined) for the first three; the fourth (`TestAddMemberToUnknownGroupReturnsErrNotFound`) compiles but fails once the others are stubbed in, since the current `AddMember` does not wrap `ErrNotFound` yet.

- [ ] **Step 3: Add JSON tags to `Group`, in `chatgroups.go`**

Change the existing `Group` struct (around line 60-67 of `chatgroups.go`):

```go
// Group mirrors one chat_group_threads row.
type Group struct {
	ID          int64     `json:"id"`
	Kind        Kind      `json:"kind"`
	MemberTitle string    `json:"member_title"`
	CreatedBy   int64     `json:"created_by_staff_id"`
	Lifecycle   string    `json:"lifecycle"`
	CreatedAt   time.Time `json:"created_at"`
}
```

- [ ] **Step 4: Fix `CreateGroup`'s invalid-kind error, in `chatgroups.go`**

Find:

```go
	if kind != KindMasked && kind != KindTeam {
		return 0, errors.New("kind must be 'masked' or 'team'")
	}
```

Replace with:

```go
	if kind != KindMasked && kind != KindTeam {
		return 0, fmt.Errorf("chatgroups: kind %q: %w", kind, ErrInvalidInput)
	}
```

- [ ] **Step 5: Fix `AddMember`'s not-found error, in `chatgroups.go`**

Find:

```go
	var kind Kind
	if err := s.Pool.QueryRow(ctx,
		`SELECT kind FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind); err != nil {
		return fmt.Errorf("chatgroups: looking up group %d: %w", groupID, err)
	}
```

Replace with:

```go
	var kind Kind
	if err := s.Pool.QueryRow(ctx,
		`SELECT kind FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
		}
		return fmt.Errorf("chatgroups: looking up group %d: %w", groupID, err)
	}
```

(`pgx` is already imported in `chatgroups.go` for `pgx.Tx` in `insertMembers`'s signature, so this needs no new import.)

- [ ] **Step 6: Create `chatgroups_admin.go`**

```go
// chatgroups_admin.go holds the methods Phase 2's HTTP layer needs that
// don't belong in chatgroups.go (write path) or chatgroups_reads.go
// (member-facing read path): a full group detail with its member roster,
// for the admin membership-management UI and for the message-posting
// handlers' own contact-filter/notification needs (see
// docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md §3),
// and the contact-info-filter supervision log, mirroring
// internal/chat/contactblocks.go.

package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// GroupMember is one chat_group_members row, as staff need to see it —
// unlike GroupMessage, this type IS allowed to carry a real user id and
// label together, because it is only ever returned from admin-gated routes.
type GroupMember struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	RoleInGroup string     `json:"role_in_group"`
	Masked      bool       `json:"masked"`
	MaskedLabel string     `json:"masked_label"`
	RemovedAt   *time.Time `json:"removed_at,omitempty"`
}

// GroupDetail is a group's thread row plus its full member roster.
type GroupDetail struct {
	Group
	Members []GroupMember `json:"members"`
}

// GetGroup reads one group's thread row and its full member roster
// (including removed members, so the admin UI can show history). Used by
// the admin group-detail route, and by the message-posting handlers to
// learn a group's kind (for the contact filter) and member list (for
// notification fan-out) in one query.
func (s *Store) GetGroup(ctx context.Context, groupID int64) (GroupDetail, error) {
	var gd GroupDetail
	err := s.Pool.QueryRow(ctx,
		`SELECT id, kind, member_title, created_by_staff_id, lifecycle, created_at
		   FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&gd.ID, &gd.Kind, &gd.MemberTitle, &gd.CreatedBy, &gd.Lifecycle, &gd.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupDetail{}, fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
	}
	if err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: getting group %d: %w", groupID, err)
	}

	rows, err := s.Pool.Query(ctx,
		`SELECT id, user_id, role_in_group, masked, COALESCE(masked_label, ''), removed_at
		   FROM chat_group_members WHERE group_id = $1 ORDER BY id ASC`, groupID)
	if err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: listing members of group %d: %w", groupID, err)
	}
	defer rows.Close()
	for rows.Next() {
		var m GroupMember
		if err := rows.Scan(&m.ID, &m.UserID, &m.RoleInGroup, &m.Masked, &m.MaskedLabel, &m.RemovedAt); err != nil {
			return GroupDetail{}, fmt.Errorf("chatgroups: scanning member of group %d: %w", groupID, err)
		}
		gd.Members = append(gd.Members, m)
	}
	if err := rows.Err(); err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: listing members of group %d: %w", groupID, err)
	}
	return gd, nil
}

// GroupContactBlock is one refused message, as staff read it. Mirrors
// internal/chat/contactblocks.go's ContactBlock exactly, scoped to a group
// instead of a thread.
type GroupContactBlock struct {
	ID           int64     `json:"id"`
	GroupID      int64     `json:"group_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderName   *string   `json:"sender_name"`
	Kind         string    `json:"kind"`
	MatchCount   int       `json:"match_count"`
	RedactedBody string    `json:"redacted_body"`
	CreatedAt    time.Time `json:"created_at"`
}

// RecordContactBlock appends one refused attempt. Deliberately returns its
// error rather than swallowing it, but the caller (the HTTP handler) logs
// and continues — failing to record the attempt must never turn into
// failing to BLOCK it.
func (s *Store) RecordContactBlock(ctx context.Context, groupID, senderUserID int64, kind string, matchCount int, redactedBody string) error {
	if _, err := s.Pool.Exec(ctx, `
		INSERT INTO chat_group_contact_blocks (group_id, sender_user_id, kind, match_count, redacted_body)
		VALUES ($1, $2, $3, $4, $5)`,
		groupID, senderUserID, kind, matchCount, redactedBody,
	); err != nil {
		return fmt.Errorf("chatgroups: recording contact block on group %d: %w", groupID, err)
	}
	return nil
}

// ListContactBlocks returns one group's refused attempts, newest first, with
// the sender's name resolved for the dashboard — same no-masking rule as
// AdminListMessages: this is a staff-only screen, and a supervisor who
// cannot see WHO kept trying to pass a number out cannot act on it.
func (s *Store) ListContactBlocks(ctx context.Context, groupID int64) ([]GroupContactBlock, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT b.id, b.group_id, b.sender_user_id, up.full_name,
		       b.kind, b.match_count, b.redacted_body, b.created_at
		  FROM chat_group_contact_blocks b
		  LEFT JOIN user_profiles up ON up.user_id = b.sender_user_id
		 WHERE b.group_id = $1
		 ORDER BY b.id DESC`, groupID)
	if err != nil {
		return nil, fmt.Errorf("chatgroups: listing contact blocks for group %d: %w", groupID, err)
	}
	defer rows.Close()
	out := []GroupContactBlock{}
	for rows.Next() {
		var b GroupContactBlock
		if err := rows.Scan(&b.ID, &b.GroupID, &b.SenderUserID, &b.SenderName,
			&b.Kind, &b.MatchCount, &b.RedactedBody, &b.CreatedAt); err != nil {
			return nil, fmt.Errorf("chatgroups: scanning contact block: %w", err)
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("chatgroups: listing contact blocks for group %d: %w", groupID, err)
	}
	return out, nil
}
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/chatgroups/ -v
```

Expected: every test in the package passes, including all pre-existing Phase 1 tests (this task must not regress any of them) and the five new ones from Step 1.

```bash
gofmt -l internal/chatgroups/*.go
go vet ./internal/chatgroups/...
```

Expected: both silent.

- [ ] **Step 8: Commit**

```bash
git add internal/chatgroups/chatgroups.go internal/chatgroups/chatgroups_admin.go internal/chatgroups/chatgroups_admin_test.go
git commit -m "feat(chatgroups): add GetGroup, contact-block recording, two error-typing fixes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `notify.GroupMaskedNewMessageMsg` template

**Files:**
- Modify: `backend/internal/notify/templates.go`
- Test: `backend/internal/notify/templates_chat_groups_test.go` (new file)

**Interfaces:**
- Consumes: nothing.
- Produces: `func GroupMaskedNewMessageMsg(alias, preview string, groupID int64) LocalizedMessage`, used by Task 6/8's `notifyGroupMembers`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/notify/templates_chat_groups_test.go`:

```go
package notify

import "testing"

func TestGroupMaskedNewMessageMsgUsesAliasNotRealName(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("Donor 1", "hello there", 42)

	if msg.Type != "chat_group_message" {
		t.Fatalf("Type = %q, want %q", msg.Type, "chat_group_message")
	}
	if msg.RelatedEntityType != "chat_group_thread" || msg.RelatedEntityID != 42 {
		t.Fatalf("related entity = %s/%d, want chat_group_thread/42", msg.RelatedEntityType, msg.RelatedEntityID)
	}
	if msg.Title.En != "Message from Donor 1" {
		t.Fatalf("Title.En = %q, want it to contain the alias verbatim", msg.Title.En)
	}
	if msg.Body.En != "hello there" {
		t.Fatalf("Body.En = %q, want the preview verbatim", msg.Body.En)
	}
}

func TestGroupMaskedNewMessageMsgFallsBackWhenAliasEmpty(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("", "hi", 1)
	if msg.Title.En != "Message from Member" {
		t.Fatalf("Title.En = %q, want a neutral fallback, not an empty name", msg.Title.En)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend
go test ./internal/notify/ -run TestGroupMaskedNewMessageMsg -v
```

Expected: FAIL — `undefined: GroupMaskedNewMessageMsg`.

- [ ] **Step 3: Add the template**

In `backend/internal/notify/templates.go`, immediately after the existing `ChatNewMessageMsg` function (around line 1650):

```go
// GroupMaskedNewMessageMsg is ChatNewMessageMsg's masked-group twin (OPOS
// #25284 Phase 2). `alias` is how the sender appears in THIS group — their
// own masked_label, or "Support" for a staff sender — never a real name, so
// a masked group's push notification cannot re-identify anyone the chat
// screen itself hides. Team-kind groups reuse ChatNewMessageMsg directly
// with the sender's real name; this template exists only for masked groups.
func GroupMaskedNewMessageMsg(alias, preview string, groupID int64) LocalizedMessage {
	who := alias
	if who == "" {
		who = "Member"
	}
	return LocalizedMessage{
		Type:              "chat_group_message",
		RelatedEntityType: "chat_group_thread",
		RelatedEntityID:   groupID,
		Title: LocalText{
			En:  fmt.Sprintf("Message from %s", who),
			Ar:  fmt.Sprintf("رسالة من %s", who),
			Ckb: fmt.Sprintf("نامە لە %s", who),
			Kmr: fmt.Sprintf("Peyam ji %s", who),
		},
		Body: LocalText{
			En:  preview,
			Ar:  preview,
			Ckb: preview,
			Kmr: preview,
		},
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd backend
go test ./internal/notify/ -run TestGroupMaskedNewMessageMsg -v
go test ./internal/notify/... -v
```

Expected: both new tests PASS, and the full `internal/notify` suite still passes (this task added a pure function, no existing behavior touched).

- [ ] **Step 5: Commit**

```bash
git add internal/notify/templates.go internal/notify/templates_chat_groups_test.go
git commit -m "feat(notify): add GroupMaskedNewMessageMsg template for masked group chats

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Mobile handler — `chat_group.go` skeleton + read routes (`List`, `Messages`)

**Files:**
- Create: `backend/internal/handlers/chat_group.go`
- Test: `backend/internal/handlers/chat_group_test.go` (new file; this task's tests, grown across Tasks 5-8)

**Interfaces:**
- Consumes: `chatgroups.Store` (Phase 1 + Task 3), `notify.Notifier`, `permissions.Store`, `chatlifecycle.KindGroup` (Task 1), `refuseIfArchivedForParticipant`/`mergeChatLifecycle` (existing `chat_lifecycle_gate.go`).
- Produces: `type ChatGroupHandler struct`, `func NewChatGroupHandler(s *chatgroups.Store, n *notify.Notifier, perms *permissions.Store, pool *pgxpool.Pool) *ChatGroupHandler`, `(h *ChatGroupHandler) chatErr`, `(h *ChatGroupHandler) List`, `(h *ChatGroupHandler) Messages` — all consumed by Task 6 (same file/struct), Task 9 (route registration), Task 10 (the leak test).

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/handlers/chat_group_test.go`:

```go
// chat_group_test.go — HTTP-level tests for OPOS #25284 Phase 2's chat-group
// routes. Grown across Tasks 5-8 as each handler method is added. Needs a
// throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_http
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_http?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatGroup -v
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

func newChatGroupPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chat-group HTTP integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

var chatGroupUserSeq int

func makeChatGroupUser(t *testing.T, pool *pgxpool.Pool, name string) int64 {
	t.Helper()
	ctx := context.Background()
	chatGroupUserSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status) VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("9647720%06d", chatGroupUserSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
		id, name,
	); err != nil {
		t.Fatalf("insert profile: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func makeChatGroup(t *testing.T, pool *pgxpool.Pool, staffID int64, kind chatgroups.Kind, members []chatgroups.MemberInput) int64 {
	t.Helper()
	s := chatgroups.New(pool)
	title := ""
	if kind == chatgroups.KindTeam {
		title = "Test team"
	}
	id, err := s.CreateGroup(context.Background(), kind, title, staffID, members)
	if err != nil {
		t.Fatalf("create group: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_contact_blocks WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_reads WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_messages WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
	return id
}

// newChatGroupRouter wires the mobile chat-group routes with the same
// middleware main.go uses.
func newChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)))
	participant.GET("/chat-groups", h.List)
	participant.GET("/chat-groups/:id/messages", h.Messages)
	return r, h
}

func tokenForChatGroupUser(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), userID, "chat-group-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_access_tokens WHERE user_id = $1`, userID)
	})
	return session.AccessToken
}

func getAs(t *testing.T, r *gin.Engine, token, path string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func TestChatGroupList_ReturnsCallersGroups(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, donor), "/api/chat-groups")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d groups, want 1", len(items))
	}
}

func TestChatGroupMessages_RefusesNonMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	outsider := makeChatGroupUser(t, pool, "Outsider")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, outsider), fmt.Sprintf("/api/chat-groups/%d/messages", groupID))

	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body %v)", code, body)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run ChatGroup -v
```

Expected: compile failure — `ChatGroupHandler`, `NewChatGroupHandler`, `List`, `Messages` undefined.

- [ ] **Step 3: Create `chat_group.go`**

```go
// chat_group.go exposes OPOS #25284's staff-created group chats over HTTP:
// masked donor/beneficiary/volunteer coordination and real-name volunteer
// teams. Mobile (participant-facing) endpoints live here; admin
// (staff-facing) endpoints are chat_group_admin.go on the same struct, and
// the K19-style contact filter is chat_group_contact_block.go — split by
// responsibility from the start, matching this codebase's existing
// chat.go / marriage_chat.go convention but before, not after, hitting the
// file-size cap (see
// docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md §3).
package handlers

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ChatGroupHandler exposes the chat-group endpoints.
type ChatGroupHandler struct {
	Store    *chatgroups.Store
	Notifier *notify.Notifier
	Perms    *permissions.Store
	Pool     *pgxpool.Pool
}

func NewChatGroupHandler(s *chatgroups.Store, n *notify.Notifier, perms *permissions.Store, pool *pgxpool.Pool) *ChatGroupHandler {
	return &ChatGroupHandler{Store: s, Notifier: n, Perms: perms, Pool: pool}
}

func (h *ChatGroupHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

// chatErr maps chatgroups' sentinel errors onto HTTP, mirroring chat.go's
// chatErr (see internal/chatgroups' sentinel doc comments for what each
// means).
func (h *ChatGroupHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, chatgroups.ErrNotMember):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a member of this group."})
	case errors.Is(err, chatgroups.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Group not found."})
	case errors.Is(err, chatgroups.ErrAlreadyDecided):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This request has already been decided."})
	case errors.Is(err, chatgroups.ErrInvalidInput):
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// parseGroupPageParams reads after_id/limit query params, both optional —
// zero values fall back to chatgroups' own defaults.
func parseGroupPageParams(c *gin.Context) (afterID int64, limit int) {
	afterID, _ = strconv.ParseInt(c.Query("after_id"), 10, 64)
	limit, _ = strconv.Atoi(c.Query("limit"))
	return afterID, limit
}

// GET /api/chat-groups
func (h *ChatGroupHandler) List(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListGroupsForUser(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/chat-groups/:id/messages
func (h *ChatGroupHandler) Messages(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	// An ARCHIVED group is treated as gone for a participant, same rule as
	// the donor↔owner chat (see refuseIfArchivedForParticipant's own doc
	// comment for why this is 404, not 403).
	if refuseIfArchivedForParticipant(c, h.Pool, chatlifecycle.KindGroup, id) {
		return
	}
	afterID, limit := parseGroupPageParams(c)
	items, err := h.Store.ListMessagesForMember(c.Request.Context(), id, user.UserID, afterID, limit)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, mergeChatLifecycle(c, h.Pool, chatlifecycle.KindGroup, id, gin.H{
		"success": true,
		"items":   items,
	}))
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run ChatGroup -v
```

Expected: both tests PASS.

```bash
gofmt -l internal/handlers/chat_group.go internal/handlers/chat_group_test.go
go vet ./internal/handlers/...
```

Expected: both silent.

- [ ] **Step 5: Commit**

```bash
git add internal/handlers/chat_group.go internal/handlers/chat_group_test.go
git commit -m "feat(handlers): add chat-group mobile read routes (List, Messages)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Mobile handler — write routes (`PostMessage`, `MarkRead`) + contact filter + notifications

**Files:**
- Create: `backend/internal/handlers/chat_group_contact_block.go`
- Modify: `backend/internal/handlers/chat_group.go` (add `PostMessage`, `MarkRead`, `groupSenderLabel`, `notifyGroupMembers`; re-add `strings` import if Task 5 removed it)
- Modify: `backend/internal/handlers/chat_group_test.go`

**Interfaces:**
- Consumes: `chatgroups.GetGroup` (Task 3), `moderation.ScanContact` (existing), `notify.GroupMaskedNewMessageMsg` (Task 4), `notify.ChatNewMessageMsg` (existing), `contactBlockedCode`/`contactBlockedMessage` (existing, package-private, from `chat_contact_block.go`).
- Produces: `(h *ChatGroupHandler) PostMessage`, `(h *ChatGroupHandler) MarkRead`, `(h *ChatGroupHandler) refuseGroupContactDetails`, `(h *ChatGroupHandler) notifyGroupMembers`, `(h *ChatGroupHandler) groupSenderLabel` — all consumed by Task 8 (admin's `AdminPostMessage` reuses `notifyGroupMembers`/`groupSenderLabel`/`refuseGroupContactDetails`) and Task 9 (route registration).

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/handlers/chat_group_test.go`:

```go
func postAs(t *testing.T, r *gin.Engine, token, path string, body any) (int, map[string]any) {
	t.Helper()
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func countGroupMessages(t *testing.T, pool *pgxpool.Pool, groupID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_messages WHERE group_id = $1`, groupID).Scan(&n); err != nil {
		t.Fatalf("count messages: %v", err)
	}
	return n
}

func TestChatGroupPostMessage_MemberCanPost(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "hello group"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestChatGroupPostMessage_RefusesContactDetailsInMaskedGroup(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 0 {
		t.Fatalf("chat_group_messages has %d rows after a refused message; want 0", n)
	}
}

func TestChatGroupPostMessage_TeamGroupAllowsContactDetails(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	volunteer := makeChatGroupUser(t, pool, "Volunteer Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindTeam, []chatgroups.MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, volunteer),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — team groups are never filtered (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestChatGroupMarkRead_AdvancesCursor(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	msgID, err := s.PostMessage(context.Background(), groupID, donor, "one")
	if err != nil {
		t.Fatalf("seed message: %v", err)
	}

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/read", groupID), map[string]int64{"last_read_msg_id": msgID})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	var last int64
	if err := pool.QueryRow(context.Background(),
		`SELECT last_read_msg_id FROM chat_group_reads WHERE group_id = $1 AND user_id = $2`,
		groupID, donor).Scan(&last); err != nil {
		t.Fatalf("read cursor: %v", err)
	}
	if last != msgID {
		t.Fatalf("last_read_msg_id = %d, want %d", last, msgID)
	}
}

// newWriteChatGroupRouter extends newChatGroupRouter with the write routes
// this task adds.
func newWriteChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)))
	participant.GET("/chat-groups", h.List)
	participant.GET("/chat-groups/:id/messages", h.Messages)
	participant.POST("/chat-groups/:id/messages", auth.RequireNotGuest(), h.PostMessage)
	participant.POST("/chat-groups/:id/read", auth.RequireNotGuest(), h.MarkRead)
	return r, h
}
```

Add `"bytes"` to the test file's import block (needed by `postAs`'s `bytes.NewReader`).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run ChatGroup -v
```

Expected: compile failure — `PostMessage`, `MarkRead` undefined on `*ChatGroupHandler`.

- [ ] **Step 3: Add the write handlers to `chat_group.go`**

Append to `chat_group.go`, and add `"strings"` to this file's import block (Task 5's version of this file has no use for it yet — `PostMessage`/`MarkRead`/`groupSenderLabel` below are what need it):

```go
type chatGroupMessageReq struct {
	Body string `json:"body"`
}

// POST /api/chat-groups/:id/messages
func (h *ChatGroupHandler) PostMessage(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	group, err := h.Store.GetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	// A PAUSED or ENDED group refuses new messages, server-side — same rule
	// as every other chat system (chat_lifecycle_gate.go).
	if refuseIfNotSendable(c, h.Pool, chatlifecycle.KindGroup, id) {
		return
	}
	var req chatGroupMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	if h.refuseGroupContactDetails(c, group, user, req.Body) {
		return
	}
	msgID, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, req.Body)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	h.notifyGroupMembers(group, user.UserID, req.Body)
	c.JSON(http.StatusOK, gin.H{"success": true, "message_id": msgID})
}

type chatGroupReadReq struct {
	LastReadMsgID int64 `json:"last_read_msg_id"`
}

// POST /api/chat-groups/:id/read
func (h *ChatGroupHandler) MarkRead(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req chatGroupReadReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}
	if err := h.Store.MarkRead(c.Request.Context(), id, user.UserID, req.LastReadMsgID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// groupSenderLabel resolves how senderUserID's messages appear to everyone
// else in group: a masked group shows their own masked_label, or "Support"
// if their role is staff or they have no member row at all (e.g. a staff
// reply via PostMessageAsStaff, Task 8) — the same resolution
// ListMessagesForMember applies at read time, kept consistent rather than
// re-derived differently. A team group shows their real name.
func (h *ChatGroupHandler) groupSenderLabel(ctx context.Context, group chatgroups.GroupDetail, senderUserID int64) string {
	if group.Kind == chatgroups.KindTeam {
		var name string
		_ = h.Pool.QueryRow(ctx, `SELECT full_name FROM user_profiles WHERE user_id = $1`, senderUserID).Scan(&name)
		if strings.TrimSpace(name) == "" {
			return "Member"
		}
		return name
	}
	for _, m := range group.Members {
		if m.UserID == senderUserID {
			if m.RoleInGroup == "staff" {
				return "Support"
			}
			if m.MaskedLabel != "" {
				return m.MaskedLabel
			}
		}
	}
	return "Support"
}

// notifyGroupMembers fans a push out to every OTHER active member of group,
// masked or real depending on group.Kind. Fire-and-forget, matching
// chat.go's bg()/goroutine pattern. The sender's own label is resolved ONCE
// — it depends only on who sent the message, never on who is reading it, so
// there is nothing to batch per recipient (see the design spec §6 for why
// this replaced an earlier, unnecessary per-recipient-label design).
func (h *ChatGroupHandler) notifyGroupMembers(group chatgroups.GroupDetail, senderUserID int64, body string) {
	preview := body
	if r := []rune(preview); len(r) > 80 {
		preview = string(r[:80]) + "…"
	}
	label := h.groupSenderLabel(context.Background(), group, senderUserID)
	for _, m := range group.Members {
		if m.UserID == senderUserID || m.RemovedAt != nil {
			continue
		}
		recipient := m.UserID
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			var msg notify.LocalizedMessage
			if group.Kind == chatgroups.KindMasked {
				msg = notify.GroupMaskedNewMessageMsg(label, preview, group.ID)
			} else {
				msg = notify.ChatNewMessageMsg(label, preview, group.ID)
			}
			_, _ = h.Notifier.Send(ctx, recipient, msg)
		}()
	}
}
```

- [ ] **Step 4: Create `chat_group_contact_block.go`**

```go
// chat_group_contact_block.go — K19's contact-info filter, adapted for
// staff-mediated group chats. See chat_contact_block.go for the full "why
// refuse, not strip" rationale, which applies unchanged here.
//
// The exemption rule is NOT identical to the donor↔owner chat's. There, a
// thread with ANY staff party skips filtering entirely. A masked group
// ALWAYS includes staff by construction (spec §1), so reusing that
// exemption verbatim would silently disable filtering for every message any
// masked group ever carries — exactly the gap this file exists to avoid.
// Filtering here is keyed on the GROUP's kind, never on who else is present:
// masked groups filter every non-staff sender; team groups never filter at
// all, since real names are already visible and there is no masking
// invariant left to protect.
package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// refuseGroupContactDetails reports whether the message was REFUSED — when
// it returns true it has already written the response and the caller must
// stop. Reuses contactBlockedCode/contactBlockedMessage from
// chat_contact_block.go (same package, same wording — one rule, one voice).
func (h *ChatGroupHandler) refuseGroupContactDetails(c *gin.Context, group chatgroups.GroupDetail, sender *auth.ResolvedUser, body string) bool {
	if group.Kind != chatgroups.KindMasked {
		return false
	}
	if sender != nil && permissions.TierFrom(sender.StaffTier) != permissions.TierUser {
		return false // staff relay — same exemption as the donor↔owner chat
	}

	finding := moderation.ScanContact(body)
	if !finding.Blocked() {
		return false
	}

	if err := h.Store.RecordContactBlock(c.Request.Context(), group.ID, sender.UserID,
		string(finding.Kind), finding.Count, finding.Redacted); err != nil {
		log.Printf("[chat-group] could not record blocked attempt on group %d: %v", group.ID, err)
	}

	c.JSON(http.StatusUnprocessableEntity, gin.H{
		"success": false,
		"code":    contactBlockedCode,
		"kind":    string(finding.Kind),
		"error":   contactBlockedMessage(finding.Kind),
	})
	return true
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run ChatGroup -v
```

Expected: every test added in Task 5 and this task PASSES.

```bash
gofmt -l internal/handlers/chat_group*.go
go vet ./internal/handlers/...
go build ./...
```

Expected: all clean.

- [ ] **Step 6: Commit**

```bash
git add internal/handlers/chat_group.go internal/handlers/chat_group_contact_block.go internal/handlers/chat_group_test.go
git commit -m "feat(handlers): add chat-group write routes, K19 contact filter, notifications

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Admin handler — `chat_group_admin.go` skeleton + group/membership management

**Files:**
- Create: `backend/internal/handlers/chat_group_admin.go`
- Modify: `backend/internal/handlers/chat_group_test.go`

**Interfaces:**
- Consumes: `chatgroups.CreateGroup`/`AddMember`/`RemoveMember`/`GetGroup`/`ListGroupsForStaff` (Phase 1 + Task 3).
- Produces: `(h *ChatGroupHandler) AdminList`, `AdminGetGroup`, `AdminCreateGroup`, `AdminAddMember`, `AdminRemoveMember` — consumed by Task 9 (route registration).

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/handlers/chat_group_test.go`:

```go
func newAdminChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
	admin.GET("/admin/chat-groups", h.AdminList)
	admin.POST("/admin/chat-groups", h.AdminCreateGroup)
	admin.GET("/admin/chat-groups/:id", h.AdminGetGroup)
	admin.POST("/admin/chat-groups/:id/members", h.AdminAddMember)
	admin.DELETE("/admin/chat-groups/:id/members/:userId", h.AdminRemoveMember)
	return r, h
}

func tokenForStaffUser(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET staff_tier = 'admin' WHERE id = $1`, userID); err != nil {
		t.Fatalf("promote to staff: %v", err)
	}
	return tokenForChatGroupUser(t, pool, userID)
}

func TestAdminCreateGroup_CreatesMaskedGroup(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind": "masked",
		"members": []map[string]any{
			{"user_id": donor, "role_in_group": "donor"},
		},
	})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	groupIDF, ok := body["group_id"].(float64)
	if !ok || groupIDF <= 0 {
		t.Fatalf("group_id missing or invalid: %v", body)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		id := int64(groupIDF)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
}

func TestAdminCreateGroup_RejectsInvalidKind(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":    "bogus",
		"members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}},
	})

	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
}

func TestAdminAddMemberAndRemoveMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": beneficiary, "role_in_group": "beneficiary"})
	if code != http.StatusOK {
		t.Fatalf("add member: status = %d, want 200 (body %v)", code, body)
	}

	getCode, getBody := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))
	if getCode != http.StatusOK {
		t.Fatalf("get group: status = %d, want 200 (body %v)", getCode, getBody)
	}
	group, _ := getBody["group"].(map[string]any)
	members, _ := group["members"].([]any)
	if len(members) != 2 {
		t.Fatalf("got %d members after add, want 2", len(members))
	}

	req := httptest.NewRequest(http.MethodDelete,
		fmt.Sprintf("/api/admin/chat-groups/%d/members/%d", groupID, beneficiary), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("remove member: status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run 'AdminCreateGroup|AdminAddMemberAndRemoveMember' -v
```

Expected: compile failure — `AdminList`, `AdminGetGroup`, `AdminCreateGroup`, `AdminAddMember`, `AdminRemoveMember` undefined.

- [ ] **Step 3: Create `chat_group_admin.go`**

```go
// chat_group_admin.go — staff-facing chat-group endpoints: listing every
// group, creating one directly (independent of the connect-request flow,
// which is Phase 3), and managing membership. Split from chat_group.go
// (mobile) from the start — see that file's doc comment for why.
package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// GET /api/admin/chat-groups
func (h *ChatGroupHandler) AdminList(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListGroupsForStaff(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/chat-groups/:id
func (h *ChatGroupHandler) AdminGetGroup(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	group, err := h.Store.GetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "group": group})
}

type adminGroupMemberReq struct {
	UserID      int64  `json:"user_id"`
	RoleInGroup string `json:"role_in_group"`
	Label       string `json:"label"`
}

type adminCreateGroupReq struct {
	Kind        string                `json:"kind"`
	MemberTitle string                `json:"member_title"`
	Members     []adminGroupMemberReq `json:"members"`
}

// POST /api/admin/chat-groups
func (h *ChatGroupHandler) AdminCreateGroup(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req adminCreateGroupReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}
	if strings.TrimSpace(req.Kind) == "" || len(req.Members) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "kind and at least one member are required."})
		return
	}
	members := make([]chatgroups.MemberInput, len(req.Members))
	for i, m := range req.Members {
		members[i] = chatgroups.MemberInput{UserID: m.UserID, RoleInGroup: m.RoleInGroup, Label: m.Label}
	}
	groupID, err := h.Store.CreateGroup(c.Request.Context(), chatgroups.Kind(req.Kind), req.MemberTitle, user.UserID, members)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "group_id": groupID})
}

// POST /api/admin/chat-groups/:id/members
func (h *ChatGroupHandler) AdminAddMember(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req adminGroupMemberReq
	if err := c.ShouldBindJSON(&req); err != nil || req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required."})
		return
	}
	input := chatgroups.MemberInput{UserID: req.UserID, RoleInGroup: req.RoleInGroup, Label: req.Label}
	if err := h.Store.AddMember(c.Request.Context(), id, input, user.UserID); err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DELETE /api/admin/chat-groups/:id/members/:userId
func (h *ChatGroupHandler) AdminRemoveMember(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	memberUserID, err := strconv.ParseInt(c.Param("userId"), 10, 64)
	if err != nil || memberUserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user id."})
		return
	}
	if err := h.Store.RemoveMember(c.Request.Context(), id, memberUserID, user.UserID); err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run 'AdminCreateGroup|AdminAddMemberAndRemoveMember' -v
```

Expected: all PASS.

```bash
gofmt -l internal/handlers/chat_group_admin.go
go vet ./internal/handlers/...
```

Expected: silent.

- [ ] **Step 5: Commit**

```bash
git add internal/handlers/chat_group_admin.go internal/handlers/chat_group_test.go
git commit -m "feat(handlers): add admin chat-group management routes (create, add/remove member)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Admin handler — messages (`AdminMessages`, `AdminPostMessage`, `AdminContactBlocks`)

**Files:**
- Modify: `backend/internal/handlers/chat_group_admin.go`
- Modify: `backend/internal/handlers/chat_group_test.go`

**Interfaces:**
- Consumes: `chatgroups.AdminListMessages`/`PostMessageAsStaff`/`ListContactBlocks` (Phase 1 + Task 3), `refuseGroupContactDetails`/`notifyGroupMembers` (Task 6).
- Produces: `(h *ChatGroupHandler) AdminMessages`, `AdminPostMessage`, `AdminContactBlocks` — consumed by Task 9 (route registration, including the `sensitive_data` gate on `AdminMessages`) and Task 10 (the identity-leak test contrasts `Messages` against this).

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/handlers/chat_group_test.go`:

```go
func newAdminMessagesRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
	admin.GET("/admin/chat-groups/:id/messages", h.AdminMessages)
	admin.POST("/admin/chat-groups/:id/messages", h.AdminPostMessage)
	admin.GET("/admin/chat-groups/:id/contact-blocks", h.AdminContactBlocks)
	return r, h
}

func TestAdminMessages_ShowsRealIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Real Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	if _, err := s.PostMessage(context.Background(), groupID, donor, "hi from donor"); err != nil {
		t.Fatalf("seed message: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	raw, _ := json.Marshal(body)
	if !bytes.Contains(raw, []byte("Donor Real Name")) {
		t.Fatalf("admin view did not carry the real name: %s", raw)
	}
}

func TestAdminPostMessage_PostsAsStaffAndNotifiesMembers(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID),
		map[string]string{"body": "we are looking into it"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestAdminContactBlocks_ListsRecordedAttempts(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	if err := s.RecordContactBlock(context.Background(), groupID, donor, "phone", 1, "call •••"); err != nil {
		t.Fatalf("seed contact block: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/contact-blocks", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d contact blocks, want 1", len(items))
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run 'AdminMessages|AdminPostMessage|AdminContactBlocks' -v
```

Expected: compile failure — `AdminMessages`, `AdminPostMessage`, `AdminContactBlocks` undefined.

- [ ] **Step 3: Add the three methods to `chat_group_admin.go`**

Append (and add `"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"` to this file's import block — needed by `refuseIfNotSendable`'s `chatlifecycle.KindGroup` argument):

```go
// GET /api/admin/chat-groups/:id/messages
func (h *ChatGroupHandler) AdminMessages(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	afterID, limit := parseGroupPageParams(c)
	items, err := h.Store.AdminListMessages(c.Request.Context(), id, afterID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/admin/chat-groups/:id/messages — staff replies, shown as
// "Support" to non-staff members (see groupSenderLabel, chat_group.go).
func (h *ChatGroupHandler) AdminPostMessage(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	group, err := h.Store.GetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	// The pause holds for STAFF too — a pause staff could talk through would
	// not be a pause (see AdminPostMessage's equivalent comment in chat.go).
	if refuseIfNotSendable(c, h.Pool, chatlifecycle.KindGroup, id) {
		return
	}
	var req chatGroupMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	if h.refuseGroupContactDetails(c, group, user, req.Body) {
		return
	}
	msgID, err := h.Store.PostMessageAsStaff(c.Request.Context(), id, user.UserID, req.Body)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	h.notifyGroupMembers(group, user.UserID, req.Body)
	c.JSON(http.StatusOK, gin.H{"success": true, "message_id": msgID})
}

// GET /api/admin/chat-groups/:id/contact-blocks
func (h *ChatGroupHandler) AdminContactBlocks(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	items, err := h.Store.ListContactBlocks(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run ChatGroup -v
```

Expected: every chat-group test added across Tasks 5-8 PASSES.

```bash
gofmt -l internal/handlers/chat_group*.go
go vet ./internal/handlers/...
go build ./...
```

Expected: all clean.

- [ ] **Step 5: Commit**

```bash
git add internal/handlers/chat_group_admin.go internal/handlers/chat_group_test.go
git commit -m "feat(handlers): add admin chat-group message routes and contact-block log

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Wire it all into `main.go`, finish the chatlifecycle test extensions from Task 1

**Files:**
- Modify: `backend/cmd/server/main.go`
- Modify: `backend/internal/handlers/chat_lifecycle_fixtures_test.go` (finish Task 1 Step 4)
- Modify: `backend/internal/handlers/chat_lifecycle_test.go` (finish Task 1 Step 4)

**Interfaces:**
- Consumes: everything from Tasks 1-8.
- Produces: the live, reachable HTTP surface — nothing further consumes this within Phase 2; Phase 3+ builds on these routes existing.

- [ ] **Step 1: Construct `ChatGroupHandler` in `main.go`**

Add `"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"` to `main.go`'s import block.

Next to `chatH := handlers.NewChatHandler(chatStore, notifier, pool)` (line 301):

```go
	chatGroupsStore := chatgroups.New(pool)
	chatGroupH := handlers.NewChatGroupHandler(chatGroupsStore, notifier, nil, pool)
```

(`Perms` is nil here because `permStore` is constructed later in `main.go`, same as the existing `chatH.Perms = permStore` pattern below.)

At the existing line `chatH.Perms = permStore         // both parties of a donor↔owner thread` (line 452), add immediately after it:

```go
	chatGroupH.Perms = permStore
```

- [ ] **Step 2: Register the mobile routes**

In the `authed` block, immediately after the existing case-volunteer chat block (after line 812, `authed.POST("/case-chats/:id/messages", caseVolChatH.PostMessage)`):

```go
			// OPOS #25284 Phase 2 — staff-created group chats (masked
			// donor/beneficiary/volunteer coordination, real-name volunteer
			// teams). Group creation/membership is admin-only (below);
			// mobile only reads and posts into groups a member already has.
			authed.GET("/chat-groups", chatGroupH.List)
			authed.GET("/chat-groups/:id/messages", chatGroupH.Messages)
			authed.POST("/chat-groups/:id/messages", auth.RequireNotGuest(), chatGroupH.PostMessage)
			authed.POST("/chat-groups/:id/read", auth.RequireNotGuest(), chatGroupH.MarkRead)
```

- [ ] **Step 3: Register the admin routes**

In the `admin` block, immediately after the existing donor↔owner admin block (after line 989, `admin.POST("/admin/chats/:id/release", perm("messages", "edit"), chatH.AdminRelease)`):

```go
			// OPOS #25284 Phase 2 — staff-created group chats.
			admin.GET("/admin/chat-groups", perm("messages", "view"), chatGroupH.AdminList)
			admin.POST("/admin/chat-groups", perm("messages", "add"), chatGroupH.AdminCreateGroup)
			admin.GET("/admin/chat-groups/:id", perm("messages", "view"), chatGroupH.AdminGetGroup)
			admin.POST("/admin/chat-groups/:id/members", perm("messages", "edit"), chatGroupH.AdminAddMember)
			admin.DELETE("/admin/chat-groups/:id/members/:userId", perm("messages", "edit"), chatGroupH.AdminRemoveMember)
			// Reveals real identities inside a masked group — messages:view
			// alone is not enough (see design spec §4).
			admin.GET("/admin/chat-groups/:id/messages",
				perm("messages", "view"), perm("sensitive_data", "view"), chatGroupH.AdminMessages)
			admin.POST("/admin/chat-groups/:id/messages", perm("messages", "add"), chatGroupH.AdminPostMessage)
			admin.GET("/admin/chat-groups/:id/contact-blocks", perm("messages", "view"), chatGroupH.AdminContactBlocks)
```

- [ ] **Step 4: Register the lifecycle routes**

In the existing lifecycle block (after line 1012, `admin.DELETE("/admin/marriage/chats/:id", perm("marriage", "delete"), chatLifecycleH.Delete(chatlifecycle.KindMarriage))`):

```go
			admin.POST("/admin/chat-groups/:id/lifecycle", perm("messages", "edit"), chatLifecycleH.Apply(chatlifecycle.KindGroup))
			admin.DELETE("/admin/chat-groups/:id", perm("messages", "delete"), chatLifecycleH.Delete(chatlifecycle.KindGroup))
```

- [ ] **Step 5: Finish Task 1's deferred test-router edits**

In `chat_lifecycle_fixtures_test.go`'s `newLifecycleRouter` (after the existing `admin.DELETE("/admin/case-chats/:id", ...)` line), add:

```go
	groupsStore := chatgroups.New(pool)
	groupsH := NewChatGroupHandler(groupsStore, n, nil, pool)
	participant.POST("/chat-groups/:id/messages", groupsH.PostMessage)
	admin.POST("/admin/chat-groups/:id/lifecycle", lifeH.Apply(chatlifecycle.KindGroup))
	admin.DELETE("/admin/chat-groups/:id", lifeH.Delete(chatlifecycle.KindGroup))
```

Add `"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"` to this test file's import block.

In `chat_lifecycle_test.go`'s `TestChatLifecycle_ParticipantCannotModerate` map (around line 337), add:

```go
			chatlifecycle.KindGroup: "/api/admin/chat-groups/%d",
```

- [ ] **Step 6: Run the full backend test suite**

```bash
cd backend
go build ./...
go vet ./...
gofmt -l internal/... cmd/...
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./... -v
```

Expected: `go build`/`go vet`/`gofmt` all clean; every test passes, including — for the first time — the chat-group subtests inside `TestChatLifecycle_PausedThreadRefusesMessage`, `EndedThreadRefusesMessage`, `OpenThreadStillWorks`, `ResumeRestoresAPausedChat`, `EndedChatCannotBeResumed`, `EndKeepsTheHistory`, and `ParticipantCannotModerate` (these were failing/incomplete since Task 1; this is the task where they turn green). If any of these six still fail, that is this task's own regression to fix before moving on — do not treat it as pre-existing.

- [ ] **Step 7: Manually smoke-test one route against a running server**

```bash
cd backend
go run ./cmd/server &
sleep 2
curl -s http://localhost:8080/api/chat-groups -H "Authorization: Bearer invalid" | head -c 200
kill %1
```

Expected: a `401 Unauthorized` JSON body (proving the route is actually mounted and reachable, not just passing in-process tests) — do not accept "the tests pass" as proof the server itself boots and serves these routes; this is the one step in the whole plan that exercises the real binary.

- [ ] **Step 8: Commit**

```bash
git add cmd/server/main.go internal/handlers/chat_lifecycle_fixtures_test.go internal/handlers/chat_lifecycle_test.go
git commit -m "feat(main): wire chat-group routes, permissions, and lifecycle into the server

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: The identity-leak HTTP test

**Files:**
- Modify: `backend/internal/handlers/chat_group_test.go`

**Interfaces:**
- Consumes: everything from Tasks 1-9 (this is the end-to-end proof, not new production code).
- Produces: nothing further consumed — this is Phase 2's own highest-priority acceptance test per the design spec §7.

- [ ] **Step 1: Write the test**

Append to `backend/internal/handlers/chat_group_test.go` (add `"strings"` to the import block if not already present from an earlier task):

```go
// TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity is the single
// highest-priority test for this phase (design spec §7): it proves, at the
// HTTP layer, that Phase 1's structural masking guarantee survives the trip
// through gin.Context.JSON. It searches the RAW response body string, not
// just the typed fields a hand-picked assertion might miss.
func TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff Real Name")
	donor := makeChatGroupUser(t, pool, "Donor Secret Real Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Secret Real Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	donorToken := tokenForChatGroupUser(t, pool, donor)

	if code, body := postAs(t, r, donorToken, fmt.Sprintf("/api/chat-groups/%d/messages", groupID),
		map[string]string{"body": "hello from the donor side"}); code != http.StatusOK {
		t.Fatalf("seed message: status = %d (body %v)", code, body)
	}

	req := httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/chat-groups/%d/messages", groupID), nil)
	req.Header.Set("Authorization", "Bearer "+tokenForChatGroupUser(t, pool, beneficiary))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}

	raw := w.Body.String()
	forbidden := []string{
		"Donor Secret Real Name",
		"Beneficiary Secret Real Name",
		"Staff Real Name",
		fmt.Sprintf("%d", donor),
		fmt.Sprintf("%d", staff),
	}
	for _, needle := range forbidden {
		if strings.Contains(raw, needle) {
			t.Fatalf("masked-group response leaks %q: %s", needle, raw)
		}
	}
	if !strings.Contains(raw, "Donor 1") {
		t.Fatalf("expected the donor's masked label \"Donor 1\" somewhere in the response: %s", raw)
	}
}
```

- [ ] **Step 2: Run it**

```bash
cd backend
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./internal/handlers/ -run TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity -v
```

Expected: PASS. If it fails, this is a Critical, ship-blocking finding — do not weaken the assertion to make it pass; find and fix the actual leak (most likely candidates: a wrong field left un-redacted in `GroupMessage`, or the wrong Store method called from `Messages`).

- [ ] **Step 3: Run the full suite one final time**

```bash
cd backend
go build ./...
go vet ./...
gofmt -l internal/... cmd/...
TEST_DATABASE_URL='postgres://localhost:5432/<your test db>?sslmode=disable' \
  go test ./... -v
```

Expected: everything green, package-wide.

- [ ] **Step 4: Commit**

```bash
git add internal/handlers/chat_group_test.go
git commit -m "test(handlers): add the identity-leak HTTP test for masked chat groups

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
