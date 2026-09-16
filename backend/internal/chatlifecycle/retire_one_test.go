// retire_one_test.go
//
// Pins RetireDirectThreadInTx (OPOS #26466): the retire run of
// RetireAllDirectThreads, applied to ONE chat_threads row inside the caller's
// transaction. The Trash restore calls it, so a direct chat that comes back out
// of the Trash comes back closed, exactly as the production run would have left
// it:
//   - open and paused threads are ended and archived, with the run's reason;
//   - an archive stamp staff already set is kept;
//   - an ended thread keeps its end stamp and is only archived;
//   - an ended and archived thread, and every support thread, is not touched.
//
// Every case also seeds an open direct "neighbour" thread and checks it is left
// alone. The statements are the bulk run's with an id condition added, so a
// missing condition would retire the whole table, and this is what catches it.
//
// Shares newRetireFixture, makeStaffUser, threadSeed and threadRow with the
// retire tests, so it needs TEST_DATABASE_URL and skips without one.
package chatlifecycle

import (
	"testing"
	"time"
)

// ─── Cases ──────────────────────────────────────────────────────────────

// retireOneCase is one starting state and what RetireDirectThreadInTx must
// leave behind.
type retireOneCase struct {
	name string
	seed threadSeed
	// want builds the expected row from the row before the call and txTime, the
	// transaction's CURRENT_TIMESTAMP as a TIMESTAMP column reads it back.
	want       func(before threadRow, txTime string) threadRow
	wantResult RetireResult
}

// retireOneCases lists every state a restored chat_threads row can be in.
// actor performs the call; earlier is the staff member who set any stamp the
// thread already carries, at past.
func retireOneCases(actor, earlier int64, past time.Time) []retireOneCase {
	actorText := idText(actor)
	unchanged := func(before threadRow, _ string) threadRow { return before }
	endedAndArchivedByActor := func(_ threadRow, txTime string) threadRow {
		return threadRow{
			Lifecycle: StateEnded, Reason: directRetireReason, ChangedAt: txTime, ChangedBy: actorText,
			ArchivedAt: txTime, ArchivedBy: actorText, UpdatedAt: txTime,
		}
	}
	endedByActorArchiveKept := func(before threadRow, txTime string) threadRow {
		return threadRow{
			Lifecycle: StateEnded, Reason: directRetireReason, ChangedAt: txTime, ChangedBy: actorText,
			ArchivedAt: before.ArchivedAt, ArchivedBy: before.ArchivedBy, UpdatedAt: txTime,
		}
	}
	staffEnd := threadSeed{lifecycle: StateEnded, reason: ptrTo("closed by staff"), changedAt: &past, changedBy: &earlier}

	return []retireOneCase{
		{"open direct thread is ended and archived",
			threadSeed{}, endedAndArchivedByActor, RetireResult{Ended: 1}},
		{"paused direct thread is ended and archived, replacing the pause reason",
			threadSeed{lifecycle: StatePaused, reason: ptrTo("cooling off"), changedAt: &past, changedBy: &earlier},
			endedAndArchivedByActor, RetireResult{Ended: 1}},
		{"archived open direct thread is ended and keeps its archive stamp",
			threadSeed{archivedAt: &past, archivedBy: &earlier}, endedByActorArchiveKept, RetireResult{Ended: 1}},
		{"archive stamp whose archiver was deleted keeps its NULL archived_by",
			threadSeed{archivedAt: &past}, endedByActorArchiveKept, RetireResult{Ended: 1}},
		{"ended but visible direct thread is archived and keeps its end stamp",
			staffEnd,
			func(before threadRow, txTime string) threadRow {
				return threadRow{
					Lifecycle: StateEnded, Reason: before.Reason, ChangedAt: before.ChangedAt, ChangedBy: before.ChangedBy,
					ArchivedAt: txTime, ArchivedBy: actorText, UpdatedAt: txTime,
				}
			}, RetireResult{Archived: 1}},
		{"ended and archived direct thread is left exactly as it was",
			threadSeed{lifecycle: StateEnded, reason: ptrTo("closed by staff"), changedAt: &past, changedBy: &earlier,
				archivedAt: &past, archivedBy: &earlier},
			unchanged, RetireResult{}},
		{"open support thread is left exactly as it was",
			threadSeed{kind: "support"}, unchanged, RetireResult{}},
		{"ended but visible support thread is left exactly as it was",
			threadSeed{kind: "support", lifecycle: StateEnded, reason: ptrTo("closed by staff"), changedAt: &past, changedBy: &earlier},
			unchanged, RetireResult{}},
	}
}

// ─── Test ───────────────────────────────────────────────────────────────

// TestRetireDirectThreadInTxRetiresOnlyThatThread runs every case against a
// fresh thread, next to an open direct neighbour that must not change.
func TestRetireDirectThreadInTxRetiresOnlyThatThread(t *testing.T) {
	f := newRetireFixture(t)
	actor := makeStaffUser(t, f.pool, "admin")
	earlier := makeStaffUser(t, f.pool, "supervisor")
	past := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)

	for _, tc := range retireOneCases(actor, earlier, past) {
		t.Run(tc.name, func(t *testing.T) {
			id := f.seed(t, tc.seed)
			neighbour := f.seed(t, threadSeed{})
			before := f.rows(t, id, neighbour)

			res, txTime := f.retireOne(t, id, actor)

			after := f.rows(t, id, neighbour)
			if res != tc.wantResult {
				t.Errorf("RetireDirectThreadInTx(%d) = %+v, want %+v", id, res, tc.wantResult)
			}
			if want := tc.want(before[0], txTime); after[0] != want {
				t.Errorf("thread %d after the call:\n  got  %+v\n  want %+v", id, after[0], want)
			}
			if after[1] != before[1] {
				t.Errorf("neighbour thread %d changed:\n  before %+v\n  after  %+v\nthe call must retire only the thread it names",
					neighbour, before[1], after[1])
			}
		})
	}
}

// ─── Helper ─────────────────────────────────────────────────────────────

// retireOne calls RetireDirectThreadInTx on thread id in a transaction of its
// own, commits it, and returns the result with the transaction's
// CURRENT_TIMESTAMP as text. That timestamp is read inside the same session,
// so it converts to TIMESTAMP exactly as the columns the call writes do.
func (f *retireFixture) retireOne(t *testing.T, id, actor int64) (RetireResult, string) {
	t.Helper()
	tx, err := f.pool.Begin(f.ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	// A no-op once Commit has succeeded.
	defer func() { _ = tx.Rollback(f.ctx) }()

	var txTime string
	if err := tx.QueryRow(f.ctx, `SELECT CURRENT_TIMESTAMP::timestamp::text`).Scan(&txTime); err != nil {
		t.Fatalf("read the transaction timestamp: %v", err)
	}
	res, err := RetireDirectThreadInTx(f.ctx, tx, id, actor)
	if err != nil {
		t.Fatalf("RetireDirectThreadInTx(%d): %v", id, err)
	}
	if err := tx.Commit(f.ctx); err != nil {
		t.Fatalf("commit: %v", err)
	}
	return res, txTime
}
