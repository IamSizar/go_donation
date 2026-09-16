// chat_group_connect_context_test.go — HTTP-level tests for OPOS #26351:
// POST /api/chat-groups/connect-requests refuses a case or donation that does
// not exist with 400 and the code connect_context_not_found, and accepts any
// case that does exist, whatever its status or owner. An existing donation
// being accepted over HTTP is TestSubmitConnectRequest_CreatesRequest in
// chat_group_test.go. The store-level twin, with the reasoning behind the
// rule, is internal/chatgroups/chatgroups_connect_context_test.go.
//
// Needs the same throwaway Postgres as chat_group_test.go — see
// newChatGroupPool.
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// connectContextNeverExistingID is far beyond any id a test database's
// sequences hand out, so no case or donation row can hold it.
const connectContextNeverExistingID int64 = 9_000_000_000_000_000

// The refusal's machine code and sentence, pinned so that renaming either is
// a deliberate, visible change rather than a silent break for a client.
const (
	connectContextNotFoundCode    = "connect_context_not_found"
	connectContextNotFoundMessage = "We couldn't find that case or donation."
)

// ─── Fixtures ────────────────────────────────────────────────────────────

// chatGroupCaseCodeSeq numbers fixture case codes; see makeChatGroupCase.
var chatGroupCaseCodeSeq int64

// makeChatGroupCase inserts a beneficiary_cases row owned by ownerID with the
// given verification_status, and deletes it on cleanup. case_code is UNIQUE
// and internal/chatgroups inserts cases into the same database concurrently,
// so the code carries a package prefix and a nanosecond timestamp as well as
// a counter.
func makeChatGroupCase(t *testing.T, pool *pgxpool.Pool, ownerID int64, status string) int64 {
	t.Helper()
	code := fmt.Sprintf("CG-HTTP-%d-%d", time.Now().UnixNano(), atomic.AddInt64(&chatGroupCaseCodeSeq, 1))
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO beneficiary_cases (user_id, case_code, public_title, verification_status)
		VALUES ($1, $2, 'connect-context fixture', $3)
		RETURNING id`,
		ownerID, code, status,
	).Scan(&id); err != nil {
		t.Fatalf("insert case fixture: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id)
	})
	return id
}

// makeChatGroupDonation inserts a donations row made by donorID and deletes
// it on cleanup. donations.user_id is a RESTRICT foreign key to users, so
// call this after donorID's makeChatGroupUser: cleanups run last-in
// first-out, and the donation has to go before its donor can.
func makeChatGroupDonation(t *testing.T, pool *pgxpool.Pool, donorID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO donations (user_id, message, amount, payment_method)
		VALUES ($1, 'connect-context fixture', '1000', 'cash')
		RETURNING id`,
		donorID,
	).Scan(&id); err != nil {
		t.Fatalf("insert donation fixture: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, id)
	})
	return id
}

// ─── Tests ───────────────────────────────────────────────────────────────

// TestSubmitConnectRequest_RefusesUnknownContext: a case or donation id that
// names no row answers 400 with the connect_context_not_found code and the
// friendly sentence, and hands back no request id.
func TestSubmitConnectRequest_RefusesUnknownContext(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	member := makeChatGroupUser(t, pool, "Member Name")
	token := tokenForChatGroupUser(t, pool, member)

	for _, contextType := range []string{"case", "donation"} {
		t.Run(contextType, func(t *testing.T) {
			code, body := postAs(t, r, token, "/api/chat-groups/connect-requests", map[string]any{
				"context_type": contextType, "context_id": connectContextNeverExistingID, "message": "please connect me",
			})

			if code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body %v)", code, body)
			}
			if body["success"] != false || body["code"] != connectContextNotFoundCode || body["error"] != connectContextNotFoundMessage {
				t.Fatalf("body = %v, want success=false, code=%q, error=%q",
					body, connectContextNotFoundCode, connectContextNotFoundMessage)
			}
			if _, ok := body["request_id"]; ok {
				t.Fatalf("a refused request returned a request_id: %v", body)
			}
		})
	}
}

// TestSubmitConnectRequest_AcceptsExistingCaseWhateverItsStatusOrOwner pins
// the user's decision at the route: the button stays on every case, so the
// server accepts an approved, pending or rejected case, and the member's own.
func TestSubmitConnectRequest_AcceptsExistingCaseWhateverItsStatusOrOwner(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	member := makeChatGroupUser(t, pool, "Member Name")
	owner := makeChatGroupUser(t, pool, "Case Owner")
	token := tokenForChatGroupUser(t, pool, member)

	for _, tc := range []struct {
		name    string
		ownerID int64
		status  string
	}{
		{"approved case", owner, "approved"},
		{"pending case", owner, "pending"},
		{"rejected case", owner, "rejected"},
		{"the member's own pending case", member, "pending"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			caseID := makeChatGroupCase(t, pool, tc.ownerID, tc.status)

			code, body := postAs(t, r, token, "/api/chat-groups/connect-requests", map[string]any{
				"context_type": "case", "context_id": caseID, "message": "please connect me",
			})

			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %v)", code, body)
			}
			if _, ok := body["request_id"]; !ok {
				t.Fatalf("no request_id in response: %v", body)
			}
		})
	}
}
