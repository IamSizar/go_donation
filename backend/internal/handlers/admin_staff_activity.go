// GET /api/admin/staff/:id/activity — one staff member's record of what they
// have decided, for the employee profile the owner asked for.
//
// The reasoning about WHERE the data comes from lives in the package comment
// of internal/staffactivity. This file is the thin handler the project's rules
// ask for: parse, authorise, call the store, map the response.
package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
	"github.com/karam-flutter/humanitarian-backend/internal/staffactivity"
)

type StaffActivityHandler struct {
	Store *staffactivity.Store
	Perms *permissions.Store
}

func NewStaffActivityHandler(s *staffactivity.Store, p *permissions.Store) *StaffActivityHandler {
	return &StaffActivityHandler{Store: s, Perms: p}
}

// Activity answers with the profile, or 404 when no such user exists.
func (h *StaffActivityHandler) Activity(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid id."})
		return
	}

	limit, _ := strconv.Atoi(c.Query("limit"))

	summary, err := h.Store.Load(c.Request.Context(), id, limit)
	if errors.Is(err, pgx.ErrNoRows) {
		// The id came from a URL somebody can type. "No such user" is a
		// different answer from "this user has done nothing", and the page
		// shows different things for each.
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}

	// H10 — the same masking every other staff-facing list applies to a phone
	// number. This screen is about what someone DID; their contact details are
	// a separate permission, and the profile is readable without them.
	if !canViewContact(c, h.Perms) {
		summary.Phone = sensitive.Mask(summary.Phone)
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "profile": summary})
}
