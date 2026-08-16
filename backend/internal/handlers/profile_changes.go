package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/profilechanges"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// ProfileChangesHandler — staff review of user name / photo changes (#22).
type ProfileChangesHandler struct {
	Store *profilechanges.Store
	// Perms — H10. Set from main.go; nil masks (canViewContact fails closed).
	Perms *permissions.Store
}

func NewProfileChangesHandler(s *profilechanges.Store) *ProfileChangesHandler {
	return &ProfileChangesHandler{Store: s}
}

// List handles GET /api/admin/profile-changes?status=pending
func (h *ProfileChangesHandler) List(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	// Default to the queue that needs action; ?status=all shows history.
	status := strings.TrimSpace(c.Query("status"))
	switch {
	case status == "":
		status = "pending"
	case strings.EqualFold(status, "all"):
		status = ""
	}
	items, err := h.Store.List(c.Request.Context(), status, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	// H10 — the subject of the change is an app user. Like the staff
	// directory, this route has no perm() gate beyond RequireAdmin, so every
	// dashboard tier reaches it.
	//
	// DecidedByName is deliberately NOT masked: it is a NAME, and it degrades
	// to the reviewer's phone only when that staff member has no profile row.
	// Masking a name would blank the "who approved this" column for everyone;
	// the fix for the fallback belongs with the name, not here.
	if !canViewContact(c, h.Perms) {
		for i := range items {
			items[i].UserPhone = sensitive.Mask(items[i].UserPhone)
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

type decideReq struct {
	Approve bool   `json:"approve"`
	Note    string `json:"note"`
}

// Decide handles POST /api/admin/profile-changes/:id/decide
func (h *ProfileChangesHandler) Decide(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req decideReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	actor, _ := auth.UserFromGin(c)
	var adminID int64
	if actor != nil {
		adminID = actor.UserID
	}
	if err := h.Store.Decide(c.Request.Context(), id, adminID, req.Approve, req.Note); err != nil {
		// A row that is already decided (or gone) is the common case here —
		// two reviewers acting on the same item — so report it as such rather
		// than a server fault.
		c.JSON(http.StatusConflict, gin.H{
			"success": false,
			"error":   "This request is no longer pending.",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "approved": req.Approve})
}
