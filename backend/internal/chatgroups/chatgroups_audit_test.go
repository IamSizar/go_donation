package chatgroups

import (
	"context"
	"testing"
)

func TestRecordAuditWritesRow(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	if err := s.RecordAudit(context.Background(), groupID, "member_added", staff, &donor); err != nil {
		t.Fatalf("record audit: %v", err)
	}

	var action string
	var target *int64
	if err := pool.QueryRow(context.Background(),
		`SELECT action, target_user_id FROM chat_group_audit_log WHERE group_id = $1`, groupID,
	).Scan(&action, &target); err != nil {
		t.Fatalf("query audit row: %v", err)
	}
	if action != "member_added" || target == nil || *target != donor {
		t.Fatalf("audit row = action=%q target=%v, want member_added/%d", action, target, donor)
	}
}
