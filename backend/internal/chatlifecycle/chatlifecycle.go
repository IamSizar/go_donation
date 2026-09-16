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
	KindGroup    Kind = "group"    // chat_group_threads (120)
)

// System describes one chat system's tables. Every string in here is a
// compile-time literal — see the note on Kind.
type System struct {
	// Kind is the URL-facing name of this system.
	Kind Kind
	// ThreadTable holds the thread rows carrying the lifecycle columns.
	ThreadTable string
	// MessageTable and ReadTable are the child tables that would otherwise be
	// lost by a delete. They are snapshotted alongside the thread so a restore
	// brings back a conversation rather than an empty shell — see
	// handlers.trashChatThread.
	MessageTable string
	ReadTable    string
	// ExtraChildTables are further child tables to preserve: the donor chat's
	// K19 blocked-contact supervision log, and chat groups' contact-block log,
	// staff note and member roster.
	ExtraChildTables []string
	// ChildIDColumn is the foreign-key column name every child table (message,
	// read, and extra tables) uses to reference ThreadTable's id. Every system
	// through chat groups used "thread_id"; chat groups uses "group_id"
	// instead, so this is a per-system value rather than a hardcoded literal
	// in the trash/restore snapshot query.
	ChildIDColumn string
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
		ChildIDColumn:    "thread_id",
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
		Kind:         KindGroup,
		ThreadTable:  "chat_group_threads",
		MessageTable: "chat_group_messages",
		ReadTable:    "chat_group_reads",
		// The masked-group contact-block log (mirrors chat_contact_blocks),
		// the staff-only context note, and the MEMBER ROSTER all belong to
		// the group, so they travel with it through trash/restore just like
		// the donor chat's extra table does.
		//
		// chat_group_members is not optional here: a member row is what maps
		// a sender to their masked_label, so a group restored without its
		// roster comes back with every message collapsed to the "Support"
		// fallback (see handlers.groupSenderLabel and
		// chatgroups.Store.ListMessagesForMember) — a silently wrong restore,
		// which is worse than one that fails loudly.
		ExtraChildTables: []string{"chat_group_contact_blocks", "chat_group_staff_notes", "chat_group_members"},
		ChildIDColumn:    "group_id",
	},
}

// Lookup resolves a Kind to its System, or reports that it is not one of the
// four. Callers MUST route every table name through this.
func Lookup(k Kind) (System, bool) {
	s, ok := systems[k]
	return s, ok
}

// Systems returns every ACTIVELY REACHABLE system, for callers that must act
// on all of them (the dashboard's kind list, tests that assert full
// coverage).
//
// OPOS #25284 Phase 4 retired KindCase's direct volunteer↔beneficiary
// messaging entirely — no route or handler reaches it any more — so it is
// deliberately left out of this slice even though its constant and its
// systems map entry stay defined below (case_volunteer_chat_threads still
// holds historical rows the Global Constraints forbid dropping).
func Systems() []System {
	// Fixed order so a test or a UI listing is stable rather than map-random.
	return []System{systems[KindDonor], systems[KindMarriage], systems[KindStaff], systems[KindGroup]}
}

// AllSystems returns every registered chat system, including ones retired
// from active use (e.g. KindCase after OPOS #25284 Phase 4) — unlike
// Systems(), which returns only the actively-iterated subset. Use this for
// lookups that must still resolve historical/retired data (e.g. restoring a
// trashed thread row), never for UI listings of "chat systems in active use".
func AllSystems() []System {
	out := make([]System, 0, len(systems))
	for _, sys := range systems {
		out = append(out, sys)
	}
	return out
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
