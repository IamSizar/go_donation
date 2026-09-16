// AdminTopUp must leave a durable, attributed app_events row — OPOS #25290:
// "log who added funds and when" for a dashboard wallet top-up. Before this,
// WalletHandler had no Events/Pool dependency at all, so nothing surfaced a
// top-up anywhere staff could see it (the wallet_transactions ledger row
// captured created_by/created_at, but only the end user's own
// GET /api/wallet/transactions could read it).
//
// Needs a throwaway Postgres and is skipped unless TEST_DATABASE_URL is set,
// same convention as admin_user_edit_guard_test.go:
//
//	createdb godonation_wallet_log
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_wallet_log?sslmode=disable' \
//	  go test ./internal/handlers/ -run WalletTopUpLog -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// newWalletTopUpRouter wires the REAL route exactly as main.go does. Notifier
// is left nil — AdminTopUp already guards every push send behind
// `if h.Notifier != nil`, so a nil Notifier exercises the handler's real
// production nil-safety rather than needing a live FCM/OTPIQ setup for a test
// that is only about the app_events log row.
func newWalletTopUpRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	tokenStore := auth.NewTokenStore(pool)
	permStore := permissions.New(pool)
	walletStore := wallet.New(pool)
	eventsStore := events.New(pool)
	walletH := NewWalletHandler(walletStore, nil, pool, eventsStore)
	r.POST("/api/admin/users/:id/wallet/topup",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permStore, "users", "edit"),
		walletH.AdminTopUp,
	)
	return r
}

func TestWalletTopUpLogsAnAttributedEvent(t *testing.T) {
	pool := newAuthTestPool(t)

	actor := insertAccount(t, pool, "employee", "")
	target := insertAccount(t, pool, "user", "")

	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actor.id, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	body, _ := json.Marshal(map[string]any{"amount_iqd": 5000, "note": "test top-up"})
	req := httptest.NewRequest(http.MethodPost,
		"/api/admin/users/"+strconv.FormatInt(target.id, 10)+"/wallet/topup", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	newWalletTopUpRouter(pool).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
	}

	var (
		eventType string
		userID    *int64
		amount    *float64
		currency  string
		metaRaw   []byte
	)
	err = pool.QueryRow(context.Background(),
		`SELECT event_type, user_id, amount, currency, metadata
		   FROM app_events
		  WHERE event_type = 'admin_wallet_topup' AND user_id = $1
		  ORDER BY id DESC LIMIT 1`, target.id,
	).Scan(&eventType, &userID, &amount, &currency, &metaRaw)
	if err != nil {
		t.Fatalf("query app_events: %v — no attributed log row was written for the top-up", err)
	}
	if amount == nil || *amount != 5000 {
		t.Errorf("amount = %v, want 5000", amount)
	}
	if currency != "IQD" {
		t.Errorf("currency = %q, want IQD", currency)
	}
	var meta map[string]any
	if err := json.Unmarshal(metaRaw, &meta); err != nil {
		t.Fatalf("unmarshal metadata: %v", err)
	}
	if got, ok := meta["actor_user_id"].(float64); !ok || int64(got) != actor.id {
		t.Errorf("metadata.actor_user_id = %v, want %d — the log must say WHO topped up the wallet", meta["actor_user_id"], actor.id)
	}
}
