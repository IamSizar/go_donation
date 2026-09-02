// Pins the employee profile — "all of his actions and activity and all the
// causes he handled and accepted".
//
// THE PROPERTY THAT MATTERS MOST is not that the numbers are right but that
// they are THIS PERSON'S. A profile that quietly folds in a colleague's
// decisions is worse than no profile: it is used to judge someone's work, and
// nothing on the screen would reveal the mistake. So every assertion here is
// made with a second staff member present, having done the same kinds of
// things, and the test fails if any of it leaks across.
//
// The second property is that the timeline and the totals agree about the
// same underlying rows — a limit must never quietly become the total.
package handlers

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/staffactivity"
)

// seedDecisions gives one staff member one decision of each dated kind, and
// returns how many that is.
func seedDecisions(t *testing.T, pool *pgxpool.Pool, staffID int64, subject int64) int {
	t.Helper()
	ctx := context.Background()
	at := time.Now().Add(-time.Hour)

	// A reviewed case. case_code and public_title are both NOT NULL with no
	// default, so both are supplied rather than left to the schema.
	var caseID int64
	err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases
		   (user_id, case_code, public_title, full_name, national_id, phone,
		    city, address, verification_status, reviewed_by_user_id, reviewed_at)
		 VALUES ($1, $2, 'Seeded case', 'Case Subject', '', '', '', '', 'verified', $3, $4)
		 RETURNING id`,
		subject, "CASE-"+time.Now().Format("150405.000000"), staffID, at,
	).Scan(&caseID)
	if err != nil {
		t.Fatalf("seed case: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM beneficiary_cases WHERE id = $1`, caseID) })

	// A registration this staff member decided.
	if _, err := pool.Exec(ctx,
		`UPDATE users
		    SET registration_status = 'approved',
		        registration_reviewed_by = $2,
		        registration_reviewed_at = $3
		  WHERE id = $1`, subject, staffID, at,
	); err != nil {
		t.Fatalf("seed registration review: %v", err)
	}

	var pcrID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO profile_change_requests (user_id, field, status, decided_by, decided_at)
		 VALUES ($1, 'full_name', 'approved', $2, $3) RETURNING id`,
		subject, staffID, at,
	).Scan(&pcrID); err != nil {
		t.Fatalf("seed profile change: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM profile_change_requests WHERE id = $1`, pcrID) })

	var permID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO permission_audit_log (actor_id, action, target)
		 VALUES ($1, 'tier_change', 'user#99') RETURNING id`, staffID,
	).Scan(&permID); err != nil {
		t.Fatalf("seed permission log: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM permission_audit_log WHERE id = $1`, permID) })

	// case, registration, profile change, permission. Meeting requests need a
	// marriage profile to point at and are covered by the leak test instead.
	return 4
}

func TestStaffActivityCountsOnlyThisPersonsWork(t *testing.T) {
	pool := newAuthTestPool(t)
	store := staffactivity.New(pool)
	ctx := context.Background()

	mine := insertAccount(t, pool, "user", "")
	theirs := insertAccount(t, pool, "user", "")
	subjectA := insertAccount(t, pool, "user", "")
	subjectB := insertAccount(t, pool, "user", "")

	want := seedDecisions(t, pool, mine.id, subjectA.id)
	// The colleague does the same amount of the same work. Nothing of theirs
	// may appear below.
	seedDecisions(t, pool, theirs.id, subjectB.id)

	got, err := store.Load(ctx, mine.id, 100)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if got.Totals.All != want {
		t.Errorf(
			"totals.All = %d, want %d (%+v). A count that does not match the "+
				"seeded decisions means the profile is either missing this "+
				"person's work or crediting them with someone else's.",
			got.Totals.All, want, got.Totals,
		)
	}
	if len(got.Timeline) != want {
		t.Errorf("timeline has %d entries, want %d", len(got.Timeline), want)
	}
	for _, e := range got.Timeline {
		switch e.Kind {
		case "case", "registration", "profile_change", "permission", "meeting_request":
		default:
			t.Errorf("unknown timeline kind %q — the dashboard renders per kind", e.Kind)
		}
	}
	if got.Truncated {
		t.Error("reported as truncated with every row present")
	}
}

func TestStaffActivityTimelineIsNewestFirst(t *testing.T) {
	pool := newAuthTestPool(t)
	store := staffactivity.New(pool)
	ctx := context.Background()

	staff := insertAccount(t, pool, "user", "")
	subject := insertAccount(t, pool, "user", "")
	seedDecisions(t, pool, staff.id, subject.id)

	// One decision from long ago, which must sort to the bottom rather than
	// wherever the UNION happened to put it.
	old := time.Now().Add(-90 * 24 * time.Hour)
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO profile_change_requests (user_id, field, status, decided_by, decided_at)
		 VALUES ($1, 'profile_picture', 'rejected', $2, $3) RETURNING id`,
		subject.id, staff.id, old,
	).Scan(&id); err != nil {
		t.Fatalf("seed old decision: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM profile_change_requests WHERE id = $1`, id) })

	got, err := store.Load(ctx, staff.id, 100)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(got.Timeline) < 2 {
		t.Fatalf("expected several entries, got %d", len(got.Timeline))
	}
	for i := 1; i < len(got.Timeline); i++ {
		if got.Timeline[i].At.After(got.Timeline[i-1].At) {
			t.Fatalf(
				"entry %d (%s) is newer than the one above it — the page reads "+
					"top-down as most recent first",
				i, got.Timeline[i].At,
			)
		}
	}
	// Identified by WHAT it is, not by comparing wall-clock times: decided_at
	// is `timestamp without time zone`, so the offset does not survive the
	// round trip and an equality check on the instant fails for a reason that
	// has nothing to do with ordering.
	last := got.Timeline[len(got.Timeline)-1]
	if last.Kind != "profile_change" || last.Action != "rejected" {
		t.Errorf(
			"last entry is %s/%s; expected the 90-day-old rejected profile "+
				"change, so old decisions are sorting to the bottom",
			last.Kind, last.Action,
		)
	}
	if !last.At.Before(got.Timeline[0].At) {
		t.Error("the oldest entry is not older than the newest")
	}
}

// A limit shortens the LIST. It must not shorten the COUNTS, or a busy
// reviewer's profile reports a fraction of their work as the whole of it.
func TestStaffActivityLimitDoesNotChangeTotals(t *testing.T) {
	pool := newAuthTestPool(t)
	store := staffactivity.New(pool)
	ctx := context.Background()

	staff := insertAccount(t, pool, "user", "")
	subject := insertAccount(t, pool, "user", "")
	want := seedDecisions(t, pool, staff.id, subject.id)

	got, err := store.Load(ctx, staff.id, 1)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(got.Timeline) != 1 {
		t.Errorf("timeline length = %d, want the requested 1", len(got.Timeline))
	}
	if got.Totals.All != want {
		t.Errorf("totals.All = %d under a limit of 1, want %d", got.Totals.All, want)
	}
	if !got.Truncated {
		t.Error("truncation not reported, so the page would imply this is the whole history")
	}
}

// A half-written row — decided_by set, decided_at NULL — must not appear on a
// timeline, because there is no honest date to show for it.
func TestStaffActivitySkipsUndatedDecisions(t *testing.T) {
	pool := newAuthTestPool(t)
	store := staffactivity.New(pool)
	ctx := context.Background()

	staff := insertAccount(t, pool, "user", "")
	subject := insertAccount(t, pool, "user", "")

	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO profile_change_requests (user_id, field, status, decided_by, decided_at)
		 VALUES ($1, 'full_name', 'approved', $2, NULL) RETURNING id`,
		subject.id, staff.id,
	).Scan(&id); err != nil {
		t.Fatalf("seed undated decision: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM profile_change_requests WHERE id = $1`, id) })

	got, err := store.Load(ctx, staff.id, 100)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(got.Timeline) != 0 {
		t.Errorf("an undated decision reached the timeline: %+v", got.Timeline)
	}
	if got.Totals.All != 0 {
		t.Errorf("an undated decision was counted: %+v", got.Totals)
	}
}
