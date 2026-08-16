// admin_trash_credentials_test.go — what سلة المهملات may hand back (B7).
//
// # WHY THIS FILE EXISTS
//
// B7 took `users.password_hash` off the عرض page by inverting the mechanism:
// each resource declares the columns it may emit, so a credential column is
// invisible unless someone deliberately lists it (admin_detail.go).
//
// The Trash walked straight around that. A deleted row is stored as
// `to_jsonb(row.*)` — the WHOLE row — and GET /api/admin/trash re-served that
// snapshot verbatim as `items[].payload`. For `source_table = 'users'` the
// snapshot carries the two columns the detail view withholds by name:
//
//	password_hash — the bcrypt credential the account signs in with
//	google_sub    — the identifier the Google sign-in path matches on
//
// The route is gated on perm("trash","view"), and `view` is allowed by default
// for every staff tier down to `employee` (permissions.defaultAllowed), so the
// same hash B7 refused to show on the عرض page arrived on the Trash page one
// click away — for a person the matrix never granted `sensitive_data` either.
//
// # THE TRAP, WHICH IS WHY THE SECOND HALF OF THIS FILE EXISTS
//
// The obvious fix — drop the column when the snapshot is WRITTEN — would be
// worse than the leak. POST /admin/trash/:id/restore rebuilds the row out of
// that snapshot (`jsonb_populate_record`), so a payload without `password_hash`
// restores an account whose password is silently blank: nobody could sign in,
// and nothing on screen would say why. The stored snapshot must stay complete
// and the withholding must happen on DISPLAY — which is what
// TestTrashRestoreKeepsTheCredentialIntact pins, in the same file as the leak,
// because a fix that protects the preview by breaking استعادة is a worse bug
// than the one it fixes.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_h10
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test ./internal/handlers/ -run Trash -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Harness ────────────────────────────────────────────────────────────

// storedCredential is what a deleted account's snapshot has to be able to give
// back: the exact bcrypt hash and the exact OAuth subject it was deleted with.
type storedCredential struct {
	passwordHash string
	googleSub    string
}

// readCredential reads the two withheld columns straight from `users`, so a
// later assertion can compare against the real value rather than a re-hash
// (bcrypt salts every call, so two hashes of one password never match).
//
// It does NOT judge what it finds. An empty hash means one thing before the
// delete (a broken fixture) and something far worse after the restore (an
// account nobody can sign in to), and each caller says so in its own words.
func readCredential(t *testing.T, pool *pgxpool.Pool, userID int64) storedCredential {
	t.Helper()
	var got storedCredential
	if err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(password_hash, ''), COALESCE(google_sub, '')
		   FROM users WHERE id = $1`, userID).Scan(&got.passwordHash, &got.googleSub); err != nil {
		t.Fatalf("read credential of user %d: %v", userID, err)
	}
	return got
}

// credentialFixture gives an account a real bcrypt hash and google_sub, then
// hands back the stored values — refusing to continue if the fixture did not
// take, because "no credential leaked" proves nothing about an account that
// never had one.
func credentialFixture(t *testing.T, pool *pgxpool.Pool, userID int64) storedCredential {
	t.Helper()
	givePassword(t, pool, userID)
	got := readCredential(t, pool, userID)
	if got.passwordHash == "" || got.googleSub == "" {
		t.Fatalf("fixture user %d has no credential to leak — the test would prove nothing", userID)
	}
	return got
}

// trashUserAccount deletes an account through the REAL delete handler (the path
// production takes) and returns the trash entry it produced.
func trashUserAccount(t *testing.T, pool *pgxpool.Pool, userID int64) int64 {
	t.Helper()
	if status, body := callDelete(t, NewAdminDeleteHandler(pool).User, userID); status != http.StatusOK {
		t.Fatalf("delete user %d: status = %d (body: %s)", userID, status, body)
	}
	var trashID int64
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM trash_items
		  WHERE source_table = 'users' AND row_id = $1 AND restored_at IS NULL`,
		userID).Scan(&trashID); err != nil {
		t.Fatalf("locate the trash entry for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM trash_items WHERE id = $1`, trashID)
	})
	return trashID
}

// trashItemAs replays GET /api/admin/trash as `actorID` through the real chain
// — RequireAdmin, then perm("trash","view"), then the handler — and returns the
// one entry's `payload` object alongside the WHOLE response body as text.
//
// The text matters as much as the object: a credential that moved to another
// key, or rode along inside a nested value, would still be a leak, and a
// key-by-key assertion would miss it.
func trashItemAs(t *testing.T, pool *pgxpool.Pool, actorID, trashID int64) (map[string]any, string) {
	t.Helper()
	status, body := getAsStaff(t, pool, actorID, "trash", "/api/admin/trash", "/api/admin/trash",
		(&AdminTrashHandler{Pool: pool, Perms: permissions.New(pool)}).List)
	if status != http.StatusOK {
		t.Fatalf("GET /api/admin/trash: status = %d (body: %v)", status, body)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("re-encode the trash response: %v", err)
	}

	items, _ := body["items"].([]any)
	for _, entry := range items {
		row, _ := entry.(map[string]any)
		if row == nil {
			continue
		}
		if id, _ := row["id"].(float64); int64(id) != trashID {
			continue
		}
		payload, ok := row["payload"].(map[string]any)
		if !ok {
			t.Fatalf("trash entry %d has no payload object: %v", trashID, row)
		}
		return payload, string(raw)
	}
	t.Fatalf("trash entry %d was not in the response — the fixture is wrong, not the code", trashID)
	return nil, ""
}

// postAsStaff replays a POST with a JSON body as `actorID`, authenticated the
// way main.go authenticates the restore route. getAsStaff covers the GETs; the
// restore half of this file needs a body and a password.
func postAsStaff(t *testing.T, pool *pgxpool.Pool, actorID int64,
	routePattern, requestPath string, reqBody any, handler gin.HandlerFunc) (int, map[string]any) {
	t.Helper()

	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}
	encoded, err := json.Marshal(reqBody)
	if err != nil {
		t.Fatalf("encode request body: %v", err)
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST(routePattern, auth.RequireAdmin(tokenStore), handler)

	req := httptest.NewRequest(http.MethodPost, requestPath, bytes.NewReader(encoded))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode %s: %v (body: %s)", requestPath, err, rec.Body.String())
	}
	return rec.Code, decoded
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestTrashPreviewWithholdsCredentials is the B7 regression test for the Trash:
// no caller, at any tier that can open the page, receives a credential column.
//
// `supervisor` is the tier named in the finding — it holds `trash view` by
// default and `sensitive_data` by no default at all — but every tier is walked,
// including super_admin: a bcrypt hash is not a thing to put in a browser,
// however trusted the person in front of it.
func TestTrashPreviewWithholdsCredentials(t *testing.T) {
	pool := newAuthTestPool(t)

	for _, tier := range []string{"super_admin", "admin", "supervisor", "employee"} {
		t.Run("a "+tier+" does not receive password_hash", func(t *testing.T) {
			target := insertAccount(t, pool, "user", "")
			credential := credentialFixture(t, pool, target.id)

			trashID := trashUserAccount(t, pool, target.id)
			actor := insertAccount(t, pool, tier, "")
			payload, wire := trashItemAs(t, pool, actor.id, trashID)

			if v, present := payload["password_hash"]; present {
				t.Errorf("password_hash reached the Trash page: %v", v)
			}
			if v, present := payload["google_sub"]; present {
				t.Errorf("google_sub (an auth identifier) reached the Trash page: %v", v)
			}
			// The value itself, wherever it might have travelled.
			if strings.Contains(wire, credential.passwordHash) {
				t.Errorf("the deleted account's bcrypt hash is somewhere in the trash response")
			}
			if strings.Contains(wire, credential.googleSub) {
				t.Errorf("the deleted account's google_sub is somewhere in the trash response")
			}
		})
	}
}

// wantTrashUserPreviewKeys is every key a deleted ACCOUNT's preview may carry:
// the three fields the Trash page uses to say which record this is (the deleted
// row's id, who deleted it and when are separate top-level fields of the entry,
// not part of the snapshot).
//
// Written out here rather than read from trashPreviewColumns on purpose — a test
// that derives its expectation from the code under test proves only that the
// code agrees with itself. This is the independent statement of what may cross
// the wire.
var wantTrashUserPreviewKeys = map[string]bool{
	"username": true, "phone": true, "email": true,
}

// TestTrashPreviewIsDenyByDefault pins the MECHANISM rather than today's two
// leaked columns. `users` alone holds 20 columns and the Trash carries 30 other
// tables; the guarantee worth having is that a column nobody listed is not sent,
// so the next migration is safe without anyone remembering this file.
func TestTrashPreviewIsDenyByDefault(t *testing.T) {
	pool := newAuthTestPool(t)

	target := insertAccount(t, pool, "user", "")
	givePassword(t, pool, target.id)
	trashID := trashUserAccount(t, pool, target.id)

	actor := insertAccount(t, pool, "super_admin", "")
	payload, _ := trashItemAs(t, pool, actor.id, trashID)

	for key := range payload {
		if !wantTrashUserPreviewKeys[key] {
			t.Errorf("column %q was emitted without being on any allow-list", key)
		}
	}
}

// TestTrashPreviewStillIdentifiesTheRecord is the other half: withholding the
// credential must not blank the preview. An operator about to press استعادة or
// حذف نهائي has to be able to tell which record they are looking at — a Trash
// full of bare row ids is the state H15 explicitly moved away from.
func TestTrashPreviewStillIdentifiesTheRecord(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	actor := insertAccount(t, pool, "super_admin", "")

	t.Run("a deleted account still shows its sign-in identity", func(t *testing.T) {
		target := insertAccount(t, pool, "user", "")
		givePassword(t, pool, target.id)
		if _, err := pool.Exec(ctx,
			`UPDATE users SET username = $1 WHERE id = $2`,
			"trash-preview-"+strconv.FormatInt(target.id, 10), target.id); err != nil {
			t.Fatalf("set username: %v", err)
		}
		trashID := trashUserAccount(t, pool, target.id)

		payload, _ := trashItemAs(t, pool, actor.id, trashID)
		if got, _ := payload["username"].(string); got == "" {
			t.Errorf("the deleted account's username is gone from the preview (payload: %v)", payload)
		}
		if got, _ := payload["phone"].(string); got != target.phone {
			t.Errorf("phone = %q, want the real %q — a super_admin holds sensitive_data", got, target.phone)
		}
	})

	t.Run("a deleted catalogue row still shows its name", func(t *testing.T) {
		// The label columns are what the Trash page reads (previewOf in
		// admin-web/src/pages/TrashPage.tsx); a catalogue row authored in four
		// languages must keep all four.
		var categoryID int64
		if err := pool.QueryRow(ctx, `INSERT INTO project_categories
			(slug, name_en, name_ar, name_ckb, name_kmr)
			VALUES ('b7-trash-test','Test','اختبار','تاقیکردنەوە','تاقیکرن') RETURNING id`).Scan(&categoryID); err != nil {
			t.Fatalf("insert project category: %v", err)
		}
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM project_categories WHERE id = $1`, categoryID)
		})

		var trashID int64
		if err := pool.QueryRow(ctx,
			`INSERT INTO trash_items (source_table, row_id, payload, deleted_by)
			 SELECT 'project_categories', c.id, to_jsonb(c.*), $2
			   FROM project_categories c WHERE c.id = $1
			 RETURNING id`, categoryID, actor.id).Scan(&trashID); err != nil {
			t.Fatalf("insert trash item: %v", err)
		}
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM trash_items WHERE id = $1`, trashID)
		})

		payload, _ := trashItemAs(t, pool, actor.id, trashID)
		for key, want := range map[string]string{
			"name_en": "Test", "name_ar": "اختبار", "name_ckb": "تاقیکردنەوە", "name_kmr": "تاقیکرن",
		} {
			if got, _ := payload[key].(string); got != want {
				t.Errorf("payload[%q] = %q, want %q — the Trash can no longer name this record", key, got, want)
			}
		}
	})
}

// TestTrashRestoreKeepsTheCredentialIntact is the half that makes the fix
// honest. Withholding on display is only correct if the stored snapshot is
// still complete: استعادة rebuilds the account row out of it, so a snapshot
// missing `password_hash` would restore an account nobody can sign in to —
// silently, and for every account ever restored.
func TestTrashRestoreKeepsTheCredentialIntact(t *testing.T) {
	pool := newAuthTestPool(t)

	target := insertAccount(t, pool, "user", "")
	// The plaintext givePassword hashes is "hunter2"; the bcrypt check below
	// needs it, so the two have to stay in step.
	before := credentialFixture(t, pool, target.id)

	trashID := trashUserAccount(t, pool, target.id)

	// Reading the trash is what triggers the redaction; do it BEFORE restoring,
	// so a redaction that wrote itself back into the stored snapshot would be
	// caught here rather than staying invisible.
	viewer := insertAccount(t, pool, "supervisor", "")
	if _, wire := trashItemAs(t, pool, viewer.id, trashID); strings.Contains(wire, before.passwordHash) {
		t.Fatal("the hash reached the viewer — restore is not the interesting failure yet")
	}

	// The restore route is PIN-gated on the caller's OWN password (Note #26).
	const actorPassword = "restore-pin-1234"
	actor := insertAccount(t, pool, "admin", actorPassword)
	status, body := postAsStaff(t, pool, actor.id, "/api/admin/trash/:id/restore",
		"/api/admin/trash/"+strconv.FormatInt(trashID, 10)+"/restore",
		map[string]string{"password": actorPassword},
		(&AdminTrashHandler{Pool: pool, Perms: permissions.New(pool)}).Restore)
	if status != http.StatusOK {
		t.Fatalf("restore: status = %d, want 200 (body: %v)", status, body)
	}

	after := readCredential(t, pool, target.id)
	if after.passwordHash == "" {
		t.Fatal("THE RESTORED ACCOUNT HAS NO PASSWORD AT ALL — the snapshot was written without one, " +
			"so every account restored from the Trash is locked out and nothing on screen says why")
	}
	if after.passwordHash != before.passwordHash {
		t.Fatalf("THE RESTORED ACCOUNT'S PASSWORD CHANGED: %q → %q — everyone restored from the Trash would be locked out",
			before.passwordHash, after.passwordHash)
	}
	if after.googleSub != before.googleSub {
		t.Errorf("google_sub = %q, want %q — the restored account could not sign in with Google",
			after.googleSub, before.googleSub)
	}
	// The hash is only worth restoring if it still verifies the password.
	if err := bcrypt.CompareHashAndPassword([]byte(after.passwordHash), []byte("hunter2")); err != nil {
		t.Errorf("the restored hash no longer accepts the account's password: %v", err)
	}
}

// TestEveryTrashedTableDeclaresItsPreviewColumns keeps the fail-closed path from
// ever firing in front of an operator: a table routed through trashRow without a
// preview allow-list would land in the Trash showing nothing but its row id.
// Failing here is a five-line edit; discovering it in production is an admin
// guessing which record they are about to restore.
//
// No database needed, so this one runs on a bare checkout.
func TestEveryTrashedTableDeclaresItsPreviewColumns(t *testing.T) {
	for table := range restorableTables {
		cols, ok := trashPreviewColumns[table]
		if !ok || len(cols) == 0 {
			t.Errorf("%s can be trashed but declares no preview columns — its Trash row would be blank", table)
		}
	}
}
