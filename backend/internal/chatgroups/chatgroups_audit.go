// chatgroups_audit.go — "who unmasked whom": a standalone record of
// group-creation and membership-change actions. See migration
// 122_chat_group_audit_log.sql for why this is its own table rather than a
// call into internal/staffactivity (that package has no write method — it
// only aggregates other tables for a dashboard view).
package chatgroups

import (
	"context"
	"fmt"
)

// validAuditActions mirrors the migration's CHECK (action IN (...)) list
// exactly (see 122_chat_group_audit_log.sql). Kept in sync by hand — the
// database is still the last line of defense (Section 8), but a Go-level
// check here turns a typo into ErrInvalidInput instead of a raw Postgres
// 23514 constraint-violation error, matching CreateGroup's existing
// kind-validation pattern in chatgroups.go.
var validAuditActions = map[string]bool{
	"created":        true,
	"member_added":   true,
	"member_removed": true,
}

// RecordAudit appends one audit-log row. targetUserID is nil for actions
// with no single target member (e.g. "created"). Returns an error wrapping
// ErrInvalidInput if action is not one of the CHECK constraint's allowed
// values — validated here, before the INSERT runs, so an invalid action
// never reaches the database.
func (s *Store) RecordAudit(ctx context.Context, groupID int64, action string, actorStaffID int64, targetUserID *int64) error {
	if !validAuditActions[action] {
		return fmt.Errorf("chatgroups: audit action %q: %w", action, ErrInvalidInput)
	}
	if _, err := s.Pool.Exec(ctx,
		`INSERT INTO chat_group_audit_log (group_id, action, actor_staff_id, target_user_id)
		 VALUES ($1, $2, $3, $4)`,
		groupID, action, actorStaffID, targetUserID,
	); err != nil {
		return fmt.Errorf("chatgroups: recording audit action %q on group %d: %w", action, groupID, err)
	}
	return nil
}
