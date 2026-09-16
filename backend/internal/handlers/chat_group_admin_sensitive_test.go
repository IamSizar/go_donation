// chat_group_admin_sensitive_test.go — OPOS #26409 (user decision D1): who may
// read a chat group's detail, messages and contact-blocks from the dashboard.
//
// # WHAT THESE PIN
//
// Those three routes name the REAL person behind every masked label. Until
// #26409 main.go gated them with perm("sensitive_data", "view"), which is
// auth.RequirePermission, and that resolves by TIER only. Every other
// identity-revealing endpoint asks canViewContact, which honours Note 31's
// per-employee override first. So the two disagreed in both directions:
//
//   - an admin whose sensitive_data was revoked for them alone still read
//     every masked group's real names;
//   - an employee granted sensitive_data for them alone was refused.
//
// D1 moves the check into the handlers, per user, and scopes it to MASKED
// groups: a TEAM group's members already see each other's real names, so
// messages:view alone is enough there.
//
// The router below mirrors main.go's chain for these routes exactly, as it
// stands after #26409: the admin group's RequireAdmin and
// RequireDeletePassword, then perm("messages", "view"). The middleware is part
// of what is under test — a test that skipped it could pass a request
// production refuses.
//
// Needs the same throwaway Postgres as chat_group_test.go — see
// newChatGroupPool.
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// wantSensitiveRequiredCode is the refusal's machine code, pinned here as a
// literal so renaming it in the handler is a deliberate, visible break for the
// dashboard rather than a silent one.
const wantSensitiveRequiredCode = "sensitive_data_required"

// sensitiveFixtureRealName is the donor's real name in every seeded group. A
// refusal body must never contain it.
const sensitiveFixtureRealName = "Sensitive Donor Secret Name"

// neverExistingGroupID is far beyond any id the test database hands out.
const neverExistingGroupID int64 = 9_000_000_000_000_000

// ─── Router, wired with main.go's gates ─────────────────────────────────

// newAdminGroupReadRouter mounts the admin chat-group READ routes behind the
// chain main.go builds for them after #26409: RequireAdmin and
// RequireDeletePassword on the admin group, then perm("messages", "view") on
// each route. No route carries perm("sensitive_data", "view") any more; the
// masked-group check lives in the handlers.
func newAdminGroupReadRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	perms := permissions.New(pool)
	// perm mirrors main.go's helper of the same name.
	perm := func(module, action string) gin.HandlerFunc {
		return auth.RequirePermission(perms, module, action)
	}
	h := NewChatGroupHandler(chatgroups.New(pool), notify.New(pool), perms, pool)

	r := gin.New()
	admin := r.Group("/api", auth.RequireAdmin(tokens), RequireDeletePassword(pool))
	admin.GET("/admin/chat-groups/:id", perm("messages", "view"), h.AdminGetGroup)
	admin.GET("/admin/chat-groups/:id/messages", perm("messages", "view"), h.AdminMessages)
	admin.GET("/admin/chat-groups/:id/contact-blocks", perm("messages", "view"), h.AdminContactBlocks)
	admin.GET("/admin/chat-groups/connect-requests", perm("messages", "view"), h.AdminListConnectRequests)
	admin.GET("/admin/chat-groups/connect-requests/:id", perm("messages", "view"), h.AdminGetConnectRequest)
	return r
}

// ─── Fixtures ────────────────────────────────────────────────────────────

// adminReadFixture is one seeded group whose three read routes each have
// something to return: a member, a message and a contact block.
type adminReadFixture struct {
	groupID int64
	donorID int64
}

// seedAdminReadGroup creates a group of `kind` with one donor member named
// sensitiveFixtureRealName, one message from that donor and one refused
// contact-details attempt. Cleanup is makeChatGroup's and makeChatGroupUser's.
func seedAdminReadGroup(t *testing.T, pool *pgxpool.Pool, kind chatgroups.Kind) adminReadFixture {
	t.Helper()
	ctx := context.Background()
	creator := makeChatGroupStaffUser(t, pool, "Group Creator", "admin")
	// A team group takes only volunteers and staff, so the fixture's one
	// member is a volunteer account there, and a donor in a masked group —
	// which is where a donor belongs.
	memberRoleID, roleInGroup := 1, "donor"
	if kind == chatgroups.KindTeam {
		memberRoleID, roleInGroup = 3, "volunteer"
	}
	donor := makeChatGroupRoleUser(t, pool, sensitiveFixtureRealName, memberRoleID)
	groupID := makeChatGroup(t, pool, creator, kind,
		[]chatgroups.MemberInput{{UserID: donor, RoleInGroup: roleInGroup}})
	store := chatgroups.New(pool)
	if _, err := store.PostMessage(ctx, groupID, donor, "hello from the donor"); err != nil {
		t.Fatalf("seed message: %v", err)
	}
	if err := store.RecordContactBlock(ctx, groupID, donor, "phone", 1, "call me on ••••"); err != nil {
		t.Fatalf("seed contact block: %v", err)
	}
	return adminReadFixture{groupID: groupID, donorID: donor}
}

// adminGroupReadPath is one of the three identity-revealing read routes.
type adminGroupReadPath struct {
	name string
	path string
}

// adminGroupReadPaths lists the three routes D1 gates, for one group. Every
// test walks this same list, so no route can be left out of one of them.
func adminGroupReadPaths(groupID int64) []adminGroupReadPath {
	return []adminGroupReadPath{
		{"group detail", fmt.Sprintf("/api/admin/chat-groups/%d", groupID)},
		{"messages", fmt.Sprintf("/api/admin/chat-groups/%d/messages", groupID)},
		{"contact blocks", fmt.Sprintf("/api/admin/chat-groups/%d/contact-blocks", groupID)},
	}
}

// staffActor creates a staff user on `tier` and signs them in.
func staffActor(t *testing.T, pool *pgxpool.Pool, name, tier string) (int64, string) {
	t.Helper()
	id := makeChatGroupStaffUser(t, pool, name, tier)
	return id, tokenForChatGroupUser(t, pool, id)
}

// grantSensitiveForUser sets Note 31's per-EMPLOYEE override to allowed — the
// twin of admin_contact_view_test.go's denySensitiveForUser.
func grantSensitiveForUser(t *testing.T, pool *pgxpool.Pool, userID int64, tier string) {
	t.Helper()
	store := permissions.New(pool)
	if err := store.SetUserOverride(context.Background(), userID, permissions.TierFrom(tier),
		sensitive.Module, permissions.ActionView, true); err != nil {
		t.Fatalf("grant per-user sensitive_data: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions WHERE user_id=$1 AND module=$2`, userID, sensitive.Module)
	})
}

// requireTierPermission fails the test unless `tier` resolves (module, view)
// to `want` by tier alone. It turns a test's premise — "this tier lacks
// sensitive_data" — into a checked fact, so a stray tier-wide override from
// elsewhere cannot make a per-user test pass for the wrong reason.
func requireTierPermission(t *testing.T, pool *pgxpool.Pool, tier, module string, want bool) {
	t.Helper()
	got, err := permissions.New(pool).Allowed(context.Background(), permissions.TierFrom(tier), module, permissions.ActionView)
	if err != nil {
		t.Fatalf("resolve %s %s:view: %v", tier, module, err)
	}
	if got != want {
		t.Fatalf("premise broken: tier %s %s:view = %v, want %v", tier, module, got, want)
	}
}

// getRawAdminAs sends a GET and returns the status, the raw body and the
// decoded body. The raw body is what a leak assertion searches; the decoded
// body is what a field assertion reads. It is not main's getRawAs
// (chat_guest_reads_test.go), which returns only the status and the raw body.
func getRawAdminAs(t *testing.T, r *gin.Engine, token, path string) (int, string, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	decoded := map[string]any{}
	_ = json.Unmarshal(w.Body.Bytes(), &decoded)
	return w.Code, w.Body.String(), decoded
}

// assertAllReadable walks every read route and requires a 200 success.
func assertAllReadable(t *testing.T, r *gin.Engine, token string, groupID int64) {
	t.Helper()
	for _, route := range adminGroupReadPaths(groupID) {
		t.Run(route.name, func(t *testing.T) {
			code, raw, body := getRawAdminAs(t, r, token, route.path)
			if code != http.StatusOK || body["success"] != true {
				t.Fatalf("status = %d, want 200 success (body %s)", code, raw)
			}
		})
	}
}

// assertAllRefusedAsSensitive walks every read route and requires the 403
// sensitive_data_required refusal, with nothing identifying in the body.
func assertAllRefusedAsSensitive(t *testing.T, r *gin.Engine, token string, pool *pgxpool.Pool, fx adminReadFixture) {
	t.Helper()
	donorPhone := lookUpUserPhone(t, pool, fx.donorID)
	for _, route := range adminGroupReadPaths(fx.groupID) {
		t.Run(route.name, func(t *testing.T) {
			code, raw, body := getRawAdminAs(t, r, token, route.path)
			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 (body %s)", code, raw)
			}
			if body["code"] != wantSensitiveRequiredCode {
				t.Fatalf("code = %v, want %q (body %s)", body["code"], wantSensitiveRequiredCode, raw)
			}
			if body["success"] != false {
				t.Fatalf("success = %v, want false (body %s)", body["success"], raw)
			}
			if msg, _ := body["error"].(string); strings.TrimSpace(msg) == "" {
				t.Fatalf("error sentence is empty (body %s)", raw)
			}
			for _, needle := range []string{sensitiveFixtureRealName, fmt.Sprintf("%d", fx.donorID), donorPhone} {
				if strings.Contains(raw, needle) {
					t.Fatalf("refusal body leaks %q: %s", needle, raw)
				}
			}
		})
	}
}

// ─── Masked groups: the per-user answer decides ─────────────────────────

// TestAdminGroupReads_MaskedGroup_PerUserGrantLetsEmployeeRead: an employee's
// tier does not hold sensitive_data, but a Super-Admin granted it to this one
// employee. The per-user answer wins, as it does on GET
// /api/admin/permissions/me.
func TestAdminGroupReads_MaskedGroup_PerUserGrantLetsEmployeeRead(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	requireTierPermission(t, pool, "employee", "messages", true)
	fx := seedAdminReadGroup(t, pool, chatgroups.KindMasked)
	employee, token := staffActor(t, pool, "Granted Employee", "employee")
	grantSensitiveForUser(t, pool, employee, "employee")

	assertAllReadable(t, r, token, fx.groupID)
}

// TestAdminGroupReads_MaskedGroup_PerUserRevokeRefusesAdmin: an admin's tier
// holds sensitive_data by default, but it was revoked for this one admin. The
// three routes refuse with the stable code and name nobody.
func TestAdminGroupReads_MaskedGroup_PerUserRevokeRefusesAdmin(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "admin", sensitive.Module, true)
	fx := seedAdminReadGroup(t, pool, chatgroups.KindMasked)
	admin, token := staffActor(t, pool, "Revoked Admin", "admin")
	denySensitiveForUser(t, pool, admin, "admin")

	assertAllRefusedAsSensitive(t, r, token, pool, fx)
}

// TestAdminGroupReads_MaskedGroup_EmployeeWithoutSensitiveRefused is the
// control for the grant test above: the same employee tier with no grant is
// refused, so the grant is what let that employee in.
func TestAdminGroupReads_MaskedGroup_EmployeeWithoutSensitiveRefused(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	fx := seedAdminReadGroup(t, pool, chatgroups.KindMasked)
	_, token := staffActor(t, pool, "Plain Employee", "employee")

	assertAllRefusedAsSensitive(t, r, token, pool, fx)
}

// TestAdminGroupReads_MaskedGroup_SuperAdminReads: super_admin is always
// allowed and cannot be overridden.
func TestAdminGroupReads_MaskedGroup_SuperAdminReads(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	fx := seedAdminReadGroup(t, pool, chatgroups.KindMasked)
	_, token := staffActor(t, pool, "Super Admin", "super_admin")

	assertAllReadable(t, r, token, fx.groupID)
}

// ─── Team groups: messages:view is enough ───────────────────────────────

// TestAdminGroupReads_TeamGroup_MessagesViewAloneReads: a team group's members
// see each other's real names already, so staff holding messages:view but not
// sensitive_data read it.
func TestAdminGroupReads_TeamGroup_MessagesViewAloneReads(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	requireTierPermission(t, pool, "employee", "messages", true)
	fx := seedAdminReadGroup(t, pool, chatgroups.KindTeam)
	_, token := staffActor(t, pool, "Team Employee", "employee")

	assertAllReadable(t, r, token, fx.groupID)
}

// ─── A group that does not exist ────────────────────────────────────────

// TestAdminGroupReads_MissingGroupIs404: a group id that names no row answers
// chatErr's 404 group_not_found body (wantGroupNotFound, OPOS #26410) on all
// three routes — for a caller who could read it and for one who could not, so
// existence is checked before the permission.
func TestAdminGroupReads_MissingGroupIs404(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	_, adminToken := staffActor(t, pool, "Admin Reader", "admin")
	_, employeeToken := staffActor(t, pool, "Employee Reader", "employee")

	for _, caller := range []struct{ name, token string }{{"admin", adminToken}, {"employee", employeeToken}} {
		t.Run(caller.name, func(t *testing.T) {
			for _, route := range adminGroupReadPaths(neverExistingGroupID) {
				t.Run(route.name, func(t *testing.T) {
					code, _, body := getRawAdminAs(t, r, caller.token, route.path)
					assertChatGroupRefusal(t, code, body, wantGroupNotFound)
				})
			}
		})
	}
}
