// chatgroups_members.go holds every write to chat_group_members: the initial
// members of a new group (insertMembers, used by CreateGroup and
// ApproveConnectRequest), one member added to an existing group or a removed
// one brought back (AddMember), and a soft removal (RemoveMember), together
// with the label rules they share. Split out of chatgroups.go, whose
// "Membership writes" section this was, so both files stay under the
// 500-line cap.
//
// Migration 120 puts two unique rules on the table, and a write that breaks
// one is reported by name rather than as a raw Postgres error (OPOS #26410):
// UNIQUE (group_id, user_id) is ErrMemberConflict, and the case-insensitive
// index over active masked labels is ErrLabelConflict. See memberConflict.

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
// what to store instead. It returns ErrLabelContact, which the admin routes
// answer as 400 group_label_contact; that sentinel wraps ErrInvalidInput, so
// callers that matched ErrInvalidInput before OPOS #26410 still do. The error
// leaves the label itself out, so the contact detail never reaches a log.
//
// Only ever called with a non-empty, caller-supplied label — an
// auto-generated label ("Donor 1") must never reach this function.
func refuseContactInLabel(label string) error {
	if finding := moderation.ScanContact(label); finding.Blocked() {
		return fmt.Errorf("chatgroups: masked label: %w", ErrLabelContact)
	}
	return nil
}

// ─── Unique violations ──────────────────────────────────────────────────

// pgUniqueViolation is Postgres' SQLSTATE for a unique-constraint violation.
const pgUniqueViolation = "23505"

// The names Postgres gives migration 120's two unique rules on
// chat_group_members, as PgError.ConstraintName reports them (checked against
// pg_constraint and pg_indexes on a migrated database). A migration that
// renames either must update these, or its conflicts fall back to a 500.
const (
	memberUserConstraint  = "chat_group_members_group_id_user_id_key"
	memberLabelConstraint = "uq_chat_group_members_active_label"
)

// memberConflict names the conflict behind a failed chat_group_members write:
// ErrMemberConflict for a unique violation on (group_id, user_id),
// ErrLabelConflict for one on the active-label index, and nil for any other
// error, which the caller returns as the database failure it is. Matched on
// the SQLSTATE and constraint name, never on message text.
func memberConflict(err error) error {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != pgUniqueViolation {
		return nil
	}
	switch pgErr.ConstraintName {
	case memberUserConstraint:
		return ErrMemberConflict
	case memberLabelConstraint:
		return ErrLabelConflict
	}
	return nil
}

// wrapMemberWriteError wraps err, a failed chat_group_members write, with the
// description what. A conflict memberConflict recognises goes into the chain
// ahead of the database error, which stays after it so a log still shows the
// constraint.
func wrapMemberWriteError(what string, err error) error {
	if conflict := memberConflict(err); conflict != nil {
		return fmt.Errorf("%s: %w: %w", what, conflict, err)
	}
	return fmt.Errorf("%s: %w", what, err)
}

// ─── Membership writes ──────────────────────────────────────────────────

// memberExecer is what insertMemberRow, reactivateMemberRow and
// refuseTeamMemberRole need. pgx.Tx satisfies it, and every caller writes
// inside a transaction: CreateGroup, ApproveConnectRequest and AddMember.
type memberExecer interface {
	Exec(ctx context.Context, sql string, arguments ...any) (pgconn.CommandTag, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ─── The team-group rule ────────────────────────────────────────────────

// Role ids as users.role_id stores them. handlers/registration.go accepts
// 1..3 and branches on each: 1 assigns the donor's grantor code, 2 the
// recipient details, 3 the volunteer code and profile. They are the
// authoritative account role; chat_group_members.role_in_group is free text
// staff type and has no constraint behind it, so it decides nothing here.
const (
	roleIDDonor       = 1
	roleIDBeneficiary = 2
)

// teamMemberRefusedSQL reports whether userID may NOT join a team group:
// their account is a donor or a beneficiary and they hold no staff tier.
//
// staff_tier is the single definition of a staff account across this codebase
// (internal/auth/middleware.go; internal/notify's staff fan-out uses the same
// four tiers), and it wins over role_id: a coordinator who first registered as
// a donor and was later given dashboard access is staff, and belongs in a team
// group.
//
// A user id with no users row at all is not refused — the rule refuses
// confirmed donors and beneficiaries and changes nothing else, the same way
// insertMemberRowSQL's guest check refuses only confirmed guests.
const teamMemberRefusedSQL = `
	SELECT EXISTS (
		SELECT 1 FROM users
		 WHERE id = $1::integer
		   AND role_id IN ($2::integer, $3::integer)
		   AND staff_tier NOT IN ('super_admin', 'admin', 'supervisor', 'employee'))`

// refuseTeamMemberRole returns ErrTeamMemberRole when userID is a donor or
// beneficiary account, and nil otherwise. Callers must only call it for a
// kind='team' group — a masked group takes any mix.
func refuseTeamMemberRole(ctx context.Context, q memberExecer, groupID, userID int64) error {
	var refused bool
	if err := q.QueryRow(ctx, teamMemberRefusedSQL, userID, roleIDDonor, roleIDBeneficiary).Scan(&refused); err != nil {
		return fmt.Errorf("chatgroups: checking the account role of user %d for team group %d: %w", userID, groupID, err)
	}
	if refused {
		return fmt.Errorf("chatgroups: adding member %d to team group %d: %w", userID, groupID, ErrTeamMemberRole)
	}
	return nil
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

// insertMemberRow is the ONLY place this package writes a new
// chat_group_members row, so the guest rule holds on every path that adds a
// member: CreateGroup and ApproveConnectRequest (through insertMembers) and
// AddMember. AddMember's other path, bringing a removed member back, applies
// the same rule in reactivateMemberRowSQL.
//
// A row whose masked is false belongs to a TEAM group (the only two kinds are
// masked and team), so this is also where the team-group rule holds for every
// new member: a donor or beneficiary account is refused before anything is
// written.
//
// Returns, wrapped with the user and group ids:
//   - ErrTeamMemberRole when the group is a team group and row.userID is a
//     donor or beneficiary account;
//   - ErrGuestMember when row.userID is a guest account;
//   - ErrMemberConflict when the user already has a row in the group — a
//     member list naming them twice, or a concurrent add of the same person;
//   - ErrLabelConflict when row.label is held by another active member,
//     ignoring case.
//
// Any other database failure is returned wrapped with the same context.
func insertMemberRow(ctx context.Context, q memberExecer, row memberRow) error {
	if !row.masked {
		if err := refuseTeamMemberRole(ctx, q, row.groupID, row.userID); err != nil {
			return err
		}
	}
	what := fmt.Sprintf("chatgroups: adding member %d to group %d", row.userID, row.groupID)
	tag, err := q.Exec(ctx, insertMemberRowSQL,
		row.groupID, row.userID, row.roleInGroup, row.masked, nullIfEmpty(row.label), row.addedByStaffID,
	)
	if err != nil {
		return wrapMemberWriteError(what, err)
	}
	// The SELECT always yields exactly one row unless its NOT EXISTS guest
	// check filters it out, so zero rows written means the user is a guest.
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("%s: %w", what, ErrGuestMember)
	}
	return nil
}

// reactivateMemberRowSQL brings back a removed membership by clearing
// removed_at and removed_by, and nothing else: the row keeps its id, masked
// label, role, added_at and added_by_staff_id (the admin route's audit log
// records who re-added the member, and when). Like insertMemberRowSQL it
// refuses a guest account in the same statement, so a guest row written
// before OPOS #26355 cannot become active this way either.
//
// Clearing removed_at puts the row back under
// uq_chat_group_members_active_label, so when the member's label has gone to
// someone else meanwhile the UPDATE fails with a unique violation and the row
// stays removed.
const reactivateMemberRowSQL = `
	UPDATE chat_group_members
	   SET removed_at = NULL, removed_by = NULL
	 WHERE id = $1
	   AND removed_at IS NOT NULL
	   AND NOT EXISTS (SELECT 1 FROM users WHERE users.id = chat_group_members.user_id AND users.is_guest)`

// reactivateMemberRow brings back the removed membership memberID. The caller
// must have locked that row in the same transaction and seen it removed, as
// addMemberInTx does.
//
// Returns ErrGuestMember when the member is a guest account and
// ErrLabelConflict when their label now belongs to another active member; the
// row stays removed either way.
func reactivateMemberRow(ctx context.Context, q memberExecer, memberID int64) error {
	what := fmt.Sprintf("chatgroups: reactivating membership %d", memberID)
	tag, err := q.Exec(ctx, reactivateMemberRowSQL, memberID)
	if err != nil {
		return wrapMemberWriteError(what, err)
	}
	// The row is locked and was removed, so only the guest check can have
	// filtered it out.
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("%s: %w", what, ErrGuestMember)
	}
	return nil
}

// insertMembers adds members to an existing group within tx. masked is
// derived from kind ONCE, here — CreateGroup and ApproveConnectRequest both go
// through this (and AddMember applies the same derivation), so a masked group
// can never end up with an unmasked member.
//
// Stops at the first member it cannot add and returns why: a contact detail
// in a label (ErrLabelContact), a guest account (ErrGuestMember), a user
// listed twice (ErrMemberConflict), or two labels that differ only in case
// (ErrLabelConflict). The caller's transaction then rolls back every member
// before it, and the group with them.
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

// AddMember adds one member to an existing group, or brings back a member who
// was removed from it. masked is ALWAYS derived from the group's own kind —
// never accepted from the caller.
//
// A new member of a masked group whose caller left Label blank gets the next
// label in the group's per-role auto-label sequence (the count of members
// ever added under that role), so a member added later gets the next number,
// not a restarted "1" — matching insertMembers' counter for the initial batch.
//
// A REMOVED member is reactivated, not refused (the user's decision D3, OPOS
// #26410): their existing row gets removed_at and removed_by cleared and
// keeps its member id, masked label and role, so the messages they sent
// before and after the removal resolve to the same speaker. input.RoleInGroup
// and input.Label are IGNORED for them, so a returning member cannot be
// renamed through this call. A caller-supplied label is still scanned for
// contact details first, and refused if it has any, stored or not.
//
// The lookup and the write share one transaction with the member's existing
// row locked, so a concurrent add or removal of the same person cannot slip in
// between. Nothing is written when AddMember returns:
//   - ErrNotFound for an unknown group;
//   - ErrLabelContact when a masked group's caller-supplied label carries a
//     phone number or email address;
//   - ErrMemberConflict when the user is already an active member;
//   - ErrLabelConflict when the label — a new member's, or a returning
//     member's old one — is held by another active member, ignoring case;
//   - ErrGuestMember when the user is a guest account;
//   - ErrTeamMemberRole when the group is a team group and the user is a donor
//     or beneficiary account — for a returning member as much as a new one.
func (s *Store) AddMember(ctx context.Context, groupID int64, input MemberInput, addedByStaffID int64) error {
	kind, err := s.groupKind(ctx, groupID)
	if err != nil {
		return err
	}
	row := memberRow{
		groupID:        groupID,
		userID:         input.UserID,
		roleInGroup:    input.RoleInGroup,
		masked:         kind == KindMasked,
		addedByStaffID: addedByStaffID,
	}
	// A team-group member is never masked, so their label stays blank.
	if row.masked {
		row.label = strings.TrimSpace(input.Label)
		if row.label != "" {
			if err := refuseContactInLabel(row.label); err != nil {
				return err
			}
		}
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("chatgroups: adding member %d to group %d: begin transaction: %w", row.userID, groupID, err)
	}
	defer tx.Rollback(ctx)
	if err := addMemberInTx(ctx, tx, row); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("chatgroups: adding member %d to group %d: commit: %w", row.userID, groupID, err)
	}
	return nil
}

// groupKind reads groupID's kind, failing with ErrNotFound when no such group
// exists.
func (s *Store) groupKind(ctx context.Context, groupID int64) (Kind, error) {
	var kind Kind
	err := s.Pool.QueryRow(ctx, `SELECT kind FROM chat_group_threads WHERE id = $1`, groupID).Scan(&kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
	}
	if err != nil {
		return "", fmt.Errorf("chatgroups: looking up group %d: %w", groupID, err)
	}
	return kind, nil
}

// existingMemberSQL finds the user's membership row in the group, if any,
// and locks it until the transaction ends.
const existingMemberSQL = `
	SELECT id, removed_at IS NOT NULL
	  FROM chat_group_members
	 WHERE group_id = $1 AND user_id = $2
	   FOR UPDATE`

// addMemberInTx writes row inside tx: a brand-new membership when the user has
// never been in the group, or their removed membership reactivated (see
// AddMember). A user who is already active is ErrMemberConflict.
func addMemberInTx(ctx context.Context, tx pgx.Tx, row memberRow) error {
	var memberID int64
	var isRemoved bool
	err := tx.QueryRow(ctx, existingMemberSQL, row.groupID, row.userID).Scan(&memberID, &isRemoved)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return insertNewMember(ctx, tx, row)
	case err != nil:
		return fmt.Errorf("chatgroups: looking up member %d in group %d: %w", row.userID, row.groupID, err)
	case !isRemoved:
		return fmt.Errorf("chatgroups: adding member %d to group %d: %w", row.userID, row.groupID, ErrMemberConflict)
	}
	// Bringing a removed member back (OPOS #26410) obeys the team-group rule
	// too, so a donor who was in a team group from before the rule existed
	// cannot return through it. insertMemberRow covers the other branch.
	if !row.masked {
		if err := refuseTeamMemberRole(ctx, tx, row.groupID, row.userID); err != nil {
			return err
		}
	}
	if err := reactivateMemberRow(ctx, tx, memberID); err != nil {
		return fmt.Errorf("chatgroups: re-adding member %d to group %d: %w", row.userID, row.groupID, err)
	}
	return nil
}

// insertNewMember inserts row as a brand-new membership, first giving a masked
// member with no label the next auto-label for their role.
func insertNewMember(ctx context.Context, tx pgx.Tx, row memberRow) error {
	if row.masked && row.label == "" {
		var n int
		if err := tx.QueryRow(ctx,
			`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1 AND role_in_group = $2`,
			row.groupID, row.roleInGroup,
		).Scan(&n); err != nil {
			return fmt.Errorf("chatgroups: counting %s members in group %d: %w", row.roleInGroup, row.groupID, err)
		}
		row.label = autoLabel(row.roleInGroup, n+1)
	}
	return insertMemberRow(ctx, tx, row)
}

// RemoveMember soft-removes a member (removed_at/removed_by). Never DELETE
// — a deleted row breaks historical label resolution for that member's past
// messages (see Task 6). Removing a member who is not currently active
// (never a member, or already removed) is an error, not a silent no-op.
// AddMember brings a removed member back on the same row.
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
