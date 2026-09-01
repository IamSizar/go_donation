// field_rule_patch_route_test.go — owner #15, end to end.
//
// field_rule_enforcement_test.go proves the LOGIC of the required/hidden
// check. This proves it is actually WIRED into the route the dashboard posts
// to, which is a separate claim and historically the one that goes wrong: a
// guard that is written and never called looks exactly like a guard that
// works.
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_fr?sslmode=disable' \
//	  go test ./internal/handlers/ -run FieldRuleRejectionReaches -v
package handlers

import (
	"context"
	"net/http"
	"testing"
)

// TestFieldRuleRejectionReachesTheRealPatchRoute drives PATCH
// /api/admin/users/:id the way the Edit modal does — real session, real
// target account, real role — and asserts the refusal is a friendly envelope
// naming the field, not a bare 400, and that the row is left untouched.
func TestFieldRuleRejectionReachesTheRealPatchRoute(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	setRuleState(t, ctx, "volunteer_tribe_clan", "required")

	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	// insertAccount creates role_id 1 (a Grantor). This account is the
	// Volunteer whose namespace the rule above belongs to.
	if _, err := pool.Exec(ctx, `UPDATE users SET role_id = 3 WHERE id = $1`, target.id); err != nil {
		t.Fatalf("set role: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture, tribe_clan)
		 VALUES ($1, 'Ali', 'male', 'Erbil', '', 'Barzani')`, target.id); err != nil {
		t.Fatalf("seed profile: %v", err)
	}

	status, resp := patchUserAs(t, pool, actor.id, target.id, map[string]any{"tribe_clan": ""})
	t.Logf("PATCH /api/admin/users/%d {\"tribe_clan\":\"\"} -> %d %v", target.id, status, resp)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 - a required field was cleared", status)
	}
	if resp["code"] != "field_required_by_rule" || resp["field"] != "tribe_clan" {
		t.Errorf("envelope = %v, want it to name the field and the reason", resp)
	}
	if msg, _ := resp["error"].(string); msg == "" {
		t.Error("no user-facing message - a 400 with no message is the bug this replaces")
	}

	// A refusal must never leave a half-applied edit.
	var tribe string
	if err := pool.QueryRow(ctx,
		`SELECT tribe_clan FROM user_profiles WHERE user_id = $1`, target.id).Scan(&tribe); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if tribe != "Barzani" {
		t.Errorf("tribe_clan = %q - the refused edit was applied anyway", tribe)
	}
}

// TestFieldRuleLeavesUngovernedAccountsAlone — the same PATCH against a
// GRANTOR must still succeed, because `volunteer_tribe_clan` is a Volunteer's
// rule and namespaces do not leak. Without this, "enforcement" would read as
// "the dashboard stopped working".
func TestFieldRuleLeavesUngovernedAccountsAlone(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	setRuleState(t, ctx, "volunteer_tribe_clan", "required")

	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "") // role_id 1, a Grantor
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture, tribe_clan)
		 VALUES ($1, 'Sara', 'female', 'Erbil', '', 'Barzani')`, target.id); err != nil {
		t.Fatalf("seed profile: %v", err)
	}

	status, resp := patchUserAs(t, pool, actor.id, target.id, map[string]any{"tribe_clan": ""})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 - a volunteer rule blocked a grantor edit (body: %v)", status, resp)
	}
}
