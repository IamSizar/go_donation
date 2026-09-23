package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/marketplacesections"
)

// MarketplaceSectionsHandler powers the admin-curated store "sections" CMS.
// A public GET feeds the app's section rail (active, in-window, non-empty
// only); the admin routes (gated in main.go) add/edit/reorder/delete
// sections and assign their product membership.
type MarketplaceSectionsHandler struct {
	Store *marketplacesections.Store
}

func NewMarketplaceSectionsHandler(s *marketplacesections.Store) *MarketplaceSectionsHandler {
	return &MarketplaceSectionsHandler{Store: s}
}

// PublicList — GET /api/marketplace/sections.
func (h *MarketplaceSectionsHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/marketplace/sections (all, incl. inactive/empty).
func (h *MarketplaceSectionsHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/marketplace/sections.
func (h *MarketplaceSectionsHandler) Add(c *gin.Context) {
	var req marketplacesections.Section
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
	c.JSON(http.StatusOK, gin.H{"success": true, "section": saved})
}

// Update — PATCH /api/admin/marketplace/sections/:id.
func (h *MarketplaceSectionsHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid section id."})
		return
	}
	var req marketplacesections.Section
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "section": saved})
}

// Reorder — POST /api/admin/marketplace/sections/reorder.
func (h *MarketplaceSectionsHandler) Reorder(c *gin.Context) {
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

// Delete — DELETE /api/admin/marketplace/sections/:id.
func (h *MarketplaceSectionsHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid section id."})
		return
	}
	trashRow(c, h.Store.Pool, "marketplace_sections", id)
}

// Products — GET /api/admin/marketplace/sections/:id/products. Returns the
// ids of the products currently assigned, so the dashboard picker can
// pre-check them.
func (h *MarketplaceSectionsHandler) Products(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid section id."})
		return
	}
	ids, err := h.Store.ProductIDs(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "product_ids": ids})
}

// SetProducts — PUT /api/admin/marketplace/sections/:id/products. Replaces
// the section's whole product list with the given set.
func (h *MarketplaceSectionsHandler) SetProducts(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid section id."})
		return
	}
	var req struct {
		ProductIDs []int64 `json:"product_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.SetProducts(c.Request.Context(), id, req.ProductIDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
