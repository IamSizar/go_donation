package handlers

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/areas"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AreasHandler powers the cities / districts / sub-districts manager
// (migration 136). A public GET feeds the app's cascading location pickers;
// the admin routes (admin tier, main.go) add / edit / reorder / delete.
type AreasHandler struct {
	Store *areas.Store
}

func NewAreasHandler(s *areas.Store) *AreasHandler { return &AreasHandler{Store: s} }

func areasError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, areas.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": err.Error(), "code": "not_found"})
	case errors.Is(err, areas.ErrHasChildren):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": err.Error(), "code": "has_children"})
	case errors.Is(err, areas.ErrDuplicate):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": err.Error(), "code": "duplicate"})
	case errors.Is(err, areas.ErrBadGov), errors.Is(err, areas.ErrBadLevel),
		errors.Is(err, areas.ErrBadParent), errors.Is(err, areas.ErrNameRequired):
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
	default:
		log.Printf("areas: %s %s: %v", c.Request.Method, c.Request.URL.Path, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

func governorateParam(c *gin.Context) (string, bool) {
	g := strings.TrimSpace(c.Query("governorate"))
	if !areas.IsGovernorate(g) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "governorate is required and must be one of the 18."})
		return "", false
	}
	return g, true
}

// PublicList — GET /api/areas?governorate=Nineveh — active areas only (a
// hidden city takes its branch with it), all three levels in one response.
func (h *AreasHandler) PublicList(c *gin.Context) {
	g, ok := governorateParam(c)
	if !ok {
		return
	}
	items, err := h.Store.List(c.Request.Context(), g, true)
	if err != nil {
		areasError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/areas?governorate=Nineveh — every area, hidden included.
func (h *AreasHandler) AdminList(c *gin.Context) {
	g, ok := governorateParam(c)
	if !ok {
		return
	}
	items, err := h.Store.List(c.Request.Context(), g, false)
	if err != nil {
		areasError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/areas — {governorate, level, parent_id?, name_ar, name_en, name_ckb, name_kmr}.
func (h *AreasHandler) Add(c *gin.Context) {
	var req areas.Area
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
		areasError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "area": saved})
}

// Update — PATCH /api/admin/areas/:id — names + active.
func (h *AreasHandler) Update(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req areas.Area
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		areasError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "area": saved})
}

// Reorder — POST /api/admin/areas/reorder — {ids:[…]} for one sibling list.
func (h *AreasHandler) Reorder(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.Reorder(c.Request.Context(), req.IDs); err != nil {
		areasError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// Delete — DELETE /api/admin/areas/:id — to the Trash, like every CMS list.
// Refused while it still has districts / sub-districts under it.
func (h *AreasHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid area id."})
		return
	}
	if err := h.Store.CanDelete(c.Request.Context(), id); err != nil {
		areasError(c, err)
		return
	}
	trashRow(c, h.Store.Pool, "location_areas", id)
}
