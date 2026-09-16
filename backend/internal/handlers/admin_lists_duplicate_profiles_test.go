// admin_lists_duplicate_profiles_test.go — the operator-facing admin lists must
// show each row once even when the person on it has two user_profiles rows
// (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches — in the paginated lists
// that means both the page AND the total_items count.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_dup?sslmode=disable' \
//	  go test ./internal/handlers/ -run DuplicateProfiles -count=1
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupProfilesPool connects to TEST_DATABASE_URL and brings it up to date
// with the real migrations.
func newDupProfilesPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping duplicate-profile list tests")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// makeDupProfilesUser inserts a user with two profile rows (the older first).
func makeDupProfilesUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			id, name); err != nil {
			t.Fatalf("insert profile: %v", err)
		}
	}
	return id
}

// callAsStaff runs one handler with a signed-in staff user in the context and
// the given query string, and returns the decoded JSON body.
func callAsStaff(t *testing.T, h gin.HandlerFunc, query string) map[string]any {
	t.Helper()
	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest(http.MethodGet, "/?"+query, nil)
	// "auth.user" is auth.contextUserKey; requireAuth only checks that a
	// ResolvedUser is present, and these lists take no further permission.
	c.Set("auth.user", &auth.ResolvedUser{UserID: 1, RoleID: 1, Active: 1, IsAdmin: 1, StaffTier: "super_admin"})

	h(c)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body %s: %v", rec.Body.String(), err)
	}
	return body
}

// assertOnePagedRow checks a paginated admin list returned exactly one item and
// counted exactly one — the page and the COUNT join profiles separately, so
// both have to be asserted.
func assertOnePagedRow(t *testing.T, body map[string]any, what string) {
	t.Helper()
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("%s: got %d items, want 1", what, len(items))
	}
	if total, _ := body["total_items"].(float64); total != 1 {
		t.Errorf("%s: total_items = %v, want 1 — the COUNT joins profiles too", what, total)
	}
}

func TestInKindDonationsListsOneRowPerDonationWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	donor := makeDupProfilesUser(t, pool)
	item := fmt.Sprintf("dup-blankets-%d", rand.Intn(1000000))
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO in_kind_donations (donor_user_id, category, item_name) VALUES ($1, 'goods', $2) RETURNING id`,
		donor, item,
	).Scan(&id); err != nil {
		t.Fatalf("insert in-kind donation: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM in_kind_donations WHERE id = $1`, id)
	})

	h := &AdminListsHandler{Pool: pool}
	assertOnePagedRow(t, callAsStaff(t, h.InKindDonations, "q="+item), "in-kind donations")
}

func TestSupportTicketsListsOneRowPerTicketWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	user := makeDupProfilesUser(t, pool)
	subject := fmt.Sprintf("dup-ticket-%d", rand.Intn(1000000))
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO support_tickets (user_id, subject, message) VALUES ($1, $2, 'body') RETURNING id`,
		user, subject,
	).Scan(&id); err != nil {
		t.Fatalf("insert ticket: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM support_tickets WHERE id = $1`, id)
	})

	h := &AdminListsHandler{Pool: pool}
	assertOnePagedRow(t, callAsStaff(t, h.SupportTickets, "q="+subject), "support tickets")
}

func TestCampaignsListsOneRowPerCampaignWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	owner := makeDupProfilesUser(t, pool)
	title := fmt.Sprintf("dup-campaign-%d", rand.Intn(1000000))
	var id int64
	if err := pool.QueryRow(context.Background(),
		// Every column named here is NOT NULL with no default on campaigns.
		`INSERT INTO campaigns (title, title_ar, description, description_ar,
		                        address, beneficiaries, goal_amount, raised_amount, owner_user_id)
		 VALUES ($1, $1, 'seed', 'seed', 'Erbil', 10, 1000, 0, $2) RETURNING id`, title, owner,
	).Scan(&id); err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM campaigns WHERE id = $1`, id)
	})

	h := &AdminListsHandler{Pool: pool}
	assertOnePagedRow(t, callAsStaff(t, h.Campaigns, "q="+title), "campaigns")
}

// seedDupSignup creates an open mission and one pending signup on it from a
// volunteer with two profile rows.
func seedDupSignup(t *testing.T, pool *pgxpool.Pool) (missionID, signupID int64, title string) {
	t.Helper()
	ctx := context.Background()
	volunteer := makeDupProfilesUser(t, pool)
	title = fmt.Sprintf("dup-mission-%d", rand.Intn(1000000))
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title, status, city, section)
		 VALUES ($1, 'open', 'Erbil', 'Field work') RETURNING id`, title,
	).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups (mission_id, user_id, status) VALUES ($1, $2, 'pending') RETURNING id`,
		missionID, volunteer,
	).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM volunteer_mission_signups WHERE mission_id = $1`, missionID)
		_, _ = pool.Exec(ctx, `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})
	return missionID, signupID, title
}

func TestVolunteerMissionSignupsListsOneRowPerSignupWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	_, _, title := seedDupSignup(t, pool)

	h := &AdminListsHandler{Pool: pool}
	assertOnePagedRow(t, callAsStaff(t, h.VolunteerMissionSignups, "q="+title), "mission signups")
}

// TestVolunteerBoardCountsASignupOnceWithDuplicateProfiles reads the board's
// own per-mission counts: a duplicated volunteer put the same person in the
// lane twice, so the mission looked twice as staffed as it was.
func TestVolunteerBoardCountsASignupOnceWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	missionID, _, _ := seedDupSignup(t, pool)

	h := &AdminListsHandler{Pool: pool}
	body := callAsStaff(t, h.VolunteerBoard, "")
	missions, _ := body["missions"].([]any)
	found := false
	for _, m := range missions {
		mm, _ := m.(map[string]any)
		if id, _ := mm["id"].(float64); int64(id) != missionID {
			continue
		}
		found = true
		counts, _ := mm["counts"].(map[string]any)
		if pending, _ := counts["pending"].(float64); pending != 1 {
			t.Errorf("mission %d: pending = %v, want 1", missionID, pending)
		}
		lanes, _ := mm["lanes"].(map[string]any)
		if p, _ := lanes["pending"].([]any); len(p) != 1 {
			t.Errorf("mission %d: pending lane holds %d signups, want 1", missionID, len(p))
		}
	}
	if !found {
		t.Fatalf("mission %d is missing from the board", missionID)
	}
}

// TestTrashListsOneRowPerDeletionWithDuplicateProfiles covers admin_trash's
// list, whose deleted_by name joins profiles the same way.
func TestTrashListsOneRowPerDeletionWithDuplicateProfiles(t *testing.T) {
	pool := newDupProfilesPool(t)
	deleter := makeDupProfilesUser(t, pool)
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO trash_items (source_table, row_id, deleted_by, payload)
		 VALUES ('support_tickets', $1, $2, '{}'::jsonb) RETURNING id`,
		900000000+rand.Intn(90000000), deleter,
	).Scan(&id); err != nil {
		t.Fatalf("insert trash item: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM trash_items WHERE id = $1`, id)
	})

	h := &AdminTrashHandler{Pool: pool}
	body := callAsStaff(t, h.List, "")
	items, _ := body["items"].([]any)
	got := 0
	for _, it := range items {
		m, _ := it.(map[string]any)
		if rowID, _ := m["id"].(float64); int64(rowID) == id {
			got++
			if name, _ := m["deleted_by_name"].(string); name != "Oldest Profile Name" {
				t.Errorf("deleted_by_name = %q, want the oldest profile row's name", name)
			}
		}
	}
	if got != 1 {
		t.Fatalf("trash item %d listed %d times, want 1", id, got)
	}
}
