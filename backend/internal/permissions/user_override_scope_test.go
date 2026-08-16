// user_override_scope_test.go — a per-EMPLOYEE permission must stay on that
// employee.
//
// # WHAT THIS FOUND
//
// Note 31 added per-user overrides: a Super-Admin can grant or deny one named
// staff member a permission without moving their whole tier. Two queries
// resolve them, and only one of the two knew about the distinction:
//
//	AllowedForUser  … WHERE user_id=$1 AND module=$2 AND action=$3   ✔
//	Allowed         … WHERE tier=$1    AND module=$2 AND action=$3   ✘
//
// `role_permissions` stores both kinds of row in the same table — a tier-wide
// override has user_id NULL, a per-user override has user_id set AND carries
// the person's tier for the audit trail (SetUserOverride's own comment says the
// tier is stored "for the audit trail only; resolution never reads it back").
// Resolution DID read it back: Allowed matched on tier alone, so a per-user row
// was indistinguishable from a tier-wide one.
//
// Both directions are wrong, and the second is a privilege escalation:
//
//   - deny ONE employee → every colleague on their tier loses it too;
//   - grant ONE employee → every colleague on their tier GAINS it.
//
// The grant direction is the dangerous one. `RequirePermission` — the gate on
// every admin route — calls Allowed, not AllowedForUser, so giving one
// supervisor `users delete` handed it to all of them.
//
// This surfaced while wiring H10, whose redaction resolves `sensitive_data` per
// user precisely so it agrees with GET /api/admin/permissions/me. It is a
// separate defect with a separate fix, tested separately.
//
//	createdb godonation_h10
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test ./internal/permissions/ -run UserOverrideScope -v
package permissions

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// newPermTestPool connects to the throwaway database named by
// TEST_DATABASE_URL. Skips when unset, so a bare checkout stays green — the
// same convention every other integration test in this repo uses.
//
// It does NOT run migrations: role_permissions has existed since the Phase 6
// schema, and the handler-package tests that share this database bring it up to
// date. Skipping keeps this package's suite fast.
func newPermTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping permission-scope integration test")
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seedUser inserts a throwaway staff row to hang a per-user override on. The
// override table has an FK to users on some deployments, and a real id keeps
// the test honest either way.
func seedUser(t *testing.T, pool *pgxpool.Pool, tier string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier,
		                    registration_status, account_status)
		 VALUES ('964770' || (random()*9999999)::bigint, 1, 1, 0, $1, 'approved', 'active')
		 RETURNING id`, tier).Scan(&id)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM role_permissions WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// TestUserOverrideScopeDoesNotLeakToTier is the regression test. The module is
// deliberately `sensitive_data`, whose default is admins-only, so both
// directions are observable on one tier: a supervisor starts denied, an admin
// starts allowed.
func TestUserOverrideScopeDoesNotLeakToTier(t *testing.T) {
	pool := newPermTestPool(t)
	store := New(pool)
	ctx := context.Background()

	t.Run("granting one supervisor does not grant every supervisor", func(t *testing.T) {
		lucky := seedUser(t, pool, string(TierSupervisor))
		colleague := seedUser(t, pool, string(TierSupervisor))

		if err := store.SetUserOverride(ctx, lucky, TierSupervisor, "sensitive_data", ActionView, true); err != nil {
			t.Fatalf("set per-user override: %v", err)
		}

		// The person it was granted to.
		got, err := store.AllowedForUser(ctx, lucky, TierSupervisor, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("AllowedForUser(lucky): %v", err)
		}
		if !got {
			t.Error("the override did not reach the person it was set for")
		}

		// Everybody else on that tier. This is the escalation.
		got, err = store.AllowedForUser(ctx, colleague, TierSupervisor, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("AllowedForUser(colleague): %v", err)
		}
		if got {
			t.Error("a colleague inherited a permission granted to ONE person — per-user overrides are leaking tier-wide")
		}

		// And the tier-wide question itself, which is what RequirePermission
		// asks on every admin route.
		got, err = store.Allowed(ctx, TierSupervisor, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("Allowed(supervisor): %v", err)
		}
		if got {
			t.Error("Allowed() read a per-user row as a tier-wide override — every route gate now grants it")
		}
	})

	t.Run("denying one admin does not deny every admin", func(t *testing.T) {
		singledOut := seedUser(t, pool, string(TierAdmin))
		colleague := seedUser(t, pool, string(TierAdmin))

		if err := store.SetUserOverride(ctx, singledOut, TierAdmin, "sensitive_data", ActionView, false); err != nil {
			t.Fatalf("set per-user override: %v", err)
		}

		got, err := store.AllowedForUser(ctx, singledOut, TierAdmin, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("AllowedForUser(singledOut): %v", err)
		}
		if got {
			t.Error("the denial did not reach the person it was set for")
		}

		got, err = store.AllowedForUser(ctx, colleague, TierAdmin, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("AllowedForUser(colleague): %v", err)
		}
		if !got {
			t.Error("a colleague lost a permission denied to ONE person — per-user overrides are leaking tier-wide")
		}
	})

	t.Run("a tier-wide override still works", func(t *testing.T) {
		// The other half: narrowing the query must not stop the الصلاحيات
		// matrix from working, which is the ONLY way most permissions are set.
		if err := store.SetOverride(ctx, string(TierEmployee), "sensitive_data", ActionView, true); err != nil {
			t.Fatalf("set tier override: %v", err)
		}
		t.Cleanup(func() {
			_, _ = pool.Exec(ctx,
				`DELETE FROM role_permissions WHERE tier=$1 AND module='sensitive_data' AND user_id IS NULL`,
				string(TierEmployee))
		})

		got, err := store.Allowed(ctx, TierEmployee, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("Allowed(employee): %v", err)
		}
		if !got {
			t.Error("a tier-wide grant stopped taking effect")
		}

		anyone := seedUser(t, pool, string(TierEmployee))
		got, err = store.AllowedForUser(ctx, anyone, TierEmployee, "sensitive_data", ActionView)
		if err != nil {
			t.Fatalf("AllowedForUser(anyone): %v", err)
		}
		if !got {
			t.Error("an employee with no personal override stopped inheriting their tier's grant")
		}
	})

	t.Run("the matrix does not draw a per-employee override as a tier one", func(t *testing.T) {
		// ListOverrides feeds the الصلاحيات screen. Now that enforcement
		// distinguishes the two kinds of row, a display that still conflates
		// them would show a Super-Admin a tick the server does not honour —
		// worse than the original bug, because nobody would go looking.
		person := seedUser(t, pool, string(TierSupervisor))
		if err := store.SetUserOverride(ctx, person, TierSupervisor, "reports", ActionExport, true); err != nil {
			t.Fatalf("set per-user override: %v", err)
		}

		rows, err := store.ListOverrides(ctx)
		if err != nil {
			t.Fatalf("ListOverrides: %v", err)
		}
		for _, o := range rows {
			if o.Tier == string(TierSupervisor) && o.Module == "reports" && o.Action == ActionExport {
				t.Fatal("a per-employee override is being drawn as a tier-wide cell on the permissions matrix")
			}
		}
	})
}
