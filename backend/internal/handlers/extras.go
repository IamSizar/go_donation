package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/dashboard"
	"github.com/karam-flutter/humanitarian-backend/internal/history"
	"github.com/karam-flutter/humanitarian-backend/internal/inkind"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/reports"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
	"github.com/karam-flutter/humanitarian-backend/internal/support"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// ============================================================
// /api/users  (admin paginated list — sanitized)
// ============================================================

type UsersAdminHandler struct {
	Users *users.Store
}

func NewUsersAdminHandler(u *users.Store) *UsersAdminHandler {
	return &UsersAdminHandler{Users: u}
}

func (h *UsersAdminHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	res, err := h.Users.PaginatedList(c.Request.Context(), page, perPage, c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status":     "success",
		"data":       res.Items,
		"pagination": res.Pagination,
	})
}

// ============================================================
// /api/support  (POST: submit ticket)
// ============================================================

type SupportHandler struct {
	Store    *support.Store
	Notifier *notify.Notifier
}

func NewSupportHandler(s *support.Store, n *notify.Notifier) *SupportHandler {
	return &SupportHandler{Store: s, Notifier: n}
}

func (h *SupportHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	uid := int64(asInt(data["user_id"]))
	if uid <= 0 {
		uid = tokenUser.UserID
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	subject := asStr(data["subject"])
	message := asStr(data["message"])

	id, err := h.Store.Insert(c.Request.Context(), uid, subject, message)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing subject or message."})
		return
	}
	// Phase 18 — centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), uid,
		notify.SupportSubmittedMsg(strings.TrimSpace(subject), id))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "open"})
}

// ============================================================
// /api/in_kind_donations  (GET list, POST submit)
// ============================================================

type InKindHandler struct {
	Store    *inkind.Store
	Notifier *notify.Notifier
}

func NewInKindHandler(s *inkind.Store, n *notify.Notifier) *InKindHandler {
	return &InKindHandler{Store: s, Notifier: n}
}

func (h *InKindHandler) Get(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	uidStr := strings.TrimSpace(c.Query("user_id"))
	var uid int64
	if uidStr != "" {
		uid, _ = strconv.ParseInt(uidStr, 10, 64)
		if uid > 0 && (tokenUser == nil || tokenUser.UserID != uid) {
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
			return
		}
	}
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.List(c.Request.Context(), uid, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func (h *InKindHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	donor := int64(asInt(data["donor_user_id"]))
	if donor == 0 {
		donor = int64(asInt(data["user_id"]))
	}
	if donor <= 0 || donor != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	if tokenUser.RoleID != 1 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	cat := asStr(data["category"])
	item := asStr(data["item_name"])
	var quantity, condition, pickup, notes *string
	if v := asStr(data["quantity"]); v != "" {
		quantity = &v
	}
	if v := asStr(data["condition_note"]); v != "" {
		condition = &v
	}
	if v := asStr(data["pickup_address"]); v != "" {
		pickup = &v
	}
	if v := asStr(data["notes"]); v != "" {
		notes = &v
	}

	id, err := h.Store.Insert(c.Request.Context(), donor, cat, item, quantity, condition, pickup, notes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing category or item_name."})
		return
	}
	// Phase 18 — centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), donor,
		notify.InKindSubmittedMsg(strings.TrimSpace(item), id))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "submitted"})
}

// ============================================================
// /api/marriage  (GET list, POST submit)
// ============================================================

type MarriageHandler struct {
	Store    *marriage.Store
	Notifier *notify.Notifier
	// Client note — Marriage "Subscription": wallet payments for a package
	// purchase.
	Wallet *wallet.Store
}

func NewMarriageHandler(s *marriage.Store, n *notify.Notifier, w *wallet.Store) *MarriageHandler {
	return &MarriageHandler{Store: s, Notifier: n, Wallet: w}
}

// notifyStaffInBackground alerts staff (dashboard) about a new submission on a
// detached goroutine, so a slow fan-out never blocks the user's 200 response.
// Best-effort — errors are logged, not returned. Mirrors
// BeneficiaryHandler.notifyStaffInBackground (beneficiary.go).
func (h *MarriageHandler) notifyStaffInBackground(m notify.LocalizedMessage) {
	if h.Notifier == nil {
		return
	}
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if _, err := h.Notifier.BroadcastToStaff(bg, m); err != nil {
			log.Printf("[notify] staff submission alert failed: %v", err)
		}
	}()
}

func (h *MarriageHandler) Get(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	minAge, _ := strconv.Atoi(strings.TrimSpace(c.Query("min_age")))
	maxAge, _ := strconv.Atoi(strings.TrimSpace(c.Query("max_age")))
	minWeight, _ := strconv.Atoi(strings.TrimSpace(c.Query("min_weight")))
	maxWeight, _ := strconv.Atoi(strings.TrimSpace(c.Query("max_weight")))
	minHeight, _ := strconv.Atoi(strings.TrimSpace(c.Query("min_height")))
	maxHeight, _ := strconv.Atoi(strings.TrimSpace(c.Query("max_height")))
	beforeID, _ := strconv.ParseInt(strings.TrimSpace(c.Query("before_id")), 10, 64)
	items, err := h.Store.List(c.Request.Context(), marriage.SearchFilters{
		Status:           strings.TrimSpace(c.Query("status")),
		Q:                c.Query("q"),
		Gender:           strings.TrimSpace(c.Query("gender")),
		MinAge:           minAge,
		MaxAge:           maxAge,
		MaritalStatus:    strings.TrimSpace(c.Query("marital_status")),
		Religion:         strings.TrimSpace(c.Query("religion")),
		EmploymentStatus: strings.TrimSpace(c.Query("employment_status")),
		MinWeight:        minWeight,
		MaxWeight:        maxWeight,
		MinHeight:        minHeight,
		MaxHeight:        maxHeight,
		Limit:            limit,
		BeforeID:         beforeID,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// MyProfiles — GET /api/marriage/mine (Note #18). The current user's OWN
// submitted profile(s), in any status — unlike the public Get/List above
// (which only surfaces active/under_review/submitted profiles to browsers),
// a user needs to see their own profile even when it's rejected/closed/
// paused, so status is unfiltered here.
func (h *MarriageHandler) MyProfiles(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.List(c.Request.Context(), marriage.SearchFilters{Status: "all", OwnedByUser: user.UserID})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// SavedList — GET /api/marriage/saved (#46). The current user's bookmarks.
func (h *MarriageHandler) SavedList(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.List(c.Request.Context(), marriage.SearchFilters{Status: "all", SavedByUser: user.UserID})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// ToggleSave — POST /api/marriage/:id/save (#46).
func (h *MarriageHandler) ToggleSave(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	pid, _ := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if pid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid profile id."})
		return
	}
	saved, err := h.Store.ToggleSaved(c.Request.Context(), user.UserID, pid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "saved": saved})
}

// RequestMeeting — POST /api/marriage/:id/request-meeting (#46) — body {message}.
func (h *MarriageHandler) RequestMeeting(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	pid, _ := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if pid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid profile id."})
		return
	}
	data := collectBody(c)
	id, err := h.Store.RequestMeeting(c.Request.Context(), user.UserID, pid, asStr(data["message"]))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "pending"})
}

func (h *MarriageHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	uid := int64(asInt(data["user_id"]))
	if uid <= 0 || uid != tokenUser.UserID {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing user_id."})
		return
	}
	// Client note #43 — was restricted to role_id==2 (Beneficiary); the
	// client wants every account category able to submit a marriage profile,
	// with no role-based restriction (guests are still blocked, via
	// RequireNotGuest() on the route).

	var gender, city, social, private *string
	if v := asStr(data["gender"]); v != "" {
		gender = &v
	}
	if v := asStr(data["city"]); v != "" {
		city = &v
	}
	if v := asStr(data["social_summary"]); v != "" {
		social = &v
	}
	if v := asStr(data["private_notes"]); v != "" {
		private = &v
	}
	var agePtr *int
	if n := asInt(data["age"]); n > 0 {
		agePtr = &n
	}
	// Client note — Marriage "Search" filters: marital status/religion/
	// employment status/weight/height, collected on the same registration
	// form.
	var maritalStatus, religion, employmentStatus *string
	if v := asStr(data["marital_status"]); v != "" {
		maritalStatus = &v
	}
	if v := asStr(data["religion"]); v != "" {
		religion = &v
	}
	if v := asStr(data["employment_status"]); v != "" {
		employmentStatus = &v
	}
	var weightPtr, heightPtr *int
	if n := asInt(data["weight_kg"]); n > 0 {
		weightPtr = &n
	}
	if n := asInt(data["height_cm"]); n > 0 {
		heightPtr = &n
	}
	subStatus := strings.TrimSpace(asStr(data["subscription_status"]))
	visibility := strings.TrimSpace(asStr(data["visibility_level"])) // #42 — privacy
	// Marriage Posts — the owner's own photo, uploaded separately first via
	// the generic POST /api/uploads endpoint (same convention as everywhere
	// else); this just saves the returned path.
	var photoUrl *string
	if v := asStr(data["photo_url"]); v != "" {
		photoUrl = &v
	}

	id, code, err := h.Store.Insert(c.Request.Context(), uid, gender, agePtr, city, social, private,
		maritalStatus, religion, employmentStatus, weightPtr, heightPtr, subStatus, visibility, photoUrl)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to create profile."})
		return
	}
	// Phase 18 — centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), uid,
		notify.MarriageSubmittedMsg(code, id))
	// Note #18 — also alert staff on the dashboard that a new profile needs
	// review (previously only the submitting user was notified, same gap
	// beneficiary cases had before Requirement B1).
	h.notifyStaffInBackground(notify.NewMarriageProfileAdminMsg(code, id))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "profile_code": code, "status": "submitted"})
}

// ============================================================
// /api/sponsorships  (GET list, POST create/cancel)
// ============================================================

type SponsorshipsHandler struct {
	Store    *sponsorships.Store
	Notifier *notify.Notifier
}

func NewSponsorshipsHandler(s *sponsorships.Store, n *notify.Notifier) *SponsorshipsHandler {
	return &SponsorshipsHandler{Store: s, Notifier: n}
}

func (h *SponsorshipsHandler) Get(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if uid > 0 && (tokenUser == nil || tokenUser.UserID != uid) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	// #21 — beneficiary "My Entitlements" view: sponsorships that benefit the
	// caller (their case is being sponsored), rather than ones they fund.
	if c.Query("as") == "beneficiary" {
		if tokenUser == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
			return
		}
		beneficiaryUID := uid
		if beneficiaryUID <= 0 {
			beneficiaryUID = tokenUser.UserID
		}
		items, err := h.Store.ListByBeneficiary(c.Request.Context(), beneficiaryUID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		// #53 — hide the sponsorship money from the eligible person. The amount
		// and currency never leave the server for this view.
		for i := range items {
			items[i].Amount = ""
			items[i].Currency = ""
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
		return
	}

	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.List(c.Request.Context(), uid, c.Query("q"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func (h *SponsorshipsHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	action := strings.TrimSpace(asStr(data["action"]))

	if action == "cancel" {
		id := int64(asInt(data["id"]))
		if id == 0 {
			id = int64(asInt(data["sponsorship_id"]))
		}
		uid := int64(asInt(data["donor_user_id"]))
		if uid == 0 {
			uid = int64(asInt(data["user_id"]))
		}
		if uid <= 0 {
			uid = tokenUser.UserID
		}
		if uid != tokenUser.UserID {
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
			return
		}
		res, projectID, err := h.Store.Cancel(c.Request.Context(), id, uid)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing sponsorship cancel data."})
			return
		}
		if res == sponsorships.CancelNotFound {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Sponsorship not found."})
			return
		}
		label := "General support"
		if projectID != nil {
			if p, _ := h.Store.GetApprovedProject(c.Request.Context(), *projectID); p != nil {
				label = p.ProjectTitle
			}
		}
		// Phase 18 — centralised 4-language template.
		_, _ = h.Notifier.Send(c.Request.Context(), uid,
			notify.SponsorshipCancelledByDonorMsg(label, id))
		c.JSON(http.StatusOK, gin.H{"success": true, "status": "cancelled"})
		return
	}

	donor := int64(asInt(data["donor_user_id"]))
	if donor == 0 {
		donor = int64(asInt(data["user_id"]))
	}
	if donor <= 0 || donor != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	if tokenUser.RoleID != 1 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	sType := asStr(data["sponsorship_type"])
	if sType == "" {
		sType = asStr(data["type"])
	}
	amount, _ := asFloat(data["amount"])
	currency := asStr(data["currency"])
	interval := asStr(data["schedule_interval"])
	notes := asStr(data["notes"])
	var notesPtr *string
	if strings.TrimSpace(notes) != "" {
		notesPtr = &notes
	}
	var caseID, projectID *int64
	if n := int64(asInt(data["beneficiary_case_id"])); n > 0 {
		caseID = &n
	}
	if n := int64(asInt(data["project_request_id"])); n > 0 {
		projectID = &n
	} else if n := int64(asInt(data["campaign_id"])); n > 0 {
		projectID = &n
	}

	// If a project_request_id was given, it must exist + be approved.
	var project *sponsorships.ProjectRow
	if projectID != nil {
		p, err := h.Store.GetApprovedProject(c.Request.Context(), *projectID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if p == nil {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Campaign not found or not approved."})
			return
		}
		project = p
	}

	var nextDuePtr *time.Time
	if raw := strings.TrimSpace(asStr(data["next_due_date"])); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			nextDuePtr = &t
		}
	}

	id, err := h.Store.Insert(c.Request.Context(),
		donor, caseID, projectID, sType, amount, currency, interval, nextDuePtr, notesPtr,
	)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing sponsorship_type or amount."})
		return
	}
	label := "General support"
	if project != nil {
		label = project.ProjectTitle
	}
	amountLabel := strconv.FormatFloat(amount, 'f', 0, 64)
	currOut := strings.ToUpper(strings.TrimSpace(currency))
	if currOut == "" {
		currOut = "IQD"
	}
	// Phase 18 — centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), donor,
		notify.SponsorshipSubmittedMsg(amountLabel, currOut, label, id))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "pending"})
}

// ============================================================
// /api/volunteers  (GET hub, POST apply / join_mission)
// ============================================================

type VolunteersHandler struct {
	Store    *volunteers.Store
	Notifier *notify.Notifier // Phase 21b — submit-time acknowledgements
}

func NewVolunteersHandler(s *volunteers.Store, n *notify.Notifier) *VolunteersHandler {
	return &VolunteersHandler{Store: s, Notifier: n}
}

// Missions — GET /api/missions
//
// Phase 21b — clean REST resource for browsing open volunteer missions.
// Previously the mobile app had to call /api/volunteer_hub and pluck
// `items` out of a multi-field response. This endpoint returns just the
// missions array, which is what most callers actually want.
//
// Query params:
//
//	?limit=N   — optional cap, defaults to 100 (max 200)
//	?status=X  — optional status filter; defaults to 'open' so the
//	             "what can I sign up for" use case works without a flag.
//	             Pass 'all' to see every mission regardless of status.
//
// Response shape:
//
//	{
//	  "success": true,
//	  "items": [ { id, title, ..., status, accepted_volunteers, pending_volunteers }, ... ],
//	  "total": N
//	}
//
// Auth: requires a valid bearer (any signed-in user) — admin gets the same
// list shape. We don't surface signup info per-row here; clients should
// hit /api/volunteer_hub when they want their joined-missions overlay.
func (h *VolunteersHandler) Missions(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))

	// The store has ListOpenMissions today; we keep that as the default
	// (status=open) and add the "all" passthrough by calling ListAllMissions
	// when explicitly asked.
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	var missions []volunteers.Mission
	var err error
	if status == "all" {
		missions, err = h.Store.ListAllMissions(c.Request.Context(), limit)
	} else {
		// 'open' (default) or any unknown value → fall back to open.
		missions, err = h.Store.ListOpenMissions(c.Request.Context(), limit)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"items":   missions,
		"total":   len(missions),
	})
}

func (h *VolunteersHandler) Get(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if uid > 0 && (tokenUser == nil || tokenUser.UserID != uid) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	missions, err := h.Store.ListOpenMissions(c.Request.Context(), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	var apps []volunteers.Application
	var joined []volunteers.JoinedMission
	if uid > 0 {
		apps, _ = h.Store.ApplicationsForUser(c.Request.Context(), uid)
		joined, _ = h.Store.JoinedMissionsForUser(c.Request.Context(), uid)
	}
	c.JSON(http.StatusOK, gin.H{
		"success":         true,
		"items":           missions,
		"applications":    apps,
		"joined_missions": joined,
	})
}

func (h *VolunteersHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	action := strings.TrimSpace(asStr(data["action"]))
	if action == "" {
		action = "apply"
	}
	uid := int64(asInt(data["user_id"]))
	if uid <= 0 || uid != tokenUser.UserID {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing user_id."})
		return
	}
	if tokenUser.RoleID != 3 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	if action == "join_mission" {
		missionID := int64(asInt(data["mission_id"]))
		if missionID <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing mission_id."})
			return
		}
		var notesPtr *string
		if v := strings.TrimSpace(asStr(data["notes"])); v != "" {
			notesPtr = &v
		}
		res, err := h.Store.JoinMission(c.Request.Context(), uid, missionID, notesPtr)
		if err != nil {
			msg := err.Error()
			switch msg {
			case "mission not found or not open":
				c.JSON(http.StatusNotFound, gin.H{"success": false, "error": msg})
			case "mission full":
				c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This mission is already full."})
			default:
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": msg})
			}
			return
		}
		// Phase 21b — fire the "we got your join request" notification
		// (4 langs). Skip when the row already existed: re-joining the
		// same mission should not double-notify.
		if h.Notifier != nil && !res.Existing && res.SignupID > 0 {
			missionTitle := ""
			if m, mErr := h.Store.GetMission(c.Request.Context(), missionID); mErr == nil && m != nil {
				missionTitle = m.Title
			}
			_, _ = h.Notifier.Send(c.Request.Context(), uid,
				notify.VolunteerMissionJoinSubmittedMsg(missionTitle, res.SignupID))
		}

		out := gin.H{"success": true, "status": res.Status}
		if res.Existing {
			out["existing"] = true
			out["signup_id"] = res.SignupID
		}
		c.JSON(http.StatusOK, out)
		return
	}

	// apply
	fullName := strings.TrimSpace(firstNonEmpty(asStr(data["full_name"]), asStr(data["name"])))
	phone := strings.TrimSpace(asStr(data["phone"]))
	city := strings.TrimSpace(asStr(data["city"]))
	skills := strings.TrimSpace(asStr(data["skills"]))
	availability := strings.TrimSpace(asStr(data["availability"]))
	var expPtr *string
	if v := strings.TrimSpace(asStr(data["experience"])); v != "" {
		expPtr = &v
	}

	// Phase 26 — structured skill chips + per-day availability schedule.
	// Both fields are optional (legacy clients keep working with just the
	// free-form `skills` + `availability` text); when present, they go
	// into dedicated columns / the availability table.
	skillTags := volunteers.FilterSkillKeys(asStrSlice(data["skill_tags"]))
	schedule := volunteers.NormalizeSchedule(parseSchedule(data["availability_schedule"]))

	// If the client only sent structured data, synthesize the legacy
	// free-text equivalents so the admin's existing "skills" / "availability"
	// columns still show something readable.
	if skills == "" && len(skillTags) > 0 {
		skills = strings.Join(skillTags, ", ")
	}
	if availability == "" && len(schedule) > 0 {
		parts := make([]string, 0, len(schedule))
		for _, d := range schedule {
			parts = append(parts, strings.Title(d.Day)+" "+d.TimeFrom+"-"+d.TimeTo)
		}
		availability = strings.Join(parts, ", ")
	}

	id, err := h.Store.InsertApplication(c.Request.Context(), volunteers.ApplicationInput{
		UserID:       uid,
		FullName:     fullName,
		Phone:        phone,
		City:         city,
		Skills:       skills,
		Availability: availability,
		Experience:   expPtr,
		SkillTags:    skillTags,
		Schedule:     schedule,
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	// Phase 21b — fire the "we received your application" acknowledgement
	// (4 langs). Mirrors the equivalent for donor / beneficiary submits.
	if h.Notifier != nil {
		_, _ = h.Notifier.Send(c.Request.Context(), uid,
			notify.VolunteerApplicationSubmittedMsg(fullName, id))
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "submitted"})
}

// ============================================================
// /api/reports  (admin)
// ============================================================

type ReportsHandler struct {
	Store *reports.Store
}

func NewReportsHandler(s *reports.Store) *ReportsHandler {
	return &ReportsHandler{Store: s}
}

func (h *ReportsHandler) Get(c *gin.Context) {
	r, err := h.Store.Compute(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":                   true,
		"donations":                 r.Donations,
		"beneficiary_cases":         r.BeneficiaryCases,
		"project_requests":          r.ProjectRequests,
		"expenses":                  r.Expenses,
		"volunteers":                r.Volunteers,
		"volunteer_signup_statuses": r.VolunteerSignupStatuses,
	})
}

// ============================================================
// /api/dashboard?user_id=N  (role-aware summary)
// ============================================================

type DashboardHandler struct {
	Store *dashboard.Store
	Users *users.Store
}

func NewDashboardHandler(s *dashboard.Store, u *users.Store) *DashboardHandler {
	return &DashboardHandler{Store: s, Users: u}
}

func (h *DashboardHandler) Get(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if uid <= 0 {
		uid = tokenUser.UserID
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	role, _ := h.Users.GetRoleID(c.Request.Context(), uid)
	sum, err := h.Store.Compute(c.Request.Context(), uid, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"user_id":  uid,
		"role_id":  role,
		"role_key": dashboard.RoleKey(role),
		"summary":  sum,
	})
}

// ============================================================
// /api/history?user_id=N  (activity timeline)
// ============================================================

type HistoryHandler struct {
	Store *history.Store
	Users *users.Store
}

func NewHistoryHandler(s *history.Store, u *users.Store) *HistoryHandler {
	return &HistoryHandler{Store: s, Users: u}
}

func (h *HistoryHandler) Get(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if uid <= 0 {
		uid = tokenUser.UserID
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	role, _ := h.Users.GetRoleID(c.Request.Context(), uid)
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	res, err := h.Store.Build(c.Request.Context(), uid, role, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"role":           res.Role,
		"summary":        res.Summary,
		"kind_options":   res.KindOptions,
		"status_options": res.StatusOptions,
		"items":          res.Items,
	})
}
