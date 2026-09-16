// seed_test.go — integration tests for the chat end-to-end test fixture.
//
// These run the SAME functions cmd/seed-test-users calls, against a throwaway
// Postgres brought up to date with the real migrations. They are skipped
// unless TEST_DATABASE_URL is set, matching every other DB test in this repo
// (see internal/users/duplicate_profiles_test.go).
//
// What they pin down, in the order the brief asks for it:
//
//   - Seed creates the whole account matrix with the right role, tier and
//     account state;
//   - E1 (employee) holds NO sensitive_data grant — the masked-group test in
//     docs/testing/chat-e2e-test-plan-2026-09.md step 8 is worthless if it does;
//   - a second Seed run duplicates nothing (users.phone is UNIQUE and PR #134
//     normalises it, so a duplicate would be a hard failure, not a cosmetic one);
//   - Cleanup removes exactly this prefix's accounts and leaves every other row
//     in the database alone;
//   - the marriage fixtures (two profiles and one pending meeting request) are
//     created, reach the dashboard's meeting-requests inbox as PENDING, survive
//     a second run without duplicating, and are removed by the same Cleanup.
package seedtestusers

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
)

// newTestPool connects to TEST_DATABASE_URL and migrates it, then closes the
// pool when the test ends.
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping seed-test-users integration test")
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

// uniquePrefix keeps concurrent runs (and repeated local runs against one
// database) from fighting over the same usernames and phone numbers.
func uniquePrefix(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("t%06d", rand.Intn(1000000))
}

// countUsers returns how many rows this prefix's accounts occupy, counted by
// username so it is independent of the Seed result itself.
func countUsers(t *testing.T, pool *pgxpool.Pool, prefix string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM users WHERE username LIKE $1`, prefix+"\\_%",
	).Scan(&n); err != nil {
		t.Fatalf("count users for prefix %q: %v", prefix, err)
	}
	return n
}

// TestSeedCreatesTheMatrix is the main test: seed, check every account, seed
// again, check nothing doubled, clean up, check everything went and nothing
// else moved.
func TestSeedCreatesTheMatrix(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	prefix := uniquePrefix(t)
	// Always clean up, even when an assertion below fails part-way through, so
	// a failing run does not poison the next one.
	t.Cleanup(func() { _, _ = Cleanup(context.Background(), pool, prefix) })

	// A bystander account that Cleanup must not touch. It deliberately carries
	// the same shape as a seeded member — a phone, a role — so the only thing
	// separating it from the fixture is its identity.
	//
	// It is also a super_admin, which models the database this command will
	// actually be run against: Zaid's own Super Admin already exists there. A
	// database whose ONLY super_admin is the seeded one is a different case,
	// and Cleanup refuses to delete it — see TestCleanupKeepsTheLastSuperAdmin.
	bystanderPhone := fmt.Sprintf("9647%08d", rand.Intn(100000000))
	var bystanderID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, registration_status, username, staff_tier)
		 VALUES ($1, 1, 'approved', $2, 'super_admin') RETURNING id`,
		bystanderPhone, prefix+"-bystander",
	).Scan(&bystanderID); err != nil {
		t.Fatalf("insert bystander: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, bystanderID)
	})

	// ─── First run ───────────────────────────────────────────────────────
	res, err := Seed(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Seed: %v", err)
	}
	if len(res.Accounts) != len(Specs) {
		t.Fatalf("Seed returned %d accounts, want %d", len(res.Accounts), len(Specs))
	}
	if res.Created != len(Specs) {
		t.Errorf("first Seed created %d accounts, want %d", res.Created, len(Specs))
	}

	byKey := map[string]Account{}
	for _, a := range res.Accounts {
		byKey[a.Key] = a
	}

	for _, spec := range Specs {
		acct, ok := byKey[spec.Key]
		if !ok {
			t.Fatalf("Seed produced no account for %q", spec.Key)
		}
		if acct.UserID <= 0 {
			t.Fatalf("%s: got user id %d", spec.Key, acct.UserID)
		}

		var (
			roleID    *int
			staffTier string
			regStatus string
			acctState string
			isGuest   bool
			phone     *string
			username  *string
			hash      *string
		)
		if err := pool.QueryRow(ctx,
			`SELECT role_id, staff_tier, registration_status, account_status,
			        is_guest, phone, username, password_hash
			   FROM users WHERE id = $1`, acct.UserID,
		).Scan(&roleID, &staffTier, &regStatus, &acctState, &isGuest, &phone, &username, &hash); err != nil {
			t.Fatalf("%s: read back user %d: %v", spec.Key, acct.UserID, err)
		}

		gotRole := 0
		if roleID != nil {
			gotRole = *roleID
		}
		if gotRole != spec.RoleID {
			t.Errorf("%s: role_id = %d, want %d", spec.Key, gotRole, spec.RoleID)
		}
		// A non-staff account keeps the column's own NOT NULL default, 'user'
		// (migration 015) — the tier that has no dashboard at all.
		wantTier := spec.StaffTier
		if wantTier == "" {
			wantTier = "user"
		}
		if staffTier != wantTier {
			t.Errorf("%s: staff_tier = %q, want %q", spec.Key, staffTier, wantTier)
		}
		// Every account must be usable immediately: a 'pending' registration
		// cannot enter the app at all, so a fixture that stops there is not a
		// fixture.
		if regStatus != "approved" {
			t.Errorf("%s: registration_status = %q, want \"approved\"", spec.Key, regStatus)
		}
		if acctState != "active" {
			t.Errorf("%s: account_status = %q, want \"active\"", spec.Key, acctState)
		}
		if isGuest != spec.IsGuest {
			t.Errorf("%s: is_guest = %v, want %v", spec.Key, isGuest, spec.IsGuest)
		}
		if hash == nil || *hash == "" {
			t.Errorf("%s: password_hash is empty — the account cannot sign in", spec.Key)
		}
		if username == nil || *username != acct.Username {
			t.Errorf("%s: username = %v, want %q", spec.Key, username, acct.Username)
		}
		// The guest is the one account with no phone: "continue as guest" never
		// asks for a number (internal/users.InsertGuest).
		if spec.IsGuest {
			if phone != nil {
				t.Errorf("%s: guest has phone %q, want none", spec.Key, *phone)
			}
		} else {
			if phone == nil || *phone != acct.Phone {
				t.Errorf("%s: phone = %v, want %q", spec.Key, phone, acct.Phone)
			}
		}

		// Every account needs a profile row with a findable name: staff read
		// names off it everywhere, and a blank one is indistinguishable from a
		// save that failed.
		var profiles int
		if err := pool.QueryRow(ctx,
			`SELECT COUNT(*) FROM user_profiles WHERE user_id = $1 AND full_name <> ''`, acct.UserID,
		).Scan(&profiles); err != nil {
			t.Fatalf("%s: count profiles: %v", spec.Key, err)
		}
		if profiles != 1 {
			t.Errorf("%s: %d named user_profiles rows, want exactly 1", spec.Key, profiles)
		}
	}

	// ─── The sensitive_data rule ─────────────────────────────────────────
	//
	// Step 8 of the test plan turns on exactly one switch and watches the
	// screen change. If the seeder hands E1 that switch already on, the step
	// proves nothing. No per-user override row at all is the correct state:
	// the employee tier's default for sensitive_data/view is already "no"
	// (internal/permissions.moduleDefaultAllowed).
	e1 := byKey["E1"]
	var overrides int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM role_permissions WHERE user_id = $1`, e1.UserID,
	).Scan(&overrides); err != nil {
		t.Fatalf("count E1 overrides: %v", err)
	}
	if overrides != 0 {
		t.Errorf("E1 carries %d per-user permission override(s), want 0", overrides)
	}

	// A granted override must be swept away by a re-run, or a seeder used
	// twice in one afternoon silently leaves step 8 already-passed.
	if _, err := pool.Exec(ctx,
		`INSERT INTO role_permissions (user_id, tier, module, action, allowed, updated_at)
		 VALUES ($1, 'employee', 'sensitive_data', 'view', TRUE, NOW())`, e1.UserID,
	); err != nil {
		t.Fatalf("plant E1 sensitive_data override: %v", err)
	}

	// ─── Second run: nothing duplicates ──────────────────────────────────
	before := countUsers(t, pool, prefix)
	res2, err := Seed(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("second Seed: %v", err)
	}
	if res2.Created != 0 {
		t.Errorf("second Seed created %d accounts, want 0", res2.Created)
	}
	if after := countUsers(t, pool, prefix); after != before {
		t.Errorf("second Seed changed the account count: %d → %d", before, after)
	}
	for _, a := range res2.Accounts {
		if got := byKey[a.Key].UserID; a.UserID != got {
			t.Errorf("%s: second Seed returned user id %d, want the original %d", a.Key, a.UserID, got)
		}
	}
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM role_permissions WHERE user_id = $1`, e1.UserID,
	).Scan(&overrides); err != nil {
		t.Fatalf("recount E1 overrides: %v", err)
	}
	if overrides != 0 {
		t.Errorf("after re-seeding, E1 still carries %d override(s), want 0", overrides)
	}

	// ─── Cleanup ─────────────────────────────────────────────────────────
	cl, err := Cleanup(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Cleanup: %v", err)
	}
	if cl.Deleted != len(Specs) {
		t.Errorf("Cleanup deleted %d accounts, want %d", cl.Deleted, len(Specs))
	}
	if n := countUsers(t, pool, prefix); n != 0 {
		t.Errorf("%d seeded account(s) survived Cleanup, want 0", n)
	}
	// The bystander is the whole point of the "and nothing else" requirement.
	var bystanderAlive int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users WHERE id = $1`, bystanderID,
	).Scan(&bystanderAlive); err != nil {
		t.Fatalf("check bystander: %v", err)
	}
	if bystanderAlive != 1 {
		t.Fatalf("Cleanup deleted the bystander account %d", bystanderID)
	}

	// Cleanup on an already-clean database is a no-op, not an error.
	cl2, err := Cleanup(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("second Cleanup: %v", err)
	}
	if cl2.Deleted != 0 {
		t.Errorf("second Cleanup deleted %d accounts, want 0", cl2.Deleted)
	}
}

// TestCleanupLeavesForeignAccountsAlone proves the prefix match cannot reach
// an account the seeder did not create, even one whose username starts with
// the same letters. Cleanup matches the exact identity pair it would have
// written, never a LIKE.
func TestCleanupLeavesForeignAccountsAlone(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	prefix := uniquePrefix(t)

	// Same username the seeder would use for D, but a phone outside the
	// reserved block — i.e. a real account that happens to collide by name.
	// Cleanup must refuse it.
	impostorPhone := fmt.Sprintf("9647%08d", rand.Intn(100000000))
	var impostorID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, registration_status, username)
		 VALUES ($1, 1, 'approved', $2) RETURNING id`,
		impostorPhone, prefix+"_d",
	).Scan(&impostorID); err != nil {
		t.Fatalf("insert impostor: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, impostorID)
	})

	cl, err := Cleanup(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Cleanup: %v", err)
	}
	if cl.Deleted != 0 {
		t.Errorf("Cleanup deleted %d account(s), want 0", cl.Deleted)
	}
	if len(cl.Refused) == 0 {
		t.Errorf("Cleanup did not report refusing the impostor account")
	}
	var alive int
	if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE id = $1`, impostorID).Scan(&alive); err != nil {
		t.Fatalf("check impostor: %v", err)
	}
	if alive != 1 {
		t.Fatalf("Cleanup deleted the impostor account %d", impostorID)
	}
}

// TestCleanupKeepsTheLastSuperAdmin covers the one account Cleanup will not
// remove on request: a database left with no Super Admin has nobody who can
// grant a permission or empty the Trash, and no screen that can make one.
func TestCleanupKeepsTheLastSuperAdmin(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	prefix := uniquePrefix(t)

	var supers int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users WHERE staff_tier = 'super_admin'`,
	).Scan(&supers); err != nil {
		t.Fatalf("count super admins: %v", err)
	}
	if supers > 0 {
		t.Skip("this database already has a super_admin — the last-one case cannot be reproduced here")
	}

	if _, err := Seed(ctx, pool, prefix); err != nil {
		t.Fatalf("Seed: %v", err)
	}
	cl, err := Cleanup(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Cleanup: %v", err)
	}
	if cl.Deleted != len(Specs)-1 {
		t.Errorf("Cleanup deleted %d accounts, want %d (everything but SA)", cl.Deleted, len(Specs)-1)
	}
	refusedSA := false
	for _, r := range cl.Refused {
		if r.Key == "SA" {
			refusedSA = true
		}
	}
	if !refusedSA {
		t.Errorf("Cleanup did not refuse the last Super Admin; refusals: %+v", cl.Refused)
	}
	// Remove it by hand so the next test in this package starts clean.
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM users WHERE LOWER(username) = LOWER($1)`, prefix+"_sa")
	})
}

// TestPlanIsDeterministicAndFake guards the two properties the operator is
// asked to trust in the printed table: the same prefix always yields the same
// credentials, and every number is in the reserved block that cannot be a real
// Iraqi mobile.
func TestPlanIsDeterministicAndFake(t *testing.T) {
	a := Plan("test")
	b := Plan("test")
	if len(a) != len(Specs) {
		t.Fatalf("Plan returned %d accounts, want %d", len(a), len(Specs))
	}
	seenPhone := map[string]bool{}
	seenUser := map[string]bool{}
	for i := range a {
		if a[i] != b[i] {
			t.Errorf("Plan is not deterministic at %d: %+v vs %+v", i, a[i], b[i])
		}
		if a[i].Phone != "" {
			if !InReservedPhoneBlock(a[i].Phone) {
				t.Errorf("%s: phone %q is outside the reserved block %s",
					a[i].Key, a[i].Phone, ReservedPhoneBlockLabel)
			}
			if seenPhone[a[i].Phone] {
				t.Errorf("%s: phone %q is used twice", a[i].Key, a[i].Phone)
			}
			seenPhone[a[i].Phone] = true
		}
		if seenUser[a[i].Username] {
			t.Errorf("%s: username %q is used twice", a[i].Key, a[i].Username)
		}
		seenUser[a[i].Username] = true
	}
}

// ─── The marriage fixtures ──────────────────────────────────────────────────

// countMarriageRows returns how many marriage profiles and meeting requests
// belong to a set of seeded users, counted straight off the tables so it is
// independent of the Seed result.
func countMarriageRows(t *testing.T, pool *pgxpool.Pool, userIDs []int64) (profiles, requests int) {
	t.Helper()
	ctx := context.Background()
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marriage_profiles WHERE user_id = ANY($1)`, userIDs,
	).Scan(&profiles); err != nil {
		t.Fatalf("count marriage profiles: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marriage_meeting_requests WHERE from_user_id = ANY($1)`, userIDs,
	).Scan(&requests); err != nil {
		t.Fatalf("count meeting requests: %v", err)
	}
	return profiles, requests
}

// TestSeedCreatesTheMarriageFixtures covers step 5 of the test plan: the
// client cannot approve a meeting request that does not exist, so Seed has to
// leave two profiles and one PENDING request behind — in the state the
// dashboard's Marriage → Marriage Requests screen lists as awaiting a
// decision — without duplicating them on a second run, and Cleanup has to take
// them away again.
func TestSeedCreatesTheMarriageFixtures(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	prefix := uniquePrefix(t)
	t.Cleanup(func() { _, _ = Cleanup(context.Background(), pool, prefix) })

	// Another Super Admin, so the Cleanup assertion at the end measures the
	// marriage rows and not the "never delete the last super_admin" rule, which
	// has its own test (TestCleanupKeepsTheLastSuperAdmin). It also models the
	// real database, where Zaid's own Super Admin already exists.
	var bystanderID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, registration_status, username, staff_tier)
		 VALUES ($1, 'approved', $2, 'super_admin') RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)), prefix+"-bystander-sa",
	).Scan(&bystanderID); err != nil {
		t.Fatalf("insert bystander super admin: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, bystanderID)
	})

	res, err := Seed(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Seed: %v", err)
	}
	if res.Marriage == nil {
		t.Fatalf("Seed returned no marriage fixtures")
	}
	byKey := map[string]Account{}
	ids := make([]int64, 0, len(res.Accounts))
	for _, a := range res.Accounts {
		byKey[a.Key] = a
		ids = append(ids, a.UserID)
	}

	// ─── The two profiles ────────────────────────────────────────────────
	if len(res.Marriage.Profiles) != len(MarriageProfileSpecs) {
		t.Fatalf("Seed returned %d marriage profiles, want %d",
			len(res.Marriage.Profiles), len(MarriageProfileSpecs))
	}
	for _, p := range res.Marriage.Profiles {
		if p.ProfileID <= 0 || p.ProfileCode == "" {
			t.Fatalf("%s: marriage profile came back as %+v", p.OwnerKey, p)
		}
		if want := byKey[p.OwnerKey].UserID; p.OwnerUserID != want {
			t.Errorf("%s: profile owner is user %d, want %d", p.OwnerKey, p.OwnerUserID, want)
		}
		var (
			status, visible string
			gender, city    *string
			age             *int
			notes           *string
			ownerDeleted    *string
		)
		if err := pool.QueryRow(ctx,
			`SELECT status, visibility_level, gender, city, age, private_notes,
			        owner_deleted_at::text
			   FROM marriage_profiles WHERE id = $1`, p.ProfileID,
		).Scan(&status, &visible, &gender, &city, &age, &notes, &ownerDeleted); err != nil {
			t.Fatalf("%s: read back profile %d: %v", p.OwnerKey, p.ProfileID, err)
		}
		// 'active' + a non-private visibility + no owner delete is exactly the
		// set marriage.Store.List serves to a searching member, so this is what
		// "findable in the app's search" means (internal/marriage/marriage.go).
		if status != "active" {
			t.Errorf("%s: profile status = %q, want \"active\"", p.OwnerKey, status)
		}
		if visible == "private" {
			t.Errorf("%s: profile visibility_level = %q — search skips private profiles", p.OwnerKey, visible)
		}
		if ownerDeleted != nil {
			t.Errorf("%s: profile carries owner_deleted_at = %q, so search hides it", p.OwnerKey, *ownerDeleted)
		}
		// The app's own gender filter offers 'Male'/'Female' capitalised
		// (humanitarian/lib/modules/marriage/screens/marriage_search_screen.dart)
		// and matches exactly, so anything else is unfindable there.
		if gender == nil || (*gender != "Male" && *gender != "Female") {
			t.Errorf("%s: profile gender = %v, want \"Male\" or \"Female\"", p.OwnerKey, gender)
		}
		if city == nil || *city == "" {
			t.Errorf("%s: profile has no city", p.OwnerKey)
		}
		if age == nil || *age <= 0 {
			t.Errorf("%s: profile has no age", p.OwnerKey)
		}
		if notes == nil || *notes != marriageFixtureNote(prefix) {
			t.Errorf("%s: private_notes = %v, want the fixture marker Cleanup matches on", p.OwnerKey, notes)
		}
	}

	// ─── The pending request, as the dashboard sees it ───────────────────
	requester := byKey[MarriageRequesterKey]
	if res.Marriage.RequesterUserID != requester.UserID {
		t.Errorf("request is from user %d, want %s (user %d)",
			res.Marriage.RequesterUserID, MarriageRequesterKey, requester.UserID)
	}
	// ListMeetingRequests is the query behind
	// GET /api/admin/marriage/meeting-requests, which is the only thing the
	// dashboard screen reads — asserting on it is asserting on the screen.
	inbox, err := marriagechat.New(pool).ListMeetingRequests(ctx)
	if err != nil {
		t.Fatalf("ListMeetingRequests: %v", err)
	}
	seen := 0
	for _, r := range inbox {
		if r.ID != res.Marriage.RequestID {
			continue
		}
		seen++
		if r.Status != "pending" {
			t.Errorf("the seeded request is %q, want \"pending\" — the dashboard offers Approve only on a pending row", r.Status)
		}
		if r.FromUserID != requester.UserID {
			t.Errorf("request from_user_id = %d, want %d", r.FromUserID, requester.UserID)
		}
		if r.ProfileID != res.Marriage.AboutProfileID {
			t.Errorf("request profile_id = %d, want %d", r.ProfileID, res.Marriage.AboutProfileID)
		}
		if r.OwnerUserID != byKey[MarriageRequestAboutKey].UserID {
			t.Errorf("request profile owner = %d, want %s's user id", r.OwnerUserID, MarriageRequestAboutKey)
		}
		if r.OwnerUserID == r.FromUserID {
			t.Errorf("requester and profile owner are the same account — approving would be refused")
		}
		// The inbox shows both names; a blank one reads as a broken row.
		if r.FromName == nil || *r.FromName == "" || r.OwnerName == nil || *r.OwnerName == "" {
			t.Errorf("the inbox row has a nameless party: from=%v owner=%v", r.FromName, r.OwnerName)
		}
	}
	if seen != 1 {
		t.Fatalf("the seeded request appears %d time(s) in the dashboard inbox, want exactly 1", seen)
	}

	// ─── Second run: nothing duplicates ──────────────────────────────────
	profilesBefore, requestsBefore := countMarriageRows(t, pool, ids)
	res2, err := Seed(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("second Seed: %v", err)
	}
	profilesAfter, requestsAfter := countMarriageRows(t, pool, ids)
	if profilesAfter != profilesBefore || requestsAfter != requestsBefore {
		t.Errorf("second Seed changed the marriage rows: profiles %d → %d, requests %d → %d",
			profilesBefore, profilesAfter, requestsBefore, requestsAfter)
	}
	if res2.Marriage == nil || res2.Marriage.RequestID != res.Marriage.RequestID {
		t.Errorf("second Seed returned a different meeting request: %+v", res2.Marriage)
	}
	for i, p := range res2.Marriage.Profiles {
		if p.ProfileID != res.Marriage.Profiles[i].ProfileID {
			t.Errorf("%s: second Seed returned profile %d, want the original %d",
				p.OwnerKey, p.ProfileID, res.Marriage.Profiles[i].ProfileID)
		}
		if p.Created {
			t.Errorf("%s: second Seed reports the profile as newly created", p.OwnerKey)
		}
	}

	// ─── Staff can actually approve it ───────────────────────────────────
	//
	// The point of the fixture is the click the client is about to make, so
	// this runs it: the same function POST /api/admin/marriage/meeting-requests
	// /:id/approve calls. It needs nothing the seed did not already provide —
	// no extra field, no staff input beyond the session — and it must open a
	// thread waiting for the profile owner, which is step 5's invite.
	//
	// It runs last, after the idempotency checks: approving decides the
	// request, and a decided request is deliberately not reused.
	thread, ownerID, err := marriagechat.New(pool).ApproveMeetingRequest(ctx, res.Marriage.RequestID, byKey["SA"].UserID)
	if err != nil {
		t.Fatalf("ApproveMeetingRequest on the seeded request: %v", err)
	}
	if thread.Status != "pending" {
		t.Errorf("approved thread status = %q, want \"pending\" (waiting for the profile owner to accept)", thread.Status)
	}
	if ownerID != byKey[MarriageRequestAboutKey].UserID {
		t.Errorf("approval says the owner to notify is %d, want %s's user id", ownerID, MarriageRequestAboutKey)
	}

	// ─── Cleanup takes the marriage rows with it ─────────────────────────
	cl, err := Cleanup(ctx, pool, prefix)
	if err != nil {
		t.Fatalf("Cleanup: %v", err)
	}
	// A marriage profile is ON DELETE RESTRICT on its owner (migration 002),
	// so an account whose profile survived cannot be deleted at all: this
	// assertion is what proves Cleanup removed the marriage rows first.
	if cl.Deleted != len(Specs) {
		t.Errorf("Cleanup deleted %d accounts, want %d; refusals: %+v", cl.Deleted, len(Specs), cl.Refused)
	}
	if p, r := countMarriageRows(t, pool, ids); p != 0 || r != 0 {
		t.Errorf("after Cleanup: %d marriage profile(s) and %d meeting request(s) survived, want 0 and 0", p, r)
	}
	// The chat the approval opened goes with them (it cascades from both the
	// profile and the request, migration 058).
	var threads int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marriage_chat_threads WHERE id = $1`, thread.ID,
	).Scan(&threads); err != nil {
		t.Fatalf("count marriage chat threads: %v", err)
	}
	if threads != 0 {
		t.Errorf("the seeded marriage chat thread %d survived Cleanup", thread.ID)
	}
}
