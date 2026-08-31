// Package chatlifecycle is the ONE implementation of END / PAUSE / RESUME /
// ARCHIVE / UNARCHIVE for every chat in the product.
//
// The product has four independent chat systems, each with its own table, its
// own store package and its own handler (donor↔owner, marriage, staff↔staff,
// case-volunteer). Before this package, three of the five lifecycle actions
// did not exist anywhere and the two that resembled them ("declined") meant
// something else entirely. Re-implementing the rules four times would
// guarantee they drift, so the rules live here once and each system supplies
// only its table name.
//
// THE STATE MODEL
//
//	open    — normal. Anybody who is otherwise allowed to post, may post.
//	paused  — TEMPORARY and REVERSIBLE. Nobody may send (participants OR
//	          staff); both participants still READ the whole history and are
//	          shown the reason. Staff resume it back to `open`.
//	ended   — FINAL. Read-only for everyone, forever. There is deliberately no
//	          transition out of `ended`: "reopening" a conversation is a new
//	          thread, not a resurrected one. History is never destroyed.
//
// Archiving is tracked separately (archived_at / archived_by) because it
// answers a different question — see migration 117 for the full reasoning.
// Archived hides the thread from the PARTICIPANTS; staff keep seeing it.
//
// WHO MAY DO ANY OF THIS: staff only, in all four systems. This package is
// only ever reachable from routes mounted on the `admin` group, which
// authenticates a dashboard session before any handler runs; the mobile API
// exposes no lifecycle route at all. A participant therefore cannot end,
// pause, archive or delete a chat — enforced by routing, and pinned by
// chat_lifecycle_test.go.
package chatlifecycle

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── States ─────────────────────────────────────────────────────────────

const (
	StateOpen   = "open"
	StatePaused = "paused"
	StateEnded  = "ended"
)

// ─── Actions a staff member may request ─────────────────────────────────

const (
	ActionEnd       = "end"
	ActionPause     = "pause"
	ActionResume    = "resume"
	ActionArchive   = "archive"
	ActionUnarchive = "unarchive"
)

var (
	// ErrUnknownAction — the request named something that is not one of the
	// five actions above.
	ErrUnknownAction = errors.New("unknown chat lifecycle action")
	// ErrNotFound — no thread with that id in that system.
	ErrNotFound = errors.New("chat thread not found")
	// ErrEnded — refuses resume (and pause) on a thread that has been ended.
	// Ending is final by the owner's decision; a new conversation is a new
	// thread.
	ErrEnded = errors.New("this chat has been ended and cannot be reopened")
	// ErrNotPaused — resume only makes sense on a paused thread.
	ErrNotPaused = errors.New("this chat is not paused")
)

// ─── The four chat systems ──────────────────────────────────────────────

// Kind identifies one of the four chat systems. It is the ONLY thing a caller
// supplies that reaches SQL, and it never does so directly: it is looked up in
// `systems` below and the package-level literal table names found there are
// what gets interpolated. A value that is not a key is rejected, so a request
// parameter can never become a table name.
type Kind string

const (
	KindDonor    Kind = "donor"    // chat_threads (012)
	KindMarriage Kind = "marriage" // marriage_chat_threads (058)
	KindStaff    Kind = "staff"    // staff_chat_threads (059)
	KindCase     Kind = "case"     // case_volunteer_chat_threads (061)
)

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
}

// systems is the whitelist. A Kind that is not a key here is refused before
// any SQL is built.
var systems = map[Kind]System{
	KindDonor: {
		Kind:         KindDonor,
		ThreadTable:  "chat_threads",
		MessageTable: "chat_messages",
		ReadTable:    "chat_reads",
		// K19's record of the messages this thread refused to carry. It
		// cascades from the thread, so it has to travel with it or a restored
		// thread would quietly lose its moderation history.
		ExtraChildTables: []string{"chat_contact_blocks"},
	},
	KindMarriage: {
		Kind:         KindMarriage,
		ThreadTable:  "marriage_chat_threads",
		MessageTable: "marriage_chat_messages",
		ReadTable:    "marriage_chat_reads",
	},
	KindStaff: {
		Kind:         KindStaff,
		ThreadTable:  "staff_chat_threads",
		MessageTable: "staff_chat_messages",
		ReadTable:    "staff_chat_reads",
	},
	KindCase: {
		Kind:         KindCase,
		ThreadTable:  "case_volunteer_chat_threads",
		MessageTable: "case_volunteer_chat_messages",
		ReadTable:    "case_volunteer_chat_reads",
	},
}

// Lookup resolves a Kind to its System, or reports that it is not one of the
// four. Callers MUST route every table name through this.
func Lookup(k Kind) (System, bool) {
	s, ok := systems[k]
	return s, ok
}

// Systems returns every registered system, for callers that must act on all
// four (the dashboard's kind list, tests that assert full coverage).
func Systems() []System {
	// Fixed order so a test or a UI listing is stable rather than map-random.
	return []System{systems[KindDonor], systems[KindMarriage], systems[KindStaff], systems[KindCase]}
}

// ChildTables lists every FK child whose rows must survive a trash/restore.
func (s System) ChildTables() []string {
	out := []string{s.MessageTable, s.ReadTable}
	return append(out, s.ExtraChildTables...)
}

// ─── Reading the current state ──────────────────────────────────────────

// State is a thread's lifecycle as stored, for one of the four systems.
type State struct {
	Lifecycle  string  `json:"lifecycle"`
	Reason     *string `json:"lifecycle_reason"`
	IsArchived bool    `json:"is_archived"`
}

// CanSend reports whether a new message may be stored in this thread.
// Paused and ended both refuse; archived does NOT, on its own — archiving is
// about visibility, and staff may still be working an archived-but-open
// thread from the dashboard.
func (s State) CanSend() bool { return s.Lifecycle == StateOpen }

// Load reads one thread's lifecycle state.
func Load(ctx context.Context, pool *pgxpool.Pool, k Kind, threadID int64) (State, error) {
	sys, ok := Lookup(k)
	if !ok {
		return State{}, fmt.Errorf("chatlifecycle: %w: %q", ErrUnknownAction, k)
	}
	var st State
	var archivedAt *string
	err := pool.QueryRow(ctx,
		// Table name comes from the whitelist above, never from a request.
		"SELECT lifecycle, lifecycle_reason, archived_at::text FROM "+sys.ThreadTable+" WHERE id = $1",
		threadID,
	).Scan(&st.Lifecycle, &st.Reason, &archivedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return st, ErrNotFound
	}
	if err != nil {
		return st, fmt.Errorf("chatlifecycle load %s/%d: %w", sys.ThreadTable, threadID, err)
	}
	st.IsArchived = archivedAt != nil
	return st, nil
}

// ─── Refusal, as a typed error the handlers turn into HTTP ──────────────

// SendRefusedError is returned when a thread will not accept a message
// because of its lifecycle. It carries the state and the staff member's
// reason so the API response can tell the user WHY rather than just "no".
type SendRefusedError struct {
	State State
}

func (e *SendRefusedError) Error() string {
	if e.State.Lifecycle == StateEnded {
		return "this chat has been ended"
	}
	return "this chat is paused"
}

// UserMessage is the friendly, actionable sentence shown to a participant.
// It always says WHY: the staff member's reason when there is one, and a
// plain explanation of the state when there is not. The app localises using
// the `code`/`lifecycle` fields alongside it; this English text is the
// fallback for any client that does not.
func (e *SendRefusedError) UserMessage() string {
	reason := ""
	if e.State.Reason != nil {
		reason = strings.TrimSpace(*e.State.Reason)
	}
	base := "This conversation has been paused by our team, so new messages cannot be sent right now. You can still read it, and our team can resume it."
	if e.State.Lifecycle == StateEnded {
		base = "This conversation has been closed by our team. You can still read it, but no new messages can be sent."
	}
	if reason != "" {
		return base + " Reason: " + reason
	}
	return base
}

// EnsureSendable is the SERVER-SIDE gate every send path calls before storing
// a message. The app hiding its composer is a courtesy; this is the rule.
// Returns a *SendRefusedError when the thread is paused or ended.
func EnsureSendable(ctx context.Context, pool *pgxpool.Pool, k Kind, threadID int64) error {
	st, err := Load(ctx, pool, k, threadID)
	if err != nil {
		return err
	}
	if !st.CanSend() {
		return &SendRefusedError{State: st}
	}
	return nil
}

// ─── Applying a transition ──────────────────────────────────────────────

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
func Apply(ctx context.Context, pool *pgxpool.Pool, k Kind, threadID int64, action, reason string, actorID int64) (State, error) {
	sys, ok := Lookup(k)
	if !ok {
		return State{}, fmt.Errorf("chatlifecycle: %w: %q", ErrUnknownAction, k)
	}
	current, err := Load(ctx, pool, k, threadID)
	if err != nil {
		return State{}, err
	}
	reason = strings.TrimSpace(reason)
	// A reason longer than this is a note, not a label — and it is rendered
	// inside a banner on a phone. Truncated rather than refused so a staff
	// member's action never fails on formatting.
	if len([]rune(reason)) > 500 {
		reason = string([]rune(reason)[:500])
	}

	switch action {
	case ActionPause:
		if current.Lifecycle == StateEnded {
			return current, ErrEnded
		}
		return setLifecycle(ctx, pool, sys, threadID, StatePaused, reason, actorID)

	case ActionResume:
		if current.Lifecycle == StateEnded {
			return current, ErrEnded
		}
		if current.Lifecycle != StatePaused {
			return current, ErrNotPaused
		}
		// Resuming clears the reason: the explanation belonged to the pause.
		return setLifecycle(ctx, pool, sys, threadID, StateOpen, "", actorID)

	case ActionEnd:
		// Idempotent: ending an ended thread is a no-op, not an error, so a
		// staff member who clicks twice is not shown a scary failure.
		if current.Lifecycle == StateEnded && reason == "" {
			return current, nil
		}
		return setLifecycle(ctx, pool, sys, threadID, StateEnded, reason, actorID)

	case ActionArchive:
		return setArchived(ctx, pool, sys, threadID, true, actorID)

	case ActionUnarchive:
		return setArchived(ctx, pool, sys, threadID, false, actorID)

	default:
		return current, fmt.Errorf("%w: %q", ErrUnknownAction, action)
	}
}

// setLifecycle writes the new lifecycle value plus its audit trail.
// `reason` is stored as NULL when empty so "no reason given" and "the empty
// string" are not two different things downstream.
func setLifecycle(ctx context.Context, pool *pgxpool.Pool, sys System, threadID int64, next, reason string, actorID int64) (State, error) {
	var reasonArg *string
	if reason != "" {
		reasonArg = &reason
	}
	var st State
	var archivedAt *string
	err := pool.QueryRow(ctx,
		"UPDATE "+sys.ThreadTable+` SET lifecycle = $2, lifecycle_reason = $3,
		        lifecycle_changed_at = CURRENT_TIMESTAMP, lifecycle_changed_by = $4,
		        updated_at = CURRENT_TIMESTAMP
		  WHERE id = $1
		  RETURNING lifecycle, lifecycle_reason, archived_at::text`,
		threadID, next, reasonArg, actorID,
	).Scan(&st.Lifecycle, &st.Reason, &archivedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return st, ErrNotFound
	}
	if err != nil {
		return st, fmt.Errorf("chatlifecycle set %s on %s/%d: %w", next, sys.ThreadTable, threadID, err)
	}
	st.IsArchived = archivedAt != nil
	return st, nil
}

// setArchived hides the thread from the participants (true) or puts it back
// (false). Idempotent in both directions.
func setArchived(ctx context.Context, pool *pgxpool.Pool, sys System, threadID int64, archived bool, actorID int64) (State, error) {
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
