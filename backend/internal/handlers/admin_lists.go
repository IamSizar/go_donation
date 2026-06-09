package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AdminListsHandler aggregates the cross-user admin list endpoints that don't
// belong to a richer domain package. Each method returns a paginated response
// with the standard envelope used elsewhere.
type AdminListsHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminListsHandler(pool *pgxpool.Pool) *AdminListsHandler {
	return &AdminListsHandler{Pool: pool}
}

type page struct {
	page       int
	perPage    int
	totalItems int
	totalPages int
}

func paginate(c *gin.Context) (int, int, int) {
	p, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	pp, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	if p < 1 {
		p = 1
	}
	if pp <= 0 || pp > 200 {
		pp = 20
	}
	return p, pp, (p - 1) * pp
}

func pageMeta(p, pp, total int) page {
	tp := (total + pp - 1) / pp
	if tp < 1 {
		tp = 1
	}
	return page{page: p, perPage: pp, totalItems: total, totalPages: tp}
}

func envelopePage(items any, meta page) gin.H {
	return gin.H{
		"success":     true,
		"items":       items,
		"page":        meta.page,
		"per_page":    meta.perPage,
		"total_items": meta.totalItems,
		"total_pages": meta.totalPages,
		"has_more":    meta.page < meta.totalPages,
	}
}

func requireAuth(c *gin.Context) bool {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return false
	}
	return true
}

// =====================================================
// /api/admin/notifications  — cross-user notifications
// =====================================================

type adminNotification struct {
	ID                   int64      `json:"id"`
	UserID               *int       `json:"user_id"`
	RoleID               *int       `json:"role_id"`
	Title                string     `json:"title"`
	TitleAr              *string    `json:"title_ar"`
	Body                 string     `json:"body"`
	BodyAr               *string    `json:"body_ar"`
	NotificationType     *string    `json:"notification_type"`
	NotificationCategory string     `json:"notification_category"`
	Priority             int        `json:"priority"`
	IsRead               int        `json:"is_read"`
	CreatedAt            time.Time  `json:"created_at"`
	ReadAt               *time.Time `json:"read_at"`
}

func (h *AdminListsHandler) Notifications(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	category := strings.TrimSpace(c.Query("category"))
	readStatus := strings.ToLower(strings.TrimSpace(c.Query("read_status")))

	args := []any{}
	where := []string{"1=1"}
	if category != "" {
		args = append(args, category)
		where = append(where, "notification_category = $"+strconv.Itoa(len(args)))
	}
	switch readStatus {
	case "read":
		where = append(where, "is_read = 1")
	case "unread":
		where = append(where, "is_read = 0")
	}
	whereSQL := strings.Join(where, " AND ")

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM app_notifications WHERE "+whereSQL, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT id, user_id, role_id, title, title_ar, body, body_ar,
		       notification_type, notification_category, priority, is_read,
		       created_at, read_at
		  FROM app_notifications
		 WHERE `+whereSQL+`
		 ORDER BY id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer rows.Close()
	items := []adminNotification{}
	for rows.Next() {
		var n adminNotification
		if err := rows.Scan(&n.ID, &n.UserID, &n.RoleID, &n.Title, &n.TitleAr, &n.Body, &n.BodyAr,
			&n.NotificationType, &n.NotificationCategory, &n.Priority, &n.IsRead,
			&n.CreatedAt, &n.ReadAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		items = append(items, n)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/in_kind_donations
// =====================================================

type adminInKind struct {
	ID            int64     `json:"id"`
	DonorUserID   *int      `json:"donor_user_id"`
	DonorPhone    *string   `json:"donor_phone"`
	DonorFullName *string   `json:"donor_full_name"`
	Category      string    `json:"category"`
	ItemName      string    `json:"item_name"`
	Quantity      *string   `json:"quantity"`
	ConditionNote *string   `json:"condition_note"`
	PickupAddress *string   `json:"pickup_address"`
	Status        string    `json:"status"`
	Notes         *string   `json:"notes"`
	CreatedAt     time.Time `json:"created_at"`
}

func (h *AdminListsHandler) InKindDonations(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	status := strings.TrimSpace(c.Query("status"))
	q := strings.TrimSpace(c.Query("q"))

	args := []any{}
	where := []string{"1=1"}
	if status != "" && !strings.EqualFold(status, "all") {
		args = append(args, status)
		where = append(where, "k.status = $"+strconv.Itoa(len(args)))
	}
	if q != "" {
		args = append(args, "%"+q+"%")
		idx := strconv.Itoa(len(args))
		where = append(where, "(k.item_name ILIKE $"+idx+" OR k.category ILIKE $"+idx+" OR k.notes ILIKE $"+idx+")")
	}
	whereSQL := strings.Join(where, " AND ")

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM in_kind_donations k WHERE "+whereSQL, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT k.id, k.donor_user_id, u.phone, up.full_name, k.category, k.item_name,
		       k.quantity, k.condition_note, k.pickup_address, k.status, k.notes, k.created_at
		  FROM in_kind_donations k
		  LEFT JOIN users u ON u.id = k.donor_user_id
		  LEFT JOIN user_profiles up ON up.user_id = k.donor_user_id
		 WHERE `+whereSQL+`
		 ORDER BY k.id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer rows.Close()
	items := []adminInKind{}
	for rows.Next() {
		var k adminInKind
		if err := rows.Scan(&k.ID, &k.DonorUserID, &k.DonorPhone, &k.DonorFullName,
			&k.Category, &k.ItemName, &k.Quantity, &k.ConditionNote, &k.PickupAddress,
			&k.Status, &k.Notes, &k.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		items = append(items, k)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/support_tickets
// =====================================================

type adminTicket struct {
	ID            int64     `json:"id"`
	UserID        *int      `json:"user_id"`
	UserPhone     *string   `json:"user_phone"`
	UserFullName  *string   `json:"user_full_name"`
	Subject       string    `json:"subject"`
	Message       string    `json:"message"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

func (h *AdminListsHandler) SupportTickets(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	status := strings.TrimSpace(c.Query("status"))
	q := strings.TrimSpace(c.Query("q"))

	args := []any{}
	where := []string{"1=1"}
	if status != "" && !strings.EqualFold(status, "all") {
		args = append(args, status)
		where = append(where, "t.status = $"+strconv.Itoa(len(args)))
	}
	if q != "" {
		args = append(args, "%"+q+"%")
		idx := strconv.Itoa(len(args))
		where = append(where, "(t.subject ILIKE $"+idx+" OR t.message ILIKE $"+idx+")")
	}
	whereSQL := strings.Join(where, " AND ")

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM support_tickets t WHERE "+whereSQL, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT t.id, t.user_id, u.phone, up.full_name,
		       t.subject, t.message, t.status, t.created_at, t.updated_at
		  FROM support_tickets t
		  LEFT JOIN users u ON u.id = t.user_id
		  LEFT JOIN user_profiles up ON up.user_id = t.user_id
		 WHERE `+whereSQL+`
		 ORDER BY t.id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer rows.Close()
	items := []adminTicket{}
	for rows.Next() {
		var t adminTicket
		if err := rows.Scan(&t.ID, &t.UserID, &t.UserPhone, &t.UserFullName,
			&t.Subject, &t.Message, &t.Status, &t.CreatedAt, &t.UpdatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		items = append(items, t)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/volunteer_applications
// =====================================================

type scheduleRow struct {
	Day      string `json:"day"`
	TimeFrom string `json:"from"`
	TimeTo   string `json:"to"`
}

type adminApplication struct {
	ID                   int64          `json:"id"`
	UserID               *int           `json:"user_id"`
	UserPhone            *string        `json:"user_phone"`
	FullName             string         `json:"full_name"`
	Phone                *string        `json:"phone"`
	City                 *string        `json:"city"`
	Skills               *string        `json:"skills"`
	SkillTags            []string       `json:"skill_tags"`
	Experience           *string        `json:"experience"`
	Availability         *string        `json:"availability"`
	AvailabilitySchedule []scheduleRow  `json:"availability_schedule"`
	Status               string         `json:"status"`
	CreatedAt            time.Time      `json:"created_at"`
}

func (h *AdminListsHandler) VolunteerApplications(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	status := strings.TrimSpace(c.Query("status"))
	q := strings.TrimSpace(c.Query("q"))
	// Phase 26: structured filters. `skill` accepts a single canonical
	// catalogue key (driver_car, first_aid, ...). `day` filters to
	// volunteers available on that day-of-week.
	skill := strings.ToLower(strings.TrimSpace(c.Query("skill")))
	day := strings.ToLower(strings.TrimSpace(c.Query("day")))

	args := []any{}
	where := []string{"1=1"}
	if status != "" && !strings.EqualFold(status, "all") {
		args = append(args, status)
		where = append(where, "a.status = $"+strconv.Itoa(len(args)))
	}
	if q != "" {
		args = append(args, "%"+q+"%")
		idx := strconv.Itoa(len(args))
		where = append(where, "(a.full_name ILIKE $"+idx+" OR a.phone ILIKE $"+idx+" OR a.city ILIKE $"+idx+" OR a.skills ILIKE $"+idx+")")
	}
	if skill != "" {
		// `a.skill_tags @> ARRAY[$N]` uses the GIN index from migration 008.
		args = append(args, skill)
		where = append(where, "a.skill_tags @> ARRAY[$"+strconv.Itoa(len(args))+"]::text[]")
	}
	if day != "" {
		args = append(args, day)
		where = append(where,
			"EXISTS (SELECT 1 FROM volunteer_application_availability va "+
				"WHERE va.application_id = a.id AND va.day_of_week = $"+strconv.Itoa(len(args))+")")
	}
	whereSQL := strings.Join(where, " AND ")

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM volunteer_applications a WHERE "+whereSQL, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	// Per-day schedule is aggregated as a JSON array via a LEFT JOIN on a
	// correlated subquery, so each application row carries its own
	// schedule without an N+1.
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT a.id, a.user_id, u.phone, a.full_name, a.phone, a.city, a.skills,
		       a.skill_tags,
		       a.experience, a.availability,
		       COALESCE(sched.schedule_json, '[]'::json),
		       a.status, a.created_at
		  FROM volunteer_applications a
		  LEFT JOIN users u ON u.id = a.user_id
		  LEFT JOIN (
		    SELECT application_id,
		           json_agg(json_build_object(
		             'day', day_of_week,
		             'from', time_from,
		             'to', time_to
		           ) ORDER BY
		             CASE day_of_week
		               WHEN 'mon' THEN 1 WHEN 'tue' THEN 2 WHEN 'wed' THEN 3
		               WHEN 'thu' THEN 4 WHEN 'fri' THEN 5 WHEN 'sat' THEN 6
		               WHEN 'sun' THEN 7
		             END
		           ) AS schedule_json
		      FROM volunteer_application_availability
		     GROUP BY application_id
		  ) sched ON sched.application_id = a.id
		 WHERE `+whereSQL+`
		 ORDER BY a.id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer rows.Close()
	items := []adminApplication{}
	for rows.Next() {
		var a adminApplication
		var scheduleJSON []byte
		if err := rows.Scan(&a.ID, &a.UserID, &a.UserPhone, &a.FullName, &a.Phone, &a.City,
			&a.Skills, &a.SkillTags, &a.Experience, &a.Availability,
			&scheduleJSON, &a.Status, &a.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		if a.SkillTags == nil {
			a.SkillTags = []string{}
		}
		if len(scheduleJSON) > 0 {
			_ = json.Unmarshal(scheduleJSON, &a.AvailabilitySchedule)
		}
		if a.AvailabilitySchedule == nil {
			a.AvailabilitySchedule = []scheduleRow{}
		}
		items = append(items, a)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/audit_logs
// =====================================================

type adminAuditLog struct {
	ID            int64     `json:"id"`
	UserID        int       `json:"user_id"`
	ActorSource   string    `json:"actor_source"`
	ActorUserID   *int      `json:"actor_user_id"`
	ChangedField  string    `json:"changed_field"`
	OldValue      *string   `json:"old_value"`
	NewValue      *string   `json:"new_value"`
	MetadataJSON  *string   `json:"metadata_json"`
	CreatedAt     time.Time `json:"created_at"`
}

func (h *AdminListsHandler) AuditLogs(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	userIDStr := strings.TrimSpace(c.Query("user_id"))
	field := strings.TrimSpace(c.Query("field"))

	args := []any{}
	where := []string{"1=1"}
	if userIDStr != "" {
		if uid, err := strconv.Atoi(userIDStr); err == nil && uid > 0 {
			args = append(args, uid)
			where = append(where, "user_id = $"+strconv.Itoa(len(args)))
		}
	}
	if field != "" {
		args = append(args, field)
		where = append(where, "changed_field = $"+strconv.Itoa(len(args)))
	}
	whereSQL := strings.Join(where, " AND ")

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM user_profile_audit_logs WHERE "+whereSQL, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT id, user_id, actor_source, actor_user_id, changed_field,
		       old_value, new_value, metadata_json, created_at
		  FROM user_profile_audit_logs
		 WHERE `+whereSQL+`
		 ORDER BY id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	defer rows.Close()
	items := []adminAuditLog{}
	for rows.Next() {
		var a adminAuditLog
		if err := rows.Scan(&a.ID, &a.UserID, &a.ActorSource, &a.ActorUserID,
			&a.ChangedField, &a.OldValue, &a.NewValue, &a.MetadataJSON, &a.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		items = append(items, a)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/campaigns — Phase 14 admin list for the REAL `campaigns` table
//
// Note: the legacy /api/campaigns endpoint (in internal/campaigns) projects
// rows from `beneficiary_project_requests` for the mobile app's backwards
// compatibility. This admin endpoint reads from the actual `campaigns` table
// so the SPA can manage its rows directly.
// =====================================================

type adminCampaign struct {
	ID                int64   `json:"id"`
	Title             string  `json:"title"`
	TitleAr           string  `json:"title_ar"`
	TitleSorani       *string `json:"title_sorani"`
	TitleBadini       *string `json:"title_badini"`
	Description       string  `json:"description"`
	DescriptionAr     string  `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	Address           string  `json:"address"`
	Beneficiaries     string  `json:"beneficiaries"`
	GoalAmount        string  `json:"goal_amount"`
	RaisedAmount      string  `json:"raised_amount"`
	IsActive          int     `json:"is_active"` // Mirror of status='active'; kept for legacy SPA clients.
	Status            string  `json:"status"`    // Phase 15.1 — 'active' | 'hidden' | 'finished'.
}

func (h *AdminListsHandler) Campaigns(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	q := strings.TrimSpace(c.Query("q"))

	args := []any{}
	where := "WHERE 1=1"
	if q != "" {
		args = append(args, "%"+q+"%")
		where += " AND (title ILIKE $" + strconv.Itoa(len(args)) +
			" OR title_ar ILIKE $" + strconv.Itoa(len(args)) +
			" OR address ILIKE $" + strconv.Itoa(len(args)) + ")"
	}

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM campaigns "+where, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT id, title, title_ar, title_sorani, title_badini,
		       description, description_ar, description_sorani, description_badini,
		       address, beneficiaries, goal_amount, raised_amount, is_active, status
		  FROM campaigns
		 `+where+`
		 ORDER BY id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()
	items := []adminCampaign{}
	for rows.Next() {
		var cm adminCampaign
		if err := rows.Scan(&cm.ID, &cm.Title, &cm.TitleAr, &cm.TitleSorani, &cm.TitleBadini,
			&cm.Description, &cm.DescriptionAr, &cm.DescriptionSorani, &cm.DescriptionBadini,
			&cm.Address, &cm.Beneficiaries, &cm.GoalAmount, &cm.RaisedAmount, &cm.IsActive, &cm.Status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		items = append(items, cm)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/volunteer_mission_signups — Phase 21
// =====================================================
//
// Cross-user list of signups so the admin can approve / mark attendance /
// mark completion / mark no_show from one page. Joins:
//   • volunteer_missions for the mission title (+ city + date for context)
//   • users + user_profiles for the volunteer's name + phone
//
// Filters:
//   ?status=pending|approved|joined|... — repeatable not supported here;
//   if more than one is needed in future, add a comma-split parser.
//   ?q=… — free-text match across mission title + volunteer name + phone.

type adminMissionSignup struct {
	ID                     int64   `json:"id"`
	UserID                 int64   `json:"user_id"`
	UserFullName           *string `json:"user_full_name"`
	UserPhone              *string `json:"user_phone"`
	MissionID              int64   `json:"mission_id"`
	MissionTitle           string  `json:"mission_title"`
	MissionCity            *string `json:"mission_city"`
	MissionDate            *string `json:"mission_date"`     // YYYY-MM-DD or null
	Status                 string  `json:"status"`
	HoursServed            string  `json:"hours_served"`     // numeric → string for display safety
	CheckedInAt            *string `json:"checked_in_at"`    // ISO-8601 or null
	CompletedAt            *string `json:"completed_at"`
	CompletionRequestedAt  *string `json:"completion_requested_at"`
	Notes                  *string `json:"notes"`
	VolunteerCompletionNote *string `json:"volunteer_completion_note"`
	CreatedAt              string  `json:"created_at"`
}

func (h *AdminListsHandler) VolunteerMissionSignups(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	q := strings.TrimSpace(c.Query("q"))
	status := strings.TrimSpace(c.Query("status"))

	where := "WHERE 1=1"
	args := []any{}
	if status != "" {
		args = append(args, status)
		where += " AND s.status = $" + strconv.Itoa(len(args))
	}
	if q != "" {
		args = append(args, "%"+q+"%")
		idx := strconv.Itoa(len(args))
		where += " AND (m.title ILIKE $" + idx +
			" OR up.full_name ILIKE $" + idx +
			" OR u.phone ILIKE $" + idx + ")"
	}

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		`SELECT COUNT(*)
		   FROM volunteer_mission_signups s
		   LEFT JOIN volunteer_missions m ON m.id = s.mission_id
		   LEFT JOIN users u              ON u.id = s.user_id
		   LEFT JOIN user_profiles up     ON up.user_id = s.user_id `+where,
		args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT s.id, s.user_id, up.full_name, u.phone,
		       s.mission_id, COALESCE(m.title, '(deleted mission)'), m.city,
		       to_char(m.mission_date, 'YYYY-MM-DD') AS mission_date,
		       s.status, s.hours_served::text,
		       to_char(s.checked_in_at,           'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS checked_in_at,
		       to_char(s.completed_at,            'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS completed_at,
		       to_char(s.completion_requested_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS completion_requested_at,
		       s.notes, s.volunteer_completion_note,
		       to_char(s.created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
		  FROM volunteer_mission_signups s
		  LEFT JOIN volunteer_missions m ON m.id = s.mission_id
		  LEFT JOIN users u              ON u.id = s.user_id
		  LEFT JOIN user_profiles up     ON up.user_id = s.user_id
		 `+where+`
		 ORDER BY
		   CASE s.status
		     WHEN 'pending'              THEN 0
		     WHEN 'completion_requested' THEN 1
		     WHEN 'approved'             THEN 2
		     WHEN 'joined'               THEN 3
		     ELSE                             9
		   END,
		   s.created_at DESC, s.id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()
	items := []adminMissionSignup{}
	for rows.Next() {
		var r adminMissionSignup
		if err := rows.Scan(
			&r.ID, &r.UserID, &r.UserFullName, &r.UserPhone,
			&r.MissionID, &r.MissionTitle, &r.MissionCity, &r.MissionDate,
			&r.Status, &r.HoursServed,
			&r.CheckedInAt, &r.CompletedAt, &r.CompletionRequestedAt,
			&r.Notes, &r.VolunteerCompletionNote,
			&r.CreatedAt,
		); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		items = append(items, r)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// Silence unused-import warning when this is the only consumer (time has
// callers elsewhere in this file so no-op here).
var _ = time.Now

// =====================================================
// /api/admin/missions — Phase 22 — volunteer mission management
// =====================================================
//
// Admin browse-and-edit list. Each row includes signup counts so the admin
// can see "5 of 8 needed volunteers approved" at a glance.

type adminMission struct {
	ID                int64   `json:"id"`
	Title             string  `json:"title"`
	TitleAr           *string `json:"title_ar"`
	TitleSorani       *string `json:"title_sorani"`
	TitleBadini       *string `json:"title_badini"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	City              *string `json:"city"`
	MissionDate       *string `json:"mission_date"`        // YYYY-MM-DD
	NeededVolunteers  *int    `json:"needed_volunteers"`
	Status            string  `json:"status"`
	ProjectRequestID  *int64  `json:"project_request_id"`
	AcceptedVolunteers int    `json:"accepted_volunteers"` // approved+joined+completed
	PendingVolunteers  int    `json:"pending_volunteers"`  // pending+completion_requested
	CreatedAt         string  `json:"created_at"`
}

func (h *AdminListsHandler) VolunteerMissions(c *gin.Context) {
	if !requireAuth(c) {
		return
	}
	p, pp, off := paginate(c)
	q := strings.TrimSpace(c.Query("q"))
	status := strings.TrimSpace(c.Query("status"))

	where := "WHERE 1=1"
	args := []any{}
	if status != "" && status != "all" {
		args = append(args, status)
		where += " AND m.status = $" + strconv.Itoa(len(args))
	}
	if q != "" {
		args = append(args, "%"+q+"%")
		idx := strconv.Itoa(len(args))
		where += " AND (m.title ILIKE $" + idx +
			" OR m.title_ar ILIKE $" + idx +
			" OR m.city ILIKE $" + idx + ")"
	}

	var total int
	if err := h.Pool.QueryRow(c.Request.Context(),
		"SELECT COUNT(*) FROM volunteer_missions m "+where, args...,
	).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, pp, off)
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT m.id, m.title, m.title_ar, m.title_sorani, m.title_badini,
		       m.description, m.description_ar, m.description_sorani, m.description_badini,
		       m.city,
		       to_char(m.mission_date, 'YYYY-MM-DD') AS mission_date,
		       m.needed_volunteers, m.status, m.project_request_id,
		       COALESCE(c.accepted_count, 0),
		       COALESCE(c.pending_count,  0),
		       to_char(m.created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
		  FROM volunteer_missions m
		  LEFT JOIN (
		    SELECT mission_id,
		           SUM(CASE WHEN status IN ('approved','joined','completed') THEN 1 ELSE 0 END) AS accepted_count,
		           SUM(CASE WHEN status IN ('pending','completion_requested') THEN 1 ELSE 0 END) AS pending_count
		      FROM volunteer_mission_signups
		     GROUP BY mission_id
		  ) c ON c.mission_id = m.id
		 `+where+`
		 ORDER BY
		   CASE m.status
		     WHEN 'draft'  THEN 0
		     WHEN 'open'   THEN 1
		     WHEN 'closed' THEN 2
		     ELSE             9
		   END,
		   COALESCE(m.mission_date, '2999-12-31'::date) ASC, m.id DESC
		 LIMIT $`+strconv.Itoa(limitIdx)+` OFFSET $`+strconv.Itoa(offsetIdx),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()
	items := []adminMission{}
	for rows.Next() {
		var m adminMission
		if err := rows.Scan(
			&m.ID, &m.Title, &m.TitleAr, &m.TitleSorani, &m.TitleBadini,
			&m.Description, &m.DescriptionAr, &m.DescriptionSorani, &m.DescriptionBadini,
			&m.City, &m.MissionDate, &m.NeededVolunteers, &m.Status, &m.ProjectRequestID,
			&m.AcceptedVolunteers, &m.PendingVolunteers, &m.CreatedAt,
		); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		items = append(items, m)
	}
	c.JSON(http.StatusOK, envelopePage(items, pageMeta(p, pp, total)))
}

// =====================================================
// /api/admin/volunteer_board — Phase 24 — per-mission Kanban view
// =====================================================
//
// For each non-draft mission, returns the signups grouped into 4 lanes
// the admin board renders:
//
//   pending   — admin still needs to decide
//   approved  — admin OK'd but volunteer hasn't shown up yet
//   on_mission — joined + completion_requested (actively volunteering)
//   completed — finished in the last 30 days
//
// Rejected / cancelled / no_show are deliberately NOT included — they're
// terminal failures and would clutter the board. They're still findable
// via the regular Mission signups tab if needed.
//
// Drafts are excluded too: admin doesn't need to "manage" volunteers for
// a mission that isn't published yet.

type boardSignup struct {
	ID            int64   `json:"id"`
	UserID        int64   `json:"user_id"`
	FullName      *string `json:"full_name"`
	Phone         *string `json:"phone"`
	Status        string  `json:"status"`
	Notes         *string `json:"notes"`
	CheckedInAt   *string `json:"checked_in_at"`
	CompletedAt   *string `json:"completed_at"`
	CompletionReq *string `json:"completion_requested_at"`
	HoursServed   string  `json:"hours_served"`
	CreatedAt     string  `json:"created_at"`
}

type boardLanes struct {
	Pending   []boardSignup `json:"pending"`
	Approved  []boardSignup `json:"approved"`
	OnMission []boardSignup `json:"on_mission"` // joined + completion_requested
	Completed []boardSignup `json:"completed"`  // last 30 days
}

type boardMission struct {
	ID                int64   `json:"id"`
	Title             string  `json:"title"`
	TitleAr           *string `json:"title_ar"`
	TitleSorani       *string `json:"title_sorani"`
	TitleBadini       *string `json:"title_badini"`
	City              *string `json:"city"`
	MissionDate       *string `json:"mission_date"`
	NeededVolunteers  *int    `json:"needed_volunteers"`
	Status            string  `json:"status"`
	Lanes             boardLanes `json:"lanes"`
	// Quick counts so the SPA can render header chips without re-iterating.
	Counts struct {
		Pending   int `json:"pending"`
		Approved  int `json:"approved"`
		OnMission int `json:"on_mission"`
		Completed int `json:"completed"`
	} `json:"counts"`
}

// VolunteerBoard returns ALL non-draft missions with their signups lane-grouped.
// One DB round-trip via two queries: missions + signups, then we group in Go.
func (h *AdminListsHandler) VolunteerBoard(c *gin.Context) {
	if !requireAuth(c) {
		return
	}

	// 1. Missions (skip drafts — board is for live work)
	mrows, err := h.Pool.Query(c.Request.Context(), `
		SELECT id, title, title_ar, title_sorani, title_badini,
		       city, to_char(mission_date, 'YYYY-MM-DD'), needed_volunteers, status
		  FROM volunteer_missions
		 WHERE status <> 'draft'
		 ORDER BY
		   CASE status
		     WHEN 'open'      THEN 0
		     WHEN 'closed'    THEN 1
		     WHEN 'completed' THEN 2
		     ELSE                  9
		   END,
		   COALESCE(mission_date, '2999-12-31'::date) ASC, id ASC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer mrows.Close()

	missionByID := map[int64]*boardMission{}
	missions := []*boardMission{}
	for mrows.Next() {
		m := &boardMission{Lanes: boardLanes{
			Pending: []boardSignup{}, Approved: []boardSignup{},
			OnMission: []boardSignup{}, Completed: []boardSignup{},
		}}
		if err := mrows.Scan(&m.ID, &m.Title, &m.TitleAr, &m.TitleSorani, &m.TitleBadini,
			&m.City, &m.MissionDate, &m.NeededVolunteers, &m.Status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		missions = append(missions, m)
		missionByID[m.ID] = m
	}

	// 2. Signups (only the statuses we care about for the board).
	//    "Completed" is windowed to the last 30 days — keeps the column
	//    manageable; older completions are still visible via /volunteers.
	srows, err := h.Pool.Query(c.Request.Context(), `
		SELECT s.id, s.user_id, up.full_name, u.phone, s.mission_id,
		       s.status, s.notes,
		       to_char(s.checked_in_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS checked_in_at,
		       to_char(s.completed_at,  'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS completed_at,
		       to_char(s.completion_requested_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS comp_req_at,
		       s.hours_served::text,
		       to_char(s.created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
		  FROM volunteer_mission_signups s
		  LEFT JOIN users u          ON u.id = s.user_id
		  LEFT JOIN user_profiles up ON up.user_id = s.user_id
		 WHERE s.status IN ('pending', 'approved', 'joined', 'completion_requested', 'completed')
		   AND (s.status <> 'completed' OR s.completed_at >= CURRENT_TIMESTAMP - INTERVAL '30 days')
		 ORDER BY s.id DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer srows.Close()

	for srows.Next() {
		var sg boardSignup
		var missionID int64
		if err := srows.Scan(
			&sg.ID, &sg.UserID, &sg.FullName, &sg.Phone, &missionID,
			&sg.Status, &sg.Notes,
			&sg.CheckedInAt, &sg.CompletedAt, &sg.CompletionReq,
			&sg.HoursServed, &sg.CreatedAt,
		); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		m, ok := missionByID[missionID]
		if !ok {
			// Signup references a draft / deleted mission — skip.
			continue
		}
		switch sg.Status {
		case "pending":
			m.Lanes.Pending = append(m.Lanes.Pending, sg)
			m.Counts.Pending++
		case "approved":
			m.Lanes.Approved = append(m.Lanes.Approved, sg)
			m.Counts.Approved++
		case "joined", "completion_requested":
			m.Lanes.OnMission = append(m.Lanes.OnMission, sg)
			m.Counts.OnMission++
		case "completed":
			m.Lanes.Completed = append(m.Lanes.Completed, sg)
			m.Counts.Completed++
		}
	}

	// 3. Totals across all missions — used by the page header.
	totals := struct {
		Missions  int `json:"missions"`
		Pending   int `json:"pending"`
		Approved  int `json:"approved"`
		OnMission int `json:"on_mission"`
		Completed int `json:"completed"`
	}{Missions: len(missions)}
	for _, m := range missions {
		totals.Pending += m.Counts.Pending
		totals.Approved += m.Counts.Approved
		totals.OnMission += m.Counts.OnMission
		totals.Completed += m.Counts.Completed
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"missions": missions,
		"totals":   totals,
	})
}
