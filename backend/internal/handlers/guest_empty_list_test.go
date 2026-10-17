package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// A guest and a general user (role 6) are both kept out of chats. The list a
// signed-in app polls every few seconds must answer them with an empty list,
// not a 403 the app shows as a red error box with a Retry that can never work.
func TestGuestGetsEmptyListCoversGuestsAndGeneralUsers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		name     string
		user     *auth.ResolvedUser
		wantBody string
		wantNext bool
	}{
		{"guest", &auth.ResolvedUser{IsGuest: true, RoleID: 1}, `{"items":[],"success":true}`, false},
		{"general user", &auth.ResolvedUser{RoleID: 6}, `{"items":[],"success":true}`, false},
		{"donor passes through", &auth.ResolvedUser{RoleID: 1}, "", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(rec)
			c.Request = httptest.NewRequest(http.MethodGet, "/api/chat-groups", nil)
			c.Set("auth.user", tc.user)
			GuestGetsEmptyList()(c)
			if tc.wantNext {
				if c.IsAborted() {
					t.Fatalf("a donor must reach the handler")
				}
				return
			}
			if !c.IsAborted() || rec.Code != http.StatusOK || rec.Body.String() != tc.wantBody {
				t.Fatalf("code=%d aborted=%v body=%s, want 200 %s", rec.Code, c.IsAborted(), rec.Body.String(), tc.wantBody)
			}
		})
	}
}
