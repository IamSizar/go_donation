package handlers

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/donations"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// DonationsHandler ports percentage/api/donate/*.
type DonationsHandler struct {
	Store    *donations.Store
	Notifier *notify.Notifier // Phase 18 — campaign-owner notification on donate
}

func NewDonationsHandler(s *donations.Store, n *notify.Notifier) *DonationsHandler {
	return &DonationsHandler{Store: s, Notifier: n}
}

// POST /api/donate?user_id=N
// Accepts form-encoded or JSON body with fields:
//
//	campaigns_id, message, amount, payment_method
//
// If user_id query is provided and a Bearer token is presented, it must match.
// When user_id is absent, we fall back to the token's user id.
func (h *DonationsHandler) Create(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)

	queryUID, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	var uid int64
	switch {
	case queryUID > 0:
		if tokenUser == nil || tokenUser.UserID != queryUID {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Unauthorized request. Please sign in again.",
			})
			return
		}
		uid = queryUID
	case tokenUser != nil:
		uid = tokenUser.UserID
	default:
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}

	// Pull fields supporting both form-encoded and JSON bodies.
	var jsonBody map[string]any
	if strings.Contains(strings.ToLower(c.ContentType()), "application/json") {
		_ = c.ShouldBindJSON(&jsonBody)
	}

	get := func(key string) (string, bool) {
		if jsonBody != nil {
			if v, ok := jsonBody[key]; ok && v != nil {
				return strings.TrimSpace(toString(v)), true
			}
		}
		if v := c.PostForm(key); v != "" {
			return strings.TrimSpace(v), true
		}
		return "", false
	}

	var campaignID *int64
	if v, ok := get("campaigns_id"); ok {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil && n > 0 {
			campaignID = &n
		}
	}

	var msgPtr *string
	if v, ok := get("message"); ok {
		msgPtr = &v
	} else {
		def := "No message provided"
		msgPtr = &def
	}

	var amountPtr *string
	if v, ok := get("amount"); ok {
		amountPtr = &v
	}

	var methodPtr *string
	if v, ok := get("payment_method"); ok {
		methodPtr = &v
	}

	// Phase 18 — capture the donor's display name now so the project-owner
	// notification reads "Sizar Ahmed donated …" rather than "user #8 …".
	donorName := ""
	if tokenUser != nil {
		donorName = strings.TrimSpace(tokenUser.Phone) // fallback to phone if name absent
	}
	_ = donorName // used below in the post-insert notify step

	ins, err := h.Store.Insert(c.Request.Context(), uid, campaignID, msgPtr, amountPtr, methodPtr)
	if err != nil {
		// Lifecycle-gate errors map to 400/410 so the donor app can show
		// a meaningful "this campaign just ended" message instead of a
		// generic "Failed to insert donation."
		switch {
		case errors.Is(err, donations.ErrCampaignFinished):
			c.JSON(http.StatusGone, gin.H{ // 410 — resource intentionally gone
				"success": false,
				"error":   "This campaign has finished and is no longer accepting donations.",
				"code":    "campaign_finished",
			})
			return
		case errors.Is(err, donations.ErrCampaignNotFound),
			errors.Is(err, donations.ErrCampaignNotDonatable):
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "This campaign isn't available for donations right now.",
				"code":    "campaign_unavailable",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to insert donation.",
		})
		return
	}

	// Phase 18 — fire a "new donation received" notification to the project
	// owner. The campaigns table is currently admin-managed (no owner column),
	// so this is a graceful no-op today; the helper looks for an
	// owner_user_id column and silently skips when none exists. When/if a
	// future migration adds owner_user_id to campaigns (or moves donations
	// back to beneficiary_project_requests), this notification starts
	// firing automatically with no additional code change.
	if h.Notifier != nil && campaignID != nil && ins != nil {
		go h.notifyProjectOwnerOfDonation(uid, *campaignID, ins.ID, donorName, amountPtr)
	}

	// Phase 18b — donor-facing submit acknowledgement. Says "we got your
	// X IQD donation to Y, it's being reviewed". Without this, donors hear
	// nothing until admin approves (which can be hours later).
	if h.Notifier != nil && ins != nil {
		go h.notifyDonorOfSubmission(uid, campaignID, ins.ID, amountPtr)
	}

	c.JSON(http.StatusOK, gin.H{
		"success":             true,
		"data":                []gin.H{{"id": uid}},
		"inserted_donations":  []*donations.InsertedDonation{ins},
	})
}

// notifyDonorOfSubmission sends the donor a "we got your donation, it's
// being reviewed" acknowledgement immediately after a successful Insert.
// Runs in its own goroutine so a slow campaign lookup never delays the
// /donate response.
func (h *DonationsHandler) notifyDonorOfSubmission(
	donorID int64, campaignID *int64, donationID int64, amountPtr *string,
) {
	bg, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	amount := ""
	if amountPtr != nil {
		amount = *amountPtr
	}
	campaignName := "general donation"
	if campaignID != nil {
		var title string
		if err := h.Notifier.Pool.QueryRow(bg,
			`SELECT title FROM campaigns WHERE id = $1`,
			*campaignID,
		).Scan(&title); err == nil && title != "" {
			campaignName = title
		}
	}
	// Campaigns are IQD-only today (the campaigns table has no currency
	// column — see notes in campaigns.go listSelect).
	msg := notify.DonationSubmittedMsg(amount, "IQD", campaignName, donationID)
	_, _ = h.Notifier.Send(bg, donorID, msg)
}

// notifyProjectOwnerOfDonation runs in its own goroutine so a slow lookup
// doesn't block the donor's checkout response. It detects the owner column
// dynamically — if `campaigns.owner_user_id` (or any future column matching
// our convention) doesn't exist, the lookup quietly fails and we drop out.
//
// Why dynamic? The Go port's `campaigns` schema has no owner column today.
// The PHP path notified beneficiaries because donations referenced their
// project requests, not admin campaigns. If we ever migrate donations to
// also reference beneficiary_project_requests, this helper picks that up
// without any code change here.
func (h *DonationsHandler) notifyProjectOwnerOfDonation(
	donorID, campaignID, donationID int64,
	donorName string,
	amountPtr *string,
) {
	// Use a fresh context — the parent request may have already returned.
	bg, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	// First: try the owner column if it exists (probes information_schema).
	var hasOwnerCol bool
	if err := h.Notifier.Pool.QueryRow(bg,
		`SELECT EXISTS (
		   SELECT 1 FROM information_schema.columns
		    WHERE table_name = 'campaigns' AND column_name = 'owner_user_id')`,
	).Scan(&hasOwnerCol); err != nil || !hasOwnerCol {
		return
	}

	// Owner column exists — look it up + notify.
	var ownerID *int64
	var title string
	if err := h.Notifier.Pool.QueryRow(bg,
		`SELECT owner_user_id, title FROM campaigns WHERE id = $1`,
		campaignID,
	).Scan(&ownerID, &title); err != nil {
		return
	}
	if ownerID == nil || *ownerID <= 0 || *ownerID == donorID {
		// Don't self-notify if the donor IS the project owner.
		return
	}
	amount := ""
	if amountPtr != nil {
		amount = *amountPtr
	}
	msg := notify.DonationReceivedOnProjectMsg(amount, "IQD", title, donorName, donationID)
	_, _ = h.Notifier.Send(bg, *ownerID, msg)
}

// POST /api/donate/:id/cancel
//
// Phase 23 — donor-driven cancel. Only the donor who made the donation can
// cancel it, and only while it's still in `delivery_status='registered'`
// (admin hasn't processed it yet). On success the campaign's raised_amount
// is rolled back so the totals stay consistent.
//
// Returns 403 / 409 with a specific reason rather than a generic 400 so the
// Flutter side can render the right "you can't cancel this" message.
func (h *DonationsHandler) Cancel(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation id."})
		return
	}

	amount, campaignID, err := h.Store.CancelByDonor(c.Request.Context(), id, tokenUser.UserID)
	if err != nil {
		switch {
		case errors.Is(err, donations.ErrDonationNotFound):
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Donation not found."})
		case errors.Is(err, donations.ErrDonationNotOwned):
			c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You can only cancel your own donations."})
		case errors.Is(err, donations.ErrDonationNotCancellable):
			c.JSON(http.StatusConflict, gin.H{
				"success": false,
				"error":   "This donation has already been processed and can no longer be cancelled. Please contact support if you need to make a change.",
			})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to cancel donation."})
		}
		return
	}

	// Fire a confirmation notification to the donor (4 languages). Best-effort
	// — a notification failure shouldn't fail the cancel response.
	if h.Notifier != nil {
		campaignName := "general donation"
		if campaignID != nil {
			var title string
			if err := h.Notifier.Pool.QueryRow(c.Request.Context(),
				`SELECT title FROM campaigns WHERE id = $1`, *campaignID,
			).Scan(&title); err == nil && title != "" {
				campaignName = title
			}
		}
		_, _ = h.Notifier.Send(c.Request.Context(), tokenUser.UserID,
			notify.DonationCancelledByDonorMsg(amount, "IQD", campaignName, id))
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"id":      id,
		"status":  "cancelled",
	})
}

// POST or GET /api/donate/my_donations  (user_id via body or query)
// Bearer required; user_id MUST match the token's user.
func (h *DonationsHandler) My(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}

	uidRaw := strings.TrimSpace(c.PostForm("user_id"))
	if uidRaw == "" {
		uidRaw = strings.TrimSpace(c.Query("user_id"))
	}
	if uidRaw == "" {
		// JSON body fallback
		var body struct {
			UserID any `json:"user_id"`
		}
		if strings.Contains(strings.ToLower(c.ContentType()), "application/json") {
			if err := c.ShouldBindJSON(&body); err == nil && body.UserID != nil {
				uidRaw = toString(body.UserID)
			}
		}
	}

	uid, err := strconv.ParseInt(uidRaw, 10, 64)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Missing or invalid user_id.",
		})
		return
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}

	items, stats, err := h.Store.ListByUser(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"success": false,
			"error":   "Could not fetch donations or stats.",
			"items":   []any{},
			"summary": stats,
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"summary": stats,
		"items":   items,
	})
}

// GET /api/donations?page=N&per_page=M  — admin list view of every donation
// with joined donor and campaign info. Auth-required (any signed-in user can
// fetch; in a future phase we can restrict to admin-roled users).
func (h *DonationsHandler) AdminList(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))

	res, err := h.Store.AdminList(c.Request.Context(), page, perPage, c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"items":       res.Items,
		"page":        res.Page,
		"per_page":    res.PerPage,
		"total_items": res.TotalItems,
		"total_pages": res.TotalPages,
		"has_more":    res.HasMore,
	})
}

// GET /api/beneficiary/campaign-donations
// Bearer required; returns all campaigns owned by the signed-in beneficiary
// and every donation made to each one, with donor name + phone.
// Response shape:
//
//	{ success, campaigns: [ { id, title, goal_amount, raised_amount, status,
//	                          donations: [ { id, amount, delivery_status,
//	                                         payment_method, message,
//	                                         transaction_date, donor_name,
//	                                         donor_phone } ] } ] }
func (h *DonationsHandler) BeneficiaryCampaignDonations(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	type donationRow struct {
		ID              int64   `json:"id"`
		DonorUserID     int64   `json:"donor_user_id"`
		Amount          string  `json:"amount"`
		DeliveryStatus  string  `json:"delivery_status"`
		PaymentMethod   string  `json:"payment_method"`
		Message         string  `json:"message"`
		TransactionDate string  `json:"transaction_date"`
		DonorName       *string `json:"donor_name"`
		DonorPhone      *string `json:"donor_phone"`
	}
	type campaignRow struct {
		ID           int64          `json:"id"`
		Title        string         `json:"title"`
		TitleAr      string         `json:"title_ar"`
		GoalAmount   string         `json:"goal_amount"`
		RaisedAmount string         `json:"raised_amount"`
		Status       string         `json:"status"`
		Donations    []*donationRow `json:"donations"`
	}

	// Step 1: all campaigns owned by this beneficiary.
	campRows, err := h.Store.Pool.Query(c.Request.Context(), `
		SELECT id, title, title_ar, goal_amount::text, raised_amount::text, status
		  FROM campaigns
		 WHERE owner_user_id = $1
		 ORDER BY id DESC`, tokenUser.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer campRows.Close()

	campaigns := []*campaignRow{}
	campByID := map[int64]*campaignRow{}
	for campRows.Next() {
		var cr campaignRow
		if err := campRows.Scan(&cr.ID, &cr.Title, &cr.TitleAr, &cr.GoalAmount, &cr.RaisedAmount, &cr.Status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		cr.Donations = []*donationRow{}
		campaigns = append(campaigns, &cr)
		campByID[cr.ID] = &cr
	}
	campRows.Close()

	if len(campaigns) == 0 {
		c.JSON(http.StatusOK, gin.H{"success": true, "campaigns": []any{}})
		return
	}

	// Step 2: all donations for those campaigns + joined donor info.
	dRows, err := h.Store.Pool.Query(c.Request.Context(), `
		SELECT d.id, d.user_id, d.campaign_id, d.amount::text, d.delivery_status,
		       d.payment_method, d.message, d.transaction_date::text,
		       up.full_name, u.phone
		  FROM donations d
		  JOIN campaigns c ON c.id = d.campaign_id
		  LEFT JOIN users u ON u.id = d.user_id
		  LEFT JOIN user_profiles up ON up.user_id = d.user_id
		 WHERE c.owner_user_id = $1
		 ORDER BY d.transaction_date DESC`, tokenUser.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer dRows.Close()
	for dRows.Next() {
		var (
			dr       donationRow
			campID   int64
		)
		if err := dRows.Scan(&dr.ID, &dr.DonorUserID, &campID, &dr.Amount, &dr.DeliveryStatus,
			&dr.PaymentMethod, &dr.Message, &dr.TransactionDate,
			&dr.DonorName, &dr.DonorPhone); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if camp, ok := campByID[campID]; ok {
			camp.Donations = append(camp.Donations, &dr)
		}
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "campaigns": campaigns})
}

func toString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case bool:
		if x {
			return "true"
		}
		return "false"
	case nil:
		return ""
	default:
		return ""
	}
}
