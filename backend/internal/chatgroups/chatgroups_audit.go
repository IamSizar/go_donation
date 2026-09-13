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

// RecordAudit appends one audit-log row. targetUserID is nil for actions
// with no single target member (e.g. "created").
func (s *Store) RecordAudit(ctx context.Context, groupID int64, action string, actorStaffID int64, targetUserID *int64) error {
	if _, err := s.Pool.Exec(ctx,
		`INSERT INTO chat_group_audit_log (group_id, action, actor_staff_id, target_user_id)
		 VALUES ($1, $2, $3, $4)`,
		groupID, action, actorStaffID, targetUserID,
	); err != nil {
		return fmt.Errorf("chatgroups: recording audit action %q on group %d: %w", action, groupID, err)
	}
	return nil
}
