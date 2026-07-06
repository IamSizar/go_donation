package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/mediacategories"
)

// MediaCategoriesHandler powers the admin-managed "Our Work" media-category CMS
// (#22). A public GET feeds the app's News & Activities filter chips; the admin
// routes (gated in main.go) add/edit/reorder/delete categories.
type MediaCategoriesHandler struct {
	Store *mediacategories.Store
}

func NewMediaCategoriesHandler(s *mediacategories.Store) *MediaCategoriesHandler {
	return &MediaCategoriesHandler{Store: s}
}

// PublicList — GET /api/media-categories (active only, no auth). Feeds the app
// filter chips so a user filters the feed by category.
func (h *MediaCategoriesHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/media-categories (all, incl. inactive).
func (h *MediaCategoriesHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/media-categories — body {name_en, name_ar, name_ckb, name_kmr, slug?}.
func (h *MediaCategoriesHandler) Add(c *gin.Context) {
	var req mediacategories.Category
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
	c.JSON(http.StatusOK, gin.H{"success": true, "category": saved})
}

// Update — PATCH /api/admin/media-categories/:id — edit names + active (slug is fixed).
func (h *MediaCategoriesHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid category id."})
		return
	}
	var req mediacategories.Category
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "category": saved})
}

// Reorder — POST /api/admin/media-categories/reorder — body {ids:[3,1,2]}.
func (h *MediaCategoriesHandler) Reorder(c *gin.Context) {
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

// Delete — DELETE /api/admin/media-categories/:id.
func (h *MediaCategoriesHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid category id."})
		return
	}
	if err := h.Store.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
