// marriage_owner_test.go — K14 at the HTTP boundary.
//
// # WHY THIS FILE EXISTS
//
// internal/marriage/owner_test.go proves the store: the UPDATEs carry
// `AND user_id = $n`, a stranger changes nothing, and the delete keeps the
// chats and the payment record. This file proves the two things that live
// above the store and could still be wrong with a perfect store underneath:
//
//  1. THE ROUTES ANSWER CORRECTLY. A stranger gets 403 and a body that does not
//     say whether the profile exists; an owner acting on a state the transition
//     does not allow gets 409 and a sentence about the state, not about
//     ownership. Those two must not collapse into each other — "not yours" for
//     a profile that IS yours is a lie, and "still under review" for somebody
//     else's profile leaks that it exists.
//
//  2. THE DELETE IS ACTUALLY RECOVERABLE. The owner's حذف stamps
//     owner_deleted_at and hides the profile everywhere in the app. Nothing
//     brings it back unless staff can, so the claim "recoverable" rests
//     entirely on AdminStatusHandler.Marriage clearing that stamp. If it did
//     not, the profile would sit in the dashboard looking editable while
//     staying invisible in the app forever.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k14?sslmode=disable' \
//	  go test ./internal/handlers/ -run MarriageOwner -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
)

// ─── Harness ────────────────────────────────────────────────────────────

var marriageOwnerSeq = time.Now().UnixNano() % 100000

// callAsUser drives an owner-scoped handler through the REAL request chain
// main.go builds for these routes — RequireBearer + RequireApproved, with a
// genuine token minted for the caller. Nothing about who-is-asking is stubbed,
// because "the handler is fine but the gate resolves the wrong user" is a way
// this feature could be wrong that a faked context would hide.
func callAsUser(t *testing.T, pool *pgxpool.Pool, method, route, path string, userID int64, handler gin.HandlerFunc, body string) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), userID, "k14-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	r := gin.New()
	r.Handle(method, route, auth.RequireBearer(tokenStore), auth.RequireApproved(), handler)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	r.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// makeOwnerFixture inserts a user and an ACTIVE engagement profile they own.
func makeOwnerFixture(t *testing.T, pool *pgxpool.Pool) (userID, profileID int64) {
	t.Helper()
	ctx := context.Background()
	marriageOwnerSeq++
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("96477%05d%04d", marriageOwnerSeq%100000, marriageOwnerSeq%10000),
	).Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID) })

	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code, city, status, visibility_level)
		 VALUES ($1, $2, 'Erbil', 'active', 'matched_summary') RETURNING id`,
		userID, fmt.Sprintf("K14-%05d-%d", marriageOwnerSeq%100000, marriageOwnerSeq),
	).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})
	return userID, profileID
}

func marriageHandlerFor(pool *pgxpool.Pool) *MarriageHandler {
	return NewMarriageHandler(marriage.New(pool), nil, nil)
}

// ─── The routes ─────────────────────────────────────────────────────────

func TestMarriageOwnerCanEditPauseResumeAndDelete(t *testing.T) {
	pool := newAuthTestPool(t)
	owner, id := makeOwnerFixture(t, pool)
	h := marriageHandlerFor(pool)
	idStr := strconv.FormatInt(id, 10)

	if code, body := callAsUser(t, pool, http.MethodPatch, "/api/marriage/:id", "/api/marriage/"+idStr,
		owner, h.UpdateMine, `{"city":"Duhok","age":31}`); code != http.StatusOK {
		t.Fatalf("PATCH returned %d: %s", code, body)
	} else if !strings.Contains(body, "Duhok") {
		t.Errorf("the response does not echo the stored profile: %s", body)
	}

	if code, body := callAsUser(t, pool, http.MethodPost, "/api/marriage/:id/pause", "/api/marriage/"+idStr+"/pause",
		owner, h.PauseMine, `{}`); code != http.StatusOK {
		t.Fatalf("pause returned %d: %s", code, body)
	}
	// Pausing an already-paused profile is a state problem, not an ownership
	// one, and has to say so.
	code, body := callAsUser(t, pool, http.MethodPost, "/api/marriage/:id/pause", "/api/marriage/"+idStr+"/pause",
		owner, h.PauseMine, `{}`)
	if code != http.StatusConflict {
		t.Errorf("pausing an already-paused profile returned %d: %s — want 409", code, body)
	}
	if strings.Contains(body, "not yours") {
		t.Errorf("the owner was told their own profile is not theirs: %s", body)
	}

	if code, body := callAsUser(t, pool, http.MethodPost, "/api/marriage/:id/resume", "/api/marriage/"+idStr+"/resume",
		owner, h.ResumeMine, `{}`); code != http.StatusOK {
		t.Fatalf("resume returned %d: %s", code, body)
	}

	code, body = callAsUser(t, pool, http.MethodDelete, "/api/marriage/:id", "/api/marriage/"+idStr,
		owner, h.DeleteMine, ``)
	if code != http.StatusOK {
		t.Fatalf("DELETE returned %d: %s", code, body)
	}
	// The wording matters: the row is still there and staff can reinstate it,
	// so a response claiming the record is gone would be untrue.
	if !strings.Contains(body, `"recoverable":true`) {
		t.Errorf("the delete response does not say it is recoverable: %s", body)
	}
}

func TestMarriageOwnerRoutesRefuseAStrangerWithoutRevealingTheProfile(t *testing.T) {
	pool := newAuthTestPool(t)
	_, id := makeOwnerFixture(t, pool)
	stranger, _ := makeOwnerFixture(t, pool)
	h := marriageHandlerFor(pool)
	idStr := strconv.FormatInt(id, 10)

	cases := []struct {
		name    string
		method  string
		route   string
		path    string
		handler gin.HandlerFunc
		body    string
	}{
		{"edit", http.MethodPatch, "/api/marriage/:id", "/api/marriage/" + idStr, h.UpdateMine, `{"city":"Nowhere"}`},
		{"pause", http.MethodPost, "/api/marriage/:id/pause", "/api/marriage/" + idStr + "/pause", h.PauseMine, `{}`},
		{"resume", http.MethodPost, "/api/marriage/:id/resume", "/api/marriage/" + idStr + "/resume", h.ResumeMine, `{}`},
		{"delete", http.MethodDelete, "/api/marriage/:id", "/api/marriage/" + idStr, h.DeleteMine, ``},
	}
	for _, tc := range cases {
		code, body := callAsUser(t, pool, tc.method, tc.route, tc.path, stranger, tc.handler, tc.body)
		if code != http.StatusForbidden {
			t.Errorf("%s by a stranger returned %d: %s — want 403", tc.name, code, body)
		}
		// A missing profile must answer the same way, or the difference between
		// the two responses is an id-enumeration oracle.
		missing := strings.Replace(tc.path, idStr, "999999999", 1)
		mCode, _ := callAsUser(t, pool, tc.method, tc.route, missing, stranger, tc.handler, tc.body)
		if mCode != code {
			t.Errorf("%s answers %d for a real profile and %d for a missing one — "+
				"the difference tells a stranger which ids exist", tc.name, code, mCode)
		}
	}

	// And the profile is untouched.
	var city, status string
	if err := pool.QueryRow(context.Background(),
		`SELECT city, status FROM marriage_profiles WHERE id = $1`, id).Scan(&city, &status); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if city != "Erbil" || status != "active" {
		t.Errorf("a stranger's requests changed the profile: city=%q status=%q", city, status)
	}
}

func TestMarriageOwnerEditRejectsAnUnknownPrivacyChoice(t *testing.T) {
	pool := newAuthTestPool(t)
	owner, id := makeOwnerFixture(t, pool)
	code, body := callAsUser(t, pool, http.MethodPatch, "/api/marriage/:id",
		"/api/marriage/"+strconv.FormatInt(id, 10), owner,
		marriageHandlerFor(pool).UpdateMine, `{"visibility_level":"everyone"}`)
	if code != http.StatusBadRequest {
		t.Errorf("an unknown visibility_level returned %d: %s — want 400", code, body)
	}
	if strings.Contains(body, "SQLSTATE") || strings.Contains(body, "constraint") {
		t.Errorf("the rejection leaks the database error to the user: %s", body)
	}
}

// ─── The restore path ───────────────────────────────────────────────────

// Everything the owner's delete claims rests on this. The stamp hides the
// profile from every app surface; only staff can clear it, and this is the
// route they already use to decide a profile's status.
func TestMarriageOwnerDeleteIsUndoneByAStaffStatusDecision(t *testing.T) {
	pool := newAuthTestPool(t)
	owner, id := makeOwnerFixture(t, pool)
	idStr := strconv.FormatInt(id, 10)

	if code, body := callAsUser(t, pool, http.MethodDelete, "/api/marriage/:id", "/api/marriage/"+idStr,
		owner, marriageHandlerFor(pool).DeleteMine, ``); code != http.StatusOK {
		t.Fatalf("DELETE returned %d: %s", code, body)
	}
	if items, err := marriage.New(pool).List(context.Background(), marriage.SearchFilters{
		Status: "all", OwnedByUser: owner, ViewerUserID: owner,
	}); err != nil {
		t.Fatalf("List: %v", err)
	} else if len(items) != 0 {
		t.Fatalf("the deleted profile is still in the owner's list")
	}

	// Staff reinstate it through the route they already use.
	adminH := NewAdminStatusHandler(pool, nil, nil, nil)
	if code, body := callAsUser(t, pool, http.MethodPost, "/api/admin/marriage/:id/status",
		"/api/admin/marriage/"+idStr+"/status", owner, adminH.Marriage,
		`{"status":"active"}`); code != http.StatusOK {
		t.Fatalf("admin status returned %d: %s", code, body)
	}

	var stamped bool
	if err := pool.QueryRow(context.Background(),
		`SELECT owner_deleted_at IS NOT NULL FROM marriage_profiles WHERE id = $1`, id).Scan(&stamped); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if stamped {
		t.Fatalf("owner_deleted_at survived a staff status decision — the profile is now " +
			"visible in the dashboard, editable there, and permanently invisible in the app")
	}
	items, err := marriage.New(pool).List(context.Background(), marriage.SearchFilters{
		Status: "all", OwnedByUser: owner, ViewerUserID: owner,
	})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(items) != 1 || items[0].ID != id {
		t.Errorf("the restored profile did not come back to the owner's list (%d items)", len(items))
	}
}
