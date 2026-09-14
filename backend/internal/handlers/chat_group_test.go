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
	"strings"
	"sync"
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
	raiseChatGroupUserIDFloor(t, pool)
	t.Cleanup(pool.Close)
	return pool
}

// chatGroupUserIDFloor mirrors internal/chatgroups/chatgroups_test.go's
// testUserIDFloor (see that file's exact comment for the full rationale):
// on a fresh database users.id starts at 1, and a numeric substring that
// small collides with digits inside the response's own fields (an "id":1,
// a "sender_member_id":1, an RFC3339 timestamp) that are not identity
// leaks at all. TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity
// searches the raw response body for the donor/staff numeric id as an
// unanchored substring specifically to catch a leak through ANY field, so
// it needs every id to be wide enough (9+ digits) that such a collision
// can never happen by chance — only a genuine leak of the real id can
// produce that substring.
//
// This package is its own test binary/process, separate from
// internal/chatgroups, so chatgroups' sync.Once does not protect it: each
// package that relies on this property needs its own floor-raising call.
const chatGroupUserIDFloor = 700000000

// raiseChatGroupUserIDFloorOnce guards raiseChatGroupUserIDFloor so it runs
// at most once per test binary — see chatGroupUserIDFloor's doc comment.
var raiseChatGroupUserIDFloorOnce sync.Once

// raiseChatGroupUserIDFloor pushes users.id's sequence to at least
// chatGroupUserIDFloor, once per test binary.
//
// This does NOT compute the new value from MAX(id) FROM users, unlike
// internal/chatgroups' equivalent helper — deliberately. `go test ./...`
// runs this package and internal/chatgroups as two separate OS processes
// CONCURRENTLY against the SAME shared Postgres database and the SAME
// physical users.id sequence. MAX(id) FROM users only reflects rows that
// currently exist, and a test's own t.Cleanup deletes its users row (but,
// by both packages' existing convention, never the chat_group_members /
// chat_group_messages rows that referenced it — those are cleaned up by
// group id, separately, and can legitimately still be in use by a
// still-running test in the OTHER process). So at any instant, MAX(id)
// can read back LOWER than ids the other process has already issued and
// is still actively using: this process would then compute
// GREATEST(that stale low max, chatGroupUserIDFloor) and setval the
// shared sequence BACKWARD, and a subsequent nextval() here would reissue
// a number the other process's still-live row already holds — corrupting
// an unrelated test's data (observed as TestChatGroupList_ReturnsCallersGroups
// suddenly seeing an extra, foreign group, because its "fresh" donor id
// collided with another process's real, currently-a-member user).
//
// Reading the SEQUENCE's own last_value instead of the TABLE's MAX(id)
// avoids this: last_value only ever moves forward (via nextval/setval),
// never backward from a concurrent DELETE, so GREATEST(last_value, floor)
// can never retreat the sequence below where either process has already
// pushed it — regardless of how the two processes interleave.
func raiseChatGroupUserIDFloor(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	raiseChatGroupUserIDFloorOnce.Do(func() {
		if _, err := pool.Exec(context.Background(), `
			SELECT setval(
				pg_get_serial_sequence('users', 'id'),
				GREATEST(
					(SELECT last_value FROM pg_sequences
					  WHERE schemaname || '.' || sequencename = pg_get_serial_sequence('users', 'id')),
					(SELECT COALESCE(MAX(id), 0) FROM users),
					$1
				))`,
			chatGroupUserIDFloor,
		); err != nil {
			t.Fatalf("raise test user id floor: %v", err)
		}
	})
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

// TestChatGroupMessages_RefusesNonMember pins the answer an outsider gets
// from the read route — and pins that it is the SAME answer whether or not
// the group has been archived.
//
// The archived subtest is the one with teeth. Messages used to run the
// archived-status gate BEFORE membership was checked (membership was only
// enforced later, inside chatgroups.Store.ListMessagesForMember), so an
// outsider probing an arbitrary group id got a 404 for an archived group and
// a 403 for a live one. That difference is an oracle: it tells someone who
// was never in a group whether staff have archived it. PostMessage and
// MarkRead already check membership first; this asserts Messages does too, by
// requiring both cases to answer 403 identically.
func TestChatGroupMessages_RefusesNonMember(t *testing.T) {
	for _, tc := range []struct {
		name     string
		archived bool
	}{
		{"live group", false},
		{"archived group", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pool := newChatGroupPool(t)
			r, _ := newChatGroupRouter(pool)
			staff := makeChatGroupUser(t, pool, "Staff")
			donor := makeChatGroupUser(t, pool, "Donor Name")
			outsider := makeChatGroupUser(t, pool, "Outsider")
			groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})

			if tc.archived {
				// Set directly: the subject is the READ route's gate order,
				// and the staff archive route is already covered by
				// chat_lifecycle_trash_test.go.
				if _, err := pool.Exec(context.Background(),
					`UPDATE chat_group_threads SET archived_at = CURRENT_TIMESTAMP WHERE id = $1`,
					groupID); err != nil {
					t.Fatalf("archive group: %v", err)
				}
			}

			code, body := getAs(t, r, tokenForChatGroupUser(t, pool, outsider), fmt.Sprintf("/api/chat-groups/%d/messages", groupID))

			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 — a non-member must not learn a group's archived state (body %v)", code, body)
			}
		})
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

// auditRow reads back one chat_group_audit_log row for (groupID, action),
// used by the three OPOS #25634 tests below to prove each admin handler
// actually wrote its audit row — not just that the handler returned 200.
func auditRow(t *testing.T, pool *pgxpool.Pool, groupID int64, action string) (actorStaffID int64, targetUserID *int64) {
	t.Helper()
	if err := pool.QueryRow(context.Background(),
		`SELECT actor_staff_id, target_user_id FROM chat_group_audit_log WHERE group_id = $1 AND action = $2`,
		groupID, action,
	).Scan(&actorStaffID, &targetUserID); err != nil {
		t.Fatalf("query audit row (group %d, action %q): %v", groupID, action, err)
	}
	return actorStaffID, targetUserID
}

// TestAdminCreateGroup_RecordsAuditRow is OPOS #25634's acceptance test for
// AdminCreateGroup: creating a group via the admin route must write a
// chat_group_audit_log row with action='created' for the new group, with no
// target user (group creation has no single target member).
func TestAdminCreateGroup_RecordsAuditRow(t *testing.T) {
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
	groupID := int64(groupIDF)
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})

	actorStaffID, targetUserID := auditRow(t, pool, groupID, "created")
	if actorStaffID != staff {
		t.Fatalf("actor_staff_id = %d, want %d", actorStaffID, staff)
	}
	if targetUserID != nil {
		t.Fatalf("target_user_id = %v, want nil for a 'created' action", *targetUserID)
	}
}

// TestAdminAddMember_RecordsAuditRow is OPOS #25634's acceptance test for
// AdminAddMember: adding a member via the admin route must write a
// chat_group_audit_log row with action='member_added' and target_user_id
// set to the member who was added.
func TestAdminAddMember_RecordsAuditRow(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForStaffUser(t, pool, staff)
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
	})

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": beneficiary, "role_in_group": "beneficiary"})
	if code != http.StatusOK {
		t.Fatalf("add member: status = %d, want 200 (body %v)", code, body)
	}

	actorStaffID, targetUserID := auditRow(t, pool, groupID, "member_added")
	if actorStaffID != staff {
		t.Fatalf("actor_staff_id = %d, want %d", actorStaffID, staff)
	}
	if targetUserID == nil || *targetUserID != beneficiary {
		t.Fatalf("target_user_id = %v, want %d", targetUserID, beneficiary)
	}
}

// TestAdminRemoveMember_RecordsAuditRow is OPOS #25634's acceptance test for
// AdminRemoveMember: removing a member via the admin route must write a
// chat_group_audit_log row with action='member_removed' and target_user_id
// set to the member who was removed.
func TestAdminRemoveMember_RecordsAuditRow(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	token := tokenForStaffUser(t, pool, staff)
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
	})

	req := httptest.NewRequest(http.MethodDelete,
		fmt.Sprintf("/api/admin/chat-groups/%d/members/%d", groupID, beneficiary), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("remove member: status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}

	actorStaffID, targetUserID := auditRow(t, pool, groupID, "member_removed")
	if actorStaffID != staff {
		t.Fatalf("actor_staff_id = %d, want %d", actorStaffID, staff)
	}
	if targetUserID == nil || *targetUserID != beneficiary {
		t.Fatalf("target_user_id = %v, want %d", targetUserID, beneficiary)
	}
}

func newAdminMessagesRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
	admin.GET("/admin/chat-groups/:id/messages", h.AdminMessages)
	admin.POST("/admin/chat-groups/:id/messages", h.AdminPostMessage)
	admin.GET("/admin/chat-groups/:id/contact-blocks", h.AdminContactBlocks)
	return r, h
}

func TestAdminMessages_ShowsRealIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Real Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	if _, err := s.PostMessage(context.Background(), groupID, donor, "hi from donor"); err != nil {
		t.Fatalf("seed message: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	raw, _ := json.Marshal(body)
	if !bytes.Contains(raw, []byte("Donor Real Name")) {
		t.Fatalf("admin view did not carry the real name: %s", raw)
	}
}

func TestAdminPostMessage_PostsAsStaffAndNotifiesMembers(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID),
		map[string]string{"body": "we are looking into it"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if n := countGroupMessages(t, pool, groupID); n != 1 {
		t.Fatalf("chat_group_messages has %d rows; want 1", n)
	}
}

func TestAdminContactBlocks_ListsRecordedAttempts(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminMessagesRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	s := chatgroups.New(pool)
	if err := s.RecordContactBlock(context.Background(), groupID, donor, "phone", 1, "call •••"); err != nil {
		t.Fatalf("seed contact block: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/contact-blocks", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d contact blocks, want 1", len(items))
	}
}

// lookUpUserPhone reads back the phone number makeChatGroupUser /
// makeChatGroupStaffUser seeded for userID, so a test can assert that
// number never leaks — a phone number is exactly the kind of leak-through-
// an-unanticipated-field the raw-string sweep in
// TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity exists to catch.
func lookUpUserPhone(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	var phone string
	if err := pool.QueryRow(context.Background(),
		`SELECT phone FROM users WHERE id = $1`, userID).Scan(&phone); err != nil {
		t.Fatalf("look up phone for user %d: %v", userID, err)
	}
	return phone
}

// TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity is the single
// highest-priority test for this phase (design spec §7): it proves, at the
// HTTP layer, that Phase 1's structural masking guarantee survives the trip
// through gin.Context.JSON. It searches the RAW response body string, not
// just the typed fields a hand-picked assertion might miss.
//
// The group has THREE senders — a donor, a beneficiary reading the
// response, and a real staff-tier MEMBER (not just the group's
// created_by_staff_id, which is never itself a member and never posts —
// see makeChatGroupStaffUser's doc comment) — so both masking branches
// ListMessagesForMember's SQL implements are exercised: a member's message
// collapses to their masked_label ("Donor 1"), and a staff member's
// message collapses to the fixed "Support" label, never the staff
// member's own real name or id.
func TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupStaffUser(t, pool, "Staff Real Name", "supervisor")
	donor := makeChatGroupUser(t, pool, "Donor Secret Real Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Secret Real Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
		{UserID: staff, RoleInGroup: "staff"},
	})
	donorPhone := lookUpUserPhone(t, pool, donor)
	beneficiaryPhone := lookUpUserPhone(t, pool, beneficiary)
	staffPhone := lookUpUserPhone(t, pool, staff)
	donorToken := tokenForChatGroupUser(t, pool, donor)
	staffToken := tokenForChatGroupUser(t, pool, staff)

	if code, body := postAs(t, r, donorToken, fmt.Sprintf("/api/chat-groups/%d/messages", groupID),
		map[string]string{"body": "hello from the donor side"}); code != http.StatusOK {
		t.Fatalf("seed donor message: status = %d (body %v)", code, body)
	}
	if code, body := postAs(t, r, staffToken, fmt.Sprintf("/api/chat-groups/%d/messages", groupID),
		map[string]string{"body": "hello from the case worker"}); code != http.StatusOK {
		t.Fatalf("seed staff message: status = %d (body %v)", code, body)
	}

	req := httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/chat-groups/%d/messages", groupID), nil)
	req.Header.Set("Authorization", "Bearer "+tokenForChatGroupUser(t, pool, beneficiary))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}

	raw := w.Body.String()
	forbidden := []string{
		"Donor Secret Real Name",
		"Beneficiary Secret Real Name",
		"Staff Real Name",
		fmt.Sprintf("%d", donor),
		fmt.Sprintf("%d", staff),
		donorPhone,
		beneficiaryPhone,
		staffPhone,
	}
	for _, needle := range forbidden {
		if strings.Contains(raw, needle) {
			t.Fatalf("masked-group response leaks %q: %s", needle, raw)
		}
	}
	if !strings.Contains(raw, "Donor 1") {
		t.Fatalf("expected the donor's masked label \"Donor 1\" somewhere in the response: %s", raw)
	}
	if !strings.Contains(raw, "Support") {
		t.Fatalf("expected the staff member's message to carry the fixed \"Support\" label somewhere in the response: %s", raw)
	}
}

func newConnectRequestRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)))
	participant.POST("/chat-groups/connect-requests", auth.RequireNotGuest(), h.SubmitConnectRequest)
	participant.GET("/chat-groups/connect-requests/mine", h.MyConnectRequests)
	return r, h
}

func TestSubmitConnectRequest_CreatesRequest(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	donor := makeChatGroupUser(t, pool, "Donor Name")

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor), "/api/chat-groups/connect-requests",
		map[string]any{"context_type": "donation", "context_id": 1, "message": "please connect me to the campaign owner"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if _, ok := body["request_id"]; !ok {
		t.Fatalf("no request_id in response: %v", body)
	}
}

func TestSubmitConnectRequest_RejectsInvalidContextType(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	donor := makeChatGroupUser(t, pool, "Donor Name")

	code, body := postAs(t, r, tokenForChatGroupUser(t, pool, donor), "/api/chat-groups/connect-requests",
		map[string]any{"context_type": "bogus", "context_id": 1, "message": "hi"})

	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
}

func TestMyConnectRequests_ReturnsOwnRequestsOnly(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	donorA := makeChatGroupUser(t, pool, "Donor A")
	donorB := makeChatGroupUser(t, pool, "Donor B")
	s := chatgroups.New(pool)
	if _, err := s.SubmitConnectRequest(context.Background(), donorA, "donation", 1, nil, "a"); err != nil {
		t.Fatalf("submit A: %v", err)
	}
	if _, err := s.SubmitConnectRequest(context.Background(), donorB, "donation", 2, nil, "b"); err != nil {
		t.Fatalf("submit B: %v", err)
	}

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, donorA), "/api/chat-groups/connect-requests/mine")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d requests, want 1 (only donorA's own)", len(items))
	}
}

// TestMyConnectRequests_NeverExposesStaffIdentity proves the fix applied to
// this task's brief: chatgroups.ConnectRequest carries a DecidedByStaff
// field (json tag decided_by_staff_id) that names the real staff member who
// approved or declined a request, and MyConnectRequests must never let that
// reach the requester — design spec §9 gives every requester a collective
// "Support" label for staff, never an individual admin's identity. This
// searches the RAW response body for the JSON key itself, the same
// structural-leak-proof style TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity
// uses above: a field-by-field assertion could miss the DTO ever being
// swapped back out for the store type by accident, but a raw substring
// search on the tag name cannot.
func TestMyConnectRequests_NeverExposesStaffIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff Real Name")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	s := chatgroups.New(pool)
	requestID, err := s.SubmitConnectRequest(context.Background(), donor, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit request: %v", err)
	}
	if err := s.DeclineConnectRequest(context.Background(), requestID, staff, "not eligible right now"); err != nil {
		t.Fatalf("decline request: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/chat-groups/connect-requests/mine", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForChatGroupUser(t, pool, donor))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", w.Code, w.Body.String())
	}
	raw := w.Body.String()
	if strings.Contains(raw, "decided_by_staff_id") {
		t.Fatalf("MyConnectRequests response leaks the staff-identity field \"decided_by_staff_id\": %s", raw)
	}
	if !strings.Contains(raw, "not eligible right now") {
		t.Fatalf("expected the decline reason to still be visible to the requester: %s", raw)
	}
}

func newAdminConnectRequestRouter(pool *pgxpool.Pool) (*gin.Engine, *ChatGroupHandler) {
	gin.SetMode(gin.TestMode)
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), permissions.New(pool), pool)
	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(auth.NewTokenStore(pool)))
	admin.GET("/admin/chat-groups/connect-requests", h.AdminListConnectRequests)
	admin.GET("/admin/chat-groups/connect-requests/:id", h.AdminGetConnectRequest)
	admin.POST("/admin/chat-groups/connect-requests/:id/approve", h.AdminApproveConnectRequest)
	admin.POST("/admin/chat-groups/connect-requests/:id/decline", h.AdminDeclineConnectRequest)
	return r, h
}

func TestAdminListConnectRequests_ReturnsAll(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	s := chatgroups.New(pool)
	reqID, err := s.SubmitConnectRequest(context.Background(), donor, "donation", 1, nil, "please")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, "/api/admin/chat-groups/connect-requests")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)

	// Find the request we just created, rather than asserting the total count.
	// The test DB is shared across all tests in this package, so the total count
	// can be higher than 1 due to other tests leaving rows behind.
	var found map[string]any
	for _, item := range items {
		if itemMap, ok := item.(map[string]any); ok {
			if id, ok := itemMap["id"].(float64); ok && id == float64(reqID) {
				found = itemMap
				break
			}
		}
	}
	if found == nil {
		t.Fatalf("request %d not found in admin list (got %d total items)", reqID, len(items))
	}
	if found["context_type"] != "donation" {
		t.Fatalf("context_type = %v, want \"donation\"", found["context_type"])
	}
	if found["status"] != "pending" {
		t.Fatalf("status = %v, want \"pending\"", found["status"])
	}
}

// TestAdminApproveConnectRequest_CreatesUsableGroup proves the whole
// submit→list-as-admin→approve→post→read-back chain end to end (design spec
// §7 point 1), not just each endpoint in isolation: submit happens over HTTP
// (not the Store directly), the submitted request must show up in the admin
// inbox BEFORE it is approved, and after approval the requester must be able
// to both post a message into the new group AND read it back.
func TestAdminApproveConnectRequest_CreatesUsableGroup(t *testing.T) {
	pool := newChatGroupPool(t)
	adminR, _ := newAdminConnectRequestRouter(pool)
	mobileR, _ := newWriteChatGroupRouter(pool)
	connectR, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	donorToken := tokenForChatGroupUser(t, pool, donor)

	// Step 1: submit over HTTP, exactly as the mobile app would.
	submitCode, submitBody := postAs(t, connectR, donorToken, "/api/chat-groups/connect-requests",
		map[string]any{"context_type": "donation", "context_id": 1, "message": "please connect me"})
	if submitCode != http.StatusOK {
		t.Fatalf("submit: status = %d, want 200 (body %v)", submitCode, submitBody)
	}
	reqIDF, ok := submitBody["request_id"].(float64)
	if !ok || reqIDF <= 0 {
		t.Fatalf("request_id missing or invalid: %v", submitBody)
	}
	reqID := int64(reqIDF)

	token := tokenForStaffUser(t, pool, staff)

	// Step 2: the submitted request must be visible in the admin inbox before
	// it is ever approved — staff cannot act on a request they can't see.
	listCode, listBody := getAs(t, adminR, token, "/api/admin/chat-groups/connect-requests")
	if listCode != http.StatusOK {
		t.Fatalf("admin list: status = %d, want 200 (body %v)", listCode, listBody)
	}
	listItems, _ := listBody["items"].([]any)
	foundInList := false
	for _, item := range listItems {
		if itemMap, ok := item.(map[string]any); ok {
			if id, ok := itemMap["id"].(float64); ok && id == float64(reqID) {
				foundInList = true
				break
			}
		}
	}
	if !foundInList {
		t.Fatalf("request %d not found in admin list before approval (got %d items)", reqID, len(listItems))
	}

	// Step 3: approve over HTTP.
	code, body := postAs(t, adminR, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
		map[string]any{
			"kind": "masked",
			"members": []map[string]any{
				{"user_id": donor, "role_in_group": "donor"},
			},
		})
	if code != http.StatusOK {
		t.Fatalf("approve: status = %d, want 200 (body %v)", code, body)
	}
	groupIDF, ok := body["group_id"].(float64)
	if !ok || groupIDF <= 0 {
		t.Fatalf("group_id missing or invalid: %v", body)
	}
	groupID := int64(groupIDF)
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_reads WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_messages WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})

	// Step 4: the group is immediately usable — post a message as the
	// (now-member) requester.
	const posted = "hello from the approved group"
	postCode, postBody := postAs(t, mobileR, donorToken,
		fmt.Sprintf("/api/chat-groups/%d/messages", groupID), map[string]string{"body": posted})
	if postCode != http.StatusOK {
		t.Fatalf("post as requester: status = %d, want 200 (body %v)", postCode, postBody)
	}

	// Step 5: read it back as the requester — the whole point of "usable".
	readCode, readBody := getAs(t, mobileR, donorToken, fmt.Sprintf("/api/chat-groups/%d/messages", groupID))
	if readCode != http.StatusOK {
		t.Fatalf("read messages: status = %d, want 200 (body %v)", readCode, readBody)
	}
	readItems, _ := readBody["items"].([]any)
	foundMessage := false
	for _, item := range readItems {
		if itemMap, ok := item.(map[string]any); ok {
			if b, _ := itemMap["body"].(string); b == posted {
				foundMessage = true
				break
			}
		}
	}
	if !foundMessage {
		t.Fatalf("posted message %q not found when read back: %v", posted, readItems)
	}
}

func TestAdminApproveConnectRequest_RejectsMembersWithoutRequester(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	s := chatgroups.New(pool)
	reqID, err := s.SubmitConnectRequest(context.Background(), donor, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
		map[string]any{
			"kind": "masked",
			"members": []map[string]any{
				{"user_id": beneficiary, "role_in_group": "beneficiary"},
			},
		})
	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
}

func TestAdminDeclineConnectRequest_ShowsReasonToRequester(t *testing.T) {
	pool := newChatGroupPool(t)
	adminR, _ := newAdminConnectRequestRouter(pool)
	mobileR, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	s := chatgroups.New(pool)
	reqID, err := s.SubmitConnectRequest(context.Background(), donor, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, adminR, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/decline", reqID),
		map[string]string{"reason": "Not eligible for this campaign."})
	if code != http.StatusOK {
		t.Fatalf("decline: status = %d, want 200 (body %v)", code, body)
	}

	mineCode, mineBody := getAs(t, mobileR, tokenForChatGroupUser(t, pool, donor), "/api/chat-groups/connect-requests/mine")
	if mineCode != http.StatusOK {
		t.Fatalf("mine: status = %d (body %v)", mineCode, mineBody)
	}
	items, _ := mineBody["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d requests, want 1", len(items))
	}
	item, _ := items[0].(map[string]any)
	if item["decline_reason"] != "Not eligible for this campaign." {
		t.Fatalf("decline_reason = %v, want the staff reason", item["decline_reason"])
	}
}

// TestAdminGetConnectRequest_ResolvesDonationContextLabel is the regression
// guard for a Critical bug in resolveConnectContext's "donation" case
// (chat_group_admin.go): donations.amount is VARCHAR(200), not numeric, so
// scanning it into a float64 always failed, the error was discarded, and the
// label silently fell all the way through to the raw "donation #4471"
// fallback — defeating the entire point of resolving context for staff. This
// inserts a REAL donation + campaign row so the happy path is proven to
// actually work, not just that the fallback doesn't crash.
func TestAdminGetConnectRequest_ResolvesDonationContextLabel(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")

	// Column lists match the actual schema (migrations/001_full_v2.sql), not
	// the schema the original finding assumed:
	//   - campaigns has no defaults for title/title_ar/description/
	//     description_ar/address/beneficiaries/goal_amount/raised_amount
	//     (all VARCHAR NOT NULL).
	//   - donations references the donor via `user_id` (not `donor_user_id`),
	//     and requires `message` and `payment_method` (both NOT NULL, no
	//     default) in addition to `amount`.
	ctx := context.Background()
	var campaignID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO campaigns (title, title_ar, description, description_ar, address, beneficiaries, goal_amount, raised_amount)
		VALUES ('Winter Relief', 'إغاثة الشتاء', 'd', 'd', 'a', '1', '1000', '0')
		RETURNING id`,
	).Scan(&campaignID); err != nil {
		t.Fatalf("insert campaign: %v", err)
	}
	var donationID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO donations (user_id, campaign_id, message, amount, payment_method)
		VALUES ($1, $2, 'test donation', '250', 'cash')
		RETURNING id`,
		donor, campaignID,
	).Scan(&donationID); err != nil {
		t.Fatalf("insert donation: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM donations WHERE id = $1`, donationID)
		_, _ = pool.Exec(ctx, `DELETE FROM campaigns WHERE id = $1`, campaignID)
	})

	s := chatgroups.New(pool)
	reqID, err := s.SubmitConnectRequest(ctx, donor, "donation", donationID, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d", reqID))
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	label, _ := body["context_label"].(string)
	if !strings.Contains(label, "250") || !strings.Contains(label, "Winter Relief") {
		t.Fatalf("context_label = %q, want it to mention the donation amount and campaign title", label)
	}
}

// TestSubmitConnectRequest_ResubmittingWhilePendingReturnsSameID is the
// HTTP-level twin of chatgroups_test.go's
// TestSubmitConnectRequestIsIdempotentWhilePending (design spec §7 point 5):
// it confirms the route itself, not just the Store, surfaces resubmit-while-
// pending idempotency — the same id comes back both times.
func TestSubmitConnectRequest_ResubmittingWhilePendingReturnsSameID(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newConnectRequestRouter(pool)
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForChatGroupUser(t, pool, donor)

	body := map[string]any{"context_type": "donation", "context_id": 1, "message": "please connect me"}

	code1, resp1 := postAs(t, r, token, "/api/chat-groups/connect-requests", body)
	if code1 != http.StatusOK {
		t.Fatalf("first submit: status = %d, want 200 (body %v)", code1, resp1)
	}
	id1, _ := resp1["request_id"].(float64)

	code2, resp2 := postAs(t, r, token, "/api/chat-groups/connect-requests", body)
	if code2 != http.StatusOK {
		t.Fatalf("second submit: status = %d, want 200 (body %v)", code2, resp2)
	}
	id2, _ := resp2["request_id"].(float64)

	if id1 == 0 || id1 != id2 {
		t.Fatalf("resubmitting while pending should return the same id: first=%v second=%v", id1, id2)
	}
}
