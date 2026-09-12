// Package chatgroups implements OPOS #25284's staff-created group chats.
//
// Two modes share one schema (see the migration for the full column list):
//   - kind='masked' — donor/beneficiary/volunteer groups. Non-staff members
//     see only a staff-assigned label, never a real name, phone, avatar, or
//     user id. Staff always sees real identities via the Admin* methods.
//   - kind='team' — volunteer team coordination. Real names, ordinary group
//     chat, staff curates membership.
//
// The masking guarantee is structural, not a filter someone could forget:
// GroupMessage (the type every non-staff response is built from) has no
// field capable of holding a user id or a real name. See
// docs/superpowers/specs/2026-09-12-masked-group-chats-design.md §5.
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
	ID          int64
	Kind        Kind
	MemberTitle string
	CreatedBy   int64
	Lifecycle   string
	CreatedAt   time.Time
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

// autoLabelName is the display noun for each role's auto-generated label —
// "Donor 1", "Beneficiary 1", etc. Staff never gets a numbered label here;
// see Task 6, where every staff-sent message collapses to the fixed
// "Support" at READ time regardless of what a staff member's own row says.
var autoLabelName = map[string]string{
	"donor":       "Donor",
	"beneficiary": "Beneficiary",
	"volunteer":   "Volunteer",
}

// autoLabel builds the auto-generated masked-member label for role, using n
// as the per-role sequence number ("Donor 1", "Donor 2", ...). Roles outside
// autoLabelName fall back to the generic "Member" noun.
func autoLabel(role string, n int) string {
	name, ok := autoLabelName[role]
	if !ok {
		name = "Member"
	}
	return fmt.Sprintf("%s %d", name, n)
}

// nullIfEmpty converts an empty string to a nil pointer so it round-trips as
// SQL NULL instead of an empty-string value.
func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// insertMembers adds members to an existing group within tx. masked is
// derived from kind ONCE, here — every call site (CreateGroup, AddMember,
// ApproveConnectRequest) goes through this, so a masked group can never end
// up with an unmasked member.
func insertMembers(ctx context.Context, tx pgx.Tx, groupID int64, kind Kind, addedByStaffID int64, members []MemberInput) error {
	masked := kind == KindMasked
	counters := map[string]int{}
	for _, m := range members {
		label := strings.TrimSpace(m.Label)
		if masked {
			if label == "" {
				counters[m.RoleInGroup]++
				label = autoLabel(m.RoleInGroup, counters[m.RoleInGroup])
			}
		} else {
			label = "" // team-group members are never masked; no label stored
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
			 VALUES ($1, $2, $3, $4, $5, $6)`,
			groupID, m.UserID, m.RoleInGroup, masked, nullIfEmpty(label), addedByStaffID,
		); err != nil {
			return fmt.Errorf("chatgroups: adding member %d to group %d: %w", m.UserID, groupID, err)
		}
	}
	return nil
}

// CreateGroup creates a thread and its initial members in one transaction.
// For a masked group, memberTitle is ignored (masked groups never carry a
// member-facing title — see the migration comment on member_title).
func (s *Store) CreateGroup(ctx context.Context, kind Kind, memberTitle string, createdByStaffID int64, members []MemberInput) (int64, error) {
	if kind != KindMasked && kind != KindTeam {
		return 0, errors.New("kind must be 'masked' or 'team'")
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

// AddMember adds one member to an existing group. masked is ALWAYS derived
// from the group's own kind — never accepted from the caller. When the
// group is masked and the caller left Label blank, the label continues the
// group's existing per-role auto-label sequence (the count of members ever
// added under that role), so a member added later gets the next number, not
// a restarted "1" — matching insertMembers' counter for the initial batch.
func (s *Store) AddMember(ctx context.Context, groupID int64, input MemberInput, addedByStaffID int64) error {
	var kind Kind
	if err := s.Pool.QueryRow(ctx,
		`SELECT kind FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind); err != nil {
		return fmt.Errorf("chatgroups: looking up group %d: %w", groupID, err)
	}
	masked := kind == KindMasked
	label := strings.TrimSpace(input.Label)
	if masked && label == "" {
		var n int
		if err := s.Pool.QueryRow(ctx,
			`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1 AND role_in_group = $2`,
			groupID, input.RoleInGroup,
		).Scan(&n); err != nil {
			return fmt.Errorf("chatgroups: counting %s members in group %d: %w", input.RoleInGroup, groupID, err)
		}
		label = autoLabel(input.RoleInGroup, n+1)
	}
	if !masked {
		label = "" // team-group members are never masked; no label stored
	}
	if _, err := s.Pool.Exec(ctx,
		`INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		groupID, input.UserID, input.RoleInGroup, masked, nullIfEmpty(label), addedByStaffID,
	); err != nil {
		return fmt.Errorf("chatgroups: adding member %d to group %d: %w", input.UserID, groupID, err)
	}
	return nil
}

// RemoveMember soft-removes a member (removed_at/removed_by). Never DELETE
// — a deleted row breaks historical label resolution for that member's past
// messages (see Task 6). Removing a member who is not currently active
// (never a member, or already removed) is an error, not a silent no-op.
func (s *Store) RemoveMember(ctx context.Context, groupID, userID, removedByStaffID int64) error {
	ct, err := s.Pool.Exec(ctx,
		`UPDATE chat_group_members SET removed_at = now(), removed_by = $3
		  WHERE group_id = $1 AND user_id = $2 AND removed_at IS NULL`,
		groupID, userID, removedByStaffID,
	)
	if err != nil {
		return fmt.Errorf("chatgroups: removing member %d from group %d: %w", userID, groupID, err)
	}
	if ct.RowsAffected() == 0 {
		return fmt.Errorf("chatgroups: member %d in group %d: %w", userID, groupID, ErrNotFound)
	}
	return nil
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
