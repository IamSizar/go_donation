// R2 #60 — the marriage chat keeps the two parties anonymous to each other, so a
// phone number or email typed into a message must be refused (and not stored);
// a plain message and a staff relay still go through.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set.
package handlers

import (
	"fmt"
	"net/http"
	"testing"
)

func TestMarriageChatRefusesContactDetailsFromParties(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	thread := insertMarriageChatThread(t, pool, requester, owner)
	url := fmt.Sprintf("/api/marriage/chats/%d/messages", thread)

	code, body := doJSON(t, r, http.MethodPost, url, tokenFor(t, pool, requester),
		map[string]string{"body": "call me on 0770 123 4567"})
	if code != http.StatusUnprocessableEntity || body["code"] != "contact_details_blocked" {
		t.Fatalf("phone: status = %d body = %v, want 422 contact_details_blocked", code, body)
	}
	code, body = doJSON(t, r, http.MethodPost, url, tokenFor(t, pool, owner),
		map[string]string{"body": "write to me at someone@example.com"})
	if code != http.StatusUnprocessableEntity || body["code"] != "contact_details_blocked" {
		t.Fatalf("email: status = %d body = %v, want 422 contact_details_blocked", code, body)
	}
	if n := countRows(t, pool, "marriage_chat_messages", "thread_id", thread); n != 0 {
		t.Fatalf("a refused message was stored (%d rows)", n)
	}

	code, _ = doJSON(t, r, http.MethodPost, url, tokenFor(t, pool, requester),
		map[string]string{"body": "when could we meet?"})
	if code != http.StatusOK {
		t.Fatalf("plain message: status = %d, want 200", code)
	}
}
