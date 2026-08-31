// chat_lifecycle_fixtures_test.go — the seeding and routing half of the chat
// lifecycle suite, split out of chat_lifecycle_test.go to keep both files
// under the repo's 500-line limit.
//
// Nothing here asserts anything. It builds one real thread in each of the
// four chat systems — including the parent rows each one requires (a marriage
// profile and meeting request, a mission signup and beneficiary case) — and
// mounts the routes with the SAME middleware main.go uses, because the
// middleware is what makes the lifecycle actions staff-only.
//
// Every fixture removes what it wrote in its own t.Cleanup: the suite must
// leave the shared test database exactly as it found it.
package handlers

import (
	"context"
	"fmt"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
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
		fmt.Sprintf("/api/chats/%d/messages", id)}
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
		fmt.Sprintf("/api/admin/staff-chats/%d/messages", id)}
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
		fmt.Sprintf("/api/marriage/chats/%d/messages", id)}
}

func seedCaseChat(t *testing.T, pool *pgxpool.Pool) chatFixture {
	t.Helper()
	ctx := context.Background()
	volunteer := makeLifecycleUser(t, pool, "user")
	beneficiary := makeLifecycleUser(t, pool, "user")
	lifecycleSeq++
	var missionID, signupID, caseID, id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title) VALUES ($1) RETURNING id`,
		fmt.Sprintf("LC mission %d", lifecycleSeq)).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups (mission_id, user_id) VALUES ($1, $2) RETURNING id`,
		missionID, volunteer).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases (case_code, public_title, user_id) VALUES ($1, $2, $3) RETURNING id`,
		fmt.Sprintf("CSE-LC-%d", lifecycleSeq), "LC case", beneficiary).Scan(&caseID); err != nil {
		t.Fatalf("insert case: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO case_volunteer_chat_threads (signup_id, case_id, volunteer_user_id, beneficiary_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		signupID, caseID, volunteer, beneficiary).Scan(&id); err != nil {
		t.Fatalf("insert case-volunteer thread: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM case_volunteer_chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM case_volunteer_chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM trash_items WHERE source_table = 'case_volunteer_chat_threads' AND row_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM case_volunteer_chat_threads WHERE id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM beneficiary_cases WHERE id = $1`, caseID)
		_, _ = pool.Exec(ctx, `DELETE FROM volunteer_mission_signups WHERE id = $1`, signupID)
		_, _ = pool.Exec(ctx, `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})
	return chatFixture{chatlifecycle.KindCase, "case_volunteer_chat_threads", "case_volunteer_chat_messages", id, volunteer,
		fmt.Sprintf("/api/case-chats/%d/messages", id)}
}

// ─── The router, wired exactly as main.go wires it ──────────────────────

// newLifecycleRouter mounts every send route plus the staff-only lifecycle
// and delete routes, with the SAME middleware main.go uses — RequireBearer on
// the participant routes, RequireAdmin on the admin group. The middleware is
// the point: it is what makes these actions staff-only.
func newLifecycleRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	n := notify.New(pool)

	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)
	staffH := NewStaffChatHandler(staffchat.New(pool), n, pool)
	caseH := NewCaseVolunteerChatHandler(casevolchat.New(pool), n)
	lifeH := NewChatLifecycleHandler(pool)

	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(tokens))
	participant.POST("/chats/:id/messages", chatH.PostMessage)
	participant.GET("/chats", chatH.List)
	participant.GET("/chats/:id/messages", chatH.Messages)
	participant.POST("/marriage/chats/:id/messages", marriageH.PostMessage)
	participant.GET("/marriage/chats", marriageH.List)
	participant.POST("/case-chats/:id/messages", caseH.PostMessage)
	participant.GET("/case-chats", caseH.List)

	admin := r.Group("/api", auth.RequireAdmin(tokens))
	admin.POST("/admin/staff-chats/:id/messages", staffH.PostMessage)
	admin.GET("/admin/staff-chats", staffH.List)
	admin.GET("/admin/chats", chatH.AdminList)
	admin.GET("/admin/marriage/chats", marriageH.AdminList)
	admin.GET("/admin/case-chats", caseH.AdminList)
	admin.POST("/admin/chats/:id/lifecycle", lifeH.Apply(chatlifecycle.KindDonor))
	admin.POST("/admin/staff-chats/:id/lifecycle", lifeH.Apply(chatlifecycle.KindStaff))
	admin.POST("/admin/marriage/chats/:id/lifecycle", lifeH.Apply(chatlifecycle.KindMarriage))
	admin.POST("/admin/case-chats/:id/lifecycle", lifeH.Apply(chatlifecycle.KindCase))
	admin.DELETE("/admin/chats/:id", lifeH.Delete(chatlifecycle.KindDonor))
	admin.DELETE("/admin/staff-chats/:id", lifeH.Delete(chatlifecycle.KindStaff))
	admin.DELETE("/admin/marriage/chats/:id", lifeH.Delete(chatlifecycle.KindMarriage))
	admin.DELETE("/admin/case-chats/:id", lifeH.Delete(chatlifecycle.KindCase))
	return r
}

// allFixtures seeds one thread in each of the four systems.
func allFixtures(t *testing.T, pool *pgxpool.Pool) []chatFixture {
	return []chatFixture{
		seedDonorChat(t, pool),
		seedMarriageChat(t, pool),
		seedStaffChat(t, pool),
		seedCaseChat(t, pool),
	}
}
