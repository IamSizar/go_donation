// chat_test.go — OPOS #25284 Phase 4 Task 1, HTTP-level twin of
// internal/chat/chat_test.go's TestRequestThreadRefusesNewDirectChat: with
// chat.Store.RequestThread now gated to always return
// chat.ErrDirectChatRetired, POST /api/chats/request must map that sentinel
// to a clean 410 Gone, not the generic 500 it fell through to before this
// task landed.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chat_request
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chat_request?sslmode=disable' \
//	  go test ./internal/handlers/ -run TestChatRequest_RefusesNewDirectChat -v
package handlers

import (
	"context"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// newChatRequestRouter wires POST /api/chats/request with the same
// middleware stack main.go uses (see cmd/server/main.go's "authed" group):
// RequireBearer + RequireApproved at the group level, RequireNotGuest on the
// route itself.
func newChatRequestRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	h := NewChatHandler(chat.New(pool), notify.New(pool), pool)
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
	authed.POST("/chats/request", auth.RequireNotGuest(), h.Request)
	return r
}

// makeChatRequestCampaign inserts a minimal campaign owned by ownerID. Column
// list matches migrations/001_full_v2.sql (every one of these is NOT NULL
// with no default) plus owner_user_id from migrations/007_campaigns_owner.sql
// — the Request handler resolves the chat's recipient through this column.
func makeChatRequestCampaign(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO campaigns (title, title_ar, description, description_ar, address, beneficiaries, goal_amount, raised_amount, owner_user_id)
		VALUES ('Test Campaign', 'حملة اختبار', 'd', 'd', 'a', '1', '1000', '0', $1)
		RETURNING id`, ownerID,
	).Scan(&id); err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM campaigns WHERE id = $1`, id)
	})
	return id
}

// makeChatRequestDonation inserts a donation from donorID to campaignID. The
// Request handler's donation_id entry path (chat.go, req.DonationID > 0)
// resolves donor/owner/campaign from this row.
func makeChatRequestDonation(t *testing.T, pool *pgxpool.Pool, donorID, campaignID int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO donations (user_id, campaign_id, message, amount, payment_method)
		VALUES ($1, $2, 'test donation', '250', 'cash')
		RETURNING id`, donorID, campaignID,
	).Scan(&id); err != nil {
		t.Fatalf("insert donation: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, id)
	})
	return id
}

// TestChatRequest_RefusesNewDirectChat is the HTTP-level guarantee behind
// Phase 4 Task 1: the donor's own donation-based request into POST
// /api/chats/request must answer 410 Gone — chat.ErrDirectChatRetired mapped
// to a clean response, per chat.go's Request — and must not create a
// chat_threads row.
//
// Reuses this package's existing test-pool (newContactBlockPool), user
// (makeContactUser) and token (tokenForChatGroupUser) helpers rather than
// inventing new ones — this file has no chat_threads route wiring of its own
// to model on (chat_contact_block_test.go covers /chats/:id/messages,
// chat_support_thread_test.go covers RequestSupportThread at the store
// level), so newChatRequestRouter above is new, but the plumbing under it
// is not.
func TestChatRequest_RefusesNewDirectChat(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatRequestRouter(pool)
	donor := makeContactUser(t, pool, "user")
	owner := makeContactUser(t, pool, "user")
	campaignID := makeChatRequestCampaign(t, pool, owner)
	donationID := makeChatRequestDonation(t, pool, donor, campaignID)
	token := tokenForChatGroupUser(t, pool, donor)

	code, body := postAs(t, r, token, "/api/chats/request", map[string]any{
		"donation_id": donationID,
	})
	if code != http.StatusGone {
		t.Fatalf("status = %d, want 410 (body %v)", code, body)
	}

	var count int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM chat_threads WHERE donor_user_id = $1 AND owner_user_id = $2`,
		donor, owner).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected no thread row inserted, got %d", count)
	}
}
