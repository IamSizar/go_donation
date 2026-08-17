package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/citycategories"
)

// CityCategoriesHandler powers the admin-managed City Guide sector CMS (#29). A
// public GET feeds the app's City Guide filter chips; the admin routes (gated
// in main.go) add/edit/reorder/delete sectors.
type CityCategoriesHandler struct {
	Store *citycategories.Store
}

func NewCityCategoriesHandler(s *citycategories.Store) *CityCategoriesHandler {
	return &CityCategoriesHandler{Store: s}
}

// PublicList — GET /api/city-categories (active only, no auth). Feeds the City
// Guide filter chips so a user narrows the directory by sector.
func (h *CityCategoriesHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/city-categories (all, incl. inactive).
func (h *CityCategoriesHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/city-categories — body {name_en, name_ar, name_ckb, name_kmr, slug?}.
func (h *CityCategoriesHandler) Add(c *gin.Context) {
	var req citycategories.Category
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
	c.JSON(http.StatusOK, gin.H{"success": true, "sector": saved})
}

// Update — PATCH /api/admin/city-categories/:id — edit names + active (slug is fixed).
func (h *CityCategoriesHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid sector id."})
		return
	}
	var req citycategories.Category
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "sector": saved})
}

// Reorder — POST /api/admin/city-categories/reorder — body {ids:[3,1,2]}.
func (h *CityCategoriesHandler) Reorder(c *gin.Context) {
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

// Delete — DELETE /api/admin/city-categories/:id.
func (h *CityCategoriesHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid sector id."})
		return
	}
	// H15 — to the Trash, not straight out of the table. This is a category authored in four languages,
	// and until now a misclick destroyed it with no way back.
	trashRow(c, h.Store.Pool, "city_categories", id)
}
