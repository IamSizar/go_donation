// OPOS #25292 — "'Add Campaign' UI inconsistent". Root cause (traced, not
// guessed): PublishProjectRequest maps an approved beneficiary_project_request
// onto a new campaigns row, but campaigns.title_ar is NOT NULL while
// beneficiary_project_requests.project_title_ar is nullable — and the app's
// own project-request submission form never collects an Arabic title at all,
// so titleAr is nil for essentially every real request. Passing that nil
// straight into the INSERT crashed with a raw "null value... violates
// not-null constraint" 500, instead of the graceful inline validation the
// sibling "Add Campaign" admin form gives for the exact same required field.
//
// This locks in the fix: publishing a project request with no Arabic title
// succeeds (defaults title_ar to "", never to the English title — this app
// never substitutes English text into an Arabic column).
//
// Needs a throwaway Postgres, skipped unless TEST_DATABASE_URL is set — see
// admin_account_status_gate_test.go's newAuthTestPool for the exact setup.
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// insertApprovedProjectRequest inserts a minimal beneficiary_project_requests
// row in 'approved' status with NO Arabic title — the shape every real
// app-submitted request actually has (project_title_ar is nullable and the
// submission form never populates it).
func insertApprovedProjectRequest(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_project_requests
		   (user_id, project_title, category, summary, description_long,
		    amount_needed, location, beneficiary_community_name, status)
		 VALUES ($1, 'Test Project', 'water', 'A short summary', 'A longer description',
		         500000, 'Mosul', 'Test Community', 'approved')
		 RETURNING id`,
		ownerID,
	).Scan(&id)
	if err != nil {
		t.Fatalf("insert project request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM beneficiary_project_requests WHERE id = $1`, id)
	})
	return id
}

func postPublishProjectRequestAs(
	t *testing.T, pool *pgxpool.Pool, actorID, requestID int64,
) (int, map[string]any) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	tokenStore := auth.NewTokenStore(pool)
	r := gin.New()
	r.POST("/api/admin/beneficiary_project_requests/:id/publish",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permissions.New(pool), "beneficiary", "edit"),
		NewAdminStatusHandler(pool, nil, nil, nil).PublishProjectRequest,
	)

	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for actor %d: %v", actorID, err)
	}
	req := httptest.NewRequest(http.MethodPost,
		"/api/admin/beneficiary_project_requests/"+strconv.FormatInt(requestID, 10)+"/publish", nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

func TestPublishProjectRequestWithNoArabicTitleSucceeds(t *testing.T) {
	pool := newAuthTestPool(t)
	setTierPermission(t, pool, "admin", "beneficiary", "edit", true)

	actor := insertAccount(t, pool, "admin", "")
	owner := insertAccount(t, pool, "", "")
	reqID := insertApprovedProjectRequest(t, pool, owner.id)

	status, body := postPublishProjectRequestAs(t, pool, actor.id, reqID)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — publishing a request with no Arabic "+
			"title must degrade gracefully like description/description_ar "+
			"already do, not crash with a raw DB error (body: %v)", status, body)
	}

	campaignID, _ := body["id"].(float64)
	if campaignID == 0 {
		t.Fatalf("response carried no campaign id: %v", body)
	}

	var titleAr string
	if err := pool.QueryRow(context.Background(),
		`SELECT title_ar FROM campaigns WHERE id = $1`, int64(campaignID),
	).Scan(&titleAr); err != nil {
		t.Fatalf("read published campaign: %v", err)
	}
	// Must never be the English title standing in for Arabic — this app
	// never substitutes English text into an Arabic column.
	if titleAr == "Test Project" {
		t.Errorf("title_ar = %q — the English title leaked into the Arabic column", titleAr)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM campaigns WHERE id = $1`, int64(campaignID))
	})
}
