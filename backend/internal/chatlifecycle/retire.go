// retire.go: the one-off bulk retirement of the donor↔owner direct chat
// (OPOS #25284 Phase 4), run by cmd/retire-direct-chats.
//
// Every other function in this package changes ONE thread at a time on a
// staff member's click. This one changes every direct thread in the table at
// once, on production. OPOS #26412 found four ways the first version could
// leave production worse than it found it. The fix for each is shaped here:
//
//  1. All or nothing. The run is ONE transaction, and a thread's END and
//     ARCHIVE are written by the same statement, so no failure can leave a
//     thread ended but still visible to its participants.
//  2. Paused threads are retired too. Left paused, staff could resume one
//     into a working direct chat: sending checks lifecycle, never kind.
//  3. The actor must be dashboard staff, checked before any row changes.
//  4. An archive stamp staff already set is kept, not overwritten.
//
// The runbook for the production run is docs/runbooks/retire-direct-chats.md.
// Its pre-flight and post-check queries mirror the two UPDATEs below, so a
// change to either statement must be made in the runbook too.
package chatlifecycle

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// directRetireReason is stamped as lifecycle_reason on every thread a run
// ends. The app shows lifecycle_reason verbatim in the ended banner, and the
// runbook's post-checks and restore match on this exact text (em dash U+2014).
const directRetireReason = "OPOS #25284 Phase 4 — direct donor-owner chat retired"

// ─── Result and refusal ─────────────────────────────────────────────────

// RetireResult reports what one RetireAllDirectThreads run changed.
type RetireResult struct {
	// Ended counts direct threads that were open or paused and are now ended.
	// Every one of them is archived too; one that staff had already archived
	// keeps its original archived_at and archived_by.
	Ended int
	// Archived counts direct threads that were already ended but still visible
	// to their participants, and are now archived. Their end stamp is kept.
	Archived int
}

// Total is every thread the run changed, the number the script has always
// printed as "ended+archived N thread(s)".
func (r RetireResult) Total() int { return r.Ended + r.Archived }

// ActorNotStaffError refuses a run whose actor is not dashboard staff. It is
// returned before any row changes, so a refused run has changed nothing.
type ActorNotStaffError struct {
	// ActorID is the id the caller passed.
	ActorID int64
	// Found is false when no users row has that id.
	Found bool
	// StaffTier is the actor's raw staff_tier, when Found.
	StaffTier string
}

// Error names the id and why it was refused, and says which accounts are
// accepted, because the operator's fix is to pick a different id.
func (e *ActorNotStaffError) Error() string {
	if !e.Found {
		return fmt.Sprintf("no user has id %d; pass the id of a dashboard staff account "+
			"(staff_tier super_admin, admin, supervisor or employee)", e.ActorID)
	}
	return fmt.Sprintf("user %d is not dashboard staff (staff_tier %q); pass the id of a "+
		"super_admin, admin, supervisor or employee account", e.ActorID, e.StaffTier)
}

// ─── The two statements ─────────────────────────────────────────────────

const (
	// lockActorSQL reads the actor's tier and holds the row FOR SHARE until
	// the transaction ends, so the actor cannot be demoted or deleted between
	// the check and the updates that record them.
	lockActorSQL = `SELECT staff_tier FROM users WHERE id = $1 FOR SHARE`

	// endAndArchiveOpenSQL ends every open or paused direct thread and
	// archives it in the SAME statement, which is what makes a half-retired
	// thread impossible. In SET, archived_at and archived_by name the row's
	// OLD values: an existing archive stamp is kept whole. archived_by is
	// decided on archived_at rather than COALESCEd on itself, because it is
	// ON DELETE SET NULL. A thread archived by a since-deleted account has a
	// time but no archiver, and must not be re-attributed to this actor.
	endAndArchiveOpenSQL = `
		UPDATE chat_threads
		   SET lifecycle            = 'ended',
		       lifecycle_reason     = $1,
		       lifecycle_changed_at = CURRENT_TIMESTAMP,
		       lifecycle_changed_by = $2,
		       archived_at          = COALESCE(archived_at, CURRENT_TIMESTAMP),
		       archived_by          = CASE WHEN archived_at IS NULL THEN $2 ELSE archived_by END,
		       updated_at           = CURRENT_TIMESTAMP
		 WHERE kind = 'direct' AND lifecycle IN ('open', 'paused')`

	// archiveEndedSQL archives ended direct threads participants can still
	// see. That covers threads staff ended by hand, and the partial state an
	// interrupted run of the original script left behind. The end stamp
	// (lifecycle_reason, _changed_at, _changed_by) belongs to whoever ended
	// the thread and is not touched.
	archiveEndedSQL = `
		UPDATE chat_threads
		   SET archived_at = CURRENT_TIMESTAMP,
		       archived_by = $1,
		       updated_at  = CURRENT_TIMESTAMP
		 WHERE kind = 'direct' AND lifecycle = 'ended' AND archived_at IS NULL`
)

// ─── Entry point ────────────────────────────────────────────────────────

// RetireAllDirectThreads retires every kind='direct' chat_threads row in one
// transaction:
//
//   - open and paused threads are ended and archived (RetireResult.Ended);
//   - ended threads still visible to participants are archived
//     (RetireResult.Archived).
//
// kind='support' rows are never selected. A re-run finds nothing to do and
// returns the zero RetireResult.
//
// Failure modes, all of which leave every row as it was:
//   - *ActorNotStaffError when actorID is not a dashboard staff account;
//   - any database error before the commit, which rolls the whole run back.
//
// A commit error is the one ambiguous case: the server may have committed
// before the connection failed. Its message says so, and the runbook's
// post-checks settle it.
func RetireAllDirectThreads(ctx context.Context, pool *pgxpool.Pool, actorID int64) (RetireResult, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return RetireResult{}, fmt.Errorf("retire direct threads: begin: %w", err)
	}
	// After a successful Commit this is a no-op (pgx.ErrTxClosed). On any
	// early return it discards the run, and the server discards an
	// unfinished transaction on its own if even the rollback cannot reach it.
	defer func() { _ = tx.Rollback(ctx) }()

	if err := requireStaffActor(ctx, tx, actorID); err != nil {
		return RetireResult{}, err
	}
	res, err := retireInTx(ctx, tx, actorID)
	if err != nil {
		return RetireResult{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RetireResult{}, fmt.Errorf("retire direct threads: commit failed, outcome unknown, "+
			"run the runbook post-checks: %w", err)
	}
	return res, nil
}

// requireStaffActor refuses an actor who is not dashboard staff. "Staff" is
// the one definition every /api/admin request is gated on
// (auth.IsDashboardStaff): permissions.CanAccessDashboard applied to
// permissions.TierFrom(staff_tier). The legacy is_admin flag is deliberately
// not read. It is called on the permissions package directly so this package
// does not import auth, and with it gin.
func requireStaffActor(ctx context.Context, tx pgx.Tx, actorID int64) error {
	var tier string
	err := tx.QueryRow(ctx, lockActorSQL, actorID).Scan(&tier)
	if errors.Is(err, pgx.ErrNoRows) {
		return &ActorNotStaffError{ActorID: actorID}
	}
	if err != nil {
		return fmt.Errorf("retire direct threads: load actor %d (rolled back, nothing changed): %w", actorID, err)
	}
	if !permissions.CanAccessDashboard(permissions.TierFrom(tier)) {
		return &ActorNotStaffError{ActorID: actorID, Found: true, StaffTier: tier}
	}
	return nil
}

// retireInTx runs the two statements inside the caller's transaction, and
// their order matters. Under READ COMMITTED each statement sees whatever was
// committed before it started. So a thread a staff member ends while statement
// 1 is running is still archived by statement 2. In the opposite order, that
// thread would slip past both. A thread statement 1 ends is archived by that
// same statement, so statement 2 never sees it.
func retireInTx(ctx context.Context, tx pgx.Tx, actorID int64) (RetireResult, error) {
	ended, err := tx.Exec(ctx, endAndArchiveOpenSQL, directRetireReason, actorID)
	if err != nil {
		return RetireResult{}, fmt.Errorf("retire direct threads: end open/paused (rolled back, nothing changed): %w", err)
	}
	archived, err := tx.Exec(ctx, archiveEndedSQL, actorID)
	if err != nil {
		return RetireResult{}, fmt.Errorf("retire direct threads: archive ended (rolled back, nothing changed): %w", err)
	}
	return RetireResult{Ended: int(ended.RowsAffected()), Archived: int(archived.RowsAffected())}, nil
}
