package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
)

// AdminCreateHandler exposes resource-creation endpoints for Phase 11.
//
// Pattern: every handler receives a JSON body with the fields the admin can
// supply. Required columns must be present and non-empty; optional columns get
// stored as NULL when empty/missing. Each handler returns {success, id} on
// 200 with the new row's primary key, or 400 with a precise reason.
//
// All routes are wired under the `admin` group so RequireAdmin has already
// authenticated the caller. The "creator" identity (admin user_id) is read
// from the auth context where the table requires a user_id.
type AdminCreateHandler struct {
	Pool     *pgxpool.Pool
	Notifier *notify.Notifier // Phase 18 — broadcast to all users on partner/media create.
	// Codes issues per-section transaction-code namespaces (#14). Optional: when
	// nil, admin-created donations keep the legacy behaviour (NULL reference when
	// the admin doesn't supply one).
	Codes *sectioncodes.Store
}

func NewAdminCreateHandler(pool *pgxpool.Pool, n *notify.Notifier) *AdminCreateHandler {
	return &AdminCreateHandler{Pool: pool, Notifier: n}
}

// broadcastInBackground runs Notifier.Broadcast on a goroutine with a fresh
// timeout context so a slow fan-out never blocks the admin's 200 response.
// roleID=0 means "every active user". Errors are logged but not returned.
func (h *AdminCreateHandler) broadcastInBackground(roleID int, msg notify.LocalizedMessage) {
	if h.Notifier == nil {
		return
	}
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		sent, err := h.Notifier.Broadcast(bg, roleID, msg)
		if err != nil {
			log.Printf("[notify] broadcast type=%s failed: %v", msg.Type, err)
			return
		}
		log.Printf("[notify] broadcast type=%s delivered to %d users", msg.Type, sent)
	}()
}

// requireString returns the trimmed value or writes a 400 and returns ("", false).
func requireString(c *gin.Context, name string, val *string) (string, bool) {
	if val == nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": name + " is required."})
		return "", false
	}
	s := strings.TrimSpace(*val)
	if s == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": name + " cannot be empty."})
		return "", false
	}
	return s, true
}

// optStringOrNil returns the trimmed value or nil (for nullable columns).
func optStringOrNil(val *string) any {
	if val == nil {
		return nil
	}
	s := strings.TrimSpace(*val)
	if s == "" {
		return nil
	}
	return s
}

// adminUserID pulls the authenticated admin's user_id from the gin context, or
// 0 if missing. RequireAdmin attaches the ResolvedUser via UserFromContext.
func adminUserID(c *gin.Context) int {
	if u, ok := auth.UserFromContext(c); ok && u != nil {
		return int(u.UserID)
	}
	return 0
}

// ============================================================
// Partner — POST /api/admin/partners
// ============================================================

func (h *AdminCreateHandler) Partner(c *gin.Context) {
	var req partnerEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	name, ok := requireString(c, "name", req.Name)
	if !ok {
		return
	}
	status := "pending"
	if req.Status != nil {
		s := strings.TrimSpace(*req.Status)
		if s != "" {
			if !inSet(s, partnerStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(partnerStatuses, ", ")})
				return
			}
			status = s
		}
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO partners
		  (name, name_ar, name_sorani, name_badini, partner_type, contact_phone, website,
		   description, description_ar, description_sorani, description_badini, logo_path, status,
		   email, social_links, location, location_ar, location_sorani, location_badini)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)
		RETURNING id`,
		name,
		optStringOrNil(req.NameAr), optStringOrNil(req.NameSorani), optStringOrNil(req.NameBadini),
		optStringOrNil(req.PartnerType), optStringOrNil(req.ContactPhone), optStringOrNil(req.Website),
		optStringOrNil(req.Description), optStringOrNil(req.DescriptionAr), optStringOrNil(req.DescriptionSorani),
		optStringOrNil(req.DescriptionBadini), optStringOrNil(req.LogoPath), status,
		optStringOrNil(req.Email), optStringOrNil(req.SocialLinks), // #26
		optStringOrNil(req.Location), optStringOrNil(req.LocationAr),
		optStringOrNil(req.LocationSorani), optStringOrNil(req.LocationBadini),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// Phase 18 — broadcast to every active user when a new partner is added,
	// but only if the partner lands in a publicly-visible state. "pending"
	// partners shouldn't be announced to the world before admin approves.
	if status == "active" {
		h.broadcastInBackground(0 /* all users */, notify.NewPartnerMsg(name, id))
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Media — POST /api/admin/media
// ============================================================

func (h *AdminCreateHandler) Media(c *gin.Context) {
	var req mediaEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	title, ok := requireString(c, "title", req.Title)
	if !ok {
		return
	}
	postType := "news"
	if req.PostType != nil {
		v := strings.TrimSpace(*req.PostType)
		if v != "" {
			if !inSet(v, mediaPostTypes) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid post_type. Allowed: " + strings.Join(mediaPostTypes, ", ")})
				return
			}
			postType = v
		}
	}
	status := "published"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, mediaStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(mediaStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var eventDate any
	if req.EventDate != nil {
		s := strings.TrimSpace(*req.EventDate)
		if s != "" {
			if len(s) != 10 || s[4] != '-' || s[7] != '-' {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "event_date must be YYYY-MM-DD."})
				return
			}
			eventDate = s
		}
	}
	createdBy := adminUserID(c)
	var id int64
	gallery := []string{} // #23 — empty array (not NULL) when none supplied
	if req.Gallery != nil {
		gallery = cleanStringSlice(*req.Gallery)
	}
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO media_posts
		  (title, title_ar, title_sorani, title_badini,
		   body, body_ar, body_sorani, body_badini,
		   post_type, media_url, link_url, event_date, status, created_by_user_id,
		   category_slug, location, location_ar, location_sorani, location_badini, gallery)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
		RETURNING id`,
		title,
		optStringOrNil(req.TitleAr), optStringOrNil(req.TitleSorani), optStringOrNil(req.TitleBadini),
		optStringOrNil(req.Body), optStringOrNil(req.BodyAr), optStringOrNil(req.BodySorani), optStringOrNil(req.BodyBadini),
		postType, optStringOrNil(req.MediaURL), optStringOrNil(req.LinkURL), eventDate, status, nullableInt(createdBy),
		optStringOrNil(req.CategorySlug), // #22
		optStringOrNil(req.Location), optStringOrNil(req.LocationAr), // #23
		optStringOrNil(req.LocationSorani), optStringOrNil(req.LocationBadini), gallery,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// Phase 18 — broadcast to every active user when a new post is published.
	// Drafts and hidden posts don't broadcast (the admin is staging them).
	if status == "published" {
		h.broadcastInBackground(0 /* all users */, notify.NewMediaPostMsg(title, id))
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Community — POST /api/admin/community
// ============================================================

func (h *AdminCreateHandler) Community(c *gin.Context) {
	var req communityEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	name, ok := requireString(c, "name", req.Name)
	if !ok {
		return
	}
	category, ok := requireString(c, "category", req.Category)
	if !ok {
		return
	}
	status := "approved"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, communityStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(communityStatuses, ", ")})
				return
			}
			status = v
		}
	}
	// #29 — sectors + gallery default to empty arrays (not NULL) when omitted.
	sectors := []string{}
	if req.Sectors != nil {
		sectors = cleanStringSlice(*req.Sectors)
	}
	gallery := []string{}
	if req.Gallery != nil {
		gallery = cleanStringSlice(*req.Gallery)
	}
	approx := 0 // #48 — privacy: approximate location flag
	if req.ApproxLocation != nil {
		if s := strings.TrimSpace(*req.ApproxLocation); s == "approx" || s == "1" {
			approx = 1
		}
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO city_directory_entries
		  (name, name_ar, name_sorani, name_badini, category, city, address, phone, email, website,
		   description, description_ar, description_sorani, description_badini, latitude, longitude, status,
		   sectors, opening_hours, opening_hours_ar, opening_hours_sorani, opening_hours_badini, gallery, approx_location)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24)
		RETURNING id`,
		name,
		optStringOrNil(req.NameAr), optStringOrNil(req.NameSorani), optStringOrNil(req.NameBadini),
		category, optStringOrNil(req.City), optStringOrNil(req.Address), optStringOrNil(req.Phone),
		optStringOrNil(req.Email), optStringOrNil(req.Website),
		optStringOrNil(req.Description), optStringOrNil(req.DescriptionAr),
		optStringOrNil(req.DescriptionSorani), optStringOrNil(req.DescriptionBadini),
		optStringOrNil(req.Latitude), optStringOrNil(req.Longitude), status,
		sectors, optStringOrNil(req.OpeningHours), optStringOrNil(req.OpeningHoursAr),
		optStringOrNil(req.OpeningHoursSorani), optStringOrNil(req.OpeningHoursBadini), gallery, approx,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Sponsorship — POST /api/admin/sponsorships
// ============================================================

type sponsorshipCreateReq struct {
	sponsorshipEditReq
	DonorUserID *int `json:"donor_user_id"`
}

func (h *AdminCreateHandler) Sponsorship(c *gin.Context) {
	var req sponsorshipCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	sponsorshipType, ok := requireString(c, "sponsorship_type", req.SponsorshipType)
	if !ok {
		return
	}
	amount := 0.0
	if req.Amount != nil {
		if *req.Amount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "amount must be >= 0."})
			return
		}
		amount = *req.Amount
	}
	currency := "IQD"
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if v != "" {
			if len(v) != 3 {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
				return
			}
			currency = v
		}
	}
	schedule := "monthly"
	if req.ScheduleInterval != nil {
		v := strings.TrimSpace(*req.ScheduleInterval)
		if v != "" {
			if !inSet(v, sponsorshipIntervals) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid schedule_interval. Allowed: " + strings.Join(sponsorshipIntervals, ", ")})
				return
			}
			schedule = v
		}
	}
	status := "pending"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, sponsorshipStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(sponsorshipStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var nextDueDate any
	if req.NextDueDate != nil {
		s := strings.TrimSpace(*req.NextDueDate)
		if s != "" {
			if len(s) != 10 || s[4] != '-' || s[7] != '-' {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "next_due_date must be YYYY-MM-DD."})
				return
			}
			nextDueDate = s
		}
	}
	var donorID any
	if req.DonorUserID != nil && *req.DonorUserID > 0 {
		donorID = *req.DonorUserID
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO sponsorships
		  (donor_user_id, sponsorship_type, amount, currency, schedule_interval, next_due_date, status, notes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		RETURNING id`,
		donorID, sponsorshipType, amount, currency, schedule, nextDueDate, status, optStringOrNil(req.Notes),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// InKindDonation — POST /api/admin/in_kind_donations
// ============================================================

type inKindCreateReq struct {
	inKindEditReq
	DonorUserID *int `json:"donor_user_id"`
}

func (h *AdminCreateHandler) InKindDonation(c *gin.Context) {
	var req inKindCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	category, ok := requireString(c, "category", req.Category)
	if !ok {
		return
	}
	itemName, ok := requireString(c, "item_name", req.ItemName)
	if !ok {
		return
	}
	status := "submitted"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, inKindStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(inKindStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var donorID any
	if req.DonorUserID != nil && *req.DonorUserID > 0 {
		donorID = *req.DonorUserID
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO in_kind_donations
		  (donor_user_id, category, item_name, quantity, condition_note, pickup_address, status, notes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		RETURNING id`,
		donorID, category, itemName,
		optStringOrNil(req.Quantity), optStringOrNil(req.ConditionNote), optStringOrNil(req.PickupAddress),
		status, optStringOrNil(req.Notes),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// SupportTicket — POST /api/admin/support_tickets
// ============================================================

type ticketCreateReq struct {
	ticketEditReq
	UserID *int `json:"user_id"`
}

func (h *AdminCreateHandler) SupportTicket(c *gin.Context) {
	var req ticketCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	subject, ok := requireString(c, "subject", req.Subject)
	if !ok {
		return
	}
	message, ok := requireString(c, "message", req.Message)
	if !ok {
		return
	}
	status := "open"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, supportStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(supportStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var userID any
	if req.UserID != nil && *req.UserID > 0 {
		userID = *req.UserID
	} else if uid := adminUserID(c); uid > 0 {
		userID = uid
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO support_tickets (user_id, subject, message, status)
		VALUES ($1,$2,$3,$4)
		RETURNING id`,
		userID, subject, message, status,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// VolunteerApplication — POST /api/admin/volunteer_applications
// ============================================================

type volunteerCreateReq struct {
	volunteerEditReq
	UserID *int `json:"user_id"`
}

func (h *AdminCreateHandler) VolunteerApplication(c *gin.Context) {
	var req volunteerCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	fullName, ok := requireString(c, "full_name", req.FullName)
	if !ok {
		return
	}
	status := "submitted"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, volunteerAppStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(volunteerAppStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var userID any
	if req.UserID != nil && *req.UserID > 0 {
		userID = *req.UserID
	}
	// Phase 26 — skill_tags is now TEXT[]. Catalogue-filter the admin's
	// input so unrecognized keys don't reach the DB.
	var skillTagsArr []string
	if req.SkillTags != nil {
		skillTagsArr = volunteers.FilterSkillKeys(*req.SkillTags)
	} else {
		skillTagsArr = []string{}
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO volunteer_applications
		  (user_id, full_name, phone, city, skills, skill_tags, other_skill, experience, availability, cv_link, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id`,
		userID, fullName,
		optStringOrNil(req.Phone), optStringOrNil(req.City), optStringOrNil(req.Skills),
		skillTagsArr, optStringOrNil(req.OtherSkill), optStringOrNil(req.Experience),
		optStringOrNil(req.Availability), optStringOrNil(req.CVLink), status,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// MarriageProfile — POST /api/admin/marriage
// ============================================================

type marriageCreateReq struct {
	marriageEditReq
	UserID *int `json:"user_id"`
}

func (h *AdminCreateHandler) MarriageProfile(c *gin.Context) {
	var req marriageCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.UserID == nil || *req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required (the user the profile belongs to)."})
		return
	}
	visibility := "employee_only"
	if req.VisibilityLevel != nil {
		v := strings.TrimSpace(*req.VisibilityLevel)
		if v != "" {
			if !inSet(v, marriageVisibility) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid visibility_level. Allowed: " + strings.Join(marriageVisibility, ", ")})
				return
			}
			visibility = v
		}
	}
	subscription := "free"
	if req.SubscriptionStatus != nil {
		v := strings.TrimSpace(*req.SubscriptionStatus)
		if v != "" {
			if !inSet(v, marriageSubscription) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid subscription_status. Allowed: " + strings.Join(marriageSubscription, ", ")})
				return
			}
			subscription = v
		}
	}
	status := "submitted"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, marriageStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(marriageStatuses, ", ")})
				return
			}
			status = v
		}
	}
	if req.Age != nil && (*req.Age < 0 || *req.Age > 200) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "age must be 0..200."})
		return
	}
	profileCode := "PRF-" + strconv.FormatInt(time.Now().UnixNano()%9_999_999_999, 10)
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO marriage_profiles
		  (user_id, profile_code, gender, age, city, social_summary, private_notes,
		   visibility_level, subscription_status, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING id`,
		*req.UserID, profileCode,
		optStringOrNil(req.Gender), nullableIntPtr(req.Age), optStringOrNil(req.City),
		optStringOrNil(req.SocialSummary), optStringOrNil(req.PrivateNotes),
		visibility, subscription, status,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "profile_code": profileCode})
}

// ============================================================
// MarketplaceProduct — POST /api/admin/marketplace/products
// ============================================================

type productCreateReq struct {
	productEditReq
	SellerUserID      *int `json:"seller_user_id"`
	BeneficiaryCaseID *int `json:"beneficiary_case_id"`
}

// productLabels normalizes the optional labels array to a non-nil, sanitized
// slice (empty → an empty Postgres array, never NULL). #28.
func productLabels(in *[]string) []string {
	if in == nil {
		return []string{}
	}
	return sanitizeLabels(*in)
}

func (h *AdminCreateHandler) MarketplaceProduct(c *gin.Context) {
	var req productCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	name, ok := requireString(c, "name", req.Name)
	if !ok {
		return
	}
	price := 0.0
	if req.Price != nil {
		if *req.Price < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "price must be >= 0."})
			return
		}
		price = *req.Price
	}
	currency := "IQD"
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if v != "" {
			if len(v) != 3 {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
				return
			}
			currency = v
		}
	}
	status := "pending"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, marketplaceProductStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(marketplaceProductStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var sellerID any
	if req.SellerUserID != nil && *req.SellerUserID > 0 {
		sellerID = *req.SellerUserID
	}
	var caseID any
	if req.BeneficiaryCaseID != nil && *req.BeneficiaryCaseID > 0 {
		caseID = *req.BeneficiaryCaseID
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO marketplace_products
		  (seller_user_id, beneficiary_case_id,
		   name, name_ar, name_sorani, name_badini,
		   description, description_ar, description_sorani, description_badini,
		   category, price, currency, image_path, stock_quantity, status,
		   category_slug, sku, specs, labels)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
		RETURNING id`,
		sellerID, caseID,
		name, optStringOrNil(req.NameAr), optStringOrNil(req.NameSorani), optStringOrNil(req.NameBadini),
		optStringOrNil(req.Description), optStringOrNil(req.DescriptionAr),
		optStringOrNil(req.DescriptionSorani), optStringOrNil(req.DescriptionBadini),
		optStringOrNil(req.Category), price, currency,
		optStringOrNil(req.ImagePath), nullableIntPtr(req.StockQuantity), status,
		optStringOrNil(req.CategorySlug), optStringOrNil(req.SKU), // #28
		optStringOrNil(req.Specs), productLabels(req.Labels),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// BeneficiaryCase — POST /api/admin/beneficiary_cases
// ============================================================

type caseCreateReq struct {
	caseEditReq
	UserID *int `json:"user_id"`
}

func (h *AdminCreateHandler) BeneficiaryCase(c *gin.Context) {
	var req caseCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	publicTitle, ok := requireString(c, "public_title", req.PublicTitle)
	if !ok {
		return
	}
	priority := "medium"
	if req.PriorityLevel != nil {
		v := strings.TrimSpace(*req.PriorityLevel)
		if v != "" {
			if !inSet(v, casePriorityLevels) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid priority_level. Allowed: " + strings.Join(casePriorityLevels, ", ")})
				return
			}
			priority = v
		}
	}
	verification := "submitted"
	if req.VerificationStatus != nil {
		v := strings.TrimSpace(*req.VerificationStatus)
		if v != "" {
			if !inSet(v, beneficiaryCaseStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid verification_status. Allowed: " + strings.Join(beneficiaryCaseStatuses, ", ")})
				return
			}
			verification = v
		}
	}
	visibility := "code_only"
	if req.PublicVisibility != nil {
		v := strings.TrimSpace(*req.PublicVisibility)
		if v != "" {
			if !inSet(v, casePublicVisibility) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid public_visibility. Allowed: " + strings.Join(casePublicVisibility, ", ")})
				return
			}
			visibility = v
		}
	}
	if req.FamilyMembersCount != nil && *req.FamilyMembersCount < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "family_members_count must be >= 0."})
		return
	}
	if req.IncomeAmount != nil && *req.IncomeAmount < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "income_amount must be >= 0."})
		return
	}
	var userID any
	if req.UserID != nil && *req.UserID > 0 {
		userID = *req.UserID
	}
	caseCode := "CSE-" + strconv.FormatInt(time.Now().UnixNano()%9_999_999_999, 10)
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO beneficiary_cases
		  (user_id, case_code, public_title, public_title_ar, public_title_sorani, public_title_badini,
		   full_name, national_id, phone, city, district, address,
		   family_members_count, income_amount,
		   housing_status, work_status, health_status, education_status, actual_needs,
		   priority_level, verification_status, public_visibility, review_notes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23)
		RETURNING id`,
		userID, caseCode, publicTitle,
		optStringOrNil(req.PublicTitleAr), optStringOrNil(req.PublicTitleSorani), optStringOrNil(req.PublicTitleBadini),
		optStringOrNil(req.FullName), optStringOrNil(req.NationalID), optStringOrNil(req.Phone),
		optStringOrNil(req.City), optStringOrNil(req.District), optStringOrNil(req.Address),
		nullableIntPtr(req.FamilyMembersCount), nullableFloatPtr(req.IncomeAmount),
		optStringOrNil(req.HousingStatus), optStringOrNil(req.WorkStatus), optStringOrNil(req.HealthStatus),
		optStringOrNil(req.EducationStatus), optStringOrNil(req.ActualNeeds),
		priority, verification, visibility, optStringOrNil(req.ReviewNotes),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "case_code": caseCode})
}

// ============================================================
// ProjectRequest — POST /api/admin/beneficiary_project_requests
// ============================================================

type projectReqCreateReq struct {
	projectReqEditReq
	UserID *int `json:"user_id"`
}

func (h *AdminCreateHandler) ProjectRequest(c *gin.Context) {
	var req projectReqCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.UserID == nil || *req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required."})
		return
	}
	projectTitle, ok := requireString(c, "project_title", req.ProjectTitle)
	if !ok {
		return
	}
	category, ok := requireString(c, "category", req.Category)
	if !ok {
		return
	}
	summary, ok := requireString(c, "summary", req.Summary)
	if !ok {
		return
	}
	descLong, ok := requireString(c, "description_long", req.DescriptionLong)
	if !ok {
		return
	}
	location, ok := requireString(c, "location", req.Location)
	if !ok {
		return
	}
	communityName, ok := requireString(c, "beneficiary_community_name", req.BeneficiaryCommunityName)
	if !ok {
		return
	}
	amount := 0.0
	if req.AmountNeeded != nil {
		if *req.AmountNeeded < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "amount_needed must be >= 0."})
			return
		}
		amount = *req.AmountNeeded
	}
	currency := "IQD"
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if v != "" {
			if len(v) != 3 {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
				return
			}
			currency = v
		}
	}
	status := "submitted"
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if v != "" {
			if !inSet(v, projectRequestStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(projectRequestStatuses, ", ")})
				return
			}
			status = v
		}
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO beneficiary_project_requests
		  (user_id, project_title, project_title_ar, project_title_sorani, project_title_badini,
		   category, category_ar, summary, summary_ar, description_long, description_long_ar,
		   amount_needed, currency, location, location_ar, beneficiary_community_name,
		   people_affected_total, male_count, female_count,
		   timeline_target, contact_person_name, contact_phone, contact_email, other_notes, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25)
		RETURNING id`,
		*req.UserID, projectTitle,
		optStringOrNil(req.ProjectTitleAr), optStringOrNil(req.ProjectTitleSorani), optStringOrNil(req.ProjectTitleBadini),
		category, optStringOrNil(req.CategoryAr), summary, optStringOrNil(req.SummaryAr),
		descLong, optStringOrNil(req.DescriptionLongAr),
		amount, currency, location, optStringOrNil(req.LocationAr), communityName,
		nullableIntPtr(req.PeopleAffectedTotal), nullableIntPtr(req.MaleCount), nullableIntPtr(req.FemaleCount),
		optStringOrNil(req.TimelineTarget), optStringOrNil(req.ContactPersonName),
		optStringOrNil(req.ContactPhone), optStringOrNil(req.ContactEmail), optStringOrNil(req.OtherNotes), status,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Donation — POST /api/admin/donations
// ============================================================

type donationCreateReq struct {
	donationEditReq
	UserID        *int    `json:"user_id"`
	CampaignID    *int    `json:"campaign_id"`
	DonationKind  *string `json:"donation_kind"`
}

var donationKinds = []string{"general", "campaign", "sponsorship", "in_kind", "operational"}

// donationTypes are the donor-facing giving types (#16/#16b), distinct from the
// internal donation_kind routing above.
var donationTypes = []string{"general", "zakat", "sadaqah"}

func (h *AdminCreateHandler) Donation(c *gin.Context) {
	var req donationCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.UserID == nil || *req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required."})
		return
	}
	message, ok := requireString(c, "message", req.Message)
	if !ok {
		return
	}
	amount, ok := requireString(c, "amount", req.Amount)
	if !ok {
		return
	}
	paymentMethod, ok := requireString(c, "payment_method", req.PaymentMethod)
	if !ok {
		return
	}
	kind := "campaign"
	if req.DonationKind != nil {
		v := strings.TrimSpace(*req.DonationKind)
		if v != "" {
			if !inSet(v, donationKinds) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation_kind. Allowed: " + strings.Join(donationKinds, ", ")})
				return
			}
			kind = v
		}
	}
	paymentStatus := 2
	if req.PaymentStatus != nil {
		if !inSetInt(*req.PaymentStatus, donationPaymentStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid payment_status. Allowed: 1 (success), 2 (pending), 3 (failed)."})
			return
		}
		paymentStatus = *req.PaymentStatus
	}
	deliveryStatus := "registered"
	if req.DeliveryStatus != nil {
		v := strings.TrimSpace(*req.DeliveryStatus)
		if v != "" {
			if !inSet(v, donationDeliveryStatuses) {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid delivery_status. Allowed: " + strings.Join(donationDeliveryStatuses, ", ")})
				return
			}
			deliveryStatus = v
		}
	}
	var campaignID any
	if req.CampaignID != nil && *req.CampaignID > 0 {
		campaignID = *req.CampaignID
	}
	// #16b — donor-facing donation type; default general, validated against the
	// known set.
	dtype := "general"
	if req.DonationType != nil && strings.TrimSpace(*req.DonationType) != "" {
		v := strings.ToLower(strings.TrimSpace(*req.DonationType))
		if !inSet(v, donationTypes) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation_type. Allowed: " + strings.Join(donationTypes, ", ")})
			return
		}
		dtype = v
	}
	// #14 — when the admin didn't supply a reference, issue this section's next
	// namespaced code (e.g. CAM-000042) instead of leaving it NULL.
	var reference any = optStringOrNil(req.ReferenceNumber)
	if (req.ReferenceNumber == nil || strings.TrimSpace(*req.ReferenceNumber) == "") && h.Codes != nil {
		if code, ok, genErr := h.Codes.NextReference(c.Request.Context(), h.Pool, kind); genErr == nil && ok {
			reference = code
		}
	}
	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO donations
		  (reference_number, user_id, campaign_id, donation_kind, donation_type, message, amount,
		   payment_status, delivery_status, payment_method, impact_note)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id`,
		reference, *req.UserID, campaignID, kind, dtype,
		message, amount, paymentStatus, deliveryStatus, paymentMethod, optStringOrNil(req.ImpactNote),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Campaign — POST /api/admin/campaigns
// ============================================================

func (h *AdminCreateHandler) Campaign(c *gin.Context) {
	var req campaignEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	// All 8 of these columns are NOT NULL with no default in the schema.
	title, ok := requireString(c, "title", req.Title)
	if !ok {
		return
	}
	titleAr, ok := requireString(c, "title_ar", req.TitleAr)
	if !ok {
		return
	}
	description, ok := requireString(c, "description", req.Description)
	if !ok {
		return
	}
	descriptionAr, ok := requireString(c, "description_ar", req.DescriptionAr)
	if !ok {
		return
	}
	address, ok := requireString(c, "address", req.Address)
	if !ok {
		return
	}
	beneficiaries, ok := requireString(c, "beneficiaries", req.Beneficiaries)
	if !ok {
		return
	}
	goalAmount, ok := requireString(c, "goal_amount", req.GoalAmount)
	if !ok {
		return
	}
	// raised_amount is also NOT NULL but defaults to "0" if the admin leaves
	// it blank (new campaigns start with nothing raised).
	raisedAmount := "0"
	if req.RaisedAmount != nil {
		s := strings.TrimSpace(*req.RaisedAmount)
		if s != "" {
			raisedAmount = s
		}
	}

	// Phase 15.1 — campaign lifecycle. Default 'active' so new campaigns
	// show up in the donor app immediately. Admin can flip to 'hidden' or
	// 'finished' later from the edit modal.
	status := "active"
	if req.Status != nil {
		s := strings.ToLower(strings.TrimSpace(*req.Status))
		if s != "" {
			if s != "active" && s != "hidden" && s != "finished" {
				c.JSON(http.StatusBadRequest, gin.H{
					"success": false,
					"error":   "status must be one of: active, hidden, finished.",
				})
				return
			}
			status = s
		}
	}
	isActive := 0
	if status == "active" {
		isActive = 1
	}

	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO campaigns
		  (title, title_ar, title_sorani, title_badini,
		   description, description_ar, description_sorani, description_badini,
		   address, beneficiaries, goal_amount, raised_amount, is_active, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		RETURNING id`,
		title, titleAr, optStringOrNil(req.TitleSorani), optStringOrNil(req.TitleBadini),
		description, descriptionAr, optStringOrNil(req.DescriptionSorani), optStringOrNil(req.DescriptionBadini),
		address, beneficiaries, goalAmount, raisedAmount, isActive, status,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// Notify all users about a newly published campaign so donors can discover
	// and support it. Only broadcast for publicly-visible (active) campaigns —
	// hidden/finished ones shouldn't ping everyone.
	if status == "active" {
		h.broadcastInBackground(0 /* all users */, notify.NewCampaignMsg(title, id))
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ===== local helpers =====

func nullableInt(v int) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullableIntPtr(v *int) any {
	if v == nil {
		return nil
	}
	return *v
}

func nullableFloatPtr(v *float64) any {
	if v == nil {
		return nil
	}
	return *v
}

// ============================================================
// Volunteer mission — POST /api/admin/missions  (Phase 22)
// ============================================================
//
// Status defaults to 'open' so new missions are immediately visible to
// volunteers. Admin can flip to 'draft' on save to stage one. When the
// mission lands in an 'open' state, NewVolunteerMissionMsg is broadcast
// to every role_id=3 user via Notifier.Broadcast(3, …).

type missionEditReq struct {
	Title             *string `json:"title"`
	TitleAr           *string `json:"title_ar"`
	TitleSorani       *string `json:"title_sorani"`
	TitleBadini       *string `json:"title_badini"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	City              *string `json:"city"`
	MissionDate       *string `json:"mission_date"`        // YYYY-MM-DD or empty
	NeededVolunteers  *int    `json:"needed_volunteers"`
	Status            *string `json:"status"`
	ProjectRequestID  *int64  `json:"project_request_id"`
}

var missionStatusesAllowed = map[string]bool{
	"draft":     true,
	"open":      true,
	"closed":    true,
	"completed": true,
	"cancelled": true,
}

func (h *AdminCreateHandler) Mission(c *gin.Context) {
	var req missionEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	title, ok := requireString(c, "title", req.Title)
	if !ok {
		return
	}
	status := "open"
	if req.Status != nil {
		s := strings.TrimSpace(*req.Status)
		if s != "" {
			if !missionStatusesAllowed[s] {
				c.JSON(http.StatusBadRequest, gin.H{
					"success": false,
					"error":   "Invalid status. Allowed: draft, open, closed, completed, cancelled.",
				})
				return
			}
			status = s
		}
	}
	var missionDate any
	if req.MissionDate != nil {
		s := strings.TrimSpace(*req.MissionDate)
		if s != "" {
			if len(s) != 10 || s[4] != '-' || s[7] != '-' {
				c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "mission_date must be YYYY-MM-DD."})
				return
			}
			missionDate = s
		}
	}

	var id int64
	err := h.Pool.QueryRow(c.Request.Context(), `
		INSERT INTO volunteer_missions
		  (title, title_ar, title_sorani, title_badini,
		   description, description_ar, description_sorani, description_badini,
		   city, mission_date, needed_volunteers, status, project_request_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
		RETURNING id`,
		title,
		optStringOrNil(req.TitleAr), optStringOrNil(req.TitleSorani), optStringOrNil(req.TitleBadini),
		optStringOrNil(req.Description), optStringOrNil(req.DescriptionAr),
		optStringOrNil(req.DescriptionSorani), optStringOrNil(req.DescriptionBadini),
		optStringOrNil(req.City), missionDate,
		nullableIntPtr(req.NeededVolunteers), status, nullableInt64Ptr(req.ProjectRequestID),
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	// Phase 22 — broadcast to all volunteers when a mission is OPEN.
	// Drafts (and pre-closed missions for some reason) don't trigger
	// because nothing has changed for volunteers yet.
	if status == "open" {
		city := ""
		if req.City != nil { city = strings.TrimSpace(*req.City) }
		date := ""
		if req.MissionDate != nil { date = strings.TrimSpace(*req.MissionDate) }
		h.broadcastInBackground(3 /* role_id volunteers */,
			notify.NewVolunteerMissionMsg(title, city, date, id))
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": status})
}

// nullableInt64Ptr returns nil when the pointer is nil/zero so we INSERT NULL.
func nullableInt64Ptr(v *int64) any {
	if v == nil || *v <= 0 {
		return nil
	}
	return *v
}
