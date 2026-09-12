package chatgroups

import (
	"context"
	"os"
	"sync/atomic"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newTestPool brings a throwaway database up to date with the real
// migrations. Skipped unless TEST_DATABASE_URL is set, so `go test ./...`
// stays green on a bare checkout:
//
//	createdb godonation_chatgroups
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups?sslmode=disable' \
//	  go test ./internal/chatgroups/ -v
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chatgroups integration test")
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

func TestNewStoreConnects(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	if s.Pool != pool {
		t.Fatal("New did not wire the pool through")
	}
}

func TestCreateGroupMasked(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	donor2 := makeTestUser(t, pool, "donor")
	staff := makeTestUser(t, pool, "staff")

	groupID, err := s.CreateGroup(ctx, KindMasked, "ignored for masked groups", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
		{UserID: donor2, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if groupID == 0 {
		t.Fatal("expected a non-zero group id")
	}

	var kind, title string
	if err := pool.QueryRow(ctx,
		`SELECT kind, member_title FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind, &title); err != nil {
		t.Fatalf("read group: %v", err)
	}
	if kind != "masked" {
		t.Errorf("kind = %q, want masked", kind)
	}
	if title != "" {
		t.Errorf("member_title = %q, want empty — masked groups never carry a member-facing title", title)
	}

	rows, err := pool.Query(ctx,
		`SELECT user_id, role_in_group, masked, masked_label FROM chat_group_members WHERE group_id = $1 ORDER BY id`, groupID)
	if err != nil {
		t.Fatalf("read members: %v", err)
	}
	defer rows.Close()
	var got []struct {
		userID int64
		role   string
		masked bool
		label  string
	}
	for rows.Next() {
		var r struct {
			userID int64
			role   string
			masked bool
			label  string
		}
		if err := rows.Scan(&r.userID, &r.role, &r.masked, &r.label); err != nil {
			t.Fatalf("scan member: %v", err)
		}
		got = append(got, r)
	}
	if len(got) != 3 {
		t.Fatalf("got %d members, want 3", len(got))
	}
	if !got[0].masked || got[0].label != "Donor 1" {
		t.Errorf("donor member = %+v, want masked=true label=Donor 1", got[0])
	}
	if !got[1].masked || got[1].label != "Beneficiary 1" {
		t.Errorf("beneficiary member = %+v, want masked=true label=Beneficiary 1", got[1])
	}
	if !got[2].masked || got[2].label != "Donor 2" {
		t.Errorf("second donor member = %+v, want masked=true label=Donor 2", got[2])
	}
}

func TestCreateGroupTeamMembersAreNeverMasked(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	v1 := makeTestUser(t, pool, "volunteer")
	v2 := makeTestUser(t, pool, "volunteer")
	staff := makeTestUser(t, pool, "staff")

	groupID, err := s.CreateGroup(ctx, KindTeam, "Distribution team", staff, []MemberInput{
		{UserID: v1, RoleInGroup: "volunteer"},
		{UserID: v2, RoleInGroup: "volunteer"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	var title string
	if err := pool.QueryRow(ctx,
		`SELECT member_title FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&title); err != nil {
		t.Fatalf("read group: %v", err)
	}
	if title != "Distribution team" {
		t.Errorf("member_title = %q, want %q", title, "Distribution team")
	}

	rows, err := pool.Query(ctx,
		`SELECT masked, masked_label FROM chat_group_members WHERE group_id = $1`, groupID)
	if err != nil {
		t.Fatalf("read members: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var masked bool
		var label *string
		if err := rows.Scan(&masked, &label); err != nil {
			t.Fatalf("scan: %v", err)
		}
		if masked {
			t.Error("team-group member has masked=true, want false")
		}
		if label != nil {
			t.Errorf("team-group member has a masked_label (%q), want NULL", *label)
		}
	}
}

// makeTestUser inserts a minimal users row and removes it on cleanup. role
// is informational only here (chatgroups doesn't read users.role_id); it's
// recorded so test failures are easier to read.
func makeTestUser(t *testing.T, pool *pgxpool.Pool, role string) int64 {
	t.Helper()
	ctx := context.Background()
	phone := "9647" + randomDigits(t, 8)
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert test user (%s): %v", role, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// testUserPhoneSeq gives each makeTestUser call a distinct phone number.
// randomDigits alone (seeded only from t.Name() and the digit index) repeats
// identically across multiple calls within the SAME test — every
// multi-member test (e.g. TestCreateGroupMasked, which inserts a donor and a
// beneficiary under one *testing.T) hit a real `users_phone_key` collision
// because of this before the counter was added.
var testUserPhoneSeq int64

func randomDigits(t *testing.T, n int) string {
	t.Helper()
	seq := atomic.AddInt64(&testUserPhoneSeq, 1)
	b := make([]byte, n)
	for i := range b {
		b[i] = byte('0' + (seq+int64(i))%10)
	}
	return string(b)
}
