package handlers

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorshipschedule"
)

// blockIfProtectedTarget enforces A-14: an account may only be modified by
// someone who outranks it, or matches its rank. Returns true (and writes the
// refusal) when the caller must be stopped. Call it right after parseID in
// user-modify handlers.
//
// H13 — the rule itself, the translatable `code`, the server-side log and the
// fail-closed behaviour on a lookup error now live in ONE place shared with
// AdminEditHandler, which had no rank check at all. See admin_user_guard.go.
// Two things changed here beyond the move:
//
//   - a failed tier lookup used to `return false`, waving the write through on
//     exactly the error where we no longer know who the target is. It now
//     refuses.
//   - the check was "is the target a super_admin?"; it is now "does the target
//     outrank the actor?", so a supervisor can no longer reset an admin's
//     password or suspend them either.
//
// changingPhone is false for every caller here — none of the status endpoints
// touch users.phone. Only PATCH /admin/users/:id does.
func (h *AdminStatusHandler) blockIfProtectedTarget(c *gin.Context, targetID int64) bool {
	return guardUserWrite(c, h.Pool, targetID, false)
}

type userStaffTierReq struct {
	StaffTier string `json:"staff_tier"`
	// H20 — see userPasswordReq. Moving the main admin's tier is the other way
	// to take the account's authority in one request.
	ConfirmationCode string `json:"confirmation_code"`
}

// POST /api/admin/users/:id/staff_tier — set a user's dashboard tier. Super-Admin
// only; refuses to demote the last remaining super_admin (Users #c / A-14).
func (h *AdminStatusHandler) UserStaffTier(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil || permissions.TierFrom(actor.StaffTier) != permissions.TierSuperAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Only a Super-Admin can change staff tiers."})
		return
	}
	var req userStaffTierReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	newTier := string(permissions.TierFrom(req.StaffTier)) // normalize; unknown → 'user'

	// H20 — the main admin's own tier may only be moved with the two-channel
	// confirmation. A no-op write (tier unchanged) is left alone: demanding an
	// out-of-band code to set a value to what it already is would only train
	// people to click through the prompt.
	if newTier != string(permissions.TierSuperAdmin) &&
		h.MainAdmin.required(c, mainAdminChange{h.Pool, id, changeKindStaffTier, req.ConfirmationCode}) {
		return
	}

	ctx := c.Request.Context()
	// Guard against removing the last super_admin.
	var curTier *string
	_ = h.Pool.QueryRow(ctx, "SELECT staff_tier FROM users WHERE id = $1", id).Scan(&curTier)
	if curTier != nil && *curTier == string(permissions.TierSuperAdmin) && newTier != string(permissions.TierSuperAdmin) {
		var supers int
		_ = h.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM users WHERE staff_tier = $1", string(permissions.TierSuperAdmin)).Scan(&supers)
		if supers <= 1 {
			c.JSON(http.StatusConflict, gin.H{"success": false, "error": "Cannot demote the last Super-Admin."})
			return
		}
	}

	ct, err := h.Pool.Exec(ctx, "UPDATE users SET staff_tier = $1 WHERE id = $2", newTier, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	// Force-logout when a tier is REDUCED, so a demotion (fewer permissions)
	// takes effect immediately rather than on the user's next token refresh.
	if curTier != nil && tierRank(*curTier) > tierRank(newTier) {
		h.forceLogout(ctx, id)
	}
	h.logAdminUserEvent(c, id, "tier", newTier)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "staff_tier": newTier})
}

// tierRank orders staff tiers by privilege so we can detect a demotion.
func tierRank(t string) int {
	switch permissions.TierFrom(t) {
	case permissions.TierSuperAdmin:
		return 4
	case permissions.TierAdmin:
		return 3
	case permissions.TierSupervisor:
		return 2
	case permissions.TierEmployee:
		return 1
	default:
		return 0
	}
}

// Note #34 — the "Add New User" window used to only take phone/role/full_name;
// the rest of user_profiles (already editable via PATCH .../:id, admin_edit.go
// User()) is now collectible at creation time too, gated per-field by the
// "user_" Field Rules prefix (migration 057) same as the Edit form's fields
// mirror the mobile app's own registration fields.
type createUserReq struct {
	Phone          string          `json:"phone"`
	RoleID         *int            `json:"role_id"`
	FullName       string          `json:"full_name"`
	Gender         *string         `json:"gender"`
	DateOfBirth    *string         `json:"date_of_birth"`
	Address        *string         `json:"address"`
	City           *string         `json:"city"`
	Occupation     *string         `json:"occupation"`
	FamilySize     jsonNullableInt `json:"family_size"`
	HousingStatus  *string         `json:"housing_status"`
	MonthlyIncome  *string         `json:"monthly_income"`
	Skills         *string         `json:"skills"`
	Availability   *string         `json:"availability"`
	Experience     *string         `json:"experience"`
	ProfilePicture *string         `json:"profile_picture"`
}

// POST /api/admin/users — staff manually creates a user (Users #g / M-07).
// Admin-created accounts skip the mobile approval flow (registration_status
// 'approved'). Phone is required and unique.
func (h *AdminStatusHandler) CreateUser(c *gin.Context) {
	var req createUserReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	phone := strings.TrimSpace(req.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Phone number is required."})
		return
	}
	// H10 — an account created with a redacted phone could never sign in and
	// could never be reached; `users.phone` is the sign-in identity.
	if rejectMaskedContactWrite(c, contactWrite{"phone", &phone}) {
		return
	}
	ctx := c.Request.Context()
	var roleArg any = nil
	if req.RoleID != nil && *req.RoleID > 0 {
		roleArg = *req.RoleID
	}
	var id int64
	err := h.Pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, registration_status)
		 VALUES ($1, $2, 'approved') RETURNING id`, phone, roleArg).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			c.JSON(http.StatusConflict, gin.H{"success": false, "error": "A user with this phone already exists."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// user_profiles columns full_name/gender/address/profile_picture are
	// NOT NULL (empty string default); the rest are nullable — same
	// pick/pickNull split as admin_edit.go's User() insert branch.
	pick := func(p *string) string {
		if p == nil {
			return ""
		}
		return strings.TrimSpace(*p)
	}
	pickNull := func(p *string) *string {
		if p == nil {
			return nil
		}
		s := strings.TrimSpace(*p)
		if s == "" {
			return nil
		}
		return &s
	}
	fullName := strings.TrimSpace(req.FullName)
	hasProfileData := fullName != "" || req.Gender != nil || req.DateOfBirth != nil || req.Address != nil ||
		req.City != nil || req.Occupation != nil || req.FamilySize.Set || req.HousingStatus != nil ||
		req.MonthlyIncome != nil || req.Skills != nil || req.Availability != nil || req.Experience != nil ||
		req.ProfilePicture != nil
	if hasProfileData {
		_, _ = h.Pool.Exec(ctx, `
			INSERT INTO user_profiles
			  (user_id, full_name, gender, address, profile_picture,
			   date_of_birth, city, occupation, family_size, housing_status,
			   monthly_income, skills, availability, experience)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
			id, fullName, pick(req.Gender), pick(req.Address), pick(req.ProfilePicture),
			pickNull(req.DateOfBirth), pickNull(req.City), pickNull(req.Occupation), req.FamilySize.IntPtr(),
			pickNull(req.HousingStatus), pickNull(req.MonthlyIncome), pickNull(req.Skills),
			pickNull(req.Availability), pickNull(req.Experience),
		)
	}
	h.logAdminUserEvent(c, id, "create", roleName(func() int {
		if req.RoleID != nil {
			return *req.RoleID
		}
		return 0
	}()))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// AdminStatusHandler exposes status-mutation endpoints for Phase 9.
// Every method behaves the same way:
//  1. Parse :id from path.
//  2. Parse JSON body for the new value(s).
//  3. Validate the new value against the allowed-values list for that resource.
//  4. UPDATE the row (one statement, one column).
//  5. Phase 18 — fire a user-facing notification when the new status is one
//     we have copy for (see admin_status_notify.go).
//  6. Return {success, id, status} on 200, or a precise 400/404 on bad input.
//
// All routes are wired under the `admin` group in main.go, so RequireAdmin
// has already authenticated the caller before any code in here runs.
type AdminStatusHandler struct {
	Pool *pgxpool.Pool
	// H20 — the two-channel confirmation guarding the main-admin account. Wired
	// late in main.go like the other optional collaborators; a nil guard
	// REFUSES a protected write rather than waving it through.
	MainAdmin *MainAdminConfirm
	Notifier  *notify.Notifier // Phase 18 — used by post-update notify helpers.
	Events    *events.Store    // Admin Notification System — user-account CRUD is
	// appended to app_events so it surfaces in the dashboard Notification Center
	// and is permanently recorded (append-only audit).
	// Note #36 — opens the Staff↔Volunteer↔Beneficiary chat the moment a
	// case-linked signup becomes approved (or later). Optional: nil skips the
	// check (defensive — lets this handler keep working even if the caller
	// forgets to wire it, just without auto-opening chats).
	CaseVolChat *casevolchat.Store
	// "Eighth: Sponsorship Schedule and Calendar" — materialises a
	// sponsorship's due dates the moment it goes active, so the tracking
	// screen and the reminder sweep have something to work with without a
	// separate manual step. Optional: nil skips generation.
	Schedule *sponsorshipschedule.Store
}

func NewAdminStatusHandler(pool *pgxpool.Pool, n *notify.Notifier, ev *events.Store, cvc *casevolchat.Store) *AdminStatusHandler {
	return &AdminStatusHandler{Pool: pool, Notifier: n, Events: ev, CaseVolChat: cvc}
}

// revokeSessionsForUser revokes every active session token for one user — the
// "force logout" security primitive. auth/token.go refuses a revoked token on
// the very next request, so the user is signed out of every device at once.
//
// H11 — this was a PRIVATE METHOD on AdminStatusHandler, which is exactly why
// the الصلاحيات screen could not use it: the permissions handler lives in
// another file with its own store and could not reach it, so unticking a
// checkbox left every affected session running. Same shape as the H15 bug, and
// the same fix — a package-level function, so "force logout" means one thing
// wherever it is written.
//
// Returns the number of sessions ended, so a caller can log what it did.
// `pool` and `userID` are the only inputs; nothing here is request-scoped.
func revokeSessionsForUser(ctx context.Context, pool *pgxpool.Pool, userID int64) (int64, error) {
	ct, err := pool.Exec(ctx,
		`UPDATE api_access_tokens SET revoked_at = NOW()
		  WHERE user_id = $1 AND revoked_at IS NULL`, userID)
	if err != nil {
		return 0, fmt.Errorf("revoking sessions for user %d: %w", userID, err)
	}
	return ct.RowsAffected(), nil
}

// revokeSessionsForTierPermission ends the sessions of everyone on `tier` whose
// EFFECTIVE answer for (module, action) just changed — used when a tier-wide
// checkbox is unticked in الصلاحيات.
//
// The NOT EXISTS is the whole point of the function. A staff member who carries
// a PER-USER override for this (module, action) is resolved by that override
// (permissions.AllowedForUser looks up by user_id alone and never consults the
// tier row), so the tier change did not reduce their authority and signing them
// out would be a logout they cannot explain. Everyone else on the tier resolved
// through the row that just changed, and must be signed out.
func revokeSessionsForTierPermission(
	ctx context.Context, pool *pgxpool.Pool, tier, module, action string,
) (int64, error) {
	ct, err := pool.Exec(ctx,
		`UPDATE api_access_tokens t
		    SET revoked_at = NOW()
		   FROM users u
		  WHERE t.user_id = u.id
		    AND t.revoked_at IS NULL
		    AND u.staff_tier = $1
		    AND NOT EXISTS (
		          SELECT 1 FROM role_permissions rp
		           WHERE rp.user_id = u.id
		             AND rp.module = $2
		             AND rp.action = $3
		        )`, tier, module, action)
	if err != nil {
		return 0, fmt.Errorf("revoking sessions for tier %s after %s/%s reduction: %w",
			tier, module, action, err)
	}
	return ct.RowsAffected(), nil
}

// forceLogout is the AdminStatusHandler's call site for the primitive above.
// Best-effort by design: a failure here must never block the security action
// that triggered it (a suspend must still suspend), but it is logged rather
// than swallowed — a force-logout that silently did nothing is the H11 class
// of bug all over again.
func (h *AdminStatusHandler) forceLogout(ctx context.Context, userID int64) {
	if _, err := revokeSessionsForUser(ctx, h.Pool, userID); err != nil {
		log.Printf("[security] force-logout failed for user %d: %v", userID, err)
	}
}

// POST /api/admin/users/:id/force_logout — on-demand revoke of every active
// session for a user (mobile + browser), without changing their account state.
// Section 25 "Force Logout of Active Sessions".
func (h *AdminStatusHandler) UserForceLogout(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	h.forceLogout(c.Request.Context(), id)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "logged_out": true})
}

type userAccountStatusReq struct {
	Status string `json:"status"`
}

// POST /api/admin/users/:id/account_status — body {status: active|suspended|banned}.
// Section 25 "Immediate Administrative Actions": suspended (temporary) and
// banned (permanent) both deactivate the account and force-logout every live
// session; active restores the account. ResolveToken denies any request from a
// suspended/banned account, so the block is enforced app-wide.
func (h *AdminStatusHandler) UserAccountStatus(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userAccountStatusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	status := strings.ToLower(strings.TrimSpace(req.Status))
	if status != "active" && status != "suspended" && status != "banned" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "status must be active, suspended, or banned."})
		return
	}
	ctx := c.Request.Context()
	// Keep the legacy `active` flag consistent with the lifecycle status.
	active := 0
	if status == "active" {
		active = 1
	}
	ct, err := h.Pool.Exec(ctx,
		"UPDATE users SET account_status = $1, active = $2 WHERE id = $3", status, active, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	// Suspend / ban → sign the account out of every device immediately.
	if status != "active" {
		h.forceLogout(ctx, id)
	}
	h.logAdminUserEvent(c, id, "status", status)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "account_status": status})
}

type userArchiveReq struct {
	Archived bool `json:"archived"`
}

// POST /api/admin/users/:id/archive — body {archived: true|false}. Note #4:
// a reversible, non-destructive alternative to Delete. Unlike Delete (which
// snapshots the row to Trash and removes it from the users table — Super
// Admin only, see admin_delete.go), archiving just flips account_status and
// leaves the row fully in place; any tier granted the "archive" permission
// (configurable per-tier on the Permissions page, defaults to Supervisor+)
// can archive AND un-archive on their own, no Super Admin needed. Distinct
// from suspended/banned (auth.RequireSuperAdmin, Section 25 "immediate
// administrative actions") — archiving is a routine housekeeping action, not
// a punitive one.
func (h *AdminStatusHandler) UserArchive(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userArchiveReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	status := "active"
	active := 1
	if req.Archived {
		status = "archived"
		active = 0
	}
	ctx := c.Request.Context()
	// Only ever transition to/from 'archived' — never clobber a suspended or
	// banned account back to 'active' just because someone hit "un-archive".
	var currentStatus string
	if err := h.Pool.QueryRow(ctx, "SELECT COALESCE(account_status, 'active') FROM users WHERE id = $1", id).Scan(&currentStatus); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	if !req.Archived && currentStatus != "archived" {
		c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "account_status": currentStatus})
		return
	}
	if req.Archived && currentStatus != "active" && currentStatus != "archived" {
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "Suspended or banned accounts can't be archived — restore them first."})
		return
	}
	ct, err := h.Pool.Exec(ctx,
		"UPDATE users SET account_status = $1, active = $2 WHERE id = $3", status, active, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	if req.Archived {
		h.forceLogout(ctx, id)
	}
	h.logAdminUserEvent(c, id, "status", status)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "account_status": status})
}

// ===== Allowed-value lists (match CHECK constraints in the schema) =====

var (
	beneficiaryCaseStatuses    = []string{"draft", "submitted", "under_review", "needs_changes", "approved", "rejected", "archived"}
	projectRequestStatuses     = []string{"pending", "submitted", "under_review", "approved", "rejected"}
	marketplaceProductStatuses = []string{"draft", "pending", "approved", "rejected", "sold_out", "hidden"}
	marketplaceOrderStatuses   = []string{"pending", "approved", "processing", "completed", "cancelled"}
	marriageStatuses           = []string{"submitted", "under_review", "active", "paused", "matched", "rejected", "closed"}
	partnerStatuses            = []string{"pending", "active", "hidden"}
	mediaStatuses              = []string{"draft", "published", "hidden"}
	commentStatuses            = []string{"pending", "approved", "hidden"} // #25 comment moderation
	communityStatuses          = []string{"pending", "approved", "rejected", "hidden"}
	// Note #19 — mandatory classification per City Guide entry.
	communitySectorTypes     = []string{"government", "private"}
	volunteerAppStatuses     = []string{"submitted", "approved", "rejected", "inactive"}
	sponsorshipStatuses      = []string{"pending", "active", "paused", "delayed", "stopped", "completed", "cancelled"}
	inKindStatuses           = []string{"submitted", "scheduled", "received", "delivered", "cancelled"}
	supportStatuses          = []string{"open", "in_progress", "resolved", "closed"}
	donationDeliveryStatuses = []string{"registered", "received", "under_review", "delivered", "paused", "suspended", "archived", "cancelled"}
	donationPaymentStatuses  = []int{1, 2, 3} // 1=success, 2=pending, 3=failed
	// Phase 21 — volunteer_mission_signups CHECK constraint allows exactly these.
	// 'pending' is the starting state on insert; admin transitions from there.
	volunteerSignupStatuses = []string{
		"pending", "approved", "rejected", "joined",
		"completion_requested", "cancelled", "completed", "no_show",
	}
	// Phase 22 — volunteer_missions CHECK constraint allows exactly these.
	volunteerMissionStatuses = []string{"draft", "open", "closed", "completed", "cancelled"}
)

type statusReq struct {
	Status string `json:"status"`
	// HoursServed is only read by MissionSignup, on a transition to
	// "completed" — every other status endpoint ignores it.
	HoursServed *float64 `json:"hours_served,omitempty"`
	// ReviewNotes is the reason behind the decision, read only by the
	// resources that pass a reviewStamp (today: beneficiary cases).
	//
	// A POINTER, so three cases stay distinguishable:
	//   nil    — key absent: leave whatever note is already on the row
	//            (this is what a bulk status change sends).
	//   ""     — key present and empty: clear the column, so a stale
	//            rejection reason cannot survive a later approval.
	//   "text" — key present: record it.
	ReviewNotes *string `json:"review_notes,omitempty"`
}

// ===== Generic helper: update one string column =====

// statusNotifyFn is the post-update notification callback. The helpers that
// implement it live in admin_status_notify.go; each one looks up the owning
// user (if any) and fires a 4-language LocalizedMessage.
type statusNotifyFn func(ctx context.Context, id int64, newStatus string)

// statusReviewNotifyFn is statusNotifyFn plus the reason the reviewer gave,
// for the resources whose decision records one. Kept separate so the eleven
// resources that do not record a reason are untouched.
type statusReviewNotifyFn func(ctx context.Context, id int64, newStatus, reason string)

// reviewStamp names the columns that record WHO decided, WHEN, and WHY, for a
// resource whose status change is a formal review rather than a bare state
// flip. Nil for every resource that has no such columns.
//
// The columns are always calling-code literals, never user input — same rule
// as `table` and `column` below.
type reviewStamp struct {
	NotesColumn      string
	ReviewedByColumn string
	ReviewedAtColumn string
}

// beneficiaryCaseReview — the three columns migration 001 has carried on
// `beneficiary_cases` since day one and that nothing ever wrote. Approving or
// rejecting someone's aid case is a decision a person made, and the record has
// to say who made it, when, and why: the app shows the applicant the outcome,
// and "rejected" with no reason and no name attached is not an answer.
var beneficiaryCaseReview = &reviewStamp{
	NotesColumn:      "review_notes",
	ReviewedByColumn: "reviewed_by_user_id",
	ReviewedAtColumn: "reviewed_at",
}

// updateStringStatus runs `UPDATE <table> SET <column> = $1 WHERE id = $2`
// after validating that the new value appears in `allowed`. table and column
// are NEVER taken from user input — only from the calling method's literals.
//
// `notifyFn` runs synchronously AFTER a successful update and BEFORE the
// 200 response. It's intentionally synchronous so the notification row is
// in the DB by the time the admin's UI refreshes (avoids "I approved it
// but the bell doesn't show anything"). Callbacks swallow their own errors
// — they never fail the admin's request.
//
// `extraSets` are additional literal SET fragments applied in the same UPDATE
// (K14 — the marriage resource uses it to clear owner_deleted_at, making a
// staff status decision the restore path for a profile its owner deleted).
// Variadic so the eleven callers that need none are untouched. Like `table` and
// `column`, these MUST be literals from this package and never request data —
// they are concatenated into the statement.
func (h *AdminStatusHandler) updateStringStatus(c *gin.Context, table, column string, allowed []string, notifyFn statusNotifyFn, extraSets ...string) {
	var wrapped statusReviewNotifyFn
	if notifyFn != nil {
		// These resources record no reason, so there is none to hand on.
		wrapped = func(ctx context.Context, id int64, newStatus, _ string) {
			notifyFn(ctx, id, newStatus)
		}
	}
	h.updateReviewedStringStatus(c, table, column, allowed, nil, wrapped, extraSets...)
}

// updateReviewedStringStatus is updateStringStatus plus the optional review
// stamp. When `review` is nil the behaviour is byte-for-byte the old one, which
// is what the other eleven status resources still get.
//
// When `review` is set it additionally writes the reviewer and the decision
// time on every status change through this endpoint (a status change here IS
// the review), and the reason when the caller sent one — see statusReq.
// ReviewNotes for the absent / empty / present distinction.
func (h *AdminStatusHandler) updateReviewedStringStatus(
	c *gin.Context, table, column string, allowed []string,
	review *reviewStamp, notifyFn statusReviewNotifyFn, extraSets ...string,
) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req statusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "status is required."})
		return
	}
	if !inSet(status, allowed) {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid status. Allowed: " + strings.Join(allowed, ", "),
		})
		return
	}

	sets := []string{column + " = $1"}
	args := []any{status}
	reason := ""
	if review != nil {
		// Who decided. NULL rather than 0 when the actor cannot be resolved:
		// reviewed_by_user_id carries an FK to users(id), and 0 would fail it.
		var reviewerArg any
		if actor, ok := auth.UserFromGin(c); ok && actor != nil && actor.UserID > 0 {
			reviewerArg = actor.UserID
		}
		args = append(args, reviewerArg)
		sets = append(sets, review.ReviewedByColumn+" = $"+strconv.Itoa(len(args)))
		sets = append(sets, review.ReviewedAtColumn+" = CURRENT_TIMESTAMP")

		if req.ReviewNotes != nil {
			reason = strings.TrimSpace(*req.ReviewNotes)
			var notesArg any
			if reason != "" {
				notesArg = reason
			}
			args = append(args, notesArg)
			sets = append(sets, review.NotesColumn+" = $"+strconv.Itoa(len(args)))
		}
	}
	// Literal fragments from the calling method (K14). Appended after the
	// parameterised sets so the $N numbering above is unaffected.
	sets = append(sets, extraSets...)
	args = append(args, id)

	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE "+table+" SET "+strings.Join(sets, ", ")+
			" WHERE id = $"+strconv.Itoa(len(args)),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	if notifyFn != nil {
		notifyFn(c.Request.Context(), id, status, reason)
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
}

// ===== Per-resource handlers =====

func (h *AdminStatusHandler) BeneficiaryCase(c *gin.Context) {
	h.updateReviewedStringStatus(c, "beneficiary_cases", "verification_status",
		beneficiaryCaseStatuses, beneficiaryCaseReview, h.notifyBeneficiaryCaseDecision)
}
func (h *AdminStatusHandler) ProjectRequest(c *gin.Context) {
	h.updateStringStatus(c, "beneficiary_project_requests", "status",
		projectRequestStatuses, h.notifyProjectRequestDecision)
}
func (h *AdminStatusHandler) MarketplaceProduct(c *gin.Context) {
	// Products don't notify a single user — they're listed by sellers and
	// admin moderates them; no per-user notification today.
	h.updateStringStatus(c, "marketplace_products", "status", marketplaceProductStatuses, nil)
}
func (h *AdminStatusHandler) MarketplaceOrder(c *gin.Context) {
	h.updateStringStatus(c, "marketplace_orders", "status",
		marketplaceOrderStatuses, h.notifyMarketplaceOrderDecision)
}

// Marriage — POST /api/admin/marriage/:id/status.
//
// K14 — this is also the RESTORE path. An owner who taps حذف does not delete
// the row (marriage_profiles' children cascade, so a real delete would take
// their mediated chats and their subscription payment record with it — see
// marriage.Store.DeleteOwnProfile); it is stamped owner_deleted_at and hidden
// from every surface of the app. Staff deciding a status on that profile is
// them putting it back, so the stamp is cleared in the same UPDATE. Without
// this the profile would be visible in the dashboard, editable, and still
// invisible in the app with nothing to explain why.
func (h *AdminStatusHandler) Marriage(c *gin.Context) {
	h.updateStringStatus(c, "marriage_profiles", "status",
		marriageStatuses, h.notifyMarriageDecision, "owner_deleted_at = NULL")
}
func (h *AdminStatusHandler) Partner(c *gin.Context) {
	// Partner-status changes don't trigger per-user notifications; broadcasts
	// happen at create-time from admin_create.go.
	h.updateStringStatus(c, "partners", "status", partnerStatuses, nil)
}
func (h *AdminStatusHandler) Media(c *gin.Context) {
	// Same — media broadcasts fire on first publish from admin_create.go.
	h.updateStringStatus(c, "media_posts", "status", mediaStatuses, nil)
}
func (h *AdminStatusHandler) Community(c *gin.Context) {
	h.updateStringStatus(c, "city_directory_entries", "status", communityStatuses, nil)
}

// MediaComment — #25. Moderate a post comment (pending → approved / hidden).
func (h *AdminStatusHandler) MediaComment(c *gin.Context) {
	h.updateStringStatus(c, "post_comments", "status", commentStatuses, nil)
}
func (h *AdminStatusHandler) VolunteerApplication(c *gin.Context) {
	h.updateStringStatus(c, "volunteer_applications", "status",
		volunteerAppStatuses, h.notifyVolunteerAppDecision)
}

// Sponsorship — unlike the other resources, a transition into 'active' needs
// next_due_date recomputed, so it can't go through the fully generic
// updateStringStatus. Insert() anchors next_due_date to submission time, so
// a slow approval of a 'pending' row can leave it already due/overdue by the
// time it goes active — the next scheduler tick would then fire an
// immediate reminder. Cancel() clears next_due_date to NULL, so reactivating
// a cancelled row would otherwise leave it with no due date, and
// DueForReminder never reminds on a NULL date. Only recompute on a genuine
// non-active -> active transition, and only when the existing date is
// already stale or missing — an already-active row keeps its date.
func (h *AdminStatusHandler) Sponsorship(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req statusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "status is required."})
		return
	}
	if !inSet(status, sponsorshipStatuses) {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid status. Allowed: " + strings.Join(sponsorshipStatuses, ", "),
		})
		return
	}

	ctx := c.Request.Context()
	var nextDue *string
	if status == "active" {
		var interval, oldStatus string
		var current *time.Time
		err := h.Pool.QueryRow(ctx,
			"SELECT schedule_interval, status, next_due_date FROM sponsorships WHERE id = $1",
			id,
		).Scan(&interval, &oldStatus, &current)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		if oldStatus != "active" && (current == nil || !current.After(time.Now().UTC())) {
			due := time.Now().UTC().Add(sponsorships.IntervalToDuration(interval)).Format("2006-01-02")
			nextDue = &due
		}
	}

	ct, err := h.Pool.Exec(ctx,
		"UPDATE sponsorships SET status = $1, next_due_date = COALESCE($3, next_due_date) WHERE id = $2",
		status, id, nextDue,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	// Activating a sponsorship builds (or tops up) its schedule. Generate is
	// idempotent — existing due dates are left alone — so re-activating a
	// paused sponsorship simply extends the schedule rather than duplicating
	// it. Best-effort: a failure here must not fail the status change, which
	// has already committed.
	if status == "active" && h.Schedule != nil {
		if _, err := h.Schedule.Generate(ctx, id, 12); err != nil {
			log.Printf("[sponsorship-schedule] generate for %d: %v", id, err)
		}
	}
	h.notifySponsorshipDecision(ctx, id, status)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
}
func (h *AdminStatusHandler) InKindDonation(c *gin.Context) {
	h.updateStringStatus(c, "in_kind_donations", "status",
		inKindStatuses, h.notifyInKindDecision)
}
func (h *AdminStatusHandler) SupportTicket(c *gin.Context) {
	h.updateStringStatus(c, "support_tickets", "status",
		supportStatuses, h.notifySupportTicketDecision)
}

// PublishProjectRequest — POST /api/admin/beneficiary_project_requests/:id/publish
//
// Phase 23. Copies an approved beneficiary_project_request into the
// `campaigns` table so grantors see it on /api/campaigns. The new campaign
// row stores `owner_user_id = project_request.user_id`, which activates
// the dormant "donation received on your project" notification wire in
// donations.go automatically.
//
// Rules:
//   - project_request must exist
//   - project_request.status must be 'approved'
//   - idempotent-ish: if a campaign with the same title already exists
//     we return it instead of creating a duplicate (admin clicking
//     Publish twice shouldn't double-insert).
func (h *AdminStatusHandler) PublishProjectRequest(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}

	// 1) Fetch the project_request and verify state + ownership.
	//    We pull `summary` (short blurb, fits VARCHAR(200)) for the
	//    campaigns.description column. `description_long` is preserved on
	//    the original project_request row for anyone who wants the full
	//    text via /detail/beneficiary_project_requests/:id.
	var ownerID int64
	var title string
	var titleAr, titleSorani, titleBadini, summary, summaryAr, location *string
	var amountNeeded *string
	var raisedAmount string
	var peopleAffected *int
	var status string
	err := h.Pool.QueryRow(c.Request.Context(), `
		SELECT user_id, project_title, project_title_ar, project_title_sorani, project_title_badini,
		       summary, summary_ar, location,
		       amount_needed::text, raised_amount::text,
		       people_affected_total, status
		  FROM beneficiary_project_requests
		 WHERE id = $1`,
		id,
	).Scan(&ownerID, &title, &titleAr, &titleSorani, &titleBadini,
		&summary, &summaryAr, &location,
		&amountNeeded, &raisedAmount, &peopleAffected, &status)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"success": false,
			"error":   "Project request not found.",
		})
		return
	}
	if status != "approved" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Only approved project requests can be published to grantors. Current status: " + status,
		})
		return
	}

	// 2) Idempotency: if a campaign already exists for this owner with
	//    matching title, return it instead of double-publishing.
	var existing int64
	if err := h.Pool.QueryRow(c.Request.Context(),
		`SELECT id FROM campaigns WHERE owner_user_id = $1 AND title = $2 LIMIT 1`,
		ownerID, title,
	).Scan(&existing); err == nil {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"id":      existing,
			"already": true,
			"message": "This project is already published to grantors.",
		})
		return
	}

	// 3) Map project_request → campaigns. `campaigns` is a flatter schema
	//    (text-typed money columns, "beneficiaries" as a free-form string).
	//
	// campaigns columns are VARCHAR(200). Clamp defensively in case a
	// project's summary / location / title overflows. Truncation uses
	// runes so multi-byte Arabic / Kurdish characters don't get sliced
	// mid-glyph.
	clamp200 := func(s string) string {
		runes := []rune(s)
		if len(runes) <= 200 {
			return s
		}
		return string(runes[:200])
	}
	addr := ""
	if location != nil {
		addr = clamp200(*location)
	}
	desc := ""
	if summary != nil {
		desc = clamp200(*summary)
	}
	descAr := ""
	if summaryAr != nil {
		descAr = clamp200(*summaryAr)
	}
	// Also clamp the address / title in case any of those columns has data
	// that overflows the 200-char column the schema enforces.
	title = clamp200(title)
	if titleAr != nil {
		v := clamp200(*titleAr)
		titleAr = &v
	}
	beneficiaries := "—"
	if peopleAffected != nil && *peopleAffected > 0 {
		beneficiaries = fmt.Sprintf("%d people", *peopleAffected)
	}
	goal := "0"
	if amountNeeded != nil && *amountNeeded != "" {
		goal = *amountNeeded
	}
	raised := raisedAmount
	if raised == "" {
		raised = "0"
	}

	var newID int64
	err = h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO campaigns
		  (title, title_ar, title_sorani, title_badini,
		   description, description_ar, description_sorani, description_badini,
		   address, beneficiaries, goal_amount, raised_amount,
		   is_active, status, owner_user_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,1,'active',$13)
		RETURNING id`,
		title, titleAr, titleSorani, titleBadini,
		desc, descAr, nil, nil,
		addr, beneficiaries, goal, raised, ownerID,
	).Scan(&newID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"id":            newID,
		"campaign_id":   newID,
		"owner_user_id": ownerID,
		"message":       "Project published to the grantor page.",
	})
}

// Mission status — Phase 22. No per-mission notification: missions are
// org-wide objects. When admin OPENS a draft mission, the broadcast that
// would have fired at create time should fire now. The wiring sits in
// notifyMissionStatusBroadcast so the create handler + status handler
// share one broadcaster.
func (h *AdminStatusHandler) Mission(c *gin.Context) {
	h.updateStringStatus(c, "volunteer_missions", "status",
		volunteerMissionStatuses, h.notifyMissionStatusBroadcast)
}

// Phase 21 — Volunteer mission signups have timestamp side-effects per
// status that the generic updateStringStatus can't express:
//
//	joined    → checked_in_at = NOW()  (admin recorded attendance)
//	completed → completed_at  = NOW()  AND checked_in_at = NOW() if null
//	            (so a direct "completed" from approved still has a timestamp)
//	anything else → completed_at cleared, since it no longer applies once the
//	            signup moves (or is undone) out of "completed"
//
// COALESCE keeps existing timestamps stable: if the admin already marked
// the volunteer joined yesterday and is now marking them completed today,
// the original checked_in_at is preserved.
func (h *AdminStatusHandler) MissionSignup(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req statusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "status is required."})
		return
	}
	if !inSet(status, volunteerSignupStatuses) {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid status. Allowed: " + strings.Join(volunteerSignupStatuses, ", "),
		})
		return
	}
	if req.HoursServed != nil && *req.HoursServed < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "hours_served must be >= 0."})
		return
	}

	// Build the timestamp side-effect tail per chosen status. Always uses
	// COALESCE so re-running the same status doesn't reset an earlier
	// timestamp. CURRENT_TIMESTAMP is server-side so the row's clock is
	// always the DB's UTC.
	extraSet := ""
	args := []interface{}{status, id}
	switch status {
	case "joined":
		extraSet = ", checked_in_at = COALESCE(checked_in_at, CURRENT_TIMESTAMP), completed_at = NULL"
	case "completed":
		extraSet = `, checked_in_at = COALESCE(checked_in_at, CURRENT_TIMESTAMP),
		             completed_at  = COALESCE(completed_at,  CURRENT_TIMESTAMP)`
		// hours_served is otherwise never written anywhere in the backend —
		// this is the one place the admin can record it.
		if req.HoursServed != nil {
			extraSet += fmt.Sprintf(", hours_served = $%d", len(args)+1)
			args = append(args, *req.HoursServed)
		}
	default:
		// Moving to any other status (including an Undo) means the signup is
		// no longer "completed" — clear the stale timestamp so the Progress
		// column doesn't keep showing a "done" date for it.
		extraSet = ", completed_at = NULL"
	}

	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE volunteer_mission_signups SET status = $1"+extraSet+" WHERE id = $2",
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}

	// Phase 18 — fire the 4-language notification to the volunteer.
	h.notifyMissionSignupDecision(c.Request.Context(), id, status)

	// Note #36 — this status change may be what makes the signup eligible for
	// the Staff↔Volunteer↔Beneficiary chat (already case-linked, now approved
	// or further along).
	ensureCaseVolChat(c.Request.Context(), h.CaseVolChat, h.Notifier, id)

	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
}

// ensureCaseVolChat opens the case-volunteer-beneficiary chat thread for a
// signup if it just became eligible, and notifies both real parties. Safe to
// call after every write that could change eligibility — a no-op otherwise.
// Free function (not a method) so both admin-side status changes and the
// volunteer's own check-in/check-out (Note #37, VolunteerCheckinHandler) can
// share it.
func ensureCaseVolChat(ctx context.Context, cvc *casevolchat.Store, notifier *notify.Notifier, signupID int64) {
	if cvc == nil {
		return
	}
	threadID, err := cvc.EnsureThreadForSignup(ctx, signupID)
	if err != nil || threadID == nil {
		return
	}
	thread, err := cvc.GetThread(ctx, *threadID)
	if err != nil {
		return
	}
	for _, uid := range []int64{thread.VolunteerUserID, thread.BeneficiaryUserID} {
		oid := uid
		go func() {
			bgCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			_, _ = notifier.Send(bgCtx, oid, notify.CaseVolunteerChatOpenedMsg(*threadID))
		}()
	}
}

// AssignSignupCase — POST /api/admin/volunteer_mission_signups/:id/assign-case
// body {beneficiary_case_id: number|null}. Links (or unlinks, with null) this
// specific volunteer's signup to a specific beneficiary case — the
// foundation the future Staff↔Volunteer↔Beneficiary chat pairs off of.
// Deliberately per-signup, not per-mission: one mission can serve several
// different beneficiaries.
func (h *AdminStatusHandler) AssignSignupCase(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req struct {
		BeneficiaryCaseID *int64 `json:"beneficiary_case_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.BeneficiaryCaseID != nil {
		var exists bool
		if err := h.Pool.QueryRow(c.Request.Context(),
			"SELECT EXISTS (SELECT 1 FROM beneficiary_cases WHERE id = $1)", *req.BeneficiaryCaseID,
		).Scan(&exists); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		if !exists {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown beneficiary case."})
			return
		}
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE volunteer_mission_signups SET beneficiary_case_id = $1 WHERE id = $2",
		req.BeneficiaryCaseID, id,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}

	// Note #36 — linking a case may be what makes an already-approved signup
	// eligible for the Staff↔Volunteer↔Beneficiary chat.
	if req.BeneficiaryCaseID != nil {
		ensureCaseVolChat(c.Request.Context(), h.CaseVolChat, h.Notifier, id)
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "beneficiary_case_id": req.BeneficiaryCaseID})
}

// ===== Donations (two status columns) =====

// recalcCampaignRaised sets campaigns.raised_amount to the sum of every
// CONFIRMED donation for that campaign. A donation only counts once the admin
// has confirmed it ('received') or fulfilled it ('delivered') — 'registered'
// (just submitted, still pending review), 'under_review', and 'cancelled' do
// NOT count. Because this recomputes from scratch every time, the stored total
// can never drift no matter how donations are inserted, edited, or cancelled.
func recalcCampaignRaised(ctx context.Context, pool *pgxpool.Pool, campaignID int64) {
	if campaignID <= 0 {
		return
	}
	_, _ = pool.Exec(ctx, `
		UPDATE campaigns
		   SET raised_amount = (
		         SELECT COALESCE(SUM(NULLIF(d.amount,'')::numeric), 0)
		           FROM donations d
		          WHERE d.campaign_id = $1
		            AND d.delivery_status IN ('received','delivered')
		       )::text
		 WHERE id = $1`, campaignID)
}

// recalcCampaignRaisedForDonation looks up the campaign a donation belongs to
// and recomputes that campaign's raised_amount. Safe no-op for general
// (campaign-less) donations. Call after any donation status/amount mutation.
func recalcCampaignRaisedForDonation(ctx context.Context, pool *pgxpool.Pool, donationID int64) {
	var campaignID *int64
	if err := pool.QueryRow(ctx,
		`SELECT campaign_id FROM donations WHERE id = $1`, donationID,
	).Scan(&campaignID); err != nil || campaignID == nil {
		return
	}
	recalcCampaignRaised(ctx, pool, *campaignID)
}

type donationStatusReq struct {
	PaymentStatus  *int    `json:"payment_status"`
	DeliveryStatus *string `json:"delivery_status"`
}

// POST /api/admin/donations/:id/status — body must include payment_status,
// delivery_status, or both. Updates whichever fields are provided.
func (h *AdminStatusHandler) Donation(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req donationStatusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.PaymentStatus == nil && req.DeliveryStatus == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Provide payment_status (1/2/3) or delivery_status, or both.",
		})
		return
	}

	sets := []string{}
	args := []any{}
	if req.PaymentStatus != nil {
		ps := *req.PaymentStatus
		if !inSetInt(ps, donationPaymentStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "Invalid payment_status. Allowed: 1 (success), 2 (pending), 3 (failed).",
			})
			return
		}
		args = append(args, ps)
		sets = append(sets, "payment_status = $"+strconv.Itoa(len(args)))
	}
	if req.DeliveryStatus != nil {
		ds := strings.TrimSpace(*req.DeliveryStatus)
		if !inSet(ds, donationDeliveryStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "Invalid delivery_status. Allowed: " + strings.Join(donationDeliveryStatuses, ", "),
			})
			return
		}
		args = append(args, ds)
		sets = append(sets, "delivery_status = $"+strconv.Itoa(len(args)))
	}
	args = append(args, id)
	sql := "UPDATE donations SET " + strings.Join(sets, ", ") + " WHERE id = $" + strconv.Itoa(len(args))

	ct, err := h.Pool.Exec(c.Request.Context(), sql, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}

	// Re-derive the campaign's raised_amount from its confirmed donations.
	// This is what makes a pending donation start (or stop) counting the
	// moment the admin changes its delivery_status — e.g. registered ->
	// delivered adds it; delivered -> cancelled removes it. Always recompute
	// (cheap) so the total can never drift.
	recalcCampaignRaisedForDonation(c.Request.Context(), h.Pool, id)

	// Phase 18 — notify the donor about the delivery decision (received /
	// delivered / cancelled).
	//
	// Phase 27.2 — also notify on payment_status changes. The "accept
	// donation" click from the admin SPA sends payment_status=1 with no
	// delivery_status, so the original Phase 18 wiring fired nothing.
	// Now success/failed transitions fire a push + DB notification too.
	if req.DeliveryStatus != nil {
		h.notifyDonationDecision(c.Request.Context(), id, strings.TrimSpace(*req.DeliveryStatus))
	}
	if req.PaymentStatus != nil {
		h.notifyDonationPaymentDecision(c.Request.Context(), id, *req.PaymentStatus)
	}

	resp := gin.H{"success": true, "id": id}
	if req.PaymentStatus != nil {
		resp["payment_status"] = *req.PaymentStatus
	}
	if req.DeliveryStatus != nil {
		resp["delivery_status"] = *req.DeliveryStatus
	}
	c.JSON(http.StatusOK, resp)
}

// ===== Users (role + active) =====

type userRoleReq struct {
	RoleID int `json:"role_id"`
}
type userActiveReq struct {
	Active int `json:"active"`
}
type userAdminReq struct {
	IsAdmin int `json:"is_admin"`
}

// POST /api/admin/users/:id/role — body {role_id}
func (h *AdminStatusHandler) UserRole(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userRoleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.RoleID < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "role_id must be >= 0 (0 clears the role)."})
		return
	}
	var arg any = req.RoleID
	if req.RoleID == 0 {
		arg = nil // store NULL when role is cleared
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE users SET role_id = $1 WHERE id = $2", arg, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	h.logAdminUserEvent(c, id, "role", roleName(req.RoleID))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "role_id": req.RoleID})
}

type userPasswordReq struct {
	Password string `json:"password"`
	// H20 — the confirmation code delivered to the main admin's phone AND
	// email. Empty on the first call (which asks for one to be sent), ignored
	// entirely for every target that is not a super_admin. Also decoded by
	// VerifyPassword, which shares this struct and simply never reads it.
	ConfirmationCode string `json:"confirmation_code"`
}

// POST /api/admin/users/:id/password — body {password}. Sets (or clears when
// empty) a user's bcrypt password hash so the dashboard login works for them.
// Phase 5 (M-05).
func (h *AdminStatusHandler) UserPassword(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userPasswordReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	// H20 — setting or clearing the main admin's password is a takeover in one
	// request, so it needs the two-channel confirmation. Runs after the body is
	// parsed (the code travels in it) and before any write.
	if h.MainAdmin.required(c, mainAdminChange{h.Pool, id, changeKindPassword, req.ConfirmationCode}) {
		return
	}
	pw := strings.TrimSpace(req.Password)
	var arg any = nil // empty password clears the hash (back to phone/OTP login)
	if pw != "" {
		if len(pw) < 4 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Password must be at least 4 characters."})
			return
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to hash password."})
			return
		}
		arg = string(hash)
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE users SET password_hash = $1 WHERE id = $2", arg, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	// Never record the password value — the event notes only that it changed.
	h.logAdminUserEvent(c, id, "password", "")
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// POST /api/admin/verify-password — body {password}. Confirms the CURRENT
// (requesting) admin's own password. Used as the PIN/step-up confirmation
// before sensitive actions like exporting data or permanently purging trash
// (Phase 7 · G-07 / A-16). Returns {ok:true} on match.
//
// Fails closed: an account with no password_hash set cannot confirm, so it
// cannot perform PIN-gated actions until a password is assigned.
func (h *AdminStatusHandler) VerifyPassword(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	var req userPasswordReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	pw := strings.TrimSpace(req.Password)
	if pw == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "ok": false, "error": "Password required."})
		return
	}
	var hash *string
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT password_hash FROM users WHERE id = $1", user.UserID).Scan(&hash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if hash == nil || *hash == "" {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "ok": false,
			"error": "No password is set on your account; ask a Super-Admin to set one."})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(*hash), []byte(pw)) != nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "ok": false, "error": "Incorrect password."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "ok": true})
}

// POST /api/admin/users/:id/active — body {active: 0 or 1}
func (h *AdminStatusHandler) UserActive(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userActiveReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.Active != 0 && req.Active != 1 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "active must be 0 or 1."})
		return
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE users SET active = $1 WHERE id = $2", req.Active, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	// Force-logout: deactivating an account must sign it out immediately so
	// the block takes effect instantly (not on the next token expiry).
	if req.Active == 0 {
		h.forceLogout(c.Request.Context(), id)
	}
	h.logAdminUserEvent(c, id, "active", "")
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "active": req.Active})
}

// POST /api/admin/users/:id/admin — body {is_admin: 0 or 1}. Lets the admin
// promote / demote other users without psql.
func (h *AdminStatusHandler) UserAdmin(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.blockIfProtectedTarget(c, id) {
		return
	}
	var req userAdminReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.IsAdmin != 0 && req.IsAdmin != 1 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "is_admin must be 0 or 1."})
		return
	}
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE users SET is_admin = $1 WHERE id = $2", req.IsAdmin, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return
	}
	h.logAdminUserEvent(c, id, "admin", "")
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "is_admin": req.IsAdmin})
}

// ===== shared helpers =====

func parseID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid id."})
		return 0, false
	}
	return id, true
}

func inSet(v string, allowed []string) bool {
	for _, x := range allowed {
		if v == x {
			return true
		}
	}
	return false
}

func inSetInt(v int, allowed []int) bool {
	for _, x := range allowed {
		if v == x {
			return true
		}
	}
	return false
}
