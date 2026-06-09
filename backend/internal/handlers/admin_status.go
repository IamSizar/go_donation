package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// AdminStatusHandler exposes status-mutation endpoints for Phase 9.
// Every method behaves the same way:
//   1. Parse :id from path.
//   2. Parse JSON body for the new value(s).
//   3. Validate the new value against the allowed-values list for that resource.
//   4. UPDATE the row (one statement, one column).
//   5. Phase 18 — fire a user-facing notification when the new status is one
//      we have copy for (see admin_status_notify.go).
//   6. Return {success, id, status} on 200, or a precise 400/404 on bad input.
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
	donationDeliveryStatuses   = []string{"registered", "received", "under_review", "delivered", "cancelled"}
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
//   • project_request must exist
//   • project_request.status must be 'approved'
//   • idempotent-ish: if a campaign with the same title already exists
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
			"success":  true,
			"id":       existing,
			"already":  true,
			"message":  "This project is already published to donors.",
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
		"success":     true,
		"id":          newID,
		"campaign_id": newID,
		"owner_user_id": ownerID,
		"message":     "Project published to the donor page.",
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

// POST /api/admin/users/:id/active — body {active: 0 or 1}
func (h *AdminStatusHandler) UserActive(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
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
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "active": req.Active})
}

// POST /api/admin/users/:id/admin — body {is_admin: 0 or 1}. Lets the admin
// promote / demote other users without psql.
func (h *AdminStatusHandler) UserAdmin(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
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

