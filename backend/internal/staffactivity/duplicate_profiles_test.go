// duplicate_profiles_test.go — a staff member's activity timeline must list a
// registration they reviewed once, even when that registrant has two
// user_profiles rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and the registration branch of timelineSQL joined it plainly — so one review
// appeared as two pieces of work done.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set. It reuses newTestPool/makeTestUser from
// store_test.go.
package staffactivity

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// giveTwoProfiles attaches two user_profiles rows (the older first) to an
// existing user.
func giveTwoProfiles(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	ctx := context.Background()
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			userID, name); err != nil {
			t.Fatalf("insert profile: %v", err)
		}
	}
}

func TestTimelineListsAReviewedRegistrationOnceWhenTheRegistrantHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	reviewer := makeTestUser(t, pool)
	registrant := makeTestUser(t, pool)
	giveTwoProfiles(t, pool, registrant)

	if _, err := pool.Exec(context.Background(),
		`UPDATE users
		    SET registration_status = 'approved',
		        registration_reviewed_by = $1,
		        registration_reviewed_at = CURRENT_TIMESTAMP
		  WHERE id = $2`, reviewer, registrant); err != nil {
		t.Fatalf("mark registration reviewed: %v", err)
	}

	summary, err := New(pool).Load(context.Background(), reviewer, 200)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	got := 0
	subject := ""
	for _, e := range summary.Timeline {
		if e.Kind == "registration" && e.EntityID == registrant {
			got++
			subject = e.Subject
		}
	}
	if got != 1 {
		t.Fatalf("registration %d appears %d times on the timeline, want 1", registrant, got)
	}
	if subject != "Oldest Profile Name" {
		t.Errorf("subject = %q, want the oldest profile row's name", subject)
	}
}
