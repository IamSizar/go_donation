// L20 — "every field's Required/Optional flag is admin-controllable".
//
// THE SHAPE OF THE BUG
// A field is controllable only if it has a row in registration_field_rules.
// SetState is a pure UPDATE (field_rules.go: `UPDATE registration_field_rules
// SET state = $2 WHERE field_key = $1`), and when it matches nothing the route
// answers 400 "Unknown field." — there is no INSERT anywhere in the codebase,
// so a missing row cannot be created through any API. A field with no seeded
// row is therefore permanently frozen: it can never be made required and never
// be hidden, whatever the admin picks on قواعد الحقول.
//
// `recipient_governorate` was exactly that. The app validates it for role 2
// (humanitarian registration_form.dart:363, reading the same _governorate value
// the grantor's field uses) and every sibling in the family was seeded —
// grantor_, volunteer_, marriage_, case_ — but the recipient's was not. So a
// grantor could be forced to give a governorate and an eligible recipient could
// not, with no way to change that from the dashboard.
//
// This test pins the family as a whole rather than the single key, because the
// defect was an asymmetry that a per-key test would not have caught: the same
// omission can recur the next time a role's form is seeded.
//
// Needs a throwaway Postgres and is skipped unless TEST_DATABASE_URL is set, so
// `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_l20          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_l20?sslmode=disable' \
//	  go test ./internal/handlers/ -run FieldRule -v
package handlers

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newFieldRulesTestPool brings a throwaway database up to date with the real
// migrations — the seeds ARE the thing under test, so a fixture schema would
// defeat the purpose.
func newFieldRulesTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping field-rules coverage test")
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

// TestFieldRuleGovernorateFamilyIsFullySeeded is the L20 regression test: every
// registration form that collects a governorate must have that field
// controllable, not just four of the five.
func TestFieldRuleGovernorateFamilyIsFullySeeded(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()

	for _, key := range []string{
		"grantor_governorate",
		"recipient_governorate", // the one that was missing
		"volunteer_governorate",
		"marriage_governorate",
		"case_governorate",
	} {
		var exists bool
		if err := pool.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM registration_field_rules WHERE field_key = $1)`,
			key,
		).Scan(&exists); err != nil {
			t.Fatalf("lookup %s: %v", key, err)
		}
		if !exists {
			t.Errorf("%s has no registration_field_rules row, so SetState would answer "+
				`"Unknown field." and an admin could never make it required or hidden`, key)
		}
	}
}

// TestFieldRuleSetStateReachesRecipientGovernorate drives the exact statement
// the SetState route runs, because "the row exists" and "the route can change
// it" are different claims and only the second one is the feature. The handler
// reads ct.RowsAffected() == 0 as "Unknown field.", so one affected row is
// precisely what makes the dashboard control work.
func TestFieldRuleSetStateReachesRecipientGovernorate(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()

	// Restore whatever the seed set, so this test leaves the table as found.
	var original string
	if err := pool.QueryRow(ctx,
		`SELECT state FROM registration_field_rules WHERE field_key = 'recipient_governorate'`,
	).Scan(&original); err != nil {
		t.Fatalf("recipient_governorate is not seeded at all: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`UPDATE registration_field_rules SET state = $1 WHERE field_key = 'recipient_governorate'`,
			original)
	})

	for _, state := range []string{"required", "hidden", "optional"} {
		ct, err := pool.Exec(ctx,
			`UPDATE registration_field_rules SET state = $2 WHERE field_key = $1`,
			"recipient_governorate", state)
		if err != nil {
			t.Fatalf("set state %q: %v", state, err)
		}
		if ct.RowsAffected() != 1 {
			t.Fatalf("setting recipient_governorate to %q affected %d rows; the route reads 0 as "+
				`"Unknown field." and refuses the change`, state, ct.RowsAffected())
		}
	}
}
