// chat_group_test.go — HTTP-level tests for OPOS #25284 Phase 2's chat-group
// routes. Grown across Tasks 5-8 as each handler method is added. Needs a
// throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_http
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_http?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatGroup -v
package handlers

import (
	"bytes"
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
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

func newChatGroupPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chat-group HTTP integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

var chatGroupUserSeq int

func makeChatGroupUser(t *testing.T, pool *pgxpool.Pool, name string) int64 {
	t.Helper()
	ctx := context.Background()
	chatGroupUserSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status) VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("9647720%06d", chatGroupUserSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
		id, name,
	); err != nil {
		t.Fatalf("insert profile: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func makeChatGroup(t *testing.T, pool *pgxpool.Pool, staffID int64, kind chatgroups.Kind, members []chatgroups.MemberInput) int64 {
	t.Helper()
	s := chatgroups.New(pool)
	title := ""
	if kind == chatgroups.KindTeam {
		title = "Test team"
	}
	id, err := s.CreateGroup(context.Background(), kind, title, staffID, members)
	if err != nil {
		t.Fatalf("create group: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_contact_blocks WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_reads WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_messages WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
	return id
}

// newChatGroupRouter wires the mobile chat-group routes with the same
// middleware main.go uses.
func newChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)))
	participant.GET("/chat-groups", h.List)
	participant.GET("/chat-groups/:id/messages", h.Messages)
	return r, h
}

func tokenForChatGroupUser(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), userID, "chat-group-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_access_tokens WHERE user_id = $1`, userID)
	})
	return session.AccessToken
}

func getAs(t *testing.T, r *gin.Engine, token, path string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func TestChatGroupList_ReturnsCallersGroups(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, donor), "/api/chat-groups")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d groups, want 1", len(items))
	}
}

func TestChatGroupMessages_RefusesNonMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	outsider := makeChatGroupUser(t, pool, "Outsider")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, outsider), fmt.Sprintf("/api/chat-groups/%d/messages", groupID))

	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body %v)", code, body)
	}
}

func postAs(t *testing.T, r *gin.Engine, token, path string, body any) (int, map[string]any) {
	t.Helper()
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func countGroupMessages(t *testing.T, pool *pgxpool.Pool, groupID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_messages WHERE group_id = $1`, groupID).Scan(&n); err != nil {
		t.Fatalf("count messages: %v", err)
	}
	return n
}

func TestChatGroupPostMessage_MemberCanPost(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "hello group"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestChatGroupPostMessage_RefusesContactDetailsInMaskedGroup(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 0 {
		t.Fatalf("chat_group_messages has %d rows after a refused message; want 0", n)
	}
}

func TestChatGroupPostMessage_TeamGroupAllowsContactDetails(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	volunteer := makeChatGroupUser(t, pool, "Volunteer Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindTeam, []chatgroups.MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, volunteer),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — team groups are never filtered (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestChatGroupMarkRead_AdvancesCursor(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	msgID, err := s.PostMessage(context.Background(), groupID, donor, "one")
	if err != nil {
		t.Fatalf("seed message: %v", err)
	}

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/read", groupID), map[string]int64{"last_read_msg_id": msgID})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	var last int64
	if err := pool.QueryRow(context.Background(),
		`SELECT last_read_msg_id FROM chat_group_reads WHERE group_id = $1 AND user_id = $2`,
		groupID, donor).Scan(&last); err != nil {
		t.Fatalf("read cursor: %v", err)
	}
	if last != msgID {
		t.Fatalf("last_read_msg_id = %d, want %d", last, msgID)
	}
}

// newWriteChatGroupRouter extends newChatGroupRouter with the write routes
// this task adds.
func newWriteChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)))
	participant.GET("/chat-groups", h.List)
	participant.GET("/chat-groups/:id/messages", h.Messages)
	participant.POST("/chat-groups/:id/messages", auth.RequireNotGuest(), h.PostMessage)
	participant.POST("/chat-groups/:id/read", auth.RequireNotGuest(), h.MarkRead)
	return r, h
}
