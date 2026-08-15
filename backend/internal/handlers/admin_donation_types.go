package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/donationtypes"
)

// DonationTypesHandler powers the admin-managed donation-type CMS (M7).
// A public GET feeds the app's donate-screen type picker; the admin routes
// (gated in main.go) add/edit/reorder/delete types.
//
// This is the fourth and last of the four things M7 asked to be controllable
// from the dashboard without a software update — the other three (projects,
// editing/deleting projects, payment methods) already worked this way.
type DonationTypesHandler struct {
	Store *donationtypes.Store
}

func NewDonationTypesHandler(s *donationtypes.Store) *DonationTypesHandler {
	return &DonationTypesHandler{Store: s}
}

// PublicList — GET /api/donation-types (active only, no auth). Feeds the app's
// donate screen so the donor sees the types the organization currently offers
// rather than three values baked into the binary.
func (h *DonationTypesHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/donation-types (all, incl. inactive).
func (h *DonationTypesHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/donation-types — body {name_en, name_ar, name_ckb, name_kmr, slug?}.
func (h *DonationTypesHandler) Add(c *gin.Context) {
	var req donationtypes.Type
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	var actorID *int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		id := actor.UserID
		actorID = &id
	}
	saved, err := h.Store.Add(c.Request.Context(), req, actorID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "donation_type": saved})
}

// Update — PATCH /api/admin/donation-types/:id — edit names + active. The slug
// is fixed: past donations already store it in donations.donation_type.
func (h *DonationTypesHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation type id."})
		return
	}
	var req donationtypes.Type
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "donation_type": saved})
}

// Reorder — POST /api/admin/donation-types/reorder — body {ids:[3,1,2]}.
func (h *DonationTypesHandler) Reorder(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.Reorder(c.Request.Context(), req.IDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// Delete — DELETE /api/admin/donation-types/:id.
func (h *DonationTypesHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid donation type id."})
		return
	}
	// H15 — to the Trash, not straight out of the table. This is a type
	// authored in four languages that past donations still reference by slug,
	// so a misclick must stay recoverable.
	trashRow(c, h.Store.Pool, "donation_types", id)
}
