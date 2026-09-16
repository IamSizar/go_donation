// apply_group_test.go
//
// Pins Apply and Load on chat groups (KindGroup, chat_group_threads).
//
// Migration 120 declared chat_group_threads.lifecycle_reason NOT NULL with an
// empty-string default, but setLifecycle stores "no reason" as NULL, the
// convention migration 118 set for the four older thread tables. So every
// group resume, and every group pause or end without a reason, failed on the
// not-null constraint and reached staff as a 500 "Database error.". No test
// drove a group through Apply, so nothing caught it. Migration 123 makes the
// column nullable, bringing chat groups onto the same convention.
//
// Shares newTestPool, makeTestUser and makeStaffUser with the retire tests, so
// it needs the same TEST_DATABASE_URL and skips without one.
package chatlifecycle

import (
	"context"
	"strconv"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixture ────────────────────────────────────────────────────────────

// makeGroup inserts a masked chat group in its default, never-moderated state
// and deletes it on cleanup. chat_group_threads has no foreign keys (migration
// 120's convention), so nothing cascades and the delete has to be explicit.
func makeGroup(t *testing.T, pool *pgxpool.Pool, staffID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO chat_group_threads (kind, created_by_staff_id) VALUES ('masked', $1) RETURNING id`,
		staffID,
	).Scan(&id); err != nil {
		t.Fatalf("insert chat group: %v", err)
	}
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DELETE FROM chat_group_threads WHERE id = $1`, id); err != nil {
			t.Errorf("delete chat group %d: %v", id, err)
		}
	})
	return id
}

// textOrNull renders a nullable reason for a failure message, telling NULL
// apart from the empty string.
func textOrNull(s *string) string {
	if s == nil {
		return nullText
	}
	return strconv.Quote(*s)
}

// assertGroupHasNoReason checks both what Apply reported and what it stored:
// the lifecycle is wantLifecycle and the reason is absent (nil, NULL).
func assertGroupHasNoReason(t *testing.T, pool *pgxpool.Pool, groupID int64, got State, wantLifecycle string) {
	t.Helper()
	if got.Lifecycle != wantLifecycle || got.Reason != nil {
		t.Fatalf("Apply returned lifecycle=%q reason=%s, want %q with no reason",
			got.Lifecycle, textOrNull(got.Reason), wantLifecycle)
	}
	var lifecycle string
	var reason *string
	if err := pool.QueryRow(context.Background(),
		`SELECT lifecycle, lifecycle_reason FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&lifecycle, &reason); err != nil {
		t.Fatalf("read chat group %d: %v", groupID, err)
	}
	if lifecycle != wantLifecycle || reason != nil {
		t.Fatalf("stored lifecycle=%q lifecycle_reason=%s, want %q and NULL",
			lifecycle, textOrNull(reason), wantLifecycle)
	}
}

// ─── Tests ──────────────────────────────────────────────────────────────

func TestApplyResumesAPausedGroup(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	staff := makeStaffUser(t, pool, "admin")
	group := makeGroup(t, pool, staff)

	// Paused WITH a reason, so the resume has a reason to clear.
	paused, err := Apply(ctx, pool, KindGroup, group, ActionPause, "Checking a report", staff)
	if err != nil {
		t.Fatalf("pause a group with a reason: %v", err)
	}
	if paused.Lifecycle != StatePaused || paused.Reason == nil || *paused.Reason != "Checking a report" {
		t.Fatalf("pause returned lifecycle=%q reason=%s, want paused with the reason kept",
			paused.Lifecycle, textOrNull(paused.Reason))
	}

	resumed, err := Apply(ctx, pool, KindGroup, group, ActionResume, "", staff)
	if err != nil {
		t.Fatalf("resume a paused group: %v", err)
	}
	assertGroupHasNoReason(t, pool, group, resumed, StateOpen)
}

func TestApplyWithoutAReasonOnAGroup(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	staff := makeStaffUser(t, pool, "admin")

	cases := []struct {
		name          string
		action        string
		reason        string
		wantLifecycle string
	}{
		{"pause with an empty reason", ActionPause, "", StatePaused},
		// Apply trims the reason, so whitespace is "no reason" too.
		{"pause with a blank reason", ActionPause, "  \n\t ", StatePaused},
		{"end with an empty reason", ActionEnd, "", StateEnded},
		{"end with a blank reason", ActionEnd, "  \n\t ", StateEnded},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			group := makeGroup(t, pool, staff)
			st, err := Apply(ctx, pool, KindGroup, group, tc.action, tc.reason, staff)
			if err != nil {
				t.Fatalf("%s on an open group: %v", tc.action, err)
			}
			assertGroupHasNoReason(t, pool, group, st, tc.wantLifecycle)
		})
	}
}

// A group nobody has moderated has no reason, the same as a new thread in the
// other chat systems. Both the app and the dashboard read the reason the
// handlers merge into their responses, so NULL for one system and "" for
// another would be two meanings of "no reason".
func TestLoadReportsNoReasonForANewGroup(t *testing.T) {
	pool := newTestPool(t)
	staff := makeStaffUser(t, pool, "admin")
	group := makeGroup(t, pool, staff)

	st, err := Load(context.Background(), pool, KindGroup, group)
	if err != nil {
		t.Fatalf("load a new group: %v", err)
	}
	if st.Lifecycle != StateOpen || st.Reason != nil {
		t.Fatalf("Load returned lifecycle=%q reason=%s for a new group, want open with no reason",
			st.Lifecycle, textOrNull(st.Reason))
	}
}
