// chatgroups_admin.go holds the methods Phase 2's HTTP layer needs that
// don't belong in chatgroups.go (write path) or chatgroups_reads.go
// (member-facing read path): a full group detail with its member roster,
// for the admin membership-management UI and for the message-posting
// handlers' own contact-filter/notification needs (see
// docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md §3),
// and the contact-info-filter supervision log, mirroring
// internal/chat/contactblocks.go.

package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// GroupMember is one chat_group_members row, as staff need to see it —
// unlike GroupMessage, this type IS allowed to carry a real user id, real
// name and label together, because only admin-gated routes serialize it.
// The member routes (handlers/chat_group.go) read a GroupDetail too, for
// their membership check and push fan-out, but never put it on the wire —
// handlers' TestChatGroupMemberReads_MaskedGroupLeaksNoRealIdentity pins that.
//
// FullName is the member's user_profiles.full_name. Only AdminGetGroup loads
// it; it is nil everywhere else, and nil when the member has no profile row
// (part of OPOS #26410). For a masked group, the admin route that returns it
// also requires sensitive_data (OPOS #26409).
type GroupMember struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	FullName    *string    `json:"full_name"`
	RoleInGroup string     `json:"role_in_group"`
	Masked      bool       `json:"masked"`
	MaskedLabel string     `json:"masked_label"`
	RemovedAt   *time.Time `json:"removed_at,omitempty"`
}

// GroupDetail is a group's thread row plus its full member roster.
type GroupDetail struct {
	Group
	Members []GroupMember `json:"members"`
}

// AdminGetGroup is GetGroup plus every roster member's real name, for the
// admin group-detail route only (part of OPOS #26410): the dashboard shows
// staff who is behind each masked label.
//
// It is a separate method rather than a column GetGroup always reads because
// the member routes call GetGroup on every poll just to check membership, and
// that path neither needs a name nor should hold one. Named like
// AdminListMessages so the two reads cannot be reached for interchangeably.
//
// Fails like GetGroup: ErrNotFound for an unknown group.
func (s *Store) AdminGetGroup(ctx context.Context, groupID int64) (GroupDetail, error) {
	gd, err := s.GetGroup(ctx, groupID)
	if err != nil {
		return GroupDetail{}, err
	}
	if len(gd.Members) == 0 {
		return gd, nil
	}
	userIDs := make([]int64, len(gd.Members))
	for i, m := range gd.Members {
		userIDs[i] = m.UserID
	}
	names, err := s.profileNames(ctx, userIDs)
	if err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: naming members of group %d: %w", groupID, err)
	}
	for i := range gd.Members {
		if name, ok := names[gd.Members[i].UserID]; ok {
			gd.Members[i].FullName = &name
		}
	}
	return gd, nil
}

// profileNames maps each of userIDs that has a user_profiles row to its
// full_name, in ONE query however many ids there are. user_profiles.user_id
// has no UNIQUE constraint, so DISTINCT ON names a user with several profile
// rows from the oldest one. A user with no profile is simply absent.
func (s *Store) profileNames(ctx context.Context, userIDs []int64) (map[int64]string, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT DISTINCT ON (user_id) user_id, full_name
		  FROM user_profiles
		 WHERE user_id = ANY($1)
		 ORDER BY user_id, id`, userIDs)
	if err != nil {
		return nil, fmt.Errorf("reading profile names: %w", err)
	}
	defer rows.Close()
	names := make(map[int64]string, len(userIDs))
	for rows.Next() {
		var userID int64
		var name string
		if err := rows.Scan(&userID, &name); err != nil {
			return nil, fmt.Errorf("scanning profile name: %w", err)
		}
		names[userID] = name
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reading profile names: %w", err)
	}
	return names, nil
}

// GetGroup reads one group's thread row and its full member roster
// (including removed members, so the admin UI can show history), WITHOUT
// member names — AdminGetGroup adds those for the admin route. Used by the
// member routes and the message-posting handlers to learn a group's kind (for
// the contact filter) and member list (for the membership check and
// notification fan-out) in one call.
func (s *Store) GetGroup(ctx context.Context, groupID int64) (GroupDetail, error) {
	var gd GroupDetail
	err := s.Pool.QueryRow(ctx,
		`SELECT id, kind, member_title, created_by_staff_id, lifecycle, created_at
		   FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&gd.ID, &gd.Kind, &gd.MemberTitle, &gd.CreatedBy, &gd.Lifecycle, &gd.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupDetail{}, fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
	}
	if err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: getting group %d: %w", groupID, err)
	}

	rows, err := s.Pool.Query(ctx,
		`SELECT id, user_id, role_in_group, masked, COALESCE(masked_label, ''), removed_at
		   FROM chat_group_members WHERE group_id = $1 ORDER BY id ASC`, groupID)
	if err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: listing members of group %d: %w", groupID, err)
	}
	defer rows.Close()
	for rows.Next() {
		var m GroupMember
		if err := rows.Scan(&m.ID, &m.UserID, &m.RoleInGroup, &m.Masked, &m.MaskedLabel, &m.RemovedAt); err != nil {
			return GroupDetail{}, fmt.Errorf("chatgroups: scanning member of group %d: %w", groupID, err)
		}
		gd.Members = append(gd.Members, m)
	}
	if err := rows.Err(); err != nil {
		return GroupDetail{}, fmt.Errorf("chatgroups: listing members of group %d: %w", groupID, err)
	}
	return gd, nil
}

// GroupKind reads only a group's kind: the one fact the admin roster, messages
// and contact-block routes need before deciding whether the caller must hold
// sensitive_data (OPOS #26409, user decision D1: masked groups need it, team
// groups do not). Cheaper than GetGroup, which also loads the whole roster.
//
// Fails with ErrNotFound when no group has that id, which the handler turns
// into its usual 404.
func (s *Store) GroupKind(ctx context.Context, groupID int64) (Kind, error) {
	var kind Kind
	err := s.Pool.QueryRow(ctx,
		`SELECT kind FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", fmt.Errorf("chatgroups: group %d: %w", groupID, ErrNotFound)
	}
	if err != nil {
		return "", fmt.Errorf("chatgroups: reading kind of group %d: %w", groupID, err)
	}
	return kind, nil
}

// GroupContactBlock is one refused message, as staff read it. Mirrors
// internal/chat/contactblocks.go's ContactBlock exactly, scoped to a group
// instead of a thread.
type GroupContactBlock struct {
	ID           int64     `json:"id"`
	GroupID      int64     `json:"group_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderName   *string   `json:"sender_name"`
	Kind         string    `json:"kind"`
	MatchCount   int       `json:"match_count"`
	RedactedBody string    `json:"redacted_body"`
	CreatedAt    time.Time `json:"created_at"`
}

// RecordContactBlock appends one refused attempt. Deliberately returns its
// error rather than swallowing it, but the caller (the HTTP handler) logs
// and continues — failing to record the attempt must never turn into
// failing to BLOCK it.
func (s *Store) RecordContactBlock(ctx context.Context, groupID, senderUserID int64, kind string, matchCount int, redactedBody string) error {
	if _, err := s.Pool.Exec(ctx, `
		INSERT INTO chat_group_contact_blocks (group_id, sender_user_id, kind, match_count, redacted_body)
		VALUES ($1, $2, $3, $4, $5)`,
		groupID, senderUserID, kind, matchCount, redactedBody,
	); err != nil {
		return fmt.Errorf("chatgroups: recording contact block on group %d: %w", groupID, err)
	}
	return nil
}

// ListContactBlocks returns one group's refused attempts, newest first, with
// the sender's name resolved for the dashboard — same no-masking rule as
// AdminListMessages: this is a staff-only screen, and a supervisor who
// cannot see WHO kept trying to pass a number out cannot act on it.
func (s *Store) ListContactBlocks(ctx context.Context, groupID int64) ([]GroupContactBlock, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT b.id, b.group_id, b.sender_user_id, up.full_name,
		       b.kind, b.match_count, b.redacted_body, b.created_at
		  FROM chat_group_contact_blocks b
		  -- LATERAL, not a plain join, for the same reason AdminListMessages
		  -- uses one (chatgroups_reads.go): user_profiles.user_id has no
		  -- UNIQUE constraint, so a sender with two rows would have each of
		  -- their refused attempts listed twice. The oldest row names them.
		  LEFT JOIN LATERAL (
		      SELECT p.full_name FROM user_profiles p
		       WHERE p.user_id = b.sender_user_id ORDER BY p.id LIMIT 1
		  ) up ON TRUE
		 WHERE b.group_id = $1
		 ORDER BY b.id DESC`, groupID)
	if err != nil {
		return nil, fmt.Errorf("chatgroups: listing contact blocks for group %d: %w", groupID, err)
	}
	defer rows.Close()
	out := []GroupContactBlock{}
	for rows.Next() {
		var b GroupContactBlock
		if err := rows.Scan(&b.ID, &b.GroupID, &b.SenderUserID, &b.SenderName,
			&b.Kind, &b.MatchCount, &b.RedactedBody, &b.CreatedAt); err != nil {
			return nil, fmt.Errorf("chatgroups: scanning contact block: %w", err)
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("chatgroups: listing contact blocks for group %d: %w", groupID, err)
	}
	return out, nil
}
