// chatgroups_members.go holds every write to chat_group_members: the initial
// members of a new group (insertMembers, used by CreateGroup and
// ApproveConnectRequest), one member added to an existing group (AddMember),
// and a soft removal (RemoveMember), together with the label rules they
// share. Split out of chatgroups.go, whose "Membership writes" section this
// was, so both files stay under the 500-line cap.

package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
)

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

// refuseContactInLabel enforces design spec §5's "Alias quality" rule that
// moderation.ScanContact runs over a staff-typed masked_label at write time —
// a staff member pasting a phone number or other contact info into a label
// is a realistic slip, since the label is the one free-text field that
// reaches a masked group's members verbatim.
//
// It REFUSES rather than redacts-and-stores, unlike the message-body filter
// this mirrors (see internal/handlers/chat_contact_block.go): a masked_label
// is a persistent, always-visible field, not a one-off message, so silently
// turning a phone number into "•••" would still need a caller decision about
// what to store instead. Returning an error wrapping ErrInvalidInput lets it
// propagate to the caller (the admin HTTP route) as a 4xx via the existing
// chatErr dispatcher, with zero handler-side changes.
//
// Only ever called with a non-empty, caller-supplied label — an
// auto-generated label ("Donor 1") must never reach this function.
func refuseContactInLabel(label string) error {
	if finding := moderation.ScanContact(label); finding.Blocked() {
		return fmt.Errorf("chatgroups: label %q: %w", label, ErrInvalidInput)
	}
	return nil
}

// ─── Membership writes ──────────────────────────────────────────────────

// memberExecer is the one method insertMemberRow needs. pgx.Tx satisfies it
// (CreateGroup and ApproveConnectRequest insert inside their transaction), and
// so does *pgxpool.Pool (AddMember's single statement).
type memberExecer interface {
	Exec(ctx context.Context, sql string, arguments ...any) (pgconn.CommandTag, error)
}

// memberRow is one chat_group_members row, fully resolved by the caller:
// masked and label are already derived from the group's kind.
type memberRow struct {
	groupID        int64
	userID         int64
	roleInGroup    string
	masked         bool
	label          string
	addedByStaffID int64
}

// insertMemberRowSQL writes one membership row only if the user is not a
// guest account. The guest check is part of the INSERT itself rather than a
// separate SELECT beforehand, so it adds no round trip per member and leaves
// no gap between checking and writing.
//
// A user id with no users row at all is not a guest, so it is inserted exactly
// as before this rule existed — the rule refuses guests and changes nothing
// else. Every parameter is cast to its column's type so the INSERT ... SELECT
// is typed explicitly rather than by inference.
const insertMemberRowSQL = `
	INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
	SELECT $1::bigint, $2::integer, $3::varchar, $4::boolean, $5::varchar, $6::integer
	 WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = $2::integer AND is_guest)`

// insertMemberRow is the ONLY place this package writes a chat_group_members
// row, so the guest rule holds on every path that adds a member: CreateGroup
// and ApproveConnectRequest (through insertMembers) and AddMember.
//
// Returns ErrGuestMember, wrapped with the user and group ids, when row.userID
// is a guest account; any database failure is returned wrapped with the same
// context.
func insertMemberRow(ctx context.Context, q memberExecer, row memberRow) error {
	tag, err := q.Exec(ctx, insertMemberRowSQL,
		row.groupID, row.userID, row.roleInGroup, row.masked, nullIfEmpty(row.label), row.addedByStaffID,
	)
	if err != nil {
		return fmt.Errorf("chatgroups: adding member %d to group %d: %w", row.userID, row.groupID, err)
	}
	// The SELECT always yields exactly one row unless its NOT EXISTS guest
	// check filters it out, so zero rows written means the user is a guest.
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("chatgroups: adding member %d to group %d: %w", row.userID, row.groupID, ErrGuestMember)
	}
	return nil
}

// insertMembers adds members to an existing group within tx. masked is
// derived from kind ONCE, here — CreateGroup and ApproveConnectRequest both go
// through this (and AddMember applies the same derivation), so a masked group
// can never end up with an unmasked member.
//
// Stops at the first member it cannot add — a contact detail in a label
// (ErrInvalidInput) or a guest account (ErrGuestMember) — and returns that
// error; the caller's transaction then rolls back every member before it.
func insertMembers(ctx context.Context, tx pgx.Tx, groupID int64, kind Kind, addedByStaffID int64, members []MemberInput) error {
	masked := kind == KindMasked
	counters := map[string]int{}
	for _, m := range members {
		label := strings.TrimSpace(m.Label)
		if masked {
			if label == "" {
				counters[m.RoleInGroup]++
				label = autoLabel(m.RoleInGroup, counters[m.RoleInGroup])
			} else if err := refuseContactInLabel(label); err != nil {
				return err
			}
		} else {
			label = "" // team-group members are never masked; no label stored
		}
		if err := insertMemberRow(ctx, tx, memberRow{
			groupID:        groupID,
			userID:         m.UserID,
			roleInGroup:    m.RoleInGroup,
			masked:         masked,
			label:          label,
			addedByStaffID: addedByStaffID,
		}); err != nil {
			return err
		}
	}
	return nil
}

// AddMember adds one member to an existing group. masked is ALWAYS derived
// from the group's own kind — never accepted from the caller. When the
// group is masked and the caller left Label blank, the label continues the
// group's existing per-role auto-label sequence (the count of members ever
// added under that role), so a member added later gets the next number, not
// a restarted "1" — matching insertMembers' counter for the initial batch.
//
// Returns ErrNotFound for an unknown group and ErrGuestMember, writing
// nothing, when input.UserID is a guest account (see insertMemberRow).
func (s *Store) AddMember(ctx context.Context, groupID int64, input MemberInput, addedByStaffID int64) error {
	var kind Kind
	if err := s.Pool.QueryRow(ctx,
		`SELECT kind FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
		}
		return fmt.Errorf("chatgroups: looking up group %d: %w", groupID, err)
	}
	masked := kind == KindMasked
	label := strings.TrimSpace(input.Label)
	if masked {
		if label == "" {
			var n int
			if err := s.Pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1 AND role_in_group = $2`,
				groupID, input.RoleInGroup,
			).Scan(&n); err != nil {
				return fmt.Errorf("chatgroups: counting %s members in group %d: %w", input.RoleInGroup, groupID, err)
			}
			label = autoLabel(input.RoleInGroup, n+1)
		} else if err := refuseContactInLabel(label); err != nil {
			return err
		}
	} else {
		label = "" // team-group members are never masked; no label stored
	}
	return insertMemberRow(ctx, s.Pool, memberRow{
		groupID:        groupID,
		userID:         input.UserID,
		roleInGroup:    input.RoleInGroup,
		masked:         masked,
		label:          label,
		addedByStaffID: addedByStaffID,
	})
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
