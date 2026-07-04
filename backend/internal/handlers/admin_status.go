package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// blockIfProtectedTarget enforces A-14: a super_admin account can only be
// modified by another super_admin. Returns true (and writes 403) when the
// caller must be stopped. Call it right after parseID in user-modify handlers.
func (h *AdminStatusHandler) blockIfProtectedTarget(c *gin.Context, targetID int64) bool {
	var tier *string
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT staff_tier FROM users WHERE id = $1", targetID).Scan(&tier); err != nil {
		return false // let the handler surface not-found / db errors normally
	}
	if tier == nil || *tier != string(permissions.TierSuperAdmin) {
		return false
	}
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil || permissions.TierFrom(actor.StaffTier) != permissions.TierSuperAdmin {
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"error": "This account is protected — only a Super-Admin can modify it."})
		return true
	}
	return false
}

type userStaffTierReq struct {
	StaffTier string `json:"staff_tier"`
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

type createUserReq struct {
	Phone    string `json:"phone"`
	RoleID   *int   `json:"role_id"`
	FullName string `json:"full_name"`
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
	if name := strings.TrimSpace(req.FullName); name != "" {
		_, _ = h.Pool.Exec(ctx, `INSERT INTO user_profiles (user_id, full_name) VALUES ($1, $2)`, id, name)
	}
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
	Pool     *pgxpool.Pool
	Notifier *notify.Notifier // Phase 18 — used by post-update notify helpers.
}

func NewAdminStatusHandler(pool *pgxpool.Pool, n *notify.Notifier) *AdminStatusHandler {
	return &AdminStatusHandler{Pool: pool, Notifier: n}
}

// forceLogout revokes every active session token for a user — the "force
// logout" security primitive. Called when an account is deactivated or its
// staff_tier is reduced, so the affected user is signed out immediately and
// the updated permissions take effect on their next request. Best-effort: a
// failure here must never block the security action that triggered it.
func (h *AdminStatusHandler) forceLogout(ctx context.Context, userID int64) {
	_, _ = h.Pool.Exec(ctx,
		`UPDATE api_access_tokens SET revoked_at = NOW()
		  WHERE user_id = $1 AND revoked_at IS NULL`, userID)
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
	communityStatuses          = []string{"pending", "approved", "rejected", "hidden"}
	volunteerAppStatuses       = []string{"submitted", "approved", "rejected", "inactive"}
	sponsorshipStatuses        = []string{"pending", "active", "paused", "delayed", "stopped", "completed", "cancelled"}
	inKindStatuses             = []string{"submitted", "scheduled", "received", "delivered", "cancelled"}
	supportStatuses            = []string{"open", "in_progress", "resolved", "closed"}
	donationDeliveryStatuses   = []string{"registered", "received", "under_review", "delivered", "paused", "archived", "cancelled"}
	donationPaymentStatuses    = []int{1, 2, 3} // 1=success, 2=pending, 3=failed
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
}

// ===== Generic helper: update one string column =====

// statusNotifyFn is the post-update notification callback. The helpers that
// implement it live in admin_status_notify.go; each one looks up the owning
// user (if any) and fires a 4-language LocalizedMessage.
type statusNotifyFn func(ctx context.Context, id int64, newStatus string)

// updateStringStatus runs `UPDATE <table> SET <column> = $1 WHERE id = $2`
// after validating that the new value appears in `allowed`. table and column
// are NEVER taken from user input — only from the calling method's literals.
//
// `notifyFn` runs synchronously AFTER a successful update and BEFORE the
// 200 response. It's intentionally synchronous so the notification row is
// in the DB by the time the admin's UI refreshes (avoids "I approved it
// but the bell doesn't show anything"). Callbacks swallow their own errors
// — they never fail the admin's request.
func (h *AdminStatusHandler) updateStringStatus(c *gin.Context, table, column string, allowed []string, notifyFn statusNotifyFn) {
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
	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE "+table+" SET "+column+" = $1 WHERE id = $2",
		status, id,
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
		notifyFn(c.Request.Context(), id, status)
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
}

// ===== Per-resource handlers =====

func (h *AdminStatusHandler) BeneficiaryCase(c *gin.Context) {
	h.updateStringStatus(c, "beneficiary_cases", "verification_status",
		beneficiaryCaseStatuses, h.notifyBeneficiaryCaseDecision)
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
func (h *AdminStatusHandler) Marriage(c *gin.Context) {
	h.updateStringStatus(c, "marriage_profiles", "status",
		marriageStatuses, h.notifyMarriageDecision)
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
func (h *AdminStatusHandler) VolunteerApplication(c *gin.Context) {
	h.updateStringStatus(c, "volunteer_applications", "status",
		volunteerAppStatuses, h.notifyVolunteerAppDecision)
}
func (h *AdminStatusHandler) Sponsorship(c *gin.Context) {
	h.updateStringStatus(c, "sponsorships", "status",
		sponsorshipStatuses, h.notifySponsorshipDecision)
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
// `campaigns` table so donors see it on /api/campaigns. The new campaign
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
			"error":   "Only approved project requests can be published to donors. Current status: " + status,
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
			"message": "This project is already published to donors.",
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
		"message":       "Project published to the donor page.",
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

	// Build the timestamp side-effect tail per chosen status. Always uses
	// COALESCE so re-running the same status doesn't reset an earlier
	// timestamp. CURRENT_TIMESTAMP is server-side so the row's clock is
	// always the DB's UTC.
	extraSet := ""
	switch status {
	case "joined":
		extraSet = ", checked_in_at = COALESCE(checked_in_at, CURRENT_TIMESTAMP)"
	case "completed":
		extraSet = `, checked_in_at = COALESCE(checked_in_at, CURRENT_TIMESTAMP),
		             completed_at  = COALESCE(completed_at,  CURRENT_TIMESTAMP)`
	}

	ct, err := h.Pool.Exec(c.Request.Context(),
		"UPDATE volunteer_mission_signups SET status = $1"+extraSet+" WHERE id = $2",
		status, id,
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

	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
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
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "role_id": req.RoleID})
}

type userPasswordReq struct {
	Password string `json:"password"`
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
