// duplicate_profiles_test.go — the reviewer's name in caseColumns must survive
// a reviewer who owns two user_profiles rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows.
// caseColumns reads the reviewer's name with a SCALAR SUBQUERY, and a scalar
// subquery that returns two rows does not merely repeat the outer row the way
// a join would — Postgres aborts the WHOLE statement with
// "more than one row returned by a subquery used as an expression". Every case
// list that touches such a reviewer therefore fails outright, not partially.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package beneficiary

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupTestPool connects to TEST_DATABASE_URL and brings it up to date with
// the real migrations, the same harness the other duplicate-profile tests use.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping beneficiary integration test")
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

// makeDupProfileUser inserts a user with two profile rows (the older first)
// and removes it afterwards; the profiles cascade with the user.
func makeDupProfileUser(t *testing.T, pool *pgxpool.Pool) int64 {
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

// seedCaseReviewedByDupUser creates one approved, publicly visible case whose
// reviewer owns two profile rows, and returns (ownerID, caseCode).
func seedCaseReviewedByDupUser(t *testing.T, pool *pgxpool.Pool) (int64, string) {
	t.Helper()
	ctx := context.Background()
	owner := makeDupProfileUser(t, pool)
	reviewer := makeDupProfileUser(t, pool)
	code := fmt.Sprintf("CSE-DUP-%06d", rand.Intn(1000000))
	var caseID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases
		   (user_id, case_code, public_title, full_name, phone, city,
		    priority_level, verification_status, public_visibility,
		    reviewed_by_user_id, reviewed_at)
		 VALUES ($1, $2, 'Duplicate reviewer case', 'Case Owner', '9647700000000', 'Erbil',
		         'medium', 'approved', 'summary', $3, CURRENT_TIMESTAMP)
		 RETURNING id`,
		owner, code, reviewer,
	).Scan(&caseID); err != nil {
		t.Fatalf("insert case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, caseID)
	})
	return owner, code
}

// TestListCasesForUserSurvivesAReviewerWithTwoProfiles is the core regression:
// on the unfixed code the scalar subquery returns two rows and the query
// ERRORS, so the owner cannot see their own case at all.
func TestListCasesForUserSurvivesAReviewerWithTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	owner, code := seedCaseReviewedByDupUser(t, pool)

	cases, err := NewStore(pool).ListCasesForUser(context.Background(), owner, "", 50)
	if err != nil {
		t.Fatalf("ListCasesForUser: %v", err)
	}
	if len(cases) != 1 || cases[0].CaseCode != code {
		t.Fatalf("got %d cases, want exactly %s once", len(cases), code)
	}
	if cases[0].ReviewedByName == nil || *cases[0].ReviewedByName != "Oldest Profile Name" {
		t.Errorf("ReviewedByName = %v, want the oldest profile row's name", cases[0].ReviewedByName)
	}
}

// TestAdminListCasesSurvivesAReviewerWithTwoProfiles covers the admin list,
// the operator-facing read that 500s on the unfixed code.
func TestAdminListCasesSurvivesAReviewerWithTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	_, code := seedCaseReviewedByDupUser(t, pool)

	page, err := NewStore(pool).AdminListCases(context.Background(), 1, 50, "", code)
	if err != nil {
		t.Fatalf("AdminListCases: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].CaseCode != code {
		t.Fatalf("got %d cases, want exactly %s once", len(page.Items), code)
	}
	if page.Items[0].ReviewedByName == nil || *page.Items[0].ReviewedByName != "Oldest Profile Name" {
		t.Errorf("ReviewedByName = %v, want the oldest profile row's name", page.Items[0].ReviewedByName)
	}
}
