// apply_race_test.go
//
// Pins OPOS #26431. Apply reads a thread's lifecycle, decides from it, then
// writes. Before the fix the write said only WHERE id = $1. So a pause or
// resume that read an open or paused thread, then lost a race to an END, wrote
// over `ended` and reopened a closed chat. The END can come from a second staff
// member or from cmd/retire-direct-chats.
//
// The race is reproduced without sleeps through testHookBeforeWrite, which runs
// after Apply has read and decided and just before it writes. The END lands in
// that window in one of two ways:
//   - committed: a second request ends the thread and commits before Apply's
//     write starts;
//   - lock wait: a transaction ends the thread and stays open, and commits only
//     once Postgres reports Apply's write blocked behind it. This is the shape
//     of the production retire run, which holds its row locks until it commits.
//
// Shares newTestPool, makeTestUser and makeStaffUser with the retire tests, so
// it needs TEST_DATABASE_URL and skips without one.
package chatlifecycle

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixture ────────────────────────────────────────────────────────────

// winnerReason is the reason the staff member who wins a race records, so a
// test can tell whose write a row holds.
const winnerReason = "set by the staff member who won the race"

// lockWaitTimeout is a failsafe against a hung test, not a timing assumption.
// A lock-wait case commits when it observes Apply blocked, never on a clock.
const lockWaitTimeout = 2 * time.Minute

// raceFixture holds the pools and the two staff members in a race: the loser,
// whose Apply call is under test, and the winner, whose change lands first.
type raceFixture struct {
	ctx  context.Context
	pool *pgxpool.Pool
	// loserPool is a second pool to the same database. Every connection in it
	// carries loserApp as its application_name, so a lock-wait case can pick
	// out the loser's own blocked write in pg_stat_activity. Without that, any
	// backend on the server that is blocked by the ending transaction would
	// count, such as another test run's write to a direct thread the retire
	// run also locked.
	loserPool *pgxpool.Pool
	loserApp  string
	loser     int64
	winner    int64
}

// newRaceFixture connects to the migrated test database and creates both
// staff members.
func newRaceFixture(t *testing.T) *raceFixture {
	t.Helper()
	pool := newTestPool(t)
	f := &raceFixture{
		ctx:      context.Background(),
		pool:     pool,
		loserApp: "chatlifecycle-race-loser-" + strconv.Itoa(os.Getpid()),
		loser:    makeStaffUser(t, pool, "employee"),
		winner:   makeStaffUser(t, pool, "admin"),
	}
	cfg, err := pgxpool.ParseConfig(os.Getenv("TEST_DATABASE_URL"))
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL for the loser's pool: %v", err)
	}
	cfg.ConnConfig.RuntimeParams["application_name"] = f.loserApp
	if f.loserPool, err = pgxpool.NewWithConfig(f.ctx, cfg); err != nil {
		t.Fatalf("connect the loser's pool: %v", err)
	}
	t.Cleanup(f.loserPool.Close)
	return f
}

// seed inserts one thread of kind k in the given lifecycle and returns its id.
// Donor and staff threads go when their participants are deleted, through
// ON DELETE CASCADE. chat_group_threads has no foreign keys (migration 120),
// so a group thread is deleted explicitly.
func (f *raceFixture) seed(t *testing.T, k Kind, lifecycle string) int64 {
	t.Helper()
	var id int64
	var err error
	switch k {
	case KindDonor:
		// A direct thread, so the retire run selects it. It gets its own pair,
		// because uq_chat_pair allows one thread per donor + owner.
		donor, owner := makeTestUser(t, f.pool, "donor"), makeTestUser(t, f.pool, "owner")
		err = f.pool.QueryRow(f.ctx, `
			INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind, lifecycle)
			VALUES ($1, $2, 'active', $1, 'direct', $3) RETURNING id`, donor, owner, lifecycle).Scan(&id)
	case KindStaff:
		a, b := makeTestUser(t, f.pool, "staff a"), makeTestUser(t, f.pool, "staff b")
		if a > b {
			a, b = b, a // chk_staff_chat_pair_ordered: user_a_id < user_b_id
		}
		err = f.pool.QueryRow(f.ctx, `
			INSERT INTO staff_chat_threads (user_a_id, user_b_id, lifecycle)
			VALUES ($1, $2, $3) RETURNING id`, a, b, lifecycle).Scan(&id)
	case KindGroup:
		err = f.pool.QueryRow(f.ctx, `
			INSERT INTO chat_group_threads (kind, created_by_staff_id, lifecycle)
			VALUES ('masked', $1, $2) RETURNING id`, f.winner, lifecycle).Scan(&id)
		if err == nil {
			t.Cleanup(func() { f.deleteThread(t, KindGroup, id) })
		}
	default:
		t.Fatalf("seed: no fixture for kind %q", k)
	}
	if err != nil {
		t.Fatalf("seed %s thread in %s: %v", k, lifecycle, err)
	}
	return id
}

// deleteThread removes a thread row the way the Trash's final DELETE does.
func (f *raceFixture) deleteThread(t *testing.T, k Kind, id int64) {
	t.Helper()
	sys, _ := Lookup(k)
	if _, err := f.pool.Exec(context.Background(), "DELETE FROM "+sys.ThreadTable+" WHERE id = $1", id); err != nil {
		t.Errorf("delete %s/%d: %v", sys.ThreadTable, id, err)
	}
}

// raceRow is what a lifecycle write sets, as comparable values, so one ==
// decides whether the winner's write survived.
type raceRow struct {
	Lifecycle, Reason, ChangedBy string
	Archived                     bool
}

// row reads one thread. A NULL reason or actor reads as "".
func (f *raceFixture) row(t *testing.T, k Kind, id int64) raceRow {
	t.Helper()
	sys, _ := Lookup(k)
	var r raceRow
	err := f.pool.QueryRow(f.ctx, `
		SELECT lifecycle, COALESCE(lifecycle_reason, ''), COALESCE(lifecycle_changed_by::text, ''),
		       archived_at IS NOT NULL
		  FROM `+sys.ThreadTable+` WHERE id = $1`, id,
	).Scan(&r.Lifecycle, &r.Reason, &r.ChangedBy, &r.Archived)
	if err != nil {
		t.Fatalf("read %s/%d: %v", sys.ThreadTable, id, err)
	}
	return r
}

// beforeFirstWrite runs fn in Apply's window between read and write, on the
// first write attempt only. Later attempts pass straight through: a re-read
// after a lost race, and any nested Apply that fn itself makes.
func beforeFirstWrite(t *testing.T, fn func()) {
	t.Helper()
	fired := false
	testHookBeforeWrite = func() {
		if fired {
			return
		}
		fired = true
		fn()
	}
	t.Cleanup(func() { testHookBeforeWrite = nil })
}

// ─── Ways to end a thread inside Apply's window ─────────────────────────

// ender builds the hook body that ends thread id, plus a wait func reporting
// whether that END itself succeeded. In the lock-wait cases the END finishes on
// another goroutine.
type ender func(f *raceFixture, t *testing.T, k Kind, id int64) (hook func(), wait func() error)

// endByRequest is a second staff member ending the thread from the dashboard:
// a whole Apply call, committed before the loser's write starts.
func endByRequest(f *raceFixture, _ *testing.T, k Kind, id int64) (func(), func() error) {
	var endErr error
	hook := func() { _, endErr = Apply(f.ctx, f.pool, k, id, ActionEnd, winnerReason, f.winner) }
	return hook, func() error { return endErr }
}

// endByRetireRun is cmd/retire-direct-chats committing a whole run.
func endByRetireRun(f *raceFixture, _ *testing.T, _ Kind, _ int64) (func(), func() error) {
	var runErr error
	hook := func() { _, runErr = RetireAllDirectThreads(f.ctx, f.pool, f.winner) }
	return hook, func() error { return runErr }
}

// retireRunInTx runs the production retire run's own statements, uncommitted.
func retireRunInTx(f *raceFixture, tx pgx.Tx, _ Kind, _ int64) error {
	_, err := retireInTx(f.ctx, tx, f.winner)
	return err
}

// endInTx ends one thread, uncommitted.
func endInTx(f *raceFixture, tx pgx.Tx, k Kind, id int64) error {
	sys, _ := Lookup(k)
	_, err := tx.Exec(f.ctx, "UPDATE "+sys.ThreadTable+` SET lifecycle = 'ended', lifecycle_reason = $2,
		lifecycle_changed_at = CURRENT_TIMESTAMP, lifecycle_changed_by = $3, updated_at = CURRENT_TIMESTAMP
		WHERE id = $1`, id, winnerReason, f.winner)
	return err
}

// endHoldingLock returns an ender that runs end in a transaction and leaves it
// open, so its row lock is held when Apply's write reaches the row. It commits
// only once Postgres reports one of the loser pool's backends blocked by that
// transaction, which can only be the loser's write. So the case must pass
// f.loserPool to Apply.
func endHoldingLock(end func(f *raceFixture, tx pgx.Tx, k Kind, id int64) error) ender {
	return func(f *raceFixture, _ *testing.T, k Kind, id int64) (func(), func() error) {
		done := make(chan error, 1)
		fired := false
		hook := func() {
			fired = true
			tx, err := f.pool.Begin(f.ctx)
			if err != nil {
				done <- fmt.Errorf("begin the ending transaction: %w", err)
				return
			}
			var pid int32
			err = tx.QueryRow(f.ctx, `SELECT pg_backend_pid()`).Scan(&pid)
			if err == nil {
				err = end(f, tx, k, id)
			}
			if err != nil {
				done <- errors.Join(fmt.Errorf("end inside the open transaction: %w", err), tx.Rollback(f.ctx))
				return
			}
			go func() { done <- f.commitOnceLoserBlocked(tx, pid) }()
		}
		wait := func() error {
			if !fired {
				return errors.New("Apply never reached its write, so the END never ran")
			}
			return <-done
		}
		return hook, wait
	}
}

// commitOnceLoserBlocked commits tx as soon as a backend of the loser's pool is
// waiting on a lock tx holds. Each check is a round trip to the server, so the
// loop needs no sleep.
func (f *raceFixture) commitOnceLoserBlocked(tx pgx.Tx, holderPID int32) error {
	waitCtx, cancel := context.WithTimeout(f.ctx, lockWaitTimeout)
	defer cancel()
	for {
		var blocked bool
		err := f.pool.QueryRow(waitCtx, `
			SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			                WHERE application_name = $2 AND $1::int = ANY (pg_blocking_pids(pid)))`,
			holderPID, f.loserApp).Scan(&blocked)
		if err != nil {
			return errors.Join(fmt.Errorf("wait for the loser's write to block on the ending transaction: %w", err), tx.Rollback(f.ctx))
		}
		if blocked {
			return tx.Commit(f.ctx)
		}
	}
}

// ─── Pause and resume never reopen an ended thread ──────────────────────

// A pause or resume that read the thread before it was ended is refused with
// ErrEnded (HTTP 409 in the dashboard), and the thread keeps the winner's END,
// both when the END committed first and when Apply's write waited on its lock.
//
// Group resume, and group pause without a reason, are left out. Either one
// stores a NULL reason, and chat_group_threads.lifecycle_reason is NOT NULL
// (migration 120). That is a separate defect, which fails with or without a
// race.
func TestApplyRefusesPauseAndResumeOnAThreadEndedAfterItsRead(t *testing.T) {
	f := newRaceFixture(t)
	cases := []struct {
		name   string
		kind   Kind
		from   string
		action string
		reason string
		end    ender
		// byRetire: the winner is the retire run, which archives the thread too
		// and records its own reason.
		byRetire bool
	}{
		{"direct pause vs a staff end", KindDonor, StateOpen, ActionPause, "cooling off", endByRequest, false},
		{"direct resume vs the retire run", KindDonor, StatePaused, ActionResume, "", endByRetireRun, true},
		{"direct pause waiting on the retire run's lock", KindDonor, StateOpen, ActionPause, "cooling off", endHoldingLock(retireRunInTx), true},
		{"direct resume waiting on the retire run's lock", KindDonor, StatePaused, ActionResume, "", endHoldingLock(retireRunInTx), true},
		{"staff resume vs a staff end", KindStaff, StatePaused, ActionResume, "", endByRequest, false},
		{"staff pause waiting on an end's lock", KindStaff, StateOpen, ActionPause, "cooling off", endHoldingLock(endInTx), false},
		{"group pause vs a staff end", KindGroup, StateOpen, ActionPause, "cooling off", endByRequest, false},
		{"group re-pause waiting on an end's lock", KindGroup, StatePaused, ActionPause, "still cooling off", endHoldingLock(endInTx), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := f.seed(t, tc.kind, tc.from)
			hook, wait := tc.end(f, t, tc.kind, id)
			beforeFirstWrite(t, hook)

			// Through the loser's own pool, which lock-wait cases watch for.
			st, err := Apply(f.ctx, f.loserPool, tc.kind, id, tc.action, tc.reason, f.loser)
			if endErr := wait(); endErr != nil {
				t.Fatalf("the concurrent END failed, so there was no race: %v", endErr)
			}
			if !errors.Is(err, ErrEnded) {
				t.Errorf("Apply(%s) = %+v, %v; want ErrEnded, because the thread was ended before the write", tc.action, st, err)
			}
			want := raceRow{Lifecycle: StateEnded, Reason: winnerReason, ChangedBy: idText(f.winner)}
			if tc.byRetire {
				want.Reason, want.Archived = directRetireReason, true
			}
			if got := f.row(t, tc.kind, id); got != want {
				t.Fatalf("thread after the race = %+v; want the END kept, %+v", got, want)
			}
		})
	}
}

// ─── The other outcomes of a lost race ──────────────────────────────────

// An END with no reason on an ended thread is a no-op. So an END that read the
// thread open, then lost the race to another END, returns the ended state and
// must not replace the winner's reason and actor with its own blank ones.
func TestApplyBlankEndAfterAConcurrentEndKeepsTheWinnersStamp(t *testing.T) {
	f := newRaceFixture(t)
	id := f.seed(t, KindStaff, StateOpen)
	hook, wait := endByRequest(f, t, KindStaff, id)
	beforeFirstWrite(t, hook)

	st, err := Apply(f.ctx, f.pool, KindStaff, id, ActionEnd, "", f.loser)
	if endErr := wait(); endErr != nil {
		t.Fatalf("the concurrent END failed, so there was no race: %v", endErr)
	}
	if err != nil || st.Lifecycle != StateEnded {
		t.Errorf("Apply(end) = %+v, %v; want the ended state and no error", st, err)
	}
	want := raceRow{Lifecycle: StateEnded, Reason: winnerReason, ChangedBy: idText(f.winner)}
	if got := f.row(t, KindStaff, id); got != want {
		t.Fatalf("thread = %+v; want the winner's END untouched, %+v", got, want)
	}
}

// A lost race is decided again against the state the winner left, not refused
// outright. A pause that read the thread open and lost to another pause is still
// a valid pause, so it lands with its own reason.
func TestApplyDecidesAgainAfterLosingARaceToAnAllowedChange(t *testing.T) {
	f := newRaceFixture(t)
	id := f.seed(t, KindDonor, StateOpen)
	var winErr error
	beforeFirstWrite(t, func() {
		_, winErr = Apply(f.ctx, f.pool, KindDonor, id, ActionPause, winnerReason, f.winner)
	})

	const loserReason = "paused again by the second staff member"
	st, err := Apply(f.ctx, f.pool, KindDonor, id, ActionPause, loserReason, f.loser)
	if winErr != nil {
		t.Fatalf("the concurrent pause failed, so there was no race: %v", winErr)
	}
	if err != nil || st.Lifecycle != StatePaused {
		t.Fatalf("Apply(pause) = %+v, %v; want paused and no error", st, err)
	}
	want := raceRow{Lifecycle: StatePaused, Reason: loserReason, ChangedBy: idText(f.loser)}
	if got := f.row(t, KindDonor, id); got != want {
		t.Fatalf("thread = %+v; want the later pause applied, %+v", got, want)
	}
}

// A thread deleted between Apply's read and its write is reported as not found
// (HTTP 404), whatever the action. The write is an UPDATE, so it cannot bring
// the thread back. Archive and unarchive decide nothing from the read beyond
// the thread existing, so this is the only race they are exposed to.
func TestApplyOnAThreadDeletedAfterItsReadIsNotFound(t *testing.T) {
	f := newRaceFixture(t)
	for _, action := range []string{ActionPause, ActionResume, ActionEnd, ActionArchive, ActionUnarchive} {
		t.Run(action, func(t *testing.T) {
			// Paused, so every one of the five actions gets as far as its write.
			id := f.seed(t, KindDonor, StatePaused)
			beforeFirstWrite(t, func() { f.deleteThread(t, KindDonor, id) })

			st, err := Apply(f.ctx, f.pool, KindDonor, id, action, "a reason", f.loser)
			if !errors.Is(err, ErrNotFound) {
				t.Errorf("Apply(%s) = %+v, %v; want ErrNotFound", action, st, err)
			}
			var n int
			if err := f.pool.QueryRow(f.ctx, `SELECT count(*) FROM chat_threads WHERE id = $1`, id).Scan(&n); err != nil {
				t.Fatalf("count thread %d: %v", id, err)
			}
			if n != 0 {
				t.Fatalf("thread %d exists again after Apply(%s) on a deleted thread", id, action)
			}
		})
	}
}

// Apply reads again only a bounded number of times. When every attempt loses
// to yet another change, it gives up with errLifecycleChanged rather than
// looping, and none of its writes has landed.
func TestApplyGivesUpWhenTheLifecycleKeepsChanging(t *testing.T) {
	f := newRaceFixture(t)
	id := f.seed(t, KindDonor, StateOpen)
	flips := 0
	// Unlike beforeFirstWrite, this hook acts on every attempt: each one flips
	// the thread between open and paused, so no attempt finds the state it read.
	testHookBeforeWrite = func() {
		flips++
		if _, err := f.pool.Exec(f.ctx, `
			UPDATE chat_threads
			   SET lifecycle = CASE lifecycle WHEN 'open' THEN 'paused' ELSE 'open' END,
			       lifecycle_reason = $2, lifecycle_changed_by = $3
			 WHERE id = $1`, id, winnerReason, f.winner); err != nil {
			t.Fatalf("flip thread %d: %v", id, err)
		}
	}
	t.Cleanup(func() { testHookBeforeWrite = nil })

	st, err := Apply(f.ctx, f.pool, KindDonor, id, ActionPause, "never lands", f.loser)
	if !errors.Is(err, errLifecycleChanged) {
		t.Fatalf("Apply(pause) = %+v, %v; want errLifecycleChanged after %d lost attempts", st, err, maxApplyAttempts)
	}
	if flips != maxApplyAttempts {
		t.Errorf("Apply reached its write %d times; want maxApplyAttempts = %d", flips, maxApplyAttempts)
	}
	if got := f.row(t, KindDonor, id); got.ChangedBy != idText(f.winner) || got.Reason != winnerReason {
		t.Fatalf("thread = %+v; want only the flips' writes, none of Apply's", got)
	}
}
