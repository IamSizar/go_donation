package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
)

// BeneficiaryHandler ports percentage/api/beneficiary_cases and
// percentage/api/beneficiary_project_requests.
type BeneficiaryHandler struct {
	Store    *beneficiary.Store
	Users    *users.Store
	Notifier *notify.Notifier
}

func NewBeneficiaryHandler(s *beneficiary.Store, u *users.Store, n *notify.Notifier) *BeneficiaryHandler {
	return &BeneficiaryHandler{Store: s, Users: u, Notifier: n}
}

// ----- /api/beneficiary_cases -----

// GET /api/beneficiary_cases?user_id=N&status=approved
// - With user_id: returns user's own cases (Bearer required, user must match).
// - Without user_id: public list of approved cases (no auth required).
func (h *BeneficiaryHandler) GetCases(c *gin.Context) {
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	status := strings.TrimSpace(c.Query("status"))

	if uid > 0 {
		tokenUser, _ := auth.UserFromGin(c)
		if tokenUser == nil || tokenUser.UserID != uid {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Unauthorized request. Please sign in again.",
			})
			return
		}
		items, err := h.Store.ListCasesForUser(c.Request.Context(), uid, status, 50)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
		return
	}

	if status == "" {
		status = "approved"
	}
	items, err := h.Store.ListPublicCases(c.Request.Context(), status, 50)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/beneficiary_cases
// Bearer required, role_id must be 2 (beneficiary), user_id must match token.
func (h *BeneficiaryHandler) PostCase(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	data := collectBody(c)
	uid := int64(asInt(data["user_id"]))
	if uid <= 0 || uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request. Please sign in again."})
		return
	}
	if tokenUser.RoleID != 2 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	in := beneficiary.CaseInput{
		UserID:        uid,
		CaseCode:      strings.TrimSpace(asStr(data["case_code"])),
		PublicTitle:   strings.TrimSpace(firstNonEmpty(asStr(data["public_title"]), asStr(data["title"]))),
		PriorityLevel: strings.TrimSpace(asStr(data["priority_level"])),
	}
	if in.PublicTitle == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing public_title."})
		return
	}
	assignOptStr(&in.PublicTitleAr, data["public_title_ar"], 255)
	assignOptStr(&in.FullName, data["full_name"], 255)
	assignOptStr(&in.NationalID, data["national_id"], 64)
	assignOptStr(&in.Phone, data["phone"], 64)
	assignOptStr(&in.City, data["city"], 128)
	assignOptStr(&in.District, data["district"], 128)
	assignOptStr(&in.Address, data["address"], 2000)
	if n := asInt(data["family_members_count"]); n > 0 {
		in.FamilyMembersCount = &n
	}
	if amt, ok := asFloat(data["income_amount"]); ok {
		in.IncomeAmount = &amt
	}
	assignOptStr(&in.HousingStatus, data["housing_status"], 128)
	assignOptStr(&in.WorkStatus, data["work_status"], 128)
	assignOptStr(&in.HealthStatus, data["health_status"], 2000)
	assignOptStr(&in.EducationStatus, data["education_status"], 2000)
	assignOptStr(&in.ActualNeeds, data["actual_needs"], 3000)

	id, code, err := h.Store.InsertCase(c.Request.Context(), in)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	// Phase 18 — uses the centralised 4-language template. The old EN+AR
	// inline strings here are now in notify/templates.go for consistency.
	_, _ = h.Notifier.Send(c.Request.Context(), uid,
		notify.BeneficiaryCaseSubmittedMsg(in.PublicTitle, id))
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        id,
		"case_code": code,
		"status":    "submitted",
	})
}

// ----- /api/beneficiary_project_requests -----

// GET /api/beneficiary_project_requests?user_id=N&status=...
// Bearer required, user_id must match token.
func (h *BeneficiaryHandler) GetRequests(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	uid, err := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing user_id."})
		return
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request. Please sign in again."})
		return
	}
	items, err := h.Store.ListRequestsForUser(c.Request.Context(), uid, strings.TrimSpace(c.Query("status")), 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/beneficiary_project_requests
// Accepts both Flutter camelCase keys and snake_case. Bearer + role 2 required.
func (h *BeneficiaryHandler) PostRequest(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Please sign in again."})
		return
	}

	data := collectBody(c)
	// Flutter camelCase → snake_case fallbacks
	mapKey(data, "userId", "user_id")
	mapKey(data, "title", "project_title")
	mapKey(data, "beneficiaryName", "beneficiary_community_name")
	mapKey(data, "peopleAffected", "people_affected_total")
	mapKey(data, "maleCount", "male_count")
	mapKey(data, "femaleCount", "female_count")
	mapKey(data, "volunteerAgeProfile", "volunteer_age_profile")
	mapKey(data, "volunteerSkills", "volunteer_skills_knowledge")
	mapKey(data, "peopleVolunteerDescription", "people_volunteers_extra_description")
	mapKey(data, "contactName", "contact_person_name")
	mapKey(data, "description", "description_long")

	uid := int64(asInt(data["user_id"]))
	if uid <= 0 || uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request. Please sign in again."})
		return
	}
	if tokenUser.RoleID != 2 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	amount, _ := asFloat(data["amount_needed"])
	if amount <= 0 {
		amount, _ = asFloat(data["amount"])
	}

	in := beneficiary.RequestInput{
		UserID:                   uid,
		ProjectTitle:             asStr(data["project_title"]),
		Category:                 asStr(data["category"]),
		Summary:                  asStr(data["summary"]),
		DescriptionLong:          asStr(data["description_long"]),
		AmountNeeded:             amount,
		Currency:                 asStr(data["currency"]),
		Location:                 asStr(data["location"]),
		BeneficiaryCommunityName: asStr(data["beneficiary_community_name"]),
		Status:                   asStr(data["status"]),
	}
	assignOptStr(&in.ProjectTitleAr, data["project_title_ar"], 255)
	assignOptStr(&in.CategoryAr, data["category_ar"], 128)
	assignOptStr(&in.SummaryAr, data["summary_ar"], 5000)
	assignOptStr(&in.DescriptionLongAr, data["description_long_ar"], 12000)
	assignOptStr(&in.LocationAr, data["location_ar"], 255)
	assignOptStr(&in.BeneficiaryCommunityNameAr, data["beneficiary_community_name_ar"], 255)
	if n := asInt(data["people_affected_total"]); n > 0 {
		in.PeopleAffectedTotal = &n
	}
	if n := asInt(data["male_count"]); n > 0 {
		in.MaleCount = &n
	}
	if n := asInt(data["female_count"]); n > 0 {
		in.FemaleCount = &n
	}
	assignOptStr(&in.VolunteerAgeProfile, data["volunteer_age_profile"], 1000)
	assignOptStr(&in.VolunteerSkillsKnowledge, data["volunteer_skills_knowledge"], 3000)
	assignOptStr(&in.PeopleVolunteersExtraDesc, data["people_volunteers_extra_description"], 3000)
	assignOptStr(&in.TimelineTarget, data["timeline_target"], 255)
	assignOptStr(&in.ContactPersonName, data["contact_person_name"], 255)
	assignOptStr(&in.ContactPhone, data["contact_phone"], 32)
	assignOptStr(&in.ContactEmail, data["contact_email"], 255)
	assignOptStr(&in.OtherNotes, data["other_notes"], 3000)

	id, storedStatus, err := h.Store.InsertRequest(c.Request.Context(), in)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid or incomplete data. Required: user_id, project title, category, summary, description, amount > 0, currency, location, beneficiary name.",
		})
		return
	}
	// Phase 18 — uses centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), uid,
		notify.ProjectRequestSubmittedMsg(in.ProjectTitle, id))
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"id":      id,
		"status":  storedStatus,
	})
}

// ----- helpers -----

// GET /api/admin/beneficiary_cases?page=&per_page=&status=
// Admin-only view across all users. Bearer required.
func (h *BeneficiaryHandler) AdminCases(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	status := strings.TrimSpace(c.Query("status"))
	if strings.EqualFold(status, "all") {
		status = ""
	}
	res, err := h.Store.AdminListCases(c.Request.Context(), page, perPage, status, c.Query("q"))
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

// GET /api/admin/beneficiary_project_requests?page=&per_page=&status=
func (h *BeneficiaryHandler) AdminRequests(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	status := strings.TrimSpace(c.Query("status"))
	if strings.EqualFold(status, "all") {
		status = ""
	}
	res, err := h.Store.AdminListRequests(c.Request.Context(), page, perPage, status, c.Query("q"))
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

// collectBody accepts JSON or form-encoded bodies and returns a map.
func collectBody(c *gin.Context) map[string]any {
	out := map[string]any{}
	if strings.Contains(strings.ToLower(c.ContentType()), "application/json") {
		_ = c.ShouldBindJSON(&out)
		return out
	}
	if err := c.Request.ParseForm(); err == nil {
		for k, v := range c.Request.PostForm {
			if len(v) > 0 {
				out[k] = v[0]
			}
		}
	}
	return out
}

func mapKey(m map[string]any, src, dst string) {
	if _, hasDst := m[dst]; hasDst {
		return
	}
	if v, hasSrc := m[src]; hasSrc {
		m[dst] = v
	}
}

func asStr(v any) string {
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

func asInt(v any) int {
	switch x := v.(type) {
	case float64:
		return int(x)
	case int:
		return x
	case int64:
		return int(x)
	case string:
		n, _ := strconv.Atoi(strings.TrimSpace(x))
		return n
	}
	return 0
}

func asFloat(v any) (float64, bool) {
	switch x := v.(type) {
	case float64:
		return x, true
	case int:
		return float64(x), true
	case int64:
		return float64(x), true
	case string:
		n, err := strconv.ParseFloat(strings.TrimSpace(x), 64)
		if err != nil {
			return 0, false
		}
		return n, true
	}
	return 0, false
}

func firstNonEmpty(a ...string) string {
	for _, s := range a {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}

// asStrSlice flattens whatever the JSON body delivered for a list field
// into a clean []string. Accepts:
//   - []any (typical JSON array)
//   - []string (rare, but cheap to handle)
//   - string  (a single value or comma-separated list, e.g. legacy clients)
//
// Returns an empty slice on anything else.
func asStrSlice(v any) []string {
	switch x := v.(type) {
	case []any:
		out := make([]string, 0, len(x))
		for _, item := range x {
			if s := strings.TrimSpace(asStr(item)); s != "" {
				out = append(out, s)
			}
		}
		return out
	case []string:
		out := make([]string, 0, len(x))
		for _, item := range x {
			if s := strings.TrimSpace(item); s != "" {
				out = append(out, s)
			}
		}
		return out
	case string:
		out := []string{}
		for _, item := range strings.Split(x, ",") {
			if s := strings.TrimSpace(item); s != "" {
				out = append(out, s)
			}
		}
		return out
	}
	return nil
}

// parseSchedule unpacks a JSON array like
//   [{ "day": "mon", "from": "09:00", "to": "17:00" }, ... ]
// into the typed []volunteers.DaySchedule. Caller still has to run
// NormalizeSchedule for validation + dedupe.
func parseSchedule(v any) []volunteers.DaySchedule {
	arr, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]volunteers.DaySchedule, 0, len(arr))
	for _, item := range arr {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, volunteers.DaySchedule{
			Day:      asStr(m["day"]),
			TimeFrom: asStr(firstNonEmptyAny(m["from"], m["time_from"])),
			TimeTo:   asStr(firstNonEmptyAny(m["to"], m["time_to"])),
		})
	}
	return out
}

// firstNonEmptyAny — like firstNonEmpty but accepting any-typed values.
// Used by parseSchedule which deals with map[string]any payloads.
func firstNonEmptyAny(a ...any) any {
	for _, v := range a {
		if s := strings.TrimSpace(asStr(v)); s != "" {
			return v
		}
	}
	return nil
}

// assignOptStr sets *target = &value when the raw value is a non-empty string,
// trimming and truncating to maxLen runes.
func assignOptStr(target **string, raw any, maxLen int) {
	s := strings.TrimSpace(asStr(raw))
	if s == "" {
		return
	}
	if maxLen > 0 {
		r := []rune(s)
		if len(r) > maxLen {
			s = string(r[:maxLen])
		}
	}
	*target = &s
}
