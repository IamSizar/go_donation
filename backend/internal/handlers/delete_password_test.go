// delete_password_test.go — "any delete requires entering the password" (N3).
//
// # WHAT THIS FILE PINS
//
// admin_delete_trash_test.go pins the FIRST half of the client's rule (a delete
// leaves a way back). This file pins the SECOND half, and the half where a bug
// is silent: a confirmation that can be skipped looks exactly like one that
// works, right up until the row it was protecting is gone.
//
// Each case therefore asserts the DATABASE, not only the status code. "403 and
// the row is still there" is the assertion; "403" alone would pass even if the
// handler had deleted the row before answering.
//
// Same convention as its sibling — the integration tests need a throwaway
// Postgres and skip unless TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_full?sslmode=disable' \
//	  go test ./internal/handlers/ -run DeletePassword -v
package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
)

// ─── Harness ────────────────────────────────────────────────────────────

// callGuardedDelete drives a delete handler through a real gin route with the
// RequireDeletePassword middleware in front of it and `actor` as the signed-in
// staff member — i.e. the exact chain production builds in main.go.
//
// `body` is the raw request body, so a test can send a right password, a wrong
// one, an absent field, no body at all, or malformed JSON.
func callGuardedDelete(t *testing.T, pool *pgxpool.Pool, actor int64, handler gin.HandlerFunc, id int64, body string) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	// "auth.user" is auth.contextUserKey — the key RequireAdmin sets and
	// auth.UserFromGin reads. Set directly because what is under test is the
	// password gate, not token resolution.
	r.Use(func(c *gin.Context) { c.Set("auth.user", &auth.ResolvedUser{UserID: actor, StaffTier: "super_admin"}) })
	r.Use(RequireDeletePassword(pool))
	r.DELETE("/x/:id", handler)

	req := httptest.NewRequest(http.MethodDelete, "/x/"+strconv.FormatInt(id, 10), strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// rowExists answers the only question that matters after a refused delete.
func rowExists(t *testing.T, pool *pgxpool.Pool, table string, id int64) bool {
	t.Helper()
	var ok bool
	if err := pool.QueryRow(context.Background(),
		`SELECT EXISTS (SELECT 1 FROM `+table+` WHERE id = $1)`, id).Scan(&ok); err != nil {
		t.Fatalf("check %s#%d: %v", table, id, err)
	}
	return ok
}

// newBannedWord inserts a blocklist fixture and cleans it up afterwards.
func newBannedWord(t *testing.T, pool *pgxpool.Pool, word string) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO banned_words (word) VALUES ($1) RETURNING id`, word).Scan(&id); err != nil {
		t.Fatalf("insert banned word: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'banned_words' AND row_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM banned_words WHERE id = $1`, id)
	})
	return id
}

// ─── The gate ───────────────────────────────────────────────────────────

// TestDeletePasswordGate is the whole rule in one table: only a correct
// password deletes, and every other body leaves the row exactly where it was.
func TestDeletePasswordGate(t *testing.T) {
	pool := newAuthTestPool(t)
	const password = "n3-correct-horse"
	actor := insertAccount(t, pool, "super_admin", password)

	cases := []struct {
		name string
		body string
		// wantStatus — 400 for "you didn't supply one", 403 for "it was wrong".
		// The two are different on purpose: the operator who mistyped needs a
		// different sentence from the operator whose client sent nothing.
		wantStatus int
	}{
		{"wrong password", `{"password":"not-my-password"}`, http.StatusForbidden},
		{"empty password", `{"password":""}`, http.StatusBadRequest},
		{"whitespace-only password", `{"password":"   "}`, http.StatusBadRequest},
		{"missing password field", `{}`, http.StatusBadRequest},
		// The dangerous one: a client that simply forgets the body must NOT
		// fall through to a successful delete.
		{"no body at all", ``, http.StatusBadRequest},
		{"malformed JSON", `{"password":`, http.StatusBadRequest},
	}

	handler := NewBannedWordsHandler(moderation.New(pool), pool).Delete

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := newBannedWord(t, pool, "n3-gate-"+strings.ReplaceAll(tc.name, " ", "-"))

			status, body := callGuardedDelete(t, pool, actor.id, handler, id, tc.body)
			if status != tc.wantStatus {
				t.Errorf("status = %d, want %d (body: %s)", status, tc.wantStatus, body)
			}
			// The assertion the status code cannot make on its own.
			if !rowExists(t, pool, "banned_words", id) {
				t.Fatalf("banned_words#%d was DELETED despite %s — the gate does not hold", id, tc.name)
			}
			if n := trashCountFor(t, pool, "banned_words", id); n != 0 {
				t.Errorf("a refused delete still wrote %d trash entries", n)
			}
			// The response must never echo what was submitted.
			if strings.Contains(body, "not-my-password") {
				t.Errorf("the submitted password was echoed back in the error: %s", body)
			}
		})
	}

	// And the other direction: the correct password really does delete.
	t.Run("correct password deletes and trashes", func(t *testing.T) {
		id := newBannedWord(t, pool, "n3-gate-correct")
		if status, body := callGuardedDelete(t, pool, actor.id, handler, id,
			`{"password":"`+password+`"}`); status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %s)", status, body)
		}
		if rowExists(t, pool, "banned_words", id) {
			t.Errorf("banned_words#%d survived a confirmed delete", id)
		}
		if n := trashCountFor(t, pool, "banned_words", id); n != 1 {
			t.Errorf("banned_words#%d left %d trash entries, want 1", id, n)
		}
	})
}

// TestDeletePasswordGateRefusesWithoutPasswordOnAccount pins the fail-closed
// direction for an account that has no password_hash at all: it cannot confirm,
// so it cannot delete. A staff member in that state is told to ask a
// Super-Admin rather than being silently allowed through.
func TestDeletePasswordGateRefusesWithoutPasswordOnAccount(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "") // no password set
	id := newBannedWord(t, pool, "n3-nopassword")

	status, body := callGuardedDelete(t, pool, actor.id,
		NewBannedWordsHandler(moderation.New(pool), pool).Delete, id, `{"password":"anything"}`)
	if status != http.StatusForbidden {
		t.Errorf("status = %d, want 403 (body: %s)", status, body)
	}
	if !rowExists(t, pool, "banned_words", id) {
		t.Fatalf("banned_words#%d was deleted by an account that cannot confirm anything", id)
	}
}

// ─── The two converted routes ───────────────────────────────────────────

// TestConvertedHardDeletesGoToTrash covers app_events and banned_words: the two
// routes that used to run `DELETE FROM` outright. Both are asserted end to end
// — deleted, in the Trash, and restorable back into their own table — because a
// row that reaches المهملات and is then refused on the way out is worse than one
// that was never trashed.
func TestConvertedHardDeletesGoToTrash(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	const password = "n3-correct-horse"
	actor := insertAccount(t, pool, "super_admin", password)

	t.Run("app_events", func(t *testing.T) {
		var id int64
		if err := pool.QueryRow(ctx,
			`INSERT INTO app_events (event_type, event_label, status, source)
			 VALUES ('n3.test', 'N3 fixture', 'success', 'test') RETURNING id`).Scan(&id); err != nil {
			t.Fatalf("insert app_event: %v", err)
		}
		t.Cleanup(func() {
			bg := context.Background()
			_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'app_events' AND row_id = $1`, id)
			_, _ = pool.Exec(bg, `DELETE FROM app_events WHERE id = $1`, id)
		})

		h := NewEventsHandler(nil, pool)
		if status, body := callGuardedDelete(t, pool, actor.id, h.AdminDelete, id,
			`{"password":"`+password+`"}`); status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %s)", status, body)
		}
		if rowExists(t, pool, "app_events", id) {
			t.Errorf("app_events#%d was not deleted", id)
		}
		if n := trashCountFor(t, pool, "app_events", id); n != 1 {
			t.Fatalf("app_events#%d left %d trash entries, want 1 — the delete was permanent", id, n)
		}
		restoreFromTrash(t, pool, actor.id, password, "app_events", id, moderation.New(pool))
		if !rowExists(t, pool, "app_events", id) {
			t.Errorf("app_events#%d did not come back out of the Trash", id)
		}
	})

	t.Run("banned_words", func(t *testing.T) {
		store := moderation.New(pool)
		id := newBannedWord(t, pool, "n3-convert-word")

		if status, body := callGuardedDelete(t, pool, actor.id,
			NewBannedWordsHandler(store, pool).Delete, id,
			`{"password":"`+password+`"}`); status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %s)", status, body)
		}
		if rowExists(t, pool, "banned_words", id) {
			t.Errorf("banned_words#%d was not deleted", id)
		}
		if n := trashCountFor(t, pool, "banned_words", id); n != 1 {
			t.Fatalf("banned_words#%d left %d trash entries, want 1", id, n)
		}
		restoreFromTrash(t, pool, actor.id, password, "banned_words", id, store)
		if !rowExists(t, pool, "banned_words", id) {
			t.Errorf("banned_words#%d did not come back out of the Trash", id)
		}
	})
}

// TestRestoringABannedWordRefreshesTheCache is the trap this change could have
// set. The blocklist lives in an in-process cache with NO TTL, and Restore puts
// the row back with a raw INSERT the Store never sees. Without the invalidation
// hook the word would sit in banned_words, be listed as restored, and quietly
// stop being enforced until the next restart.
func TestRestoringABannedWordRefreshesTheCache(t *testing.T) {
	pool := newAuthTestPool(t)
	const password = "n3-correct-horse"
	actor := insertAccount(t, pool, "super_admin", password)
	store := moderation.New(pool)

	const word = "n3-cachetrap"
	id := newBannedWord(t, pool, word)

	// Warm the cache so the word is genuinely held in memory, not lazily read.
	if blocked, err := store.Contains(context.Background(), "a comment saying "+word); err != nil {
		t.Fatalf("Contains before delete: %v", err)
	} else if !blocked {
		t.Fatalf("fixture word %q is not being blocked before the delete", word)
	}

	if status, body := callGuardedDelete(t, pool, actor.id,
		NewBannedWordsHandler(store, pool).Delete, id,
		`{"password":"`+password+`"}`); status != http.StatusOK {
		t.Fatalf("delete status = %d, want 200 (body: %s)", status, body)
	}
	if blocked, err := store.Contains(context.Background(), "a comment saying "+word); err != nil {
		t.Fatalf("Contains after delete: %v", err)
	} else if blocked {
		t.Errorf("%q is still enforced after being deleted — the cache was not refreshed", word)
	}

	restoreFromTrash(t, pool, actor.id, password, "banned_words", id, store)

	if blocked, err := store.Contains(context.Background(), "a comment saying "+word); err != nil {
		t.Fatalf("Contains after restore: %v", err)
	} else if !blocked {
		t.Errorf("%q came back from the Trash but is NOT being enforced — a restored word that isn't in the cache is silently unblocked", word)
	}
}

// restoreFromTrash drives the real Restore handler (password and all) for the
// newest un-restored trash entry of one row, wired the way main.go wires it.
//
// `bw` is the moderation Store the handler should refresh on a successful
// restore. A caller that wants to OBSERVE that refresh passes the very store
// its delete used; everyone else passes a fresh one.
func restoreFromTrash(t *testing.T, pool *pgxpool.Pool, actor int64, password, table string, rowID int64, bw *moderation.Store) {
	t.Helper()
	var trashID int64
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM trash_items
		  WHERE source_table = $1 AND row_id = $2 AND restored_at IS NULL
		  ORDER BY id DESC LIMIT 1`, table, rowID).Scan(&trashID); err != nil {
		t.Fatalf("find trash entry for %s#%d: %v", table, rowID, err)
	}

	h := NewAdminTrashHandler(pool)
	// The production wiring — restoring a word has to refresh the blocklist.
	h.BannedWords = bw

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set("auth.user", &auth.ResolvedUser{UserID: actor, StaffTier: "super_admin"}) })
	r.POST("/t/:id/restore", h.Restore)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/t/"+strconv.FormatInt(trashID, 10)+"/restore",
		strings.NewReader(`{"password":"`+password+`"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("restore %s#%d: status = %d (body: %s)", table, rowID, rec.Code, rec.Body.String())
	}
}
