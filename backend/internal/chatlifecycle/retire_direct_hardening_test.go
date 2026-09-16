// retire_direct_hardening_test.go
//
// Pins the hardening of RetireAllDirectThreads (OPOS #26412) that has to be in
// place before cmd/retire-direct-chats runs on production. A local run of the
// original script found four faults, and each one has a test here:
//
//  1. Not atomic: a run stopped between a thread's END and its ARCHIVE left
//     the thread ended but still visible, and a re-run skipped it.
//  2. Paused direct threads were skipped: staff could later resume one into a
//     working donor↔owner chat, because sending checks lifecycle, not kind.
//  3. The actor was not checked: any existing users.id was recorded as the
//     staff member who retired the chats.
//  4. An existing archive stamp was overwritten, losing who archived the
//     thread and when.
//
// Shares newTestPool and makeTestUser with retire_direct_test.go, so it needs
// the same TEST_DATABASE_URL and skips without one.
package chatlifecycle

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// raiseExceptionCode is the SQLSTATE PL/pgSQL's RAISE EXCEPTION uses by
// default, which is what failArchiveOf's trigger raises.
const raiseExceptionCode = "P0001"

// ─── Fixture ────────────────────────────────────────────────────────────

// nullText is what row() reports for a NULL column, so a whole row can be
// compared with == instead of pointer by pointer.
const nullText = "<null>"

// retireFixture holds the pool and the app user every seeded thread starts
// from. The participants never matter to a retirement; only a thread's kind,
// lifecycle and archive stamp do.
type retireFixture struct {
	ctx   context.Context
	pool  *pgxpool.Pool
	donor int64
}

// newRetireFixture connects to the migrated test database and creates the
// donor. Its cleanup deletes every seeded thread through chat_threads'
// ON DELETE CASCADE on donor_user_id.
func newRetireFixture(t *testing.T) *retireFixture {
	t.Helper()
	pool := newTestPool(t)
	return &retireFixture{
		ctx:   context.Background(),
		pool:  pool,
		donor: makeTestUser(t, pool, "donor"),
	}
}

// makeStaffUser inserts a users row holding the given staff_tier, the one
// column the retirement reads to decide whether its actor is staff.
func makeStaffUser(t *testing.T, pool *pgxpool.Pool, tier string) int64 {
	t.Helper()
	id := makeTestUser(t, pool, tier)
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET staff_tier = $1 WHERE id = $2`, tier, id); err != nil {
		t.Fatalf("set staff_tier %q on user %d: %v", tier, id, err)
	}
	return id
}

// ptrTo returns a pointer to v, for the nullable columns of a threadSeed.
func ptrTo[T any](v T) *T { return &v }

// idText renders a user id the way row() reports an id column.
func idText(id int64) string { return strconv.FormatInt(id, 10) }

// threadSeed is one chat_threads row to insert. Zero values mean an active,
// open, never-archived direct thread.
type threadSeed struct {
	kind       string
	lifecycle  string
	reason     *string
	changedAt  *time.Time
	changedBy  *int64
	archivedAt *time.Time
	archivedBy *int64
}

// seed inserts the thread and returns its id. Each thread gets its own owner,
// because uq_chat_pair (migration 012) allows one thread per donor + owner.
func (f *retireFixture) seed(t *testing.T, s threadSeed) int64 {
	t.Helper()
	if s.kind == "" {
		s.kind = "direct"
	}
	if s.lifecycle == "" {
		s.lifecycle = StateOpen
	}
	owner := makeTestUser(t, f.pool, "owner")
	var id int64
	err := f.pool.QueryRow(f.ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind,
		                          lifecycle, lifecycle_reason, lifecycle_changed_at,
		                          lifecycle_changed_by, archived_at, archived_by)
		VALUES ($1, $2, 'active', $1, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id`,
		f.donor, owner, s.kind, s.lifecycle, s.reason, s.changedAt, s.changedBy, s.archivedAt, s.archivedBy,
	).Scan(&id)
	if err != nil {
		t.Fatalf("seed %s/%s thread: %v", s.kind, s.lifecycle, err)
	}
	return id
}

// threadRow is every column a retirement may write, as text, so "this row did
// not change" is a single == comparison with timestamps included.
type threadRow struct {
	Lifecycle, Reason, ChangedAt, ChangedBy, ArchivedAt, ArchivedBy, UpdatedAt string
}

// rows reads the given threads, in the order given.
func (f *retireFixture) rows(t *testing.T, ids ...int64) []threadRow {
	t.Helper()
	out := make([]threadRow, 0, len(ids))
	for _, id := range ids {
		var r threadRow
		err := f.pool.QueryRow(f.ctx, `
			SELECT lifecycle,
			       COALESCE(lifecycle_reason, $2),
			       COALESCE(lifecycle_changed_at::text, $2),
			       COALESCE(lifecycle_changed_by::text, $2),
			       COALESCE(archived_at::text, $2),
			       COALESCE(archived_by::text, $2),
			       updated_at::text
			  FROM chat_threads WHERE id = $1`, id, nullText,
		).Scan(&r.Lifecycle, &r.Reason, &r.ChangedAt, &r.ChangedBy, &r.ArchivedAt, &r.ArchivedBy, &r.UpdatedAt)
		if err != nil {
			t.Fatalf("read thread %d: %v", id, err)
		}
		out = append(out, r)
	}
	return out
}

// pendingDirectRetirement counts the direct threads a run still has to act
// on: open or paused ones to END, and ended-but-visible ones to ARCHIVE.
// Exact counts are asserted against this rather than against what one test
// seeded, because a run acts on the whole table and other tests sharing the
// database leave rows behind.
func pendingDirectRetirement(t *testing.T, pool *pgxpool.Pool) RetireResult {
	t.Helper()
	var want RetireResult
	err := pool.QueryRow(context.Background(), `
		SELECT count(*) FILTER (WHERE lifecycle IN ('open', 'paused')),
		       count(*) FILTER (WHERE lifecycle = 'ended' AND archived_at IS NULL)
		  FROM chat_threads WHERE kind = 'direct'`,
	).Scan(&want.Ended, &want.Archived)
	if err != nil {
		t.Fatalf("count pending direct retirement: %v", err)
	}
	return want
}

// failArchiveOf makes the database refuse to archive one thread: a BEFORE
// UPDATE trigger raises the moment that row's archived_at goes from NULL to a
// value. Stopping a run at a chosen point is what proving atomicity needs.
// The trigger is removed when the (sub)test ends.
func (f *retireFixture) failArchiveOf(t *testing.T, threadID int64) {
	t.Helper()
	// Both identifiers are formatted from an int64, never from text, so this
	// Sprintf cannot inject anything.
	name := fmt.Sprintf("test_retire_fail_archive_%d", threadID)
	t.Cleanup(func() {
		ctx := context.Background()
		if _, err := f.pool.Exec(ctx, `DROP TRIGGER IF EXISTS `+name+` ON chat_threads`); err != nil {
			t.Errorf("drop trigger %s: %v", name, err)
		}
		if _, err := f.pool.Exec(ctx, `DROP FUNCTION IF EXISTS `+name+`()`); err != nil {
			t.Errorf("drop function %s: %v", name, err)
		}
	})
	stmts := []string{
		`CREATE FUNCTION ` + name + `() RETURNS trigger LANGUAGE plpgsql AS $$
		 BEGIN RAISE EXCEPTION 'injected failure archiving chat_threads/%', NEW.id; END $$`,
		fmt.Sprintf(`CREATE TRIGGER %s BEFORE UPDATE ON chat_threads FOR EACH ROW
		 WHEN (NEW.id = %d AND OLD.archived_at IS NULL AND NEW.archived_at IS NOT NULL)
		 EXECUTE FUNCTION %s()`, name, threadID, name),
	}
	for _, stmt := range stmts {
		if _, err := f.pool.Exec(f.ctx, stmt); err != nil {
			t.Fatalf("install injected failure for thread %d: %v", threadID, err)
		}
	}
}

// ─── 1. Atomicity ───────────────────────────────────────────────────────

// A run is all or nothing. Whatever stops it part-way, no thread is left ended
// but visible, and nothing the run did before the failure survives. Failure
// is injected at two points:
//   - Archiving the OPEN thread fails. That proves one thread's END and
//     ARCHIVE cannot come apart, which the original script's two separate
//     updates allowed.
//   - Archiving the already-ENDED thread fails. That happens after the open
//     thread has been ended and archived earlier in the same run, so it
//     proves the transaction rolls that earlier work back.
//
// The error must be the injected SQLSTATE. Otherwise a failure from somewhere
// else, such as the actor check, would pass without testing any rollback.
func TestRetireDirectThreadsIsAtomic(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")

	for _, failOpen := range []bool{true, false} {
		name := map[bool]string{true: "failure archiving an open thread", false: "failure archiving an ended thread"}[failOpen]
		t.Run(name, func(t *testing.T) {
			openID := f.seed(t, threadSeed{})
			endedID := f.seed(t, threadSeed{lifecycle: StateEnded})
			f.failArchiveOf(t, map[bool]int64{true: openID, false: endedID}[failOpen])
			before := f.rows(t, openID, endedID)

			res, err := RetireAllDirectThreads(f.ctx, f.pool, actor)
			var pgErr *pgconn.PgError
			if !errors.As(err, &pgErr) || pgErr.Code != raiseExceptionCode || !strings.Contains(pgErr.Message, "injected failure") {
				t.Fatalf("err = %v (result %+v); want the injected trigger failure, SQLSTATE %s", err, res, raiseExceptionCode)
			}
			if res != (RetireResult{}) {
				t.Errorf("failed run reported %+v; want the zero result, since nothing was kept", res)
			}
			if after := f.rows(t, openID, endedID); !slices.Equal(after, before) {
				t.Fatalf("failed run (%v) changed rows:\n before %+v\n after  %+v\nwant zero rows changed", err, before, after)
			}
		})
	}
}

// ─── 2. Which threads a run acts on ─────────────────────────────────────

// Open and paused direct threads are ended and archived in the same
// transaction. CURRENT_TIMESTAMP is the transaction's start time, so the end
// and archive stamps are equal only when both were written together. A paused
// thread matters because, left paused, staff could resume it into a working
// donor↔owner chat: sending checks lifecycle, not kind.
func TestRetireEndsAndArchivesOpenAndPausedDirectThreadsTogether(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	pausedBy := makeStaffUser(t, f.pool, "employee")
	pausedAt := time.Date(2026, 9, 3, 8, 0, 0, 0, time.UTC)
	openID := f.seed(t, threadSeed{})
	pausedID := f.seed(t, threadSeed{lifecycle: StatePaused, reason: ptrTo("cooling off"), changedAt: &pausedAt, changedBy: &pausedBy})

	if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	for i, got := range f.rows(t, openID, pausedID) {
		if got.Lifecycle != StateEnded || got.Reason != directRetireReason || got.ChangedBy != idText(actor) {
			t.Errorf("thread %d = %+v; want ended by actor %d with the retirement reason", i, got, actor)
		}
		if got.ArchivedAt == nullText || got.ArchivedBy != idText(actor) {
			t.Errorf("thread %d = %+v; want archived by actor %d", i, got, actor)
		}
		if got.ChangedAt != got.ArchivedAt || got.ChangedAt != got.UpdatedAt {
			t.Errorf("thread %d end=%s archive=%s updated=%s; want one transaction's timestamp", i, got.ChangedAt, got.ArchivedAt, got.UpdatedAt)
		}
	}
}

// An ended direct thread that participants can still see is archived. That
// covers the partial state an interrupted run of the original script left
// behind, and a thread staff ended by hand. The END itself is kept exactly as
// it was, because it belongs to whoever ended it.
func TestRetireArchivesEndedButUnarchivedDirectThreads(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	earlier := makeStaffUser(t, f.pool, "supervisor")
	endedAt := time.Date(2026, 9, 2, 9, 30, 0, 0, time.UTC)
	ids := []int64{
		f.seed(t, threadSeed{lifecycle: StateEnded, reason: ptrTo("closed by staff"), changedAt: &endedAt, changedBy: &earlier}),
		f.seed(t, threadSeed{lifecycle: StateEnded, reason: ptrTo(directRetireReason), changedAt: &endedAt, changedBy: &actor}),
	}
	before := f.rows(t, ids...)

	if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	for i, got := range f.rows(t, ids...) {
		if got.ArchivedAt == nullText || got.ArchivedBy != idText(actor) {
			t.Errorf("thread %d archived_at=%s archived_by=%s; want archived by actor %d", ids[i], got.ArchivedAt, got.ArchivedBy, actor)
		}
		was := before[i]
		if got.Lifecycle != was.Lifecycle || got.Reason != was.Reason || got.ChangedAt != was.ChangedAt || got.ChangedBy != was.ChangedBy {
			t.Errorf("thread %d end stamp went from %+v to %+v; want it kept", ids[i], was, got)
		}
	}
}

// ─── 3. Who may run it ──────────────────────────────────────────────────

// An actor who is not dashboard staff is refused with a typed error before a
// single row changes. The legacy is_admin flag grants nothing: production
// holds an is_admin = 1 row whose staff_tier is 'user' (see the A15 note in
// internal/auth/middleware.go).
func TestRetireRefusesNonStaffActorBeforeChangingAnything(t *testing.T) {
	f := newRetireFixture(t)
	ids := []int64{
		f.seed(t, threadSeed{}),
		f.seed(t, threadSeed{lifecycle: StatePaused}),
		f.seed(t, threadSeed{lifecycle: StateEnded}),
	}
	appUser := makeTestUser(t, f.pool, "donor")
	legacyAdmin := makeTestUser(t, f.pool, "legacy is_admin")
	if _, err := f.pool.Exec(f.ctx, `UPDATE users SET is_admin = 1 WHERE id = $1`, legacyAdmin); err != nil {
		t.Fatalf("set is_admin: %v", err)
	}
	var missing int64
	if err := f.pool.QueryRow(f.ctx, `SELECT COALESCE(MAX(id), 0) + 1000000 FROM users`).Scan(&missing); err != nil {
		t.Fatalf("pick a missing user id: %v", err)
	}
	before, pendingBefore := f.rows(t, ids...), pendingDirectRetirement(t, f.pool)

	cases := []struct {
		name      string
		actor     int64
		wantFound bool
	}{
		{"app user", appUser, true},
		{"legacy is_admin flag without a staff tier", legacyAdmin, true},
		{"no such user", missing, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := RetireAllDirectThreads(f.ctx, f.pool, tc.actor)
			var refused *ActorNotStaffError
			if !errors.As(err, &refused) {
				t.Fatalf("err = %v; want *ActorNotStaffError", err)
			}
			if refused.ActorID != tc.actor || refused.Found != tc.wantFound {
				t.Errorf("refusal = %+v; want ActorID %d, Found %v", refused, tc.actor, tc.wantFound)
			}
			if res != (RetireResult{}) {
				t.Errorf("refused run reported %+v; want the zero result", res)
			}
			if after := f.rows(t, ids...); !slices.Equal(after, before) {
				t.Fatalf("refused run changed rows:\n before %+v\n after  %+v", before, after)
			}
			if got := pendingDirectRetirement(t, f.pool); got != pendingBefore {
				t.Fatalf("refused run changed the table: pending %+v -> %+v", pendingBefore, got)
			}
		})
	}
}

// Every tier that may reach the dashboard is staff, the same answer
// auth.IsDashboardStaff gives, so the fix does not lock out a legitimate
// operator.
func TestRetireAcceptsEveryDashboardStaffTier(t *testing.T) {
	f := newRetireFixture(t)
	for _, tier := range []string{"super_admin", "admin", "supervisor", "employee"} {
		t.Run(tier, func(t *testing.T) {
			actor := makeStaffUser(t, f.pool, tier)
			id := f.seed(t, threadSeed{})
			if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
				t.Fatalf("RetireAllDirectThreads as %s: %v", tier, err)
			}
			if got := f.rows(t, id)[0]; got.Lifecycle != StateEnded || got.ChangedBy != idText(actor) {
				t.Fatalf("thread = %+v; want ended by the %s actor %d", got, tier, actor)
			}
		})
	}
}

// ─── 4. What it must not overwrite or touch ─────────────────────────────

// A thread staff had already archived keeps its original archived_at and
// archived_by. archived_by is ON DELETE SET NULL, so an archive whose archiver
// has since been removed has a time but no archiver. It must not be
// re-attributed to the actor.
func TestRetireKeepsAnExistingArchiveStamp(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	archiver := makeStaffUser(t, f.pool, "supervisor")
	archivedAt := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	ids := []int64{
		f.seed(t, threadSeed{archivedAt: &archivedAt, archivedBy: &archiver}),
		f.seed(t, threadSeed{archivedAt: &archivedAt}),
		f.seed(t, threadSeed{lifecycle: StatePaused, archivedAt: &archivedAt, archivedBy: &archiver}),
	}
	before := f.rows(t, ids...)

	if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	for i, got := range f.rows(t, ids...) {
		if got.Lifecycle != StateEnded || got.ChangedBy != idText(actor) {
			t.Errorf("thread %d = %+v; want ended by actor %d", ids[i], got, actor)
		}
		if got.ArchivedAt != before[i].ArchivedAt || got.ArchivedBy != before[i].ArchivedBy {
			t.Errorf("thread %d archive stamp went from %s/%s to %s/%s; want the original kept",
				ids[i], before[i].ArchivedAt, before[i].ArchivedBy, got.ArchivedAt, got.ArchivedBy)
		}
	}
}

// Support threads are never touched, in any state. chat_threads.kind is
// CHECKed to 'direct' or 'support' (migration 119), so support is the only
// non-direct kind that can exist. The other chat systems live in their own
// tables, which the retirement never names.
func TestRetireLeavesSupportThreadsUntouched(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	archivedAt := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	ids := []int64{
		f.seed(t, threadSeed{kind: "support"}),
		f.seed(t, threadSeed{kind: "support", lifecycle: StatePaused}),
		f.seed(t, threadSeed{kind: "support", lifecycle: StateEnded}),
		f.seed(t, threadSeed{kind: "support", archivedAt: &archivedAt}),
	}
	before := f.rows(t, ids...)

	if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	if after := f.rows(t, ids...); !slices.Equal(after, before) {
		t.Fatalf("support threads changed:\n before %+v\n after  %+v", before, after)
	}
}

// ─── 5. Re-running and reporting ────────────────────────────────────────

// A second run finds nothing to do and changes nothing, timestamps included.
func TestRetireSecondRunChangesNothing(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	archivedAt := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	ids := []int64{
		f.seed(t, threadSeed{}),
		f.seed(t, threadSeed{lifecycle: StatePaused}),
		f.seed(t, threadSeed{lifecycle: StateEnded}),
		f.seed(t, threadSeed{archivedAt: &archivedAt}),
	}
	if _, err := RetireAllDirectThreads(f.ctx, f.pool, actor); err != nil {
		t.Fatalf("first run: %v", err)
	}
	afterFirst := f.rows(t, ids...)

	res, err := RetireAllDirectThreads(f.ctx, f.pool, actor)
	if err != nil {
		t.Fatalf("second run: %v", err)
	}
	if res != (RetireResult{}) {
		t.Fatalf("second run reported %+v; want nothing changed", res)
	}
	if afterSecond := f.rows(t, ids...); !slices.Equal(afterSecond, afterFirst) {
		t.Fatalf("second run changed rows:\n first  %+v\n second %+v", afterFirst, afterSecond)
	}
}

// The result counts exactly what was pending: open and paused threads ended,
// and ended-but-visible threads archived. The script prints these counts, and
// the runbook's pre-flight predicts them.
func TestRetireReportsWhatItChanged(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	f.seed(t, threadSeed{})
	f.seed(t, threadSeed{lifecycle: StatePaused})
	f.seed(t, threadSeed{lifecycle: StateEnded})
	f.seed(t, threadSeed{lifecycle: StateEnded})
	want := pendingDirectRetirement(t, f.pool)

	got, err := RetireAllDirectThreads(f.ctx, f.pool, actor)
	if err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	if got != want {
		t.Fatalf("result = %+v; want %+v (open+paused ended, ended-but-visible archived)", got, want)
	}
	if got.Total() != want.Ended+want.Archived {
		t.Fatalf("Total() = %d; want %d", got.Total(), want.Ended+want.Archived)
	}
}
