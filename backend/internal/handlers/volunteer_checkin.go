package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// VolunteerCheckinHandler exposes Note #37's volunteer self-service
// check-in/check-out: task confirmation and verification via the app, with
// GPS location and a live photo as proof. Until now only staff could move a
// signup through approved→joined→completion_requested; these two endpoints
// let the volunteer trigger those same transitions themselves, from the
// field, with evidence attached.
//
// The photo itself is uploaded separately first (POST /api/uploads, the same
// generic upload endpoint the admin dashboard uses), and only the resulting
// path is sent here — same "upload, then save the path" convention already
// used everywhere else in this codebase (e.g. partners.logo_path).
type VolunteerCheckinHandler struct {
	Pool        *pgxpool.Pool
	Notifier    *notify.Notifier
	CaseVolChat *casevolchat.Store // Note #36 — a check-in can make an already
	// case-linked signup eligible for the Staff↔Volunteer↔Beneficiary chat.
}

func NewVolunteerCheckinHandler(pool *pgxpool.Pool, n *notify.Notifier, cvc *casevolchat.Store) *VolunteerCheckinHandler {
	return &VolunteerCheckinHandler{Pool: pool, Notifier: n, CaseVolChat: cvc}
}

type checkinReq struct {
	Lat       *float64 `json:"lat"`
	Lng       *float64 `json:"lng"`
	PhotoPath string   `json:"photo_path"`
}

// POST /api/volunteer_mission_signups/:id/check-in — only valid from
// 'approved'. Records arrival: status→'joined', checked_in_at=now, GPS +
// photo. The caller must own the signup.
func (h *VolunteerCheckinHandler) CheckIn(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req checkinReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.Lat == nil || req.Lng == nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Location (lat/lng) is required."})
		return
	}
	if req.PhotoPath == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "A photo is required."})
		return
	}
	ct, err := h.Pool.Exec(c.Request.Context(), `
		UPDATE volunteer_mission_signups
		   SET status = 'joined', checked_in_at = CURRENT_TIMESTAMP,
		       checkin_lat = $1, checkin_lng = $2, checkin_photo_path = $3
		 WHERE id = $4 AND user_id = $5 AND status = 'approved'`,
		*req.Lat, *req.Lng, req.PhotoPath, id, user.UserID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This signup isn't awaiting check-in (already checked in, not yet approved, or not yours)."})
		return
	}
	ensureCaseVolChat(c.Request.Context(), h.CaseVolChat, h.Notifier, id)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "joined"})
}

type checkoutReq struct {
	Lat       *float64 `json:"lat"`
	Lng       *float64 `json:"lng"`
	PhotoPath string   `json:"photo_path"`
	Notes     string   `json:"notes"`
}

// POST /api/volunteer_mission_signups/:id/check-out — only valid from
// 'joined'. Records departure/self-reported completion: status→
// 'completion_requested' (staff still confirms via the existing admin
// review step before it becomes 'completed'), completion_requested_at=now,
// GPS + photo + notes.
func (h *VolunteerCheckinHandler) CheckOut(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req checkoutReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.Lat == nil || req.Lng == nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Location (lat/lng) is required."})
		return
	}
	if req.PhotoPath == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "A photo is required."})
		return
	}
	ct, err := h.Pool.Exec(c.Request.Context(), `
		UPDATE volunteer_mission_signups
		   SET status = 'completion_requested', completion_requested_at = CURRENT_TIMESTAMP,
		       checkout_lat = $1, checkout_lng = $2, checkout_photo_path = $3,
		       volunteer_completion_note = NULLIF(TRIM($4), '')
		 WHERE id = $5 AND user_id = $6 AND status = 'joined'`,
		*req.Lat, *req.Lng, req.PhotoPath, req.Notes, id, user.UserID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	if ct.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This signup isn't awaiting check-out (not checked in yet, already submitted, or not yours)."})
		return
	}
	ensureCaseVolChat(c.Request.Context(), h.CaseVolChat, h.Notifier, id)
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "completion_requested"})
}
