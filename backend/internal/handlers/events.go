package handlers

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
)

// EventsHandler is the activity-event log endpoint set: the mobile app POSTs
// events here (replacing the old Firestore writes) and the admin dashboard
// reads the recent feed.
type EventsHandler struct {
	Store *events.Store
	Pool  *pgxpool.Pool
}

func NewEventsHandler(store *events.Store, pool *pgxpool.Pool) *EventsHandler {
	return &EventsHandler{Store: store, Pool: pool}
}

// Log records one activity event.
//
// POST /api/events   (authenticated)
//
// Body is the same shape the app used to write to Firestore. The authenticated
// user is authoritative for user_id/role_id when the client omits them.
func (h *EventsHandler) Log(c *gin.Context) {
	var e events.Event
	if err := c.ShouldBindJSON(&e); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid event body."})
		return
	}
	if strings.TrimSpace(e.EventType) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "event_type is required."})
		return
	}

	// The token's user is authoritative; backfill from it when the client
	// didn't send identity fields.
	if user, ok := auth.UserFromGin(c); ok && user != nil {
		if e.UserID == nil {
			uid := user.UserID
			e.UserID = &uid
		}
		if e.RoleID == nil && user.RoleID > 0 {
			rid := int64(user.RoleID)
			e.RoleID = &rid
		}
	}

	// Derive digits-only phone if the client didn't.
	if e.NumberDigits == "" && e.Number != "" {
		e.NumberDigits = digitsOnly(e.Number)
	}

	// Client epoch-ms is preserved for ordering; fall back to server time.
	if e.CreatedAtMs <= 0 {
		e.CreatedAtMs = time.Now().UnixMilli()
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	id, err := h.Store.Insert(ctx, e)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Could not record event."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// AdminList returns the most recent events for the admin feed.
//
// GET /api/admin/events?limit=100   (admin only)
func (h *EventsHandler) AdminList(c *gin.Context) {
	limit := 100
	if v := strings.TrimSpace(c.Query("limit")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	items, err := h.Store.List(ctx, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Could not load events."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func digitsOnly(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}
