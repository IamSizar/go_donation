package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorshiptypes"
)

// SponsorshipTypesHandler powers the admin-managed recurring-assistance type
// CMS behind the sponsorship schedule ("Eighth: 4. Scalability").
//
// Migration 086 created and seeded sponsorship_types for exactly this, then
// nothing was wired to it — so adding an assistance type still required SQL.
// These routes are that missing half.
type SponsorshipTypesHandler struct {
	Store *sponsorshiptypes.Store
}

func NewSponsorshipTypesHandler(s *sponsorshiptypes.Store) *SponsorshipTypesHandler {
	return &SponsorshipTypesHandler{Store: s}
}

// PublicList — GET /api/sponsorship-types (active only). Feeds the picker used
// when staff set up a recurring assistance case.
func (h *SponsorshipTypesHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/sponsorship-types (all, incl. inactive).
func (h *SponsorshipTypesHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/sponsorship-types — body {name_en, name_ar, name_ckb,
// name_kmr, default_interval?, slug?}.
func (h *SponsorshipTypesHandler) Add(c *gin.Context) {
	var req sponsorshiptypes.Type
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
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "type": saved})
}

// Update — PATCH /api/admin/sponsorship-types/:id — edit names + active (slug is fixed).
func (h *SponsorshipTypesHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid type id."})
		return
	}
	var req sponsorshiptypes.Type
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "type": saved})
}

// Reorder — POST /api/admin/sponsorship-types/reorder — body {ids:[3,1,2]}.
func (h *SponsorshipTypesHandler) Reorder(c *gin.Context) {
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

// Delete — DELETE /api/admin/sponsorship-types/:id.
func (h *SponsorshipTypesHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid type id."})
		return
	}
	// H15 — to the Trash, not straight out of the table. This is a type authored in four languages,
	// and until now a misclick destroyed it with no way back.
	trashRow(c, h.Store.Pool, "sponsorship_types", id)
}
