// chat_lifecycle_fixtures_test.go — the seeding and routing half of the chat
// lifecycle suite, split out of chat_lifecycle_test.go to keep both files
// under the repo's 500-line limit.
//
// Nothing here asserts anything. It builds one real thread in each of the
// four chat systems — including the parent rows each one requires (a marriage
// profile and meeting request, a mission signup and beneficiary case) — and
// mounts the routes behind main.go's gates, participant and admin alike,
// because the middleware is what makes the lifecycle actions staff-only. The
// chain each group gets is spelled out on newLifecycleRouter.
//
// Every fixture removes what it wrote in its own t.Cleanup: the suite must
// leave the shared test database exactly as it found it.
package handlers

import (
	"context"
	"fmt"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/staffchat"
)

// ─── Seeding one thread per chat system ─────────────────────────────────

// chatFixture is one seeded thread, described in the terms the tests need:
// which system it belongs to, who may post into it, and where its messages
// land so a refusal can be proved by counting them.
type chatFixture struct {
	Kind        chatlifecycle.Kind
	ThreadTable string
	MsgTable    string
	ThreadID    int64
	SenderID    int64 // a participant allowed to post when the thread is open
	SendPath    string
	// MsgIDColumn is the column on MsgTable that points back at ThreadID.
	// Every pre-existing system calls it "thread_id"; chat_group_messages
	// (migration 120) calls it "group_id" instead, since a group is not a
	// "thread" in this schema's vocabulary. countRows needs this to build a
	// query that actually matches a column that exists.
	MsgIDColumn string
}

func seedDonorChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	donor := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by)
		 VALUES ($1, $2, 'active', $1) RETURNING id`, donor, owner).Scan(&id); err != nil {
		t.Fatalf("insert chat thread: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_contact_blocks WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'chat_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return chatFixture{chatlifecycle.KindDonor, "chat_threads", "chat_messages", id, donor,
		fmt.Sprintf("/api/chats/%d/messages", id), "thread_id"}
}

func seedStaffChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	a := makeLifecycleUser(t, pool, "employee")
	b := makeLifecycleUser(t, pool, "employee")
	lo, hi := a, b
	if lo > hi {
		lo, hi = hi, lo
	}
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO staff_chat_threads (user_a_id, user_b_id) VALUES ($1, $2) RETURNING id`,
		lo, hi).Scan(&id); err != nil {
		t.Fatalf("insert staff thread: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM staff_chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM staff_chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'staff_chat_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM staff_chat_threads WHERE id = $1`, id)
	})
	return chatFixture{chatlifecycle.KindStaff, "staff_chat_threads", "staff_chat_messages", id, a,
		fmt.Sprintf("/api/admin/staff-chats/%d/messages", id), "thread_id"}
}

func seedMarriageChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	ctx := context.Background()
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	lifecycleSeq++
	var profileID, requestID, id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code) VALUES ($1, $2) RETURNING id`,
		owner, fmt.Sprintf("MRG-LC-%d", lifecycleSeq)).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id) VALUES ($1, $2) RETURNING id`,
		requester, profileID).Scan(&requestID); err != nil {
		t.Fatalf("insert meeting request: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_chat_threads (meeting_request_id, profile_id, requester_user_id, owner_user_id, status)
		 VALUES ($1, $2, $3, $4, 'active') RETURNING id`,
		requestID, profileID, requester, owner).Scan(&id); err != nil {
		t.Fatalf("insert marriage thread: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'marriage_chat_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `UPDATE marriage_meeting_requests SET thread_id = NULL WHERE id = $1`, requestID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_threads WHERE id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_meeting_requests WHERE id = $1`, requestID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})
	return chatFixture{chatlifecycle.KindMarriage, "marriage_chat_threads", "marriage_chat_messages", id, requester,
		fmt.Sprintf("/api/marriage/chats/%d/messages", id), "thread_id"}
}

// seedCaseChat and the case-chats routes it fed were removed by OPOS #25284
// Phase 4, which retired casevolchat's direct volunteer↔beneficiary
// messaging entirely: there is no more handler or route to seed a fixture
// for, and KindCase is no longer in chatlifecycle.Systems(). See
// chatlifecycle.go and casevolchat.go.

func seedGroupChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	ctx := context.Background()
	member := makeLifecycleUser(t, pool, "user")
	staff := makeLifecycleUser(t, pool, "employee")
	var id, memberRowID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_group_threads (kind, created_by_staff_id) VALUES ('masked', $1) RETURNING id`,
		staff).Scan(&id); err != nil {
		t.Fatalf("insert chat group thread: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
		 VALUES ($1, $2, 'donor', true, 'Donor 1', $3) RETURNING id`,
		id, member, staff).Scan(&memberRowID); err != nil {
		t.Fatalf("insert chat group member: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_contact_blocks WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_reads WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_messages WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'chat_group_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, id)
	})
	return chatFixture{chatlifecycle.KindGroup, "chat_group_threads", "chat_group_messages", id, member,
		fmt.Sprintf("/api/chat-groups/%d/messages", id), "group_id"}
}

// ─── The router, wired with main.go's gates ─────────────────────────────

// newLifecycleRouter mounts every send route plus the staff-only lifecycle
// and delete routes behind main.go's gates. The middleware is the point: it is
// what makes these actions staff-only.
//
// The participant routes get main.go's full chain: the authed group's
// RequireBearer + RequireApproved, plus RequireNotGuest on each send route, so
// no test here can pass a guest send that production refuses (OPOS #26357).
//
// The admin routes get main.go's full admin chain too (OPOS #26367):
//   - the admin group's RequireAdmin and RequireDeletePassword, so a staff
//     DELETE has to carry the acting staff member's own password, exactly as
//     the dashboard sends it (see
//     TestChatLifecycle_DeleteTrashesAndRestoreBringsBackMessages);
//   - each route's own perm() gate: messages/* for the donor, staff and group
//     chats, marriage/* for the marriage chat. The staff-chat list and send
//     routes carry no perm() gate in main.go, so they carry none here.
func newLifecycleRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	n := notify.New(pool)
	perms := permissions.New(pool)
	// perm mirrors main.go's helper of the same name.
	perm := func(module, action string) gin.HandlerFunc {
		return auth.RequirePermission(perms, module, action)
	}

	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)
	staffH := NewStaffChatHandler(staffchat.New(pool), n, pool)
	lifeH := NewChatLifecycleHandler(pool)

	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(tokens), auth.RequireApproved())
	participant.POST("/chats/:id/messages", auth.RequireNotGuest(), chatH.PostMessage)
	participant.GET("/chats", chatH.List)
	participant.GET("/chats/:id/messages", chatH.Messages)
	participant.POST("/marriage/chats/:id/messages", auth.RequireNotGuest(), marriageH.PostMessage)
	participant.GET("/marriage/chats", marriageH.List)

	admin := r.Group("/api", auth.RequireAdmin(tokens), RequireDeletePassword(pool))
	admin.POST("/admin/staff-chats/:id/messages", staffH.PostMessage)
	admin.GET("/admin/staff-chats", staffH.List)
	admin.GET("/admin/chats", perm("messages", "view"), chatH.AdminList)
	admin.GET("/admin/marriage/chats", perm("marriage", "view"), marriageH.AdminList)
	admin.POST("/admin/chats/:id/lifecycle", perm("messages", "edit"), lifeH.Apply(chatlifecycle.KindDonor))
	admin.POST("/admin/staff-chats/:id/lifecycle", perm("messages", "edit"), lifeH.Apply(chatlifecycle.KindStaff))
	admin.POST("/admin/marriage/chats/:id/lifecycle", perm("marriage", "edit"), lifeH.Apply(chatlifecycle.KindMarriage))
	admin.DELETE("/admin/chats/:id", perm("messages", "delete"), lifeH.Delete(chatlifecycle.KindDonor))
	admin.DELETE("/admin/staff-chats/:id", perm("messages", "delete"), lifeH.Delete(chatlifecycle.KindStaff))
	admin.DELETE("/admin/marriage/chats/:id", perm("marriage", "delete"), lifeH.Delete(chatlifecycle.KindMarriage))

	groupsStore := chatgroups.New(pool)
	groupsH := NewChatGroupHandler(groupsStore, n, nil, pool)
	participant.POST("/chat-groups/:id/messages", auth.RequireNotGuest(), groupsH.PostMessage)
	admin.POST("/admin/chat-groups/:id/lifecycle", perm("messages", "edit"), lifeH.Apply(chatlifecycle.KindGroup))
	admin.DELETE("/admin/chat-groups/:id", perm("messages", "delete"), lifeH.Delete(chatlifecycle.KindGroup))
	return r
}

// allFixtures seeds one thread in each of the four ACTIVELY REACHABLE systems
// (chatlifecycle.Systems()) — donor, marriage, staff, and group. KindCase is
// deliberately excluded: OPOS #25284 Phase 4 retired casevolchat's direct
// volunteer↔beneficiary messaging entirely, so it is no longer in
// chatlifecycle.Systems() and has no route left to fixture.
func allFixtures(t *testing.T, pool *pgxpool.Pool) []chatFixture {
	return []chatFixture{
		seedDonorChat(t, pool),
		seedMarriageChat(t, pool),
		seedStaffChat(t, pool),
		seedGroupChat(t, pool),
	}
}
