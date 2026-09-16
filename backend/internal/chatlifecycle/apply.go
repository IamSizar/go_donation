// apply.go: Apply, the one path by which a staff member ends, pauses, resumes,
// archives or unarchives a single chat thread, and the writes behind it.
//
// It was split out of chatlifecycle.go, which keeps the state model, the chat
// systems and the send gate, to keep both files under the repo's 500-line
// limit. OPOS #26431 made every lifecycle write conditional on the lifecycle
// it was decided from. The CONCURRENCY note on Apply explains why.
package chatlifecycle

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Applying a transition ──────────────────────────────────────────────

// errLifecycleChanged means a lifecycle write matched no row: either the
// thread's lifecycle was no longer the one Apply decided from, or the thread
// was deleted. Apply handles it by reading again. It only escapes Apply after
// maxApplyAttempts lost attempts in a row, and the handler then logs it and
// answers 500.
var errLifecycleChanged = errors.New("chat lifecycle changed while the action was being applied")

// maxApplyAttempts bounds Apply's read, decide and write loop. Each lost
// attempt means another request committed a lifecycle change to this same
// thread between Apply's read and its write. So the second attempt is almost
// always the last. Losing a third time means other staff members are flipping
// the same chat within milliseconds of each other.
const maxApplyAttempts = 3

// Apply performs one staff lifecycle action on one thread and returns the
// resulting state.
//
// The transition rules, and why each is what it is:
//
//	pause     open → paused. Reversible; the whole point is that it is
//	          temporary. Refused on an ended thread (nothing to pause).
//	resume    paused → open. Refused on an ended thread — ending is final —
//	          and on an already-open one, so a stray double-click cannot be
//	          mistaken for having un-ended something.
//	end       open|paused → ended. Terminal. History is untouched: this sets
//	          a flag, it deletes nothing.
//	archive   sets archived_at, hiding the thread from the PARTICIPANTS'
//	          lists. Independent of open/paused/ended, and idempotent.
//	unarchive clears archived_at, putting the thread back in the
//	          participants' lists in exactly the state it was in.
//
// actorID is the staff member; it is recorded so the dashboard can say who
// paused a chat and when.
//
// CONCURRENCY. Apply reads, decides, then writes, and another request can
// change the thread in between: a second staff member, or
// cmd/retire-direct-chats ending every direct thread. So a lifecycle write
// lands only while the thread's lifecycle is still the one Apply read. When it
// is not, the write matches no row, and Apply reads again and decides against
// whatever the other request left:
//   - a pause or resume that lost to an END is refused with ErrEnded (HTTP
//     409), and the thread stays ended;
//   - a resume that lost to another resume is refused with ErrNotPaused (409);
//   - an END with no reason that lost to another END is the usual no-op;
//   - a thread deleted in between is ErrNotFound (404).
//
// Every outcome is one the two requests could also have produced one after
// the other. That also holds while the competing write is still uncommitted:
// under READ COMMITTED, an UPDATE that waited on another transaction's row lock
// re-checks its WHERE clause against the row that transaction committed.
//
// Archive and unarchive decide nothing from the read beyond the thread
// existing, so their writes carry no lifecycle condition. After
// maxApplyAttempts lost attempts in a row, Apply returns an error wrapping
// errLifecycleChanged.
func Apply(ctx context.Context, pool *pgxpool.Pool, k Kind, threadID int64, action, reason string, actorID int64) (State, error) {
	sys, ok := Lookup(k)
	if !ok {
		return State{}, fmt.Errorf("chatlifecycle: %w: %q", ErrUnknownAction, k)
	}
	reason = strings.TrimSpace(reason)
	// A reason longer than this is a note, not a label — and it is rendered
	// inside a banner on a phone. Truncated rather than refused so a staff
	// member's action never fails on formatting.
	if len([]rune(reason)) > 500 {
		reason = string([]rune(reason)[:500])
	}
	req := applyRequest{sys: sys, threadID: threadID, action: action, reason: reason, actorID: actorID}

	for attempt := 0; attempt < maxApplyAttempts; attempt++ {
		current, err := Load(ctx, pool, k, threadID)
		if err != nil {
			return State{}, err
		}
		st, err := applyOnce(ctx, pool, req, current)
		if !errors.Is(err, errLifecycleChanged) {
			return st, err
		}
	}
	return State{}, fmt.Errorf("chatlifecycle %s on %s/%d, gave up after %d attempts: %w",
		action, sys.ThreadTable, threadID, maxApplyAttempts, errLifecycleChanged)
}

// applyRequest is one Apply call's inputs, with the reason already trimmed and
// capped.
type applyRequest struct {
	sys      System
	threadID int64
	action   string
	reason   string
	actorID  int64
}

// applyOnce decides req against current, the state just read, and makes the
// write that decision calls for, following the rules listed on Apply. A
// lifecycle write that lost a race returns errLifecycleChanged.
func applyOnce(ctx context.Context, pool *pgxpool.Pool, req applyRequest, current State) (State, error) {
	switch req.action {
	case ActionPause:
		if current.Lifecycle == StateEnded {
			return current, ErrEnded
		}
		return setLifecycle(ctx, pool, req, lifecycleChange{from: current.Lifecycle, to: StatePaused, reason: req.reason})

	case ActionResume:
		if current.Lifecycle == StateEnded {
			return current, ErrEnded
		}
		if current.Lifecycle != StatePaused {
			return current, ErrNotPaused
		}
		// Resuming clears the reason: the explanation belonged to the pause.
		return setLifecycle(ctx, pool, req, lifecycleChange{from: StatePaused, to: StateOpen})

	case ActionEnd:
		// Idempotent: ending an ended thread is a no-op, not an error, so a
		// staff member who clicks twice is not shown a scary failure.
		if current.Lifecycle == StateEnded && req.reason == "" {
			return current, nil
		}
		return setLifecycle(ctx, pool, req, lifecycleChange{from: current.Lifecycle, to: StateEnded, reason: req.reason})

	case ActionArchive:
		return setArchived(ctx, pool, req.sys, req.threadID, true, req.actorID)

	case ActionUnarchive:
		return setArchived(ctx, pool, req.sys, req.threadID, false, req.actorID)

	default:
		return current, fmt.Errorf("%w: %q", ErrUnknownAction, req.action)
	}
}

// ─── The writes ─────────────────────────────────────────────────────────

// testHookBeforeWrite, when set, runs after Apply has read a thread and
// decided what to do, immediately before it writes. Tests use it to land a
// concurrent change in exactly that window. It is always nil in production.
var testHookBeforeWrite func()

// runTestHookBeforeWrite calls testHookBeforeWrite when a test has set it.
func runTestHookBeforeWrite() {
	if testHookBeforeWrite != nil {
		testHookBeforeWrite()
	}
}

// lifecycleChange is one lifecycle write. from is the lifecycle the decision
// was made against, to is the new one, and reason is stored alongside it.
type lifecycleChange struct {
	from, to, reason string
}

// setLifecycle writes change.to plus its audit trail, but only while the
// thread's lifecycle is still change.from. When it is not, or the thread is
// gone, the UPDATE matches no row and returns errLifecycleChanged. Apply then
// reads again, which tells the two cases apart.
//
// `reason` is stored as NULL when empty so "no reason given" and "the empty
// string" are not two different things downstream.
func setLifecycle(ctx context.Context, pool *pgxpool.Pool, req applyRequest, change lifecycleChange) (State, error) {
	var reasonArg *string
	if change.reason != "" {
		reasonArg = &change.reason
	}
	runTestHookBeforeWrite()
	var st State
	var archivedAt *string
	err := pool.QueryRow(ctx,
		"UPDATE "+req.sys.ThreadTable+` SET lifecycle = $2, lifecycle_reason = $3,
		        lifecycle_changed_at = CURRENT_TIMESTAMP, lifecycle_changed_by = $4,
		        updated_at = CURRENT_TIMESTAMP
		  WHERE id = $1 AND lifecycle = $5
		  RETURNING lifecycle, lifecycle_reason, archived_at::text`,
		req.threadID, change.to, reasonArg, req.actorID, change.from,
	).Scan(&st.Lifecycle, &st.Reason, &archivedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return st, errLifecycleChanged
	}
	if err != nil {
		return st, fmt.Errorf("chatlifecycle set %s on %s/%d: %w", change.to, req.sys.ThreadTable, req.threadID, err)
	}
	st.IsArchived = archivedAt != nil
	return st, nil
}

// setArchived hides the thread from the participants (true) or puts it back
// (false). Idempotent in both directions.
//
// Unlike setLifecycle it carries no lifecycle condition. Archiving gives the
// same result whatever the thread's lifecycle, so there is no decision for a
// concurrent change to invalidate. A thread deleted after Apply's read matches
// no row and is reported as ErrNotFound.
func setArchived(ctx context.Context, pool *pgxpool.Pool, sys System, threadID int64, archived bool, actorID int64) (State, error) {
	runTestHookBeforeWrite()
	var st State
	var archivedAt *string
	var err error
	if archived {
		err = pool.QueryRow(ctx,
			"UPDATE "+sys.ThreadTable+` SET archived_at = CURRENT_TIMESTAMP, archived_by = $2,
			        updated_at = CURRENT_TIMESTAMP
			  WHERE id = $1
			  RETURNING lifecycle, lifecycle_reason, archived_at::text`,
			threadID, actorID,
		).Scan(&st.Lifecycle, &st.Reason, &archivedAt)
	} else {
		err = pool.QueryRow(ctx,
			"UPDATE "+sys.ThreadTable+` SET archived_at = NULL, archived_by = NULL,
			        updated_at = CURRENT_TIMESTAMP
			  WHERE id = $1
			  RETURNING lifecycle, lifecycle_reason, archived_at::text`,
			threadID,
		).Scan(&st.Lifecycle, &st.Reason, &archivedAt)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return st, ErrNotFound
	}
	if err != nil {
		return st, fmt.Errorf("chatlifecycle archive=%v on %s/%d: %w", archived, sys.ThreadTable, threadID, err)
	}
	st.IsArchived = archivedAt != nil
	return st, nil
}
