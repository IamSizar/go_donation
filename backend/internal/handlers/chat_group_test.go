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

// makeChatGroupStaffUser is makeChatGroupUser plus a real staff_tier on the
// users row. makeChatGroup's staffID parameter (created_by_staff_id) is NOT
// itself a group member and carries no tier at all, so it cannot exercise
// the contact filter's staff exemption — a test proving that exemption, or
// proving it does NOT leak into masked-group filtering by accident, needs a
// user that is both an actual chat_group_members row AND permissions.TierFrom
// != TierUser on the users table, which is what this produces.
func makeChatGroupStaffUser(t *testing.T, pool *pgxpool.Pool, name, tier string) int64 {
	t.Helper()
	ctx := context.Background()
	chatGroupUserSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, staff_tier, registration_status) VALUES ($1, 1, 1, $2, 'approved') RETURNING id`,
		fmt.Sprintf("9647720%06d", chatGroupUserSeq), tier,
	).Scan(&id); err != nil {
		t.Fatalf("insert staff user: %v", err)
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
	// staffMember is a REAL staff-tier user who is also an actual member of
	// this group (role_in_group "staff") — not just staffID/
	// created_by_staff_id, which is not a member at all and carries no
	// tier. A masked group ALWAYS includes staff by construction, so a
	// donor's message must still be filtered even though the group's
	// roster contains a staff-tier party. Without a real staff member
	// present here, this test could not catch a regression where someone
	// reintroduces the donor↔owner chat's "any staff party → skip
	// filtering entirely" exemption into this file.
	staffMember := makeChatGroupStaffUser(t, pool, "Case Worker", "supervisor")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: staffMember, RoleInGroup: "staff"},
	})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422 — a donor's message must be filtered even though the group has a staff member (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 0 {
		t.Fatalf("chat_group_messages has %d rows after a refused message; want 0", n)
	}
}

func TestChatGroupPostMessage_StaffMemberExemptFromContactFilter(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	// The SENDER here is a staff-tier user who is themselves a member of
	// the masked group — K19's mediator relaying a number on someone's
	// behalf, mirroring chat_contact_block_test.go's
	// TestContactBlock_StaffSenderIsExempt for the donor↔owner chat.
	staffMember := makeChatGroupStaffUser(t, pool, "Case Worker", "supervisor")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: staffMember, RoleInGroup: "staff"},
	})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, staffMember),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call the coordinator on 07701234567"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a staff relay must not be filtered (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestChatGroupPostMessage_RefusesNonMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	outsider := makeChatGroupUser(t, pool, "Outsider")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, outsider),
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": "call me on 07701234567"})

	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 — an outsider must be rejected as a non-member before the lifecycle gate or contact filter ever run (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 0 {
		t.Fatalf("chat_group_messages has %d rows; want 0", n)
	}
	var blocks int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_contact_blocks WHERE group_id = $1`, groupID).Scan(&blocks); err != nil {
		t.Fatalf("count contact blocks: %v", err)
	}
	if blocks != 0 {
		t.Fatalf("chat_group_contact_blocks has %d rows for a non-member's message; want 0 — the contact filter must never run before membership is checked", blocks)
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

func TestChatGroupMarkRead_RefusesNonMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	outsider := makeChatGroupUser(t, pool, "Outsider")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	msgID, err := s.PostMessage(context.Background(), groupID, donor, "one")
	if err != nil {
		t.Fatalf("seed message: %v", err)
	}

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, outsider),
		fmt.Sprintf("/api/chat-groups/%d/read", groupID), map[string]int64{"last_read_msg_id": msgID})

	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 — an outsider must not be able to create a read cursor for a group they don't belong to (body %v)", code, body)
	}
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_reads WHERE group_id = $1 AND user_id = $2`,
		groupID, outsider).Scan(&n); err != nil {
		t.Fatalf("count read cursor: %v", err)
	}
	if n != 0 {
		t.Fatalf("chat_group_reads has %d rows for a non-member; want 0", n)
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

func newAdminChatGroupRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
	admin.GET("/admin/chat-groups", h.AdminList)
	admin.POST("/admin/chat-groups", h.AdminCreateGroup)
	admin.GET("/admin/chat-groups/:id", h.AdminGetGroup)
	admin.POST("/admin/chat-groups/:id/members", h.AdminAddMember)
	admin.DELETE("/admin/chat-groups/:id/members/:userId", h.AdminRemoveMember)
	return r, h
}

func tokenForStaffUser(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET staff_tier = 'admin' WHERE id = $1`, userID); err != nil {
		t.Fatalf("promote to staff: %v", err)
	}
	return tokenForChatGroupUser(t, pool, userID)
}

func TestAdminCreateGroup_CreatesMaskedGroup(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind": "masked",
		"members": []map[string]any{
			{"user_id": donor, "role_in_group": "donor"},
		},
	})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	groupIDF, ok := body["group_id"].(float64)
	if !ok || groupIDF <= 0 {
		t.Fatalf("group_id missing or invalid: %v", body)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		id := int64(groupIDF)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
}

func TestAdminCreateGroup_RejectsInvalidKind(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":    "bogus",
		"members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}},
	})

	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
}

func TestAdminAddMemberAndRemoveMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": beneficiary, "role_in_group": "beneficiary"})
	if code != http.StatusOK {
		t.Fatalf("add member: status = %d, want 200 (body %v)", code, body)
	}

	getCode, getBody := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))
	if getCode != http.StatusOK {
		t.Fatalf("get group: status = %d, want 200 (body %v)", getCode, getBody)
	}
	group, _ := getBody["group"].(map[string]any)
	members, _ := group["members"].([]any)
	if len(members) != 2 {
		t.Fatalf("got %d members after add, want 2", len(members))
	}

	req := httptest.NewRequest(http.MethodDelete,
		fmt.Sprintf("/api/admin/chat-groups/%d/members/%d", groupID, beneficiary), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("remove member: status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}
}
