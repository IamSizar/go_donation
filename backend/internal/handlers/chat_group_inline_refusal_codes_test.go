// chat_group_inline_refusal_codes_test.go pins OPOS #26496: the chat-group
// refusals the handlers answer themselves, before or beside chatErr, carry a
// machine code in the same {success:false, error, code} envelope as chatErr's
// (OPOS #26410, chat_group_error_codes_test.go). The English sentences and
// statuses are unchanged; only the code is new:
//
//   - 401 "Unauthorized."            → unauthorized
//   - 400 inline validation sentences → group_invalid_input
//   - 500 "Database error."          → server_error
//
// The 401 test calls each handler without an authenticated user, so it needs
// no database and always runs. The 400 and 500 tests use real routes and skip
// unless TEST_DATABASE_URL is set (see chat_group_error_codes_test.go).
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// wantChatGroupUnauthorized is the refusal for a request with no user behind it.
var wantChatGroupUnauthorized = chatGroupRefusal{http.StatusUnauthorized, "unauthorized", "Unauthorized."}

// wantInvalidGroupInput is a 400 group_invalid_input keeping the handler's own
// sentence, which clients already show.
func wantInvalidGroupInput(message string) chatGroupRefusal {
	return chatGroupRefusal{http.StatusBadRequest, "group_invalid_input", message}
}

// ─── 401 ─────────────────────────────────────────────────────────────────

// TestChatGroupHandlers_UnauthorizedCarriesItsCode calls every chat-group
// handler with no user in the context. In production the auth middleware
// refuses first; this is the handlers' own defence and must match the envelope.
func TestChatGroupHandlers_UnauthorizedCarriesItsCode(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := &ChatGroupHandler{}
	handlers := map[string]gin.HandlerFunc{
		"List": h.List, "Messages": h.Messages, "PostMessage": h.PostMessage, "MarkRead": h.MarkRead,
		"SubmitConnectRequest": h.SubmitConnectRequest, "MyConnectRequests": h.MyConnectRequests,
		"AdminList": h.AdminList, "AdminGetGroup": h.AdminGetGroup, "AdminCreateGroup": h.AdminCreateGroup,
		"AdminAddMember": h.AdminAddMember, "AdminRemoveMember": h.AdminRemoveMember,
		"AdminMessages": h.AdminMessages, "AdminPostMessage": h.AdminPostMessage,
		"AdminContactBlocks": h.AdminContactBlocks, "AdminListConnectRequests": h.AdminListConnectRequests,
		"AdminGetConnectRequest": h.AdminGetConnectRequest, "AdminApproveConnectRequest": h.AdminApproveConnectRequest,
		"AdminDeclineConnectRequest": h.AdminDeclineConnectRequest,
	}
	for name, handle := range handlers {
		t.Run(name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest(http.MethodGet, "/api/chat-groups/7", nil)

			handle(c)

			code, body := decodeRecorder(t, w)
			assertChatGroupRefusal(t, code, body, wantChatGroupUnauthorized)
		})
	}
}

// ─── 400 ─────────────────────────────────────────────────────────────────

// TestChatGroupRoutes_InlineBadRequestCarriesItsCode sends each route a body it
// refuses before reaching the store.
func TestChatGroupRoutes_InlineBadRequestCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	reqID := submitTestConnectRequest(t, pool, donor)
	staffToken := tokenForStaffUser(t, pool, staff)
	donorToken := tokenForChatGroupUser(t, pool, donor)
	adminRouter, _ := newAdminChatGroupRouter(pool)
	adminMessages, _ := newAdminMessagesRouter(pool)
	connectAdmin, _ := newAdminConnectRequestRouter(pool)
	memberRouter, _ := newWriteChatGroupRouter(pool)
	connectMember, _ := newConnectRequestRouter(pool)
	approvePath := fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID)
	kindRequired := wantInvalidGroupInput("kind and at least one member are required.")

	cases := []struct {
		name   string
		router *gin.Engine
		token  string
		method string
		path   string
		body   any
		want   chatGroupRefusal
	}{
		{"admin create: not an object", adminRouter, staffToken, http.MethodPost, "/api/admin/chat-groups", "x", wantInvalidGroupInput("Invalid JSON.")},
		{"admin create: no members", adminRouter, staffToken, http.MethodPost, "/api/admin/chat-groups", map[string]any{"kind": "masked"}, kindRequired},
		{"admin add member: no user_id", adminRouter, staffToken, http.MethodPost, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID), map[string]any{}, wantInvalidGroupInput("user_id is required.")},
		{"admin remove member: bad user id", adminRouter, staffToken, http.MethodDelete, fmt.Sprintf("/api/admin/chat-groups/%d/members/abc", groupID), nil, wantInvalidGroupInput("Invalid user id.")},
		{"admin post: blank body", adminMessages, staffToken, http.MethodPost, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID), map[string]any{"body": "  "}, wantInvalidGroupInput("Message body is required.")},
		{"admin approve: not an object", connectAdmin, staffToken, http.MethodPost, approvePath, "x", wantInvalidGroupInput("Invalid JSON.")},
		{"admin approve: no kind", connectAdmin, staffToken, http.MethodPost, approvePath, map[string]any{"members": []map[string]any{{"user_id": donor}}}, kindRequired},
		{"admin decline: blank reason", connectAdmin, staffToken, http.MethodPost, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/decline", reqID), map[string]any{"reason": " "}, wantInvalidGroupInput("A decline reason is required.")},
		{"member post: blank body", memberRouter, donorToken, http.MethodPost, fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]any{"body": ""}, wantInvalidGroupInput("Message body is required.")},
		{"member mark read: not an object", memberRouter, donorToken, http.MethodPost, fmt.Sprintf("/api/chat-groups/%d/read", groupID), "x", wantInvalidGroupInput("Invalid JSON.")},
		{"member connect request: no message", connectMember, donorToken, http.MethodPost, "/api/chat-groups/connect-requests", map[string]any{"context_type": "donation", "context_id": 1}, wantInvalidGroupInput("context_type, context_id, and message are required.")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var code int
			var body map[string]any
			if tc.method == http.MethodDelete {
				code, body = deleteAs(t, tc.router, tc.token, tc.path)
			} else {
				code, body = postAs(t, tc.router, tc.token, tc.path, tc.body)
			}
			assertChatGroupRefusal(t, code, body, tc.want)
		})
	}
}

// ─── 500 ─────────────────────────────────────────────────────────────────

// TestChatGroupRoutes_DatabaseErrorCarriesItsCode points each handler's store
// at a schema missing the one table its failing query reads, while auth and
// lifecycle keep the real pool, so the store call itself fails.
func TestChatGroupRoutes_DatabaseErrorCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindTeam, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	staffToken := tokenForStaffUser(t, pool, staff)
	donorToken := tokenForChatGroupUser(t, pool, donor)

	cases := []struct {
		name    string
		missing string // the table the store cannot see
		token   string
		method  string
		path    string
		mount   func(r *gin.Engine, h *ChatGroupHandler)
	}{
		{"admin group list", "chat_group_threads", staffToken, http.MethodGet, "/api/admin/chat-groups",
			func(r *gin.Engine, h *ChatGroupHandler) { adminGroup(r, pool).GET("/admin/chat-groups", h.AdminList) }},
		{"admin messages", "chat_group_messages", staffToken, http.MethodGet, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID),
			func(r *gin.Engine, h *ChatGroupHandler) {
				adminGroup(r, pool).GET("/admin/chat-groups/:id/messages", h.AdminMessages)
			}},
		{"admin contact blocks", "chat_group_contact_blocks", staffToken, http.MethodGet, fmt.Sprintf("/api/admin/chat-groups/%d/contact-blocks", groupID),
			func(r *gin.Engine, h *ChatGroupHandler) {
				adminGroup(r, pool).GET("/admin/chat-groups/:id/contact-blocks", h.AdminContactBlocks)
			}},
		{"admin connect-request list", "chat_group_connect_requests", staffToken, http.MethodGet, "/api/admin/chat-groups/connect-requests",
			func(r *gin.Engine, h *ChatGroupHandler) {
				adminGroup(r, pool).GET("/admin/chat-groups/connect-requests", h.AdminListConnectRequests)
			}},
		{"member group list", "chat_group_threads", donorToken, http.MethodGet, "/api/chat-groups",
			func(r *gin.Engine, h *ChatGroupHandler) { memberGroup(r, pool).GET("/chat-groups", h.List) }},
		{"member mark read", "chat_group_reads", donorToken, http.MethodPost, fmt.Sprintf("/api/chat-groups/%d/read", groupID),
			func(r *gin.Engine, h *ChatGroupHandler) {
				memberGroup(r, pool).POST("/chat-groups/:id/read", h.MarkRead)
			}},
		{"member connect-request list", "chat_group_connect_requests", donorToken, http.MethodGet, "/api/chat-groups/connect-requests/mine",
			func(r *gin.Engine, h *ChatGroupHandler) {
				memberGroup(r, pool).GET("/chat-groups/connect-requests/mine", h.MyConnectRequests)
			}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gin.SetMode(gin.TestMode)
			h := NewChatGroupHandler(newStoreWithoutTables(t, pool, tc.missing), notify.New(pool), permissions.New(pool), pool)
			r := gin.New()
			tc.mount(r, h)

			var code int
			var body map[string]any
			if tc.method == http.MethodPost {
				code, body = postAs(t, r, tc.token, tc.path, map[string]any{"last_read_msg_id": 1})
			} else {
				code, body = getAs(t, r, tc.token, tc.path)
			}
			assertChatGroupRefusal(t, code, body, wantChatGroupServerError)
		})
	}
}

// ─── Helpers ─────────────────────────────────────────────────────────────

// adminGroup and memberGroup mount the auth chains the other chat-group test
// routers use, on the real pool.
func adminGroup(r *gin.Engine, pool *pgxpool.Pool) *gin.RouterGroup {
	return r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
}

func memberGroup(r *gin.Engine, pool *pgxpool.Pool) *gin.RouterGroup {
	return r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
}

// newStoreWithoutTables returns a chatgroups store whose connections see every
// public table except missing, through views in a schema created for this
// test and dropped when it ends.
func newStoreWithoutTables(t *testing.T, pool *pgxpool.Pool, missing string) *chatgroups.Store {
	t.Helper()
	ctx := context.Background()
	schema := fmt.Sprintf("chat_group_refusal_%d", chatGroupUserSeq)
	chatGroupUserSeq++
	if _, err := pool.Exec(ctx, fmt.Sprintf(`
		DO $$
		DECLARE t text;
		BEGIN
		  EXECUTE 'CREATE SCHEMA %[1]s';
		  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '%[2]s' LOOP
		    EXECUTE format('CREATE VIEW %[1]s.%%I AS SELECT * FROM public.%%I', t, t);
		  END LOOP;
		END $$`, schema, missing)); err != nil {
		t.Fatalf("create schema without %s: %v", missing, err)
	}
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DROP SCHEMA `+schema+` CASCADE`); err != nil {
			t.Logf("cleanup: drop schema %s: %v", schema, err)
		}
	})
	cfg, err := pgxpool.ParseConfig(os.Getenv("TEST_DATABASE_URL"))
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL: %v", err)
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	broken, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatalf("connect with search_path %s: %v", schema, err)
	}
	t.Cleanup(broken.Close)
	return chatgroups.New(broken)
}

// deleteAs sends an authenticated DELETE and decodes the JSON reply.
func deleteAs(t *testing.T, r *gin.Engine, token, path string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodDelete, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return decodeRecorder(t, w)
}

// decodeRecorder returns a recorded response's status and JSON body.
func decodeRecorder(t *testing.T, w *httptest.ResponseRecorder) (int, map[string]any) {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return w.Code, out
}
