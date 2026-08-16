// admin_contact_view_test.go — who actually receives a raw phone number (H10).
//
// # WHAT THESE PIN
//
// The `sensitive_data` permission existed since §24 and governed exactly one
// endpoint. The verification pass reproduced the gap live: as a `supervisor`,
// GET /api/admin/detail/users/1 answered `phone = ••••31` while
// GET /api/admin/users answered `9647500000903`. Same person, same session, two
// answers — because only the detail view had a way to ask the question.
//
// So these tests assert on the WIRE, through the real request chain, at four
// boundaries that each fail differently:
//
//  1. a supervisor (holds the module, not the permission) → masked
//  2. an admin (holds it by default)                      → raw
//  3. a supervisor GRANTED it in the matrix               → raw
//  4. an admin DENIED it for their user alone (Note 31)   → masked
//
// (4) is the one that would silently be wrong if this used the tier-only
// lookup: GET /api/admin/permissions/me — which the dashboard asks about
// itself — resolves per user, so a tier-only server answer would hide the
// column on screen while still sending the number in the JSON behind it.
//
// And the other direction, which is just as easy to get wrong: the
// ORGANISATION'S OWN published numbers must NOT be masked. A partner's office
// line is served to the public, unauthenticated, at GET /api/partners; hiding
// it from an employee protects nobody and breaks the screen.
//
//	createdb godonation_h10
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test ./internal/handlers/ -run ContactRedaction -v
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
	"github.com/karam-flutter/humanitarian-backend/internal/staffchat"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ─── Harness ────────────────────────────────────────────────────────────

// getAsStaff replays a GET as `actorID` through the real chain: the staff gate,
// the route's own permission (when it has one), then the handler.
//
// `module` may be "" for the routes that carry NO perm() gate at all — the
// staff directory and the profile-changes queue. Those are wired here exactly
// as main.go wires them, because "an employee can reach this at all" is part of
// what makes the redaction the only control on them.
func getAsStaff(t *testing.T, pool *pgxpool.Pool, actorID int64,
	module, routePattern, requestPath string, handler gin.HandlerFunc) (int, map[string]any) {
	t.Helper()

	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	chain := []gin.HandlerFunc{auth.RequireAdmin(tokenStore)}
	if module != "" {
		chain = append(chain, auth.RequirePermission(permissions.New(pool), module, "view"))
	}
	chain = append(chain, handler)
	r.GET(routePattern, chain...)

	req := httptest.NewRequest(http.MethodGet, requestPath, nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode %s: %v (body: %s)", requestPath, err, rec.Body.String())
	}
	return rec.Code, decoded
}

// grantSensitive sets the tier-wide `sensitive_data` override, cleaning up
// after itself so one subtest cannot decide another's result.
func grantSensitive(t *testing.T, pool *pgxpool.Pool, tier string, allowed bool) {
	t.Helper()
	store := permissions.New(pool)
	if err := store.SetOverride(context.Background(), tier, sensitive.Module, permissions.ActionView, allowed); err != nil {
		t.Fatalf("set %s sensitive_data override: %v", tier, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions WHERE tier=$1 AND module=$2 AND user_id IS NULL`,
			tier, sensitive.Module)
	})
}

// denySensitiveForUser sets Note 31's per-EMPLOYEE override.
func denySensitiveForUser(t *testing.T, pool *pgxpool.Pool, userID int64, tier string) {
	t.Helper()
	store := permissions.New(pool)
	if err := store.SetUserOverride(context.Background(), userID, permissions.TierFrom(tier),
		sensitive.Module, permissions.ActionView, false); err != nil {
		t.Fatalf("set per-user sensitive_data override: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions WHERE user_id=$1 AND module=$2`, userID, sensitive.Module)
	})
}

// findUserRow digs the target's row out of the users list response.
func findUserRow(t *testing.T, body map[string]any, userID int64) map[string]any {
	t.Helper()
	data, _ := body["data"].([]any)
	for _, raw := range data {
		row, _ := raw.(map[string]any)
		if row == nil {
			continue
		}
		if id, ok := row["user_id"].(float64); ok && int64(id) == userID {
			return row
		}
	}
	t.Fatalf("user %d not in the response (body: %v)", userID, body)
	return nil
}

// insertPartner creates one partner — an ORGANISATION, whose office line is
// published to the public and must survive the redaction untouched.
func insertPartner(t *testing.T, pool *pgxpool.Pool, phone, email string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO partners (name, contact_phone, email, status)
		 VALUES ('H10 fixture partner', $1, $2, 'active') RETURNING id`, phone, email).Scan(&id)
	if err != nil {
		t.Fatalf("insert partner: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM partners WHERE id = $1`, id)
	})
	return id
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestContactRedactionOnUsersList is the endpoint the verification pass
// reproduced the leak on, at all four permission positions.
func TestContactRedactionOnUsersList(t *testing.T) {
	pool := newAuthTestPool(t)

	usersRoute := func(t *testing.T, actorID, targetID int64) map[string]any {
		t.Helper()
		h := &UsersAdminHandler{Users: users.NewStore(pool), Perms: permissions.New(pool)}
		status, body := getAsStaff(t, pool, actorID, "users", "/api/admin/users",
			"/api/admin/users?per_page=200", h.List)
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		return findUserRow(t, body, targetID)
	}

	t.Run("a supervisor gets the mask", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")

		row := usersRoute(t, actor.id, target.id)
		got, _ := row["phone"].(string)

		if got == target.phone {
			t.Fatalf("phone came back RAW (%q) to a supervisor — H10 is not enforced on this endpoint", got)
		}
		if want := sensitive.Mask(target.phone); got != want {
			t.Errorf("phone = %q, want %q", got, want)
		}
	})

	t.Run("an admin gets the real number", func(t *testing.T) {
		// The permission defaults to admins only. If this failed, H10 would
		// have taken the phone column away from the people who need it.
		actor := insertAccount(t, pool, "admin", "")
		target := insertAccount(t, pool, "user", "")

		row := usersRoute(t, actor.id, target.id)
		if got, _ := row["phone"].(string); got != target.phone {
			t.Errorf("phone = %q, want the real %q — an admin was locked out of their own tool", got, target.phone)
		}
	})

	t.Run("granting the permission to supervisors turns it back on", func(t *testing.T) {
		// This is the whole client ask: a Super-Admin decides, from الصلاحيات,
		// who may see contact data. If the grant does not reach the wire, the
		// checkbox is decoration.
		grantSensitive(t, pool, string(permissions.TierSupervisor), true)
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")

		row := usersRoute(t, actor.id, target.id)
		if got, _ := row["phone"].(string); got != target.phone {
			t.Errorf("phone = %q, want the real %q — the granted permission did not take effect", got, target.phone)
		}
	})

	t.Run("denying one named admin masks only them", func(t *testing.T) {
		// Note 31's per-employee override. A tier-only lookup would pass this
		// person through — and the dashboard, which asks
		// GET /api/admin/permissions/me (per user), would hide the column while
		// the real number kept arriving in the JSON behind it.
		denied := insertAccount(t, pool, "admin", "")
		denySensitiveForUser(t, pool, denied.id, "admin")
		unaffected := insertAccount(t, pool, "admin", "")
		target := insertAccount(t, pool, "user", "")

		row := usersRoute(t, denied.id, target.id)
		if got, _ := row["phone"].(string); got != sensitive.Mask(target.phone) {
			t.Errorf("phone = %q, want the mask — the per-employee denial was ignored", got)
		}

		row = usersRoute(t, unaffected.id, target.id)
		if got, _ := row["phone"].(string); got != target.phone {
			t.Errorf("phone = %q, want the real %q — one person's denial leaked onto their whole tier", got, target.phone)
		}
	})
}

// TestContactRedactionOnUngatedRoutes covers the two routes that carry no
// perm() gate at all (main.go: staff chat is open to every dashboard tier by
// design, and so is the profile-change queue). On those, `sensitive_data` is
// not one control among several — it is the only one.
func TestContactRedactionOnUngatedRoutes(t *testing.T) {
	pool := newAuthTestPool(t)

	t.Run("the staff directory masks colleagues' sign-in numbers", func(t *testing.T) {
		actor := insertAccount(t, pool, "employee", "")
		colleague := insertAccount(t, pool, "supervisor", "")

		h := &StaffChatHandler{Store: staffchat.New(pool), Perms: permissions.New(pool)}
		status, body := getAsStaff(t, pool, actor.id, "", "/api/admin/staff-directory",
			"/api/admin/staff-directory", h.Directory)
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}

		items, _ := body["items"].([]any)
		found := false
		for _, raw := range items {
			row, _ := raw.(map[string]any)
			if row == nil {
				continue
			}
			id, _ := row["user_id"].(float64)
			if int64(id) != colleague.id {
				continue
			}
			found = true
			got, _ := row["phone"].(string)
			if got == colleague.phone {
				t.Fatalf("a colleague's sign-in number came back RAW (%q) on an ungated route", got)
			}
			if want := sensitive.Mask(colleague.phone); got != want {
				t.Errorf("phone = %q, want %q", got, want)
			}
		}
		if !found {
			t.Fatal("the colleague was not in the directory at all — the fixture is wrong, not the code")
		}
	})
}

// TestOrganisationContactSurvivesRedaction is the other half of the change, and
// the reason this is per-endpoint rather than one middleware over /api/admin.
//
// A partner's office line and a City Guide place's number are the charity's own
// published contact details — GET /api/partners serves them to anyone, with no
// token at all. A blanket rule would have hidden them from staff, which is not
// privacy, only a broken screen.
func TestOrganisationContactSurvivesRedaction(t *testing.T) {
	pool := newAuthTestPool(t)

	const orgPhone, orgEmail = "9647701112233", "office@partner.example"
	partnerID := insertPartner(t, pool, orgPhone, orgEmail)
	actor := insertAccount(t, pool, "employee", "") // no sensitive_data

	h := NewAdminDetailHandler(pool, permissions.New(pool))
	status, body := getAsStaff(t, pool, actor.id, "", "/api/admin/detail/:resource/:id",
		"/api/admin/detail/partners/"+strconv.FormatInt(partnerID, 10), h.Detail)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %v)", status, body)
	}

	item, _ := body["item"].(map[string]any)
	if item == nil {
		t.Fatalf("no item in the response: %v", body)
	}
	if got, _ := item["contact_phone"].(string); got != orgPhone {
		t.Errorf("contact_phone = %q, want the real %q — the organisation's own published number was hidden from its own staff", got, orgPhone)
	}
	if got, _ := item["email"].(string); got != orgEmail {
		t.Errorf("email = %q, want the real %q", got, orgEmail)
	}
}

// TestContactRedactionOnDetailView keeps the one endpoint that already had this
// behaviour honest, now that it shares the implementation with the other twenty.
func TestContactRedactionOnDetailView(t *testing.T) {
	pool := newAuthTestPool(t)

	actor := insertAccount(t, pool, "supervisor", "")
	target := insertAccount(t, pool, "user", "")

	h := NewAdminDetailHandler(pool, permissions.New(pool))
	status, body := getAsStaff(t, pool, actor.id, "", "/api/admin/detail/:resource/:id",
		"/api/admin/detail/users/"+strconv.FormatInt(target.id, 10), h.Detail)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %v)", status, body)
	}

	item, _ := body["item"].(map[string]any)
	got, _ := item["phone"].(string)
	if got == target.phone {
		t.Fatalf("the detail view stopped masking: %q", got)
	}
	if want := sensitive.Mask(target.phone); got != want {
		t.Errorf("phone = %q, want %q", got, want)
	}
	// B7 — the allow-list must still be doing its job alongside the mask.
	if _, leaked := item["password_hash"]; leaked {
		t.Error("password_hash is back in the detail payload")
	}
}

// TestTrashPayloadIsRedacted — the trash re-serves whole deleted rows, so a
// deleted user row would otherwise hand back the exact number the users list
// redacts, to anyone holding `trash view`.
func TestTrashPayloadIsRedacted(t *testing.T) {
	pool := newAuthTestPool(t)

	target := insertAccount(t, pool, "user", "")
	actor := insertAccount(t, pool, "supervisor", "")

	// Snapshot the row the way trashRow does, then park it in the trash.
	var trashID int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO trash_items (source_table, row_id, payload, deleted_by)
		 SELECT 'users', u.id, to_jsonb(u.*), $2 FROM users u WHERE u.id = $1
		 RETURNING id`, target.id, actor.id).Scan(&trashID)
	if err != nil {
		t.Fatalf("insert trash item: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM trash_items WHERE id = $1`, trashID)
	})

	h := &AdminTrashHandler{Pool: pool, Perms: permissions.New(pool)}
	status, body := getAsStaff(t, pool, actor.id, "trash", "/api/admin/trash", "/api/admin/trash", h.List)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %v)", status, body)
	}

	items, _ := body["items"].([]any)
	found := false
	for _, raw := range items {
		row, _ := raw.(map[string]any)
		if row == nil {
			continue
		}
		if id, _ := row["id"].(float64); int64(id) != trashID {
			continue
		}
		found = true
		payload, _ := row["payload"].(map[string]any)
		if payload == nil {
			t.Fatalf("no payload on the trash row: %v", row)
		}
		got, _ := payload["phone"].(string)
		if got == target.phone {
			t.Fatalf("the deleted account's real phone came back in the trash payload (%q)", got)
		}
		if want := sensitive.Mask(target.phone); got != want {
			t.Errorf("payload.phone = %q, want %q", got, want)
		}
	}
	if !found {
		t.Fatal("the trash row was not in the response — the fixture is wrong, not the code")
	}

	// The snapshot in the DATABASE must be untouched, or restore would put a
	// redaction back into `users.phone` — the write-guard failure H10's first
	// commit exists to prevent, arriving by a different door.
	var stored string
	if err := pool.QueryRow(context.Background(),
		`SELECT payload->>'phone' FROM trash_items WHERE id = $1`, trashID).Scan(&stored); err != nil {
		t.Fatalf("read stored payload: %v", err)
	}
	if stored != target.phone {
		t.Fatalf("THE STORED SNAPSHOT WAS REWRITTEN: %q — restoring this row would destroy the sign-in number", stored)
	}
	if strings.ContainsRune(stored, '•') {
		t.Fatal("the stored snapshot carries a redaction mark")
	}
}
