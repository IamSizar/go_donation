package chatgroups

import (
	"context"
	"errors"
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

// TestRecordAuditRejectsInvalidAction mirrors
// TestCreateGroupInvalidKindReturnsErrInvalidInput's shape: RecordAudit must
// reject an action outside the migration's CHECK constraint list itself,
// via ErrInvalidInput, before ever reaching the database — not rely on a
// raw Postgres 23514 constraint-violation error surfacing instead.
func TestRecordAuditRejectsInvalidAction(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	err = s.RecordAudit(context.Background(), groupID, "bogus", staff, &donor)
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("err = %v, want ErrInvalidInput", err)
	}

	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_audit_log WHERE group_id = $1`, groupID,
	).Scan(&n); err != nil {
		t.Fatalf("count audit rows: %v", err)
	}
	if n != 0 {
		t.Fatalf("chat_group_audit_log has %d rows after a rejected action; want 0", n)
	}
}
