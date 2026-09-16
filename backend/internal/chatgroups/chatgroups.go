// Package chatgroups implements OPOS #25284's staff-created group chats.
//
// Two modes share one schema (see the migration for the full column list):
//   - kind='masked' — donor/beneficiary/volunteer groups. Non-staff members
//     see only a staff-assigned label, never a real name, phone, avatar, or
//     user id. Staff always sees real identities via the Admin* methods.
//   - kind='team' — volunteer team coordination. Real names, ordinary group
//     chat, staff curates membership. Because the names are real, a team group
//     is for VOLUNTEERS AND STAFF ONLY: a donor or beneficiary account is
//     refused with ErrTeamMemberRole on every path that adds a member (Zaid's
//     decision, 2026-09-16). Those two belong in a masked group.
//
// The masking guarantee is structural, not a filter someone could forget:
// GroupMessage (the type every non-staff response is built from) has no
// field capable of holding a user id or a real name. See
// docs/superpowers/specs/2026-09-12-masked-group-chats-design.md §5.
//
// Membership is for full accounts only (OPOS #26355). Every participant
// chat-group route refuses a guest session, so a guest account
// (users.is_guest) is never written into chat_group_members: all three paths
// that add members — CreateGroup, AddMember, ApproveConnectRequest — go
// through insertMemberRow, which refuses a guest with ErrGuestMember, and
// AddMember's other path, bringing a removed member back, applies the same
// check. Both live in chatgroups_members.go.
package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Sentinel errors so a Phase 2 HTTP handler can map store failures to status
// codes (403 vs 404 vs 500) with errors.Is, never by matching error text.
var (
	// ErrNotMember is returned when the acting/viewing user has no active
	// membership row for the group (or was removed from it).
	ErrNotMember = errors.New("chatgroups: not an active member of this group")
	// ErrNotFound is returned when a referenced group, member, or connect
	// request does not exist.
	ErrNotFound = errors.New("chatgroups: not found")
	// ErrAlreadyDecided is returned when a connect request is no longer
	// pending (already approved or declined).
	ErrAlreadyDecided = errors.New("chatgroups: connect request already decided")
	// ErrInvalidInput is returned when caller-supplied arguments fail
	// validation before any query runs.
	ErrInvalidInput = errors.New("chatgroups: invalid input")
	// ErrGuestMember is returned when a caller tries to make a guest account
	// (users.is_guest = TRUE) a member of a group (OPOS #26355). Every
	// participant chat-group route refuses guest sessions
	// (auth.RequireNotGuest), so a guest member could never read or post —
	// locked out of a group staff believe they are in. Deliberately distinct
	// from ErrInvalidInput so the HTTP layer can give staff a specific,
	// machine-readable refusal. Enforced in exactly one place,
	// insertMemberRow.
	ErrGuestMember = errors.New("chatgroups: guest accounts cannot be chat-group members")
	// ErrTeamMemberRole is returned when a caller tries to put a donor or a
	// beneficiary account into a kind='team' group (Zaid's decision,
	// 2026-09-16). A team group serves real names to its members, so a donor
	// and a beneficiary in one would see each other's real identity — what
	// OPOS #25284 built the masked kind to prevent. Those two belong in a
	// masked group, where members see labels; masked groups are unchanged and
	// still take any mix.
	//
	// Who someone is comes from users.role_id (1 donor, 2 beneficiary,
	// 3 volunteer) and users.staff_tier, never from the group's own
	// role_in_group, which is unconstrained free text staff type. A staff
	// account is allowed whatever its role_id. Enforced in exactly two places,
	// insertMemberRow and addMemberInTx's reactivation branch, so every path
	// that adds a member is covered.
	ErrTeamMemberRole = errors.New("chatgroups: a team group can only include volunteers and staff")
	// ErrUnknownContext is returned when a connect request names a
	// beneficiary case or donation that does not exist — never created, or
	// moved to the Trash, which deletes the row from its source table
	// (OPOS #26351). See Store.SubmitConnectRequest.
	ErrUnknownContext = errors.New("chatgroups: connect request context does not exist")
	// ErrMemberConflict is returned when a caller adds someone who is already
	// an active member of the group: AddMember for a current member, or a
	// CreateGroup or ApproveConnectRequest member list naming one user twice.
	// It is migration 120's UNIQUE (group_id, user_id), reported by name
	// rather than as a raw unique violation (OPOS #26410). Re-adding a REMOVED
	// member is not a conflict; see AddMember.
	ErrMemberConflict = errors.New("chatgroups: already an active member of this group")
	// ErrLabelConflict is returned when a masked label is already held by
	// another active member of the same group, compared ignoring case —
	// migration 120's uq_chat_group_members_active_label (OPOS #26410). It is
	// also what re-adding a removed member returns when their old label has
	// since gone to someone else.
	ErrLabelConflict = errors.New("chatgroups: masked label already held by an active member")
	// ErrLabelContact is returned when a caller-supplied masked label carries
	// a phone number or email address (see refuseContactInLabel). It wraps
	// ErrInvalidInput, so errors.Is(err, ErrInvalidInput) — what callers
	// matched before #26410 gave this refusal its own name — still holds. A
	// caller that wants the specific refusal must test for ErrLabelContact
	// first.
	ErrLabelContact = fmt.Errorf("chatgroups: masked label contains contact details: %w", ErrInvalidInput)
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Kind is a chat_group_threads.kind value.
type Kind string

const (
	KindMasked Kind = "masked"
	KindTeam   Kind = "team"
)

// Group mirrors one chat_group_threads row.
type Group struct {
	ID          int64     `json:"id"`
	Kind        Kind      `json:"kind"`
	MemberTitle string    `json:"member_title"`
	CreatedBy   int64     `json:"created_by_staff_id"`
	Lifecycle   string    `json:"lifecycle"`
	CreatedAt   time.Time `json:"created_at"`
}

// MemberInput is what a caller supplies when adding someone to a group.
// Label is optional — a masked group auto-generates one ("Donor 1") when
// left blank; a team group ignores it (team members are never masked).
type MemberInput struct {
	UserID      int64
	RoleInGroup string
	Label       string
}

// GroupMessage is what a non-staff member's response is built from. It has
// NO user-id field — it is not possible to leak a real identity through
// this type because the type cannot hold one.
type GroupMessage struct {
	ID             int64     `json:"id"`
	SenderMemberID int64     `json:"sender_member_id"`
	SenderLabel    string    `json:"sender_label"`
	IsMine         bool      `json:"is_mine"`
	Body           string    `json:"body"`
	CreatedAt      time.Time `json:"created_at"`
}

// AdminGroupMessage is staff-only. Deliberately NOT built by embedding
// GroupMessage — a fully independent type, so nothing about the masked
// type's shape can be reused by mistake for a response that should carry
// real identity.
type AdminGroupMessage struct {
	ID             int64     `json:"id"`
	SenderMemberID int64     `json:"sender_member_id"`
	SenderUserID   int64     `json:"sender_user_id"`
	SenderName     string    `json:"sender_name"`
	Body           string    `json:"body"`
	CreatedAt      time.Time `json:"created_at"`
}

// CreateGroup creates a thread and its initial members in one transaction.
// For a masked group, memberTitle is ignored (masked groups never carry a
// member-facing title — see the migration comment on member_title).
//
// If any member cannot be added, the whole create fails and nothing is
// written — not the thread, not the members listed before it: a guest account
// (ErrGuestMember), a user listed twice (ErrMemberConflict), two labels that
// differ only in case (ErrLabelConflict), or a label with contact details
// (ErrLabelContact). See insertMembers.
func (s *Store) CreateGroup(ctx context.Context, kind Kind, memberTitle string, createdByStaffID int64, members []MemberInput) (int64, error) {
	if kind != KindMasked && kind != KindTeam {
		return 0, fmt.Errorf("chatgroups: kind %q: %w", kind, ErrInvalidInput)
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("chatgroups: creating group: begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	title := memberTitle
	if kind == KindMasked {
		title = ""
	}
	var groupID int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO chat_group_threads (kind, member_title, created_by_staff_id)
		 VALUES ($1, $2, $3) RETURNING id`,
		string(kind), title, createdByStaffID,
	).Scan(&groupID); err != nil {
		return 0, fmt.Errorf("chatgroups: creating group: %w", err)
	}
	if err := insertMembers(ctx, tx, groupID, kind, createdByStaffID, members); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("chatgroups: creating group %d: commit: %w", groupID, err)
	}
	return groupID, nil
}

// advanceReadCursor is shared by PostMessage and PostMessageAsStaff: the
// sender of a message always has it marked read for themselves, inside the
// SAME transaction as the insert — otherwise a sender sees their own
// message as unread on their next poll.
func advanceReadCursor(ctx context.Context, tx pgx.Tx, groupID, userID, msgID int64) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO chat_group_reads (group_id, user_id, last_read_msg_id)
		VALUES ($1, $2, $3)
		ON CONFLICT (group_id, user_id) DO UPDATE
		  SET last_read_msg_id = GREATEST(chat_group_reads.last_read_msg_id, EXCLUDED.last_read_msg_id)`,
		groupID, userID, msgID,
	)
	if err != nil {
		return fmt.Errorf("chatgroups: advancing read cursor for user %d in group %d: %w", userID, groupID, err)
	}
	return nil
}

// PostMessage records a message from an active member. Returns an error if
// senderUserID is not a current (non-removed) member of the group.
func (s *Store) PostMessage(ctx context.Context, groupID, senderUserID int64, body string) (int64, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return 0, errors.New("body must not be empty")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("chatgroups: posting message to group %d: begin transaction: %w", groupID, err)
	}
	defer tx.Rollback(ctx)

	var isMember bool
	if err := tx.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM chat_group_members
		                 WHERE group_id = $1 AND user_id = $2 AND removed_at IS NULL)`,
		groupID, senderUserID,
	).Scan(&isMember); err != nil {
		return 0, fmt.Errorf("chatgroups: checking membership for user %d in group %d: %w", senderUserID, groupID, err)
	}
	if !isMember {
		return 0, fmt.Errorf("chatgroups: user %d in group %d: %w", senderUserID, groupID, ErrNotMember)
	}

	var id int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO chat_group_messages (group_id, sender_user_id, body)
		 VALUES ($1, $2, $3) RETURNING id`,
		groupID, senderUserID, body,
	).Scan(&id); err != nil {
		return 0, fmt.Errorf("chatgroups: posting message to group %d: %w", groupID, err)
	}
	if err := advanceReadCursor(ctx, tx, groupID, senderUserID, id); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("chatgroups: posting message %d to group %d: commit: %w", id, groupID, err)
	}
	return id, nil
}

// PostMessageAsStaff records a staff reply. Any admin holding the messages
// permission may post — membership in chat_group_members is for
// notification targeting/ownership, not the access gate (spec §9); the
// permission check itself belongs in the HTTP handler in a later phase, not
// here.
func (s *Store) PostMessageAsStaff(ctx context.Context, groupID, staffUserID int64, body string) (int64, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return 0, errors.New("body must not be empty")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("chatgroups: posting staff message to group %d: begin transaction: %w", groupID, err)
	}
	defer tx.Rollback(ctx)

	var id int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO chat_group_messages (group_id, sender_user_id, body)
		 VALUES ($1, $2, $3) RETURNING id`,
		groupID, staffUserID, body,
	).Scan(&id); err != nil {
		return 0, fmt.Errorf("chatgroups: posting staff message to group %d: %w", groupID, err)
	}
	if err := advanceReadCursor(ctx, tx, groupID, staffUserID, id); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("chatgroups: posting staff message %d to group %d: commit: %w", id, groupID, err)
	}
	return id, nil
}
