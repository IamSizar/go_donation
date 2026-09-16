// chat_group_connect_not_found_test.go pins OPOS #26478: a connect request
// that does not exist answers the admin detail, approve and decline routes
// with the shared chat-group refusal envelope, code included, so admin-web
// can show its translated error.connect_request_not_found instead of the
// English fallback. The sentence is unchanged from before the code existed.
//
// TestConnectRequestErr_MapsOnlyNotFound needs no database, so it always runs.
// The route test needs a throwaway Postgres and skips unless TEST_DATABASE_URL
// is set:
//
//	createdb godonation_connect_not_found
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_connect_not_found?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'TestConnectRequestErr_MapsOnlyNotFound|TestAdminConnectRequest_MissingRequestCarriesItsCode' -v
package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// wantConnectRequestNotFound is the refusal for a connect-request id that names
// no row. The code is a contract with admin-web's locale files: never rename it.
var wantConnectRequestNotFound = chatGroupRefusal{http.StatusNotFound, "connect_request_not_found", "Connect request not found."}

// TestConnectRequestErr_MapsOnlyNotFound feeds chatErr store errors through
// connectRequestErr, wrapped the way the store returns them. Only a not-found
// changes answer; every other refusal keeps the code it had before.
func TestConnectRequestErr_MapsOnlyNotFound(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		name string
		err  error
		want chatGroupRefusal
	}{
		{"missing connect request", chatgroups.ErrNotFound, wantConnectRequestNotFound},
		{"already decided", chatgroups.ErrAlreadyDecided, wantConnectRequestDecided},
		{"invalid input", chatgroups.ErrInvalidInput, wantGroupInvalidInput},
		{"guest member", chatgroups.ErrGuestMember, wantGuestMemberNotAllowed},
		{"any other failure", errors.New("connection reset by peer"), wantChatGroupServerError},
	}
	h := &ChatGroupHandler{}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			// A real handler always has its request; chatErr logs from it.
			c.Request = httptest.NewRequest(http.MethodPost, "/api/admin/chat-groups/connect-requests/7/approve", nil)
			storeErr := fmt.Errorf("chatgroups: connect request 7: %w", tc.err)

			h.chatErr(c, connectRequestErr(storeErr))

			var body map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode %q: %v", w.Body.String(), err)
			}
			assertChatGroupRefusal(t, w.Code, body, tc.want)
		})
	}

	t.Run("keeps the store error in the chain", func(t *testing.T) {
		if err := connectRequestErr(fmt.Errorf("chatgroups: connect request 7: %w", chatgroups.ErrNotFound)); !errors.Is(err, chatgroups.ErrNotFound) {
			t.Errorf("errors.Is(%v, ErrNotFound) = false, want true", err)
		}
	})
}

// TestAdminConnectRequest_MissingRequestCarriesItsCode asks the three
// single-request routes about an id that does not exist. The approve and
// decline bodies are valid, so each request gets past validation to the store.
func TestAdminConnectRequest_MissingRequestCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)
	base := fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d", chatGroupMissingID)

	t.Run("detail", func(t *testing.T) {
		code, body := getAs(t, r, token, base)
		assertChatGroupRefusal(t, code, body, wantConnectRequestNotFound)
	})
	t.Run("approve", func(t *testing.T) {
		code, body := postAs(t, r, token, base+"/approve",
			map[string]any{"kind": "masked", "members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}}})
		assertChatGroupRefusal(t, code, body, wantConnectRequestNotFound)
	})
	t.Run("decline", func(t *testing.T) {
		code, body := postAs(t, r, token, base+"/decline", map[string]any{"reason": "Not needed."})
		assertChatGroupRefusal(t, code, body, wantConnectRequestNotFound)
	})
}
