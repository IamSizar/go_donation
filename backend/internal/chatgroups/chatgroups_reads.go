// This file holds chatgroups' read-side methods — listing groups and
// paging through a group's messages — split out of chatgroups.go to keep
// both files under this project's ~400-line file-size guidance (see the
// package doc comment in chatgroups.go for the package overview). Nothing
// here changes behavior versus what used to live in chatgroups.go: this is
// a pure relocation, not a rewrite.
package chatgroups

import (
	"context"
	"errors"
)

// maxMessagePage caps one page of ListMessagesForMember. An unbounded page
// is never acceptable on a chat history that grows without limit. A limit
// ABOVE this cap is not clamped down to it — it falls back to
// defaultMessagePage, the same as a non-positive limit (see the `limit <= 0
// || limit > maxMessagePage` guard in ListMessagesForMember).
const maxMessagePage = 100

// defaultMessagePage is the page size actually used whenever the caller does
// not supply a usable limit — both when limit is non-positive and when it
// exceeds maxMessagePage. It is deliberately SMALLER than maxMessagePage: a
// caller that asked for nothing in particular gets a modest page, and only a
// caller that explicitly names a size between 1 and maxMessagePage gets that
// size.
const defaultMessagePage = 50

// ListMessagesForMember returns messages as the GIVEN viewer would see them.
// This is the read-time projection that IS the masking guarantee — masking
// is never a storage-time decision (chat_group_messages.sender_user_id is
// always the real id), so this query is the single place where a real
// identity could reach a non-staff member. Staff use the Admin* methods and
// AdminGroupMessage instead; they never come through here.
//
// The label rules, and why each exists:
//
//   - Masked group, staff-authored message → the fixed "Support". Deliberately
//     NOT the admin's name or a per-admin label: spec §9 lets any admin
//     holding the messages permission reply, so a per-admin label would let a
//     member count and fingerprint the staff handling their case, and an
//     admin with no chat_group_members row at all (see PostMessageAsStaff)
//     has no label to show anyway. One organisational voice, always.
//   - Masked group, member-authored message → that member's masked_label
//     ("Donor 1"). The label is scoped to one (group, user) pair, so it
//     identifies a speaker inside this group without correlating that person
//     across groups.
//   - Team group → the sender's real user_profiles.full_name, for every
//     sender including staff. Team groups are never masked ("real names,
//     ordinary group chat"). If product feedback ever changes how staff
//     appear in a team group, it is this one ELSE branch and nothing else.
//
// The member join deliberately does NOT filter on `removed_at IS NULL`.
// chat_group_members is soft-deleted precisely so this query can still
// resolve a departed member's historical messages (see RemoveMember and the
// migration's comment on removed_at); filtering removed rows out here would
// make the soft delete pointless and, worse, drop a removed donor's past
// messages into the staff branch above, presenting the organisation as the
// author of what a member said. UNIQUE (group_id, user_id) on
// chat_group_members guarantees at most one row per pair, so widening the
// join cannot multiply message rows.
//
// sender_user_id is read ONLY inside SQL, to compute is_mine, and is never
// scanned into Go — GroupMessage has no field that could hold it (see the
// type's doc comment), so the id cannot reach a response even by mistake.
//
// Cursor-paginated on the monotonic message id: afterID is the highest id
// the caller already holds (0 for the first page), so a poll with the latest
// id returns an empty slice rather than the whole history again.
//
// Access gate: viewerUserID must be a CURRENT (non-removed) member of the
// group, exactly as PostMessage requires of a sender. Without it any user id
// could read any group's full history — including someone who was never a
// member, and a member whose access was deliberately revoked by
// RemoveMember. Phase 2's HTTP handler will gate this too, but the store
// layer does not silently trust that it always will; read and write are
// gated by the same predicate so they cannot drift apart.
func (s *Store) ListMessagesForMember(ctx context.Context, groupID, viewerUserID, afterID int64, limit int) ([]GroupMessage, error) {
	if limit <= 0 || limit > maxMessagePage {
		limit = defaultMessagePage
	}

	var isMember bool
	if err := s.Pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM chat_group_members
		                 WHERE group_id = $1 AND user_id = $2 AND removed_at IS NULL)`,
		groupID, viewerUserID,
	).Scan(&isMember); err != nil {
		return nil, err
	}
	if !isMember {
		return nil, errors.New("viewer is not an active member of this group")
	}

	rows, err := s.Pool.Query(ctx, `
		SELECT
		  m.id,
		  COALESCE(mem.id, 0),
		  CASE
		    WHEN g.kind = 'masked' THEN
		      CASE WHEN mem.id IS NULL OR mem.role_in_group = 'staff' THEN 'Support'
		           ELSE COALESCE(mem.masked_label, 'Member') END
		    ELSE
		      COALESCE(up.full_name, 'Member')
		  END,
		  (m.sender_user_id = $2),
		  m.body,
		  m.created_at
		FROM chat_group_messages m
		JOIN chat_group_threads g ON g.id = m.group_id
		LEFT JOIN chat_group_members mem
		  ON mem.group_id = m.group_id AND mem.user_id = m.sender_user_id
		LEFT JOIN user_profiles up ON up.user_id = m.sender_user_id
		WHERE m.group_id = $1 AND m.id > $3
		ORDER BY m.id ASC
		LIMIT $4`,
		groupID, viewerUserID, afterID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []GroupMessage{}
	for rows.Next() {
		var gm GroupMessage
		if err := rows.Scan(&gm.ID, &gm.SenderMemberID, &gm.SenderLabel, &gm.IsMine, &gm.Body, &gm.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, gm)
	}
	return out, rows.Err()
}

// AdminListMessages is the staff-only, unmasked twin of ListMessagesForMember:
// same cursor pagination over the same table, but it returns AdminGroupMessage
// (real sender_user_id and real name) instead of GroupMessage's masked label.
// Named distinctly from ListMessagesForMember (spec §5) precisely so the two
// cannot be reached for interchangeably by accident.
//
// Deliberately NO membership/access check, unlike ListMessagesForMember. Per
// spec §9, admin authority to read a group comes from the CALLER's permission
// level (perm("messages", ...) plus sensitive_data:view), checked by a later
// phase's HTTP handler — not from having a chat_group_members row. This
// mirrors PostMessageAsStaff, which already lets any admin holding the
// messages permission post into a group without needing a member row.
func (s *Store) AdminListMessages(ctx context.Context, groupID, afterID int64, limit int) ([]AdminGroupMessage, error) {
	if limit <= 0 || limit > maxMessagePage {
		limit = defaultMessagePage
	}

	rows, err := s.Pool.Query(ctx, `
		SELECT
		  m.id,
		  COALESCE(mem.id, 0),
		  m.sender_user_id,
		  COALESCE(up.full_name, u.phone, 'Unknown'),
		  m.body,
		  m.created_at
		FROM chat_group_messages m
		LEFT JOIN chat_group_members mem
		  ON mem.group_id = m.group_id AND mem.user_id = m.sender_user_id
		LEFT JOIN users u ON u.id = m.sender_user_id
		LEFT JOIN user_profiles up ON up.user_id = m.sender_user_id
		WHERE m.group_id = $1 AND m.id > $2
		ORDER BY m.id ASC
		LIMIT $3`,
		groupID, afterID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []AdminGroupMessage{}
	for rows.Next() {
		var am AdminGroupMessage
		if err := rows.Scan(&am.ID, &am.SenderMemberID, &am.SenderUserID, &am.SenderName, &am.Body, &am.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, am)
	}
	return out, rows.Err()
}
