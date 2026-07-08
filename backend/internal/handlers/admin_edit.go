package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
)

// AdminEditHandler exposes partial-update ("edit modal") endpoints for Phase 10.
//
// Pattern: every handler receives a JSON body with optional fields (pointers
// in the request struct). Only fields that are explicitly present in the body
// are added to the UPDATE — anything omitted is left untouched. Status fields,
// where they appear, are validated against the same allowed-value lists used
// by admin_status.go.
//
// All routes are wired under the `admin` group in main.go, so RequireAdmin
// has already authenticated the caller before any code in here runs.
type AdminEditHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminEditHandler(pool *pgxpool.Pool) *AdminEditHandler {
	return &AdminEditHandler{Pool: pool}
}

// setBuilder accumulates `col = $N` fragments and matching args for a partial
// UPDATE statement. Callers add fields one by one and then run exec().
type setBuilder struct {
	sets []string
	args []any
}

func (b *setBuilder) add(col string, val any) {
	b.args = append(b.args, val)
	b.sets = append(b.sets, col+" = $"+strconv.Itoa(len(b.args)))
}

// exec runs `UPDATE <table> SET <sets> WHERE id = $N` and writes the JSON
// response. Returns true on success so callers can attach any extra fields to
// the success payload if they want.
func (b *setBuilder) exec(c *gin.Context, pool *pgxpool.Pool, table string, id int64) bool {
	if len(b.sets) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "No fields to update."})
		return false
	}
	b.args = append(b.args, id)
	sql := "UPDATE " + table + " SET " + strings.Join(b.sets, ", ") +
		" WHERE id = $" + strconv.Itoa(len(b.args))
	ct, err := pool.Exec(c.Request.Context(), sql, b.args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
		return false
	}
	return true
}

// ============================================================
// Partners — PATCH /api/admin/partners/:id
// ============================================================

type partnerEditReq struct {
	Name              *string `json:"name"`
	NameAr            *string `json:"name_ar"`
	NameSorani        *string `json:"name_sorani"`
	NameBadini        *string `json:"name_badini"`
	PartnerType       *string `json:"partner_type"`
	ContactPhone      *string `json:"contact_phone"`
	Website           *string `json:"website"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	LogoPath          *string `json:"logo_path"`
	Status            *string `json:"status"`
	// #26 — contact + location.
	Email          *string `json:"email"`
	SocialLinks    *string `json:"social_links"`
	Location       *string `json:"location"`
	LocationAr     *string `json:"location_ar"`
	LocationSorani *string `json:"location_sorani"`
	LocationBadini *string `json:"location_badini"`
}

func (h *AdminEditHandler) Partner(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req partnerEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}

	b := setBuilder{}
	if req.Name != nil {
		s := strings.TrimSpace(*req.Name)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "name cannot be empty."})
			return
		}
		b.add("name", s)
	}
	addOptString(&b, "name_ar", req.NameAr)
	addOptString(&b, "name_sorani", req.NameSorani)
	addOptString(&b, "name_badini", req.NameBadini)
	addOptString(&b, "partner_type", req.PartnerType)
	addOptString(&b, "contact_phone", req.ContactPhone)
	addOptString(&b, "website", req.Website)
	addOptString(&b, "description", req.Description)
	addOptString(&b, "description_ar", req.DescriptionAr)
	addOptString(&b, "description_sorani", req.DescriptionSorani)
	addOptString(&b, "description_badini", req.DescriptionBadini)
	addOptString(&b, "logo_path", req.LogoPath)
	addOptString(&b, "email", req.Email)                 // #26
	addOptString(&b, "social_links", req.SocialLinks)    // #26
	addOptString(&b, "location", req.Location)           // #26
	addOptString(&b, "location_ar", req.LocationAr)
	addOptString(&b, "location_sorani", req.LocationSorani)
	addOptString(&b, "location_badini", req.LocationBadini)

	if req.Status != nil {
		s := strings.TrimSpace(*req.Status)
		if !inSet(s, partnerStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "Invalid status. Allowed: " + strings.Join(partnerStatuses, ", "),
			})
			return
		}
		b.add("status", s)
	}

	if !b.exec(c, h.Pool, "partners", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Media — PATCH /api/admin/media/:id
// ============================================================

type mediaEditReq struct {
	Title       *string `json:"title"`
	TitleAr     *string `json:"title_ar"`
	TitleSorani *string `json:"title_sorani"`
	TitleBadini *string `json:"title_badini"`
	Body        *string `json:"body"`
	BodyAr      *string `json:"body_ar"`
	BodySorani  *string `json:"body_sorani"`
	BodyBadini  *string `json:"body_badini"`
	PostType    *string `json:"post_type"`
	MediaURL    *string `json:"media_url"`
	LinkURL     *string `json:"link_url"`
	EventDate   *string `json:"event_date"` // YYYY-MM-DD or "" to clear
	Status      *string `json:"status"`
	// #22 — "Our Work" category tag.
	CategorySlug *string `json:"category_slug"`
	// #23 — 4-language location + media gallery.
	Location       *string   `json:"location"`
	LocationAr     *string   `json:"location_ar"`
	LocationSorani *string   `json:"location_sorani"`
	LocationBadini *string   `json:"location_badini"`
	Gallery        *[]string `json:"gallery"`
}

var mediaPostTypes = []string{"news", "activity", "event", "article", "video", "marriage"}

func (h *AdminEditHandler) Media(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req mediaEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Title != nil {
		s := strings.TrimSpace(*req.Title)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "title cannot be empty."})
			return
		}
		b.add("title", s)
	}
	addOptString(&b, "title_ar", req.TitleAr)
	addOptString(&b, "title_sorani", req.TitleSorani)
	addOptString(&b, "title_badini", req.TitleBadini)
	addOptString(&b, "body", req.Body)
	addOptString(&b, "body_ar", req.BodyAr)
	addOptString(&b, "body_sorani", req.BodySorani)
	addOptString(&b, "body_badini", req.BodyBadini)
	addOptString(&b, "media_url", req.MediaURL)
	addOptString(&b, "link_url", req.LinkURL)
	addOptString(&b, "category_slug", req.CategorySlug) // #22
	addOptString(&b, "location", req.Location)          // #23
	addOptString(&b, "location_ar", req.LocationAr)
	addOptString(&b, "location_sorani", req.LocationSorani)
	addOptString(&b, "location_badini", req.LocationBadini)
	if req.Gallery != nil { // #23 — replace the whole gallery array
		b.add("gallery", cleanStringSlice(*req.Gallery))
	}
	if req.PostType != nil {
		pt := strings.TrimSpace(*req.PostType)
		if !inSet(pt, mediaPostTypes) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid post_type. Allowed: " + strings.Join(mediaPostTypes, ", ")})
			return
		}
		b.add("post_type", pt)
	}
	if req.EventDate != nil {
		if !addOptDate(c, &b, "event_date", req.EventDate) {
			return
		}
	}
	if req.Status != nil {
		s := strings.TrimSpace(*req.Status)
		if !inSet(s, mediaStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(mediaStatuses, ", ")})
			return
		}
		b.add("status", s)
	}
	if !b.exec(c, h.Pool, "media_posts", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Community — PATCH /api/admin/community/:id
// ============================================================

type communityEditReq struct {
	Name              *string `json:"name"`
	NameAr            *string `json:"name_ar"`
	NameSorani        *string `json:"name_sorani"`
	NameBadini        *string `json:"name_badini"`
	Category          *string `json:"category"`
	City              *string `json:"city"`
	Address           *string `json:"address"`
	Phone             *string `json:"phone"`
	Email             *string `json:"email"`
	Website           *string `json:"website"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	Latitude          *string `json:"latitude"`
	Longitude         *string `json:"longitude"`
	Status            *string `json:"status"`
	// #29 — City Guide sectors, 4-language opening hours, photo gallery.
	Sectors            *[]string `json:"sectors"`
	OpeningHours       *string   `json:"opening_hours"`
	OpeningHoursAr     *string   `json:"opening_hours_ar"`
	OpeningHoursSorani *string   `json:"opening_hours_sorani"`
	OpeningHoursBadini *string   `json:"opening_hours_badini"`
	Gallery            *[]string `json:"gallery"`
	// #48 — approximate location for privacy ('approx' | 'exact').
	ApproxLocation *string `json:"approx_location"`
}

func (h *AdminEditHandler) Community(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req communityEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Name != nil {
		s := strings.TrimSpace(*req.Name)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "name cannot be empty."})
			return
		}
		b.add("name", s)
	}
	addOptString(&b, "name_ar", req.NameAr)
	addOptString(&b, "name_sorani", req.NameSorani)
	addOptString(&b, "name_badini", req.NameBadini)
	if req.Category != nil {
		s := strings.TrimSpace(*req.Category)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "category cannot be empty."})
			return
		}
		b.add("category", s)
	}
	addOptString(&b, "city", req.City)
	addOptString(&b, "address", req.Address)
	addOptString(&b, "phone", req.Phone)
	addOptString(&b, "email", req.Email)
	addOptString(&b, "website", req.Website)
	addOptString(&b, "description", req.Description)
	addOptString(&b, "description_ar", req.DescriptionAr)
	addOptString(&b, "description_sorani", req.DescriptionSorani)
	addOptString(&b, "description_badini", req.DescriptionBadini)
	addOptString(&b, "latitude", req.Latitude)
	addOptString(&b, "longitude", req.Longitude)
	// #29 — sectors + 4-language opening hours + gallery.
	addOptString(&b, "opening_hours", req.OpeningHours)
	addOptString(&b, "opening_hours_ar", req.OpeningHoursAr)
	addOptString(&b, "opening_hours_sorani", req.OpeningHoursSorani)
	addOptString(&b, "opening_hours_badini", req.OpeningHoursBadini)
	if req.Sectors != nil { // replace the whole sectors array
		b.add("sectors", cleanStringSlice(*req.Sectors))
	}
	if req.Gallery != nil { // replace the whole gallery array
		b.add("gallery", cleanStringSlice(*req.Gallery))
	}
	if req.ApproxLocation != nil { // #48 — privacy: 'approx' → 1, else 0
		v := 0
		if s := strings.TrimSpace(*req.ApproxLocation); s == "approx" || s == "1" {
			v = 1
		}
		b.add("approx_location", v)
	}
	if req.Status != nil {
		s := strings.TrimSpace(*req.Status)
		if !inSet(s, communityStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(communityStatuses, ", ")})
			return
		}
		b.add("status", s)
	}
	if !b.exec(c, h.Pool, "city_directory_entries", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// MarriageProfile — PATCH /api/admin/marriage/:id
// ============================================================

type marriageEditReq struct {
	Gender             *string `json:"gender"`
	Age                *int    `json:"age"`
	City               *string `json:"city"`
	SocialSummary      *string `json:"social_summary"`
	PrivateNotes       *string `json:"private_notes"`
	VisibilityLevel    *string `json:"visibility_level"`
	SubscriptionStatus *string `json:"subscription_status"`
	Status             *string `json:"status"`
}

var marriageVisibility = []string{"private", "employee_only", "matched_summary"}
var marriageSubscription = []string{"free", "paid", "waived"}

func (h *AdminEditHandler) Marriage(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req marriageEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	addOptString(&b, "gender", req.Gender)
	if req.Age != nil {
		if *req.Age < 0 || *req.Age > 200 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "age must be 0..200."})
			return
		}
		b.add("age", *req.Age)
	}
	addOptString(&b, "city", req.City)
	addOptString(&b, "social_summary", req.SocialSummary)
	addOptString(&b, "private_notes", req.PrivateNotes)
	if req.VisibilityLevel != nil {
		v := strings.TrimSpace(*req.VisibilityLevel)
		if !inSet(v, marriageVisibility) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid visibility_level. Allowed: " + strings.Join(marriageVisibility, ", ")})
			return
		}
		b.add("visibility_level", v)
	}
	if req.SubscriptionStatus != nil {
		v := strings.TrimSpace(*req.SubscriptionStatus)
		if !inSet(v, marriageSubscription) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid subscription_status. Allowed: " + strings.Join(marriageSubscription, ", ")})
			return
		}
		b.add("subscription_status", v)
	}
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, marriageStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(marriageStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "marriage_profiles", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// MarketplaceProduct — PATCH /api/admin/marketplace/products/:id
// ============================================================

type productEditReq struct {
	Name              *string  `json:"name"`
	NameAr            *string  `json:"name_ar"`
	NameSorani        *string  `json:"name_sorani"`
	NameBadini        *string  `json:"name_badini"`
	Description       *string  `json:"description"`
	DescriptionAr     *string  `json:"description_ar"`
	DescriptionSorani *string  `json:"description_sorani"`
	DescriptionBadini *string  `json:"description_badini"`
	Category          *string  `json:"category"`
	Price             *float64 `json:"price"`
	Currency          *string  `json:"currency"`
	ImagePath         *string  `json:"image_path"`
	StockQuantity     *int     `json:"stock_quantity"`
	Status            *string  `json:"status"`
	// #28 — CMS category + SKU + specs + labels.
	CategorySlug *string   `json:"category_slug"`
	SKU          *string   `json:"sku"`
	Specs        *string   `json:"specs"`
	Labels       *[]string `json:"labels"`
}

// marketplaceLabels is the fixed set of allowed product badges (#28).
var marketplaceLabels = []string{"new", "sale", "featured", "used", "in_stock"}

// sanitizeLabels keeps only recognized labels, de-duplicated, preserving order.
func sanitizeLabels(in []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, s := range in {
		s = strings.ToLower(strings.TrimSpace(s))
		if s != "" && inSet(s, marketplaceLabels) && !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

func (h *AdminEditHandler) MarketplaceProduct(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req productEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Name != nil {
		s := strings.TrimSpace(*req.Name)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "name cannot be empty."})
			return
		}
		b.add("name", s)
	}
	addOptString(&b, "name_ar", req.NameAr)
	addOptString(&b, "name_sorani", req.NameSorani)
	addOptString(&b, "name_badini", req.NameBadini)
	addOptString(&b, "description", req.Description)
	addOptString(&b, "description_ar", req.DescriptionAr)
	addOptString(&b, "description_sorani", req.DescriptionSorani)
	addOptString(&b, "description_badini", req.DescriptionBadini)
	addOptString(&b, "category", req.Category)
	addOptString(&b, "category_slug", req.CategorySlug) // #28
	addOptString(&b, "sku", req.SKU)
	addOptString(&b, "specs", req.Specs)
	if req.Labels != nil {
		b.add("labels", sanitizeLabels(*req.Labels))
	}
	if req.Price != nil {
		if *req.Price < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "price must be >= 0."})
			return
		}
		b.add("price", *req.Price)
	}
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if len(v) != 3 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
			return
		}
		b.add("currency", v)
	}
	addOptString(&b, "image_path", req.ImagePath)
	if req.StockQuantity != nil {
		if *req.StockQuantity < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "stock_quantity must be >= 0."})
			return
		}
		b.add("stock_quantity", *req.StockQuantity)
	}
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, marketplaceProductStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(marketplaceProductStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "marketplace_products", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// MarketplaceOrder — PATCH /api/admin/marketplace/orders/:id
// ============================================================

type orderEditReq struct {
	Quantity    *int     `json:"quantity"`
	TotalAmount *float64 `json:"total_amount"`
	Currency    *string  `json:"currency"`
	Status      *string  `json:"status"`
	BuyerNote   *string  `json:"buyer_note"`
}

func (h *AdminEditHandler) MarketplaceOrder(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req orderEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Quantity != nil {
		if *req.Quantity < 1 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "quantity must be >= 1."})
			return
		}
		b.add("quantity", *req.Quantity)
	}
	if req.TotalAmount != nil {
		if *req.TotalAmount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "total_amount must be >= 0."})
			return
		}
		b.add("total_amount", *req.TotalAmount)
	}
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if len(v) != 3 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
			return
		}
		b.add("currency", v)
	}
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, marketplaceOrderStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(marketplaceOrderStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	addOptString(&b, "buyer_note", req.BuyerNote)
	if !b.exec(c, h.Pool, "marketplace_orders", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// BeneficiaryCase — PATCH /api/admin/beneficiary_cases/:id
// ============================================================

type caseEditReq struct {
	PublicTitle        *string  `json:"public_title"`
	PublicTitleAr      *string  `json:"public_title_ar"`
	PublicTitleSorani  *string  `json:"public_title_sorani"`
	PublicTitleBadini  *string  `json:"public_title_badini"`
	FullName           *string  `json:"full_name"`
	NationalID         *string  `json:"national_id"`
	Phone              *string  `json:"phone"`
	City               *string  `json:"city"`
	District           *string  `json:"district"`
	Address            *string  `json:"address"`
	FamilyMembersCount *int     `json:"family_members_count"`
	IncomeAmount       *float64 `json:"income_amount"`
	HousingStatus      *string  `json:"housing_status"`
	WorkStatus         *string  `json:"work_status"`
	HealthStatus       *string  `json:"health_status"`
	EducationStatus    *string  `json:"education_status"`
	ActualNeeds        *string  `json:"actual_needs"`
	PriorityLevel      *string  `json:"priority_level"`
	VerificationStatus *string  `json:"verification_status"`
	PublicVisibility   *string  `json:"public_visibility"`
	ReviewNotes        *string  `json:"review_notes"`
}

var casePriorityLevels = []string{"low", "medium", "high", "urgent"}
var casePublicVisibility = []string{"code_only", "summary", "hidden"}

func (h *AdminEditHandler) BeneficiaryCase(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req caseEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.PublicTitle != nil {
		s := strings.TrimSpace(*req.PublicTitle)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "public_title cannot be empty."})
			return
		}
		b.add("public_title", s)
	}
	addOptString(&b, "public_title_ar", req.PublicTitleAr)
	addOptString(&b, "public_title_sorani", req.PublicTitleSorani)
	addOptString(&b, "public_title_badini", req.PublicTitleBadini)
	addOptString(&b, "full_name", req.FullName)
	addOptString(&b, "national_id", req.NationalID)
	addOptString(&b, "phone", req.Phone)
	addOptString(&b, "city", req.City)
	addOptString(&b, "district", req.District)
	addOptString(&b, "address", req.Address)
	if req.FamilyMembersCount != nil {
		if *req.FamilyMembersCount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "family_members_count must be >= 0."})
			return
		}
		b.add("family_members_count", *req.FamilyMembersCount)
	}
	if req.IncomeAmount != nil {
		if *req.IncomeAmount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "income_amount must be >= 0."})
			return
		}
		b.add("income_amount", *req.IncomeAmount)
	}
	addOptString(&b, "housing_status", req.HousingStatus)
	addOptString(&b, "work_status", req.WorkStatus)
	addOptString(&b, "health_status", req.HealthStatus)
	addOptString(&b, "education_status", req.EducationStatus)
	addOptString(&b, "actual_needs", req.ActualNeeds)
	if req.PriorityLevel != nil {
		v := strings.TrimSpace(*req.PriorityLevel)
		if !inSet(v, casePriorityLevels) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid priority_level. Allowed: " + strings.Join(casePriorityLevels, ", ")})
			return
		}
		b.add("priority_level", v)
	}
	if req.VerificationStatus != nil {
		v := strings.TrimSpace(*req.VerificationStatus)
		if !inSet(v, beneficiaryCaseStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid verification_status. Allowed: " + strings.Join(beneficiaryCaseStatuses, ", ")})
			return
		}
		b.add("verification_status", v)
	}
	if req.PublicVisibility != nil {
		v := strings.TrimSpace(*req.PublicVisibility)
		if !inSet(v, casePublicVisibility) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid public_visibility. Allowed: " + strings.Join(casePublicVisibility, ", ")})
			return
		}
		b.add("public_visibility", v)
	}
	addOptString(&b, "review_notes", req.ReviewNotes)
	if !b.exec(c, h.Pool, "beneficiary_cases", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// ProjectRequest — PATCH /api/admin/beneficiary_project_requests/:id
// ============================================================

type projectReqEditReq struct {
	ProjectTitle             *string  `json:"project_title"`
	ProjectTitleAr           *string  `json:"project_title_ar"`
	ProjectTitleSorani       *string  `json:"project_title_sorani"`
	ProjectTitleBadini       *string  `json:"project_title_badini"`
	Category                 *string  `json:"category"`
	CategoryAr               *string  `json:"category_ar"`
	Summary                  *string  `json:"summary"`
	SummaryAr                *string  `json:"summary_ar"`
	DescriptionLong          *string  `json:"description_long"`
	DescriptionLongAr        *string  `json:"description_long_ar"`
	AmountNeeded             *float64 `json:"amount_needed"`
	Currency                 *string  `json:"currency"`
	Location                 *string  `json:"location"`
	LocationAr               *string  `json:"location_ar"`
	BeneficiaryCommunityName *string  `json:"beneficiary_community_name"`
	PeopleAffectedTotal      *int     `json:"people_affected_total"`
	MaleCount                *int     `json:"male_count"`
	FemaleCount              *int     `json:"female_count"`
	TimelineTarget           *string  `json:"timeline_target"`
	ContactPersonName        *string  `json:"contact_person_name"`
	ContactPhone             *string  `json:"contact_phone"`
	ContactEmail             *string  `json:"contact_email"`
	OtherNotes               *string  `json:"other_notes"`
	Status                   *string  `json:"status"`
}

func (h *AdminEditHandler) ProjectRequest(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req projectReqEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.ProjectTitle != nil {
		s := strings.TrimSpace(*req.ProjectTitle)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "project_title cannot be empty."})
			return
		}
		b.add("project_title", s)
	}
	addOptString(&b, "project_title_ar", req.ProjectTitleAr)
	addOptString(&b, "project_title_sorani", req.ProjectTitleSorani)
	addOptString(&b, "project_title_badini", req.ProjectTitleBadini)
	if req.Category != nil {
		s := strings.TrimSpace(*req.Category)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "category cannot be empty."})
			return
		}
		b.add("category", s)
	}
	addOptString(&b, "category_ar", req.CategoryAr)
	if req.Summary != nil {
		s := strings.TrimSpace(*req.Summary)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "summary cannot be empty."})
			return
		}
		b.add("summary", s)
	}
	addOptString(&b, "summary_ar", req.SummaryAr)
	if req.DescriptionLong != nil {
		s := strings.TrimSpace(*req.DescriptionLong)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "description_long cannot be empty."})
			return
		}
		b.add("description_long", s)
	}
	addOptString(&b, "description_long_ar", req.DescriptionLongAr)
	if req.AmountNeeded != nil {
		if *req.AmountNeeded < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "amount_needed must be >= 0."})
			return
		}
		b.add("amount_needed", *req.AmountNeeded)
	}
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if len(v) != 3 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
			return
		}
		b.add("currency", v)
	}
	if req.Location != nil {
		s := strings.TrimSpace(*req.Location)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "location cannot be empty."})
			return
		}
		b.add("location", s)
	}
	addOptString(&b, "location_ar", req.LocationAr)
	if req.BeneficiaryCommunityName != nil {
		s := strings.TrimSpace(*req.BeneficiaryCommunityName)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "beneficiary_community_name cannot be empty."})
			return
		}
		b.add("beneficiary_community_name", s)
	}
	if req.PeopleAffectedTotal != nil {
		if *req.PeopleAffectedTotal < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "people_affected_total must be >= 0."})
			return
		}
		b.add("people_affected_total", *req.PeopleAffectedTotal)
	}
	if req.MaleCount != nil {
		if *req.MaleCount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "male_count must be >= 0."})
			return
		}
		b.add("male_count", *req.MaleCount)
	}
	if req.FemaleCount != nil {
		if *req.FemaleCount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "female_count must be >= 0."})
			return
		}
		b.add("female_count", *req.FemaleCount)
	}
	addOptString(&b, "timeline_target", req.TimelineTarget)
	addOptString(&b, "contact_person_name", req.ContactPersonName)
	addOptString(&b, "contact_phone", req.ContactPhone)
	addOptString(&b, "contact_email", req.ContactEmail)
	addOptString(&b, "other_notes", req.OtherNotes)
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, projectRequestStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(projectRequestStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "beneficiary_project_requests", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Sponsorship — PATCH /api/admin/sponsorships/:id
// ============================================================

type sponsorshipEditReq struct {
	SponsorshipType  *string  `json:"sponsorship_type"`
	Amount           *float64 `json:"amount"`
	Currency         *string  `json:"currency"`
	ScheduleInterval *string  `json:"schedule_interval"`
	NextDueDate      *string  `json:"next_due_date"` // YYYY-MM-DD or "" to clear
	Status           *string  `json:"status"`
	Notes            *string  `json:"notes"`
}

var sponsorshipIntervals = []string{"weekly", "monthly", "quarterly", "yearly"}

func (h *AdminEditHandler) Sponsorship(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req sponsorshipEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.SponsorshipType != nil {
		s := strings.TrimSpace(*req.SponsorshipType)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "sponsorship_type cannot be empty."})
			return
		}
		b.add("sponsorship_type", s)
	}
	if req.Amount != nil {
		if *req.Amount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "amount must be >= 0."})
			return
		}
		b.add("amount", *req.Amount)
	}
	if req.Currency != nil {
		v := strings.ToUpper(strings.TrimSpace(*req.Currency))
		if len(v) != 3 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "currency must be a 3-letter code."})
			return
		}
		b.add("currency", v)
	}
	if req.ScheduleInterval != nil {
		v := strings.TrimSpace(*req.ScheduleInterval)
		if !inSet(v, sponsorshipIntervals) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid schedule_interval. Allowed: " + strings.Join(sponsorshipIntervals, ", ")})
			return
		}
		b.add("schedule_interval", v)
	}
	if req.NextDueDate != nil {
		if !addOptDate(c, &b, "next_due_date", req.NextDueDate) {
			return
		}
	}
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, sponsorshipStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(sponsorshipStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	addOptString(&b, "notes", req.Notes)
	if !b.exec(c, h.Pool, "sponsorships", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// InKindDonation — PATCH /api/admin/in_kind_donations/:id
// ============================================================

type inKindEditReq struct {
	Category      *string `json:"category"`
	ItemName      *string `json:"item_name"`
	Quantity      *string `json:"quantity"`
	ConditionNote *string `json:"condition_note"`
	PickupAddress *string `json:"pickup_address"`
	Notes         *string `json:"notes"`
	Status        *string `json:"status"`
}

func (h *AdminEditHandler) InKindDonation(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req inKindEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Category != nil {
		s := strings.TrimSpace(*req.Category)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "category cannot be empty."})
			return
		}
		b.add("category", s)
	}
	if req.ItemName != nil {
		s := strings.TrimSpace(*req.ItemName)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "item_name cannot be empty."})
			return
		}
		b.add("item_name", s)
	}
	addOptString(&b, "quantity", req.Quantity)
	addOptString(&b, "condition_note", req.ConditionNote)
	addOptString(&b, "pickup_address", req.PickupAddress)
	addOptString(&b, "notes", req.Notes)
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, inKindStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(inKindStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "in_kind_donations", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// SupportTicket — PATCH /api/admin/support_tickets/:id
// ============================================================

type ticketEditReq struct {
	Subject *string `json:"subject"`
	Message *string `json:"message"`
	Status  *string `json:"status"`
}

func (h *AdminEditHandler) SupportTicket(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req ticketEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.Subject != nil {
		s := strings.TrimSpace(*req.Subject)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "subject cannot be empty."})
			return
		}
		b.add("subject", s)
	}
	if req.Message != nil {
		s := strings.TrimSpace(*req.Message)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "message cannot be empty."})
			return
		}
		b.add("message", s)
	}
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, supportStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(supportStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "support_tickets", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Donation — PATCH /api/admin/donations/:id
// ============================================================
//
// The status-only mutation lives in admin_status.go.Donation; this PATCH
// covers the broader edit (message, amount, method, etc.).

type donationEditReq struct {
	ReferenceNumber *string `json:"reference_number"`
	Message         *string `json:"message"`
	Amount          *string `json:"amount"` // amount is VARCHAR(200) in this schema
	PaymentMethod   *string `json:"payment_method"`
	ImpactNote      *string `json:"impact_note"`
	PaymentStatus   *int    `json:"payment_status"`
	DeliveryStatus  *string `json:"delivery_status"`
	DonationType    *string `json:"donation_type"`
}

func (h *AdminEditHandler) Donation(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req donationEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	addOptString(&b, "reference_number", req.ReferenceNumber)
	if req.Message != nil {
		s := strings.TrimSpace(*req.Message)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "message cannot be empty."})
			return
		}
		b.add("message", s)
	}
	if req.Amount != nil {
		s := strings.TrimSpace(*req.Amount)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "amount cannot be empty."})
			return
		}
		b.add("amount", s)
	}
	if req.PaymentMethod != nil {
		s := strings.TrimSpace(*req.PaymentMethod)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "payment_method cannot be empty."})
			return
		}
		b.add("payment_method", s)
	}
	addOptString(&b, "impact_note", req.ImpactNote)
	if req.PaymentStatus != nil {
		if !inSetInt(*req.PaymentStatus, donationPaymentStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid payment_status. Allowed: 1 (success), 2 (pending), 3 (failed)."})
			return
		}
		b.add("payment_status", *req.PaymentStatus)
	}
	if req.DeliveryStatus != nil {
		v := strings.TrimSpace(*req.DeliveryStatus)
		if !inSet(v, donationDeliveryStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid delivery_status. Allowed: " + strings.Join(donationDeliveryStatuses, ", ")})
			return
		}
		b.add("delivery_status", v)
	}
	if req.DonationType != nil {
		v := strings.ToLower(strings.TrimSpace(*req.DonationType))
		if !inSet(v, donationTypes) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation_type. Allowed: " + strings.Join(donationTypes, ", ")})
			return
		}
		b.add("donation_type", v)
	}
	if !b.exec(c, h.Pool, "donations", id) {
		return
	}
	// Editing a donation's amount or delivery_status can change how much the
	// campaign has confirmed-raised, so re-derive that total. (Shared helper
	// in admin_status.go — counts only received/delivered donations.)
	recalcCampaignRaisedForDonation(c.Request.Context(), h.Pool, id)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// VolunteerApplication — PATCH /api/admin/volunteer_applications/:id
// ============================================================

type volunteerEditReq struct {
	FullName     *string   `json:"full_name"`
	Phone        *string   `json:"phone"`
	City         *string   `json:"city"`
	Skills       *string   `json:"skills"`
	// Phase 26 — skill_tags is now TEXT[] in postgres; admin SPA passes an
	// array of canonical keys (driver_car, first_aid, ...). Keys that
	// don't match the catalogue are dropped silently.
	SkillTags    *[]string `json:"skill_tags"`
	OtherSkill   *string   `json:"other_skill"`
	Experience   *string   `json:"experience"`
	Availability *string   `json:"availability"`
	CVLink       *string   `json:"cv_link"`
	Status       *string   `json:"status"`
}

func (h *AdminEditHandler) VolunteerApplication(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req volunteerEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	if req.FullName != nil {
		s := strings.TrimSpace(*req.FullName)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "full_name cannot be empty."})
			return
		}
		b.add("full_name", s)
	}
	addOptString(&b, "phone", req.Phone)
	addOptString(&b, "city", req.City)
	addOptString(&b, "skills", req.Skills)
	if req.SkillTags != nil {
		// Catalogue-filter so admins can't insert junk that won't render
		// in either the SPA or the mobile chip grid. `add` handles the
		// $N positioning; we pass the filtered slice as-is and pgx
		// will encode it as TEXT[].
		b.add("skill_tags", volunteers.FilterSkillKeys(*req.SkillTags))
	}
	addOptString(&b, "other_skill", req.OtherSkill)
	addOptString(&b, "experience", req.Experience)
	addOptString(&b, "availability", req.Availability)
	addOptString(&b, "cv_link", req.CVLink)
	if req.Status != nil {
		v := strings.TrimSpace(*req.Status)
		if !inSet(v, volunteerAppStatuses) {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid status. Allowed: " + strings.Join(volunteerAppStatuses, ", ")})
			return
		}
		b.add("status", v)
	}
	if !b.exec(c, h.Pool, "volunteer_applications", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ===== shared helpers =====

// cleanStringSlice trims each entry and drops the empties, so a gallery array
// never stores blank paths. Returns a non-nil empty slice for a wholly-empty
// input (→ an empty Postgres array, not NULL).
func cleanStringSlice(in []string) []string {
	out := make([]string, 0, len(in))
	for _, s := range in {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// addOptString appends a column update only when the pointer is non-nil. An
// empty string is allowed (lets admins blank out a field). When the column is
// nullable, the empty string is stored as NULL.
func addOptString(b *setBuilder, col string, val *string) {
	if val == nil {
		return
	}
	s := strings.TrimSpace(*val)
	if s == "" {
		b.args = append(b.args, nil)
	} else {
		b.args = append(b.args, s)
	}
	b.sets = append(b.sets, col+" = $"+strconv.Itoa(len(b.args)))
}

// ============================================================
// User — PATCH /api/admin/users/:id          (Phase 18)
// ============================================================
//
// Edits two tables in one transaction:
//   • `users`         — phone (only column an admin should edit; role/active/
//                       is_admin live in their own dedicated /status endpoints
//                       from Phase 9 and remain untouched here)
//   • `user_profiles` — full_name, gender, address, profile_picture
//
// If the user has no profile row yet, one is upserted. We use BEGIN/COMMIT so
// a failure on the profile UPDATE rolls back the phone change too — admins
// never see a half-applied edit.

type userEditReq struct {
	Phone          *string `json:"phone"`
	FullName       *string `json:"full_name"`
	Gender         *string `json:"gender"`
	Address        *string `json:"address"`
	ProfilePicture *string `json:"profile_picture"`
}

func (h *AdminEditHandler) User(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req userEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}

	usersHasChange := req.Phone != nil
	profileHasChange := req.FullName != nil || req.Gender != nil || req.Address != nil || req.ProfilePicture != nil
	if !usersHasChange && !profileHasChange {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "No fields to update."})
		return
	}

	tx, err := h.Pool.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer tx.Rollback(c.Request.Context())

	// users.phone — NOT NULL, so reject empty.
	if req.Phone != nil {
		s := strings.TrimSpace(*req.Phone)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "phone cannot be empty."})
			return
		}
		ct, err := tx.Exec(c.Request.Context(),
			"UPDATE users SET phone = $1 WHERE id = $2", s, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		if ct.RowsAffected() == 0 {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
			return
		}
	}

	// user_profiles — UPDATE existing row, or INSERT a fresh one if the user
	// has no profile yet. The columns are NOT NULL in the schema, so we
	// default any unspecified field to an empty string when inserting.
	//
	// Note: the table lacks a UNIQUE constraint on user_id, so we can't use
	// ON CONFLICT — we branch on "does a row exist" instead.
	if profileHasChange {
		var pid int64
		err := tx.QueryRow(c.Request.Context(),
			"SELECT id FROM user_profiles WHERE user_id = $1", id,
		).Scan(&pid)
		switch {
		case err == nil:
			// UPDATE only the sent columns. user_profiles columns are NOT NULL
			// in this schema, so we store '' on empty input rather than NULL.
			b := setBuilder{}
			addNotNullString := func(col string, val *string) {
				if val == nil {
					return
				}
				b.args = append(b.args, strings.TrimSpace(*val))
				b.sets = append(b.sets, col+" = $"+strconv.Itoa(len(b.args)))
			}
			addNotNullString("full_name", req.FullName)
			addNotNullString("gender", req.Gender)
			addNotNullString("address", req.Address)
			addNotNullString("profile_picture", req.ProfilePicture)
			if len(b.sets) > 0 {
				b.args = append(b.args, pid)
				sql := "UPDATE user_profiles SET " + strings.Join(b.sets, ", ") +
					" WHERE id = $" + strconv.Itoa(len(b.args))
				if _, err := tx.Exec(c.Request.Context(), sql, b.args...); err != nil {
					c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
					return
				}
			}
		default:
			// No profile row yet. Make sure the user itself exists before
			// inserting; Phase 17's FK would also reject orphan profiles.
			var exists bool
			if err := tx.QueryRow(c.Request.Context(),
				"SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)", id,
			).Scan(&exists); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
				return
			}
			if !exists {
				c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
				return
			}
			// NOT NULL columns default to '' when not provided.
			pick := func(p *string) string {
				if p == nil {
					return ""
				}
				return strings.TrimSpace(*p)
			}
			_, err := tx.Exec(c.Request.Context(), `
				INSERT INTO user_profiles
				  (user_id, full_name, gender, address, profile_picture)
				VALUES ($1, $2, $3, $4, $5)`,
				id, pick(req.FullName), pick(req.Gender), pick(req.Address), pick(req.ProfilePicture),
			)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
				return
			}
		}
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// ============================================================
// Campaign — PATCH /api/admin/campaigns/:id
// ============================================================
//
// Note: this targets the REAL `campaigns` table (Phase 14), not the
// project-request projection the mobile app reads via /api/campaigns.

type campaignEditReq struct {
	Title             *string `json:"title"`
	TitleAr           *string `json:"title_ar"`
	TitleSorani       *string `json:"title_sorani"`
	TitleBadini       *string `json:"title_badini"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	Address           *string `json:"address"`
	Beneficiaries     *string `json:"beneficiaries"`
	GoalAmount        *string `json:"goal_amount"`
	RaisedAmount      *string `json:"raised_amount"`
	// Phase 15.1 — campaign lifecycle. One of: 'active' | 'hidden' | 'finished'.
	// nil means "leave unchanged" during a PATCH.
	Status *string `json:"status"`
}

func (h *AdminEditHandler) Campaign(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req campaignEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}

	// Required-when-provided fields: NOT NULL in the schema, so we reject
	// empty strings outright rather than turning them into NULL.
	for _, f := range []struct {
		name string
		val  *string
		col  string
	}{
		{"title", req.Title, "title"},
		{"title_ar", req.TitleAr, "title_ar"},
		{"description", req.Description, "description"},
		{"description_ar", req.DescriptionAr, "description_ar"},
		{"address", req.Address, "address"},
		{"beneficiaries", req.Beneficiaries, "beneficiaries"},
		{"goal_amount", req.GoalAmount, "goal_amount"},
		{"raised_amount", req.RaisedAmount, "raised_amount"},
	} {
		if f.val == nil {
			continue
		}
		s := strings.TrimSpace(*f.val)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": f.name + " cannot be empty."})
			return
		}
		b.add(f.col, s)
	}

	// Nullable text columns (the sorani/badini variants).
	addOptString(&b, "title_sorani", req.TitleSorani)
	addOptString(&b, "title_badini", req.TitleBadini)
	addOptString(&b, "description_sorani", req.DescriptionSorani)
	addOptString(&b, "description_badini", req.DescriptionBadini)

	// Lifecycle status — validate against the same allowed set the DB
	// check-constraint enforces, so a bad value 400s instead of 500ing.
	if req.Status != nil {
		s := strings.ToLower(strings.TrimSpace(*req.Status))
		if s != "active" && s != "hidden" && s != "finished" {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "status must be one of: active, hidden, finished.",
			})
			return
		}
		b.add("status", s)
		// Keep is_active mirrored so legacy readers don't drift.
		isActive := 0
		if s == "active" {
			isActive = 1
		}
		b.add("is_active", isActive)
	}

	if !b.exec(c, h.Pool, "campaigns", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// addOptDate validates YYYY-MM-DD (or "" → NULL) and appends the update. On
// invalid input, writes a 400 response and returns false so callers can stop.
func addOptDate(c *gin.Context, b *setBuilder, col string, val *string) bool {
	if val == nil {
		return true
	}
	s := strings.TrimSpace(*val)
	if s == "" {
		b.args = append(b.args, nil)
		b.sets = append(b.sets, col+" = $"+strconv.Itoa(len(b.args)))
		return true
	}
	// crude YYYY-MM-DD shape check; pgx parses the actual date.
	if len(s) != 10 || s[4] != '-' || s[7] != '-' {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": col + " must be YYYY-MM-DD."})
		return false
	}
	b.args = append(b.args, s)
	b.sets = append(b.sets, col+" = $"+strconv.Itoa(len(b.args)))
	return true
}

// ============================================================
// Volunteer mission — PATCH /api/admin/missions/:id  (Phase 22)
// ============================================================

func (h *AdminEditHandler) Mission(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req missionEditReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	b := setBuilder{}
	// Title is NOT NULL; reject empty-but-provided to avoid trashing the row.
	if req.Title != nil {
		s := strings.TrimSpace(*req.Title)
		if s == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "title cannot be empty."})
			return
		}
		b.add("title", s)
	}
	addOptString(&b, "title_ar", req.TitleAr)
	addOptString(&b, "title_sorani", req.TitleSorani)
	addOptString(&b, "title_badini", req.TitleBadini)
	addOptString(&b, "description", req.Description)
	addOptString(&b, "description_ar", req.DescriptionAr)
	addOptString(&b, "description_sorani", req.DescriptionSorani)
	addOptString(&b, "description_badini", req.DescriptionBadini)
	addOptString(&b, "city", req.City)
	if !addOptDate(c, &b, "mission_date", req.MissionDate) {
		return
	}
	if req.NeededVolunteers != nil {
		if *req.NeededVolunteers < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "needed_volunteers must be >= 0."})
			return
		}
		b.add("needed_volunteers", *req.NeededVolunteers)
	}
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
			b.add("status", s)
		}
	}
	if req.ProjectRequestID != nil {
		if *req.ProjectRequestID <= 0 {
			b.add("project_request_id", nil)
		} else {
			b.add("project_request_id", *req.ProjectRequestID)
		}
	}
	if !b.exec(c, h.Pool, "volunteer_missions", id) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}
