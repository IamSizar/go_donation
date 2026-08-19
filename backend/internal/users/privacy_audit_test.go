package users

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// Pins that changes to the two fields controlling what OTHER people can see
// leave an audit trail.
//
// WHY THESE TWO SPECIFICALLY
// user_profile_audit_logs already covered full_name, gender and
// profile_picture, and had zero rows for field_privacy and display_name_mode —
// which are the fields where a silent, wrong change is least likely to be
// noticed, because nothing about the victim's own screen changes. When a
// fail-open bug raised "did this already happen to anyone?", the trail could
// not answer: current state shows that nothing is wrong NOW, never that
// nothing was ever wiped.
//
// These tests need a real database. They skip without TEST_DATABASE_URL, and
// ./scripts/test-with-db.sh supplies one.

func auditTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL (or use ./scripts/test-with-db.sh)")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	// The package's other integration tests migrate the throwaway database
	// themselves; this one follows the same pattern rather than assuming a
	// schema someone else created.
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seedProfile makes a user with a profile row and returns its id.
func seedProfile(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active)
		 VALUES ('9647' || (random()*1e8)::bigint, 1, 1)
		 RETURNING id`).Scan(&id)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	// full_name/gender/address are NOT NULL with no default in 001.
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address)
		 VALUES ($1, 'test', '', '')`, id); err != nil {
		t.Fatalf("seed profile: %v", err)
	}
	t.Cleanup(func() {
		pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func auditRows(t *testing.T, pool *pgxpool.Pool, userID int64, field string) [][2]string {
	t.Helper()
	rows, err := pool.Query(context.Background(),
		`SELECT COALESCE(old_value,''), COALESCE(new_value,'')
		   FROM user_profile_audit_logs
		  WHERE user_id = $1 AND changed_field = $2
		  ORDER BY id`, userID, field)
	if err != nil {
		t.Fatalf("query audit: %v", err)
	}
	defer rows.Close()
	var out [][2]string
	for rows.Next() {
		var o, n string
		if err := rows.Scan(&o, &n); err != nil {
			t.Fatal(err)
		}
		out = append(out, [2]string{o, n})
	}
	return out
}

func TestFieldPrivacyChangeIsAudited(t *testing.T) {
	pool := auditTestPool(t)
	store := &Store{Pool: pool}
	ctx := context.Background()
	userID := seedProfile(t, pool)

	if err := store.SetFieldPrivacy(ctx, userID, []string{"phone", "address"}); err != nil {
		t.Fatalf("set: %v", err)
	}
	got := auditRows(t, pool, userID, "field_privacy")
	if len(got) != 1 {
		t.Fatalf("want 1 audit row, got %d (%v)", len(got), got)
	}
	// Sorted, so the row reads the same however the client ordered the keys.
	if got[0][1] != "address,phone" {
		t.Errorf("new_value = %q, want %q", got[0][1], "address,phone")
	}
}

func TestReorderingTheSameKeysIsNotAChange(t *testing.T) {
	// A spurious audit row is worse than none: it teaches whoever reads the
	// log to distrust it.
	pool := auditTestPool(t)
	store := &Store{Pool: pool}
	ctx := context.Background()
	userID := seedProfile(t, pool)

	if err := store.SetFieldPrivacy(ctx, userID, []string{"phone", "address"}); err != nil {
		t.Fatal(err)
	}
	if err := store.SetFieldPrivacy(ctx, userID, []string{"address", "phone"}); err != nil {
		t.Fatal(err)
	}
	if got := auditRows(t, pool, userID, "field_privacy"); len(got) != 1 {
		t.Errorf("want 1 row (the reorder is not a change), got %d: %v", len(got), got)
	}
}

func TestClearingPrivacyIsAudited(t *testing.T) {
	// The case the ticket was really about: a wipe must be visible afterwards.
	pool := auditTestPool(t)
	store := &Store{Pool: pool}
	ctx := context.Background()
	userID := seedProfile(t, pool)

	if err := store.SetFieldPrivacy(ctx, userID, []string{"phone"}); err != nil {
		t.Fatal(err)
	}
	if err := store.SetFieldPrivacy(ctx, userID, nil); err != nil {
		t.Fatal(err)
	}
	got := auditRows(t, pool, userID, "field_privacy")
	if len(got) != 2 {
		t.Fatalf("want 2 rows, got %d: %v", len(got), got)
	}
	if got[1][0] != "phone" || got[1][1] != "" {
		t.Errorf("the wipe reads %q -> %q, want \"phone\" -> \"\"", got[1][0], got[1][1])
	}
}

func TestDisplayNameModeAndAliasAreAudited(t *testing.T) {
	pool := auditTestPool(t)
	store := &Store{Pool: pool}
	ctx := context.Background()
	userID := seedProfile(t, pool)

	if err := store.SetPrivacyExtras(ctx, userID, PrivacyExtras{
		DisplayNameMode: "alias", AliasName: "أبو محمد",
	}); err != nil {
		t.Fatalf("set: %v", err)
	}
	if got := auditRows(t, pool, userID, "display_name_mode"); len(got) != 1 || got[0][1] != "alias" {
		t.Errorf("display_name_mode rows = %v, want one ending in \"alias\"", got)
	}
	if got := auditRows(t, pool, userID, "alias_name"); len(got) != 1 || got[0][1] != "أبو محمد" {
		t.Errorf("alias_name rows = %v, want one ending in the alias", got)
	}

	// A cleared alias is otherwise indistinguishable from one never set.
	if err := store.SetPrivacyExtras(ctx, userID, PrivacyExtras{
		DisplayNameMode: "real",
	}); err != nil {
		t.Fatal(err)
	}
	got := auditRows(t, pool, userID, "alias_name")
	if len(got) != 2 || got[1][0] != "أبو محمد" || got[1][1] != "" {
		t.Errorf("the clear reads %v, want a second row from the alias to empty", got)
	}
}
