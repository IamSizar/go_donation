package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casecategories"
)

// CaseCategoriesHandler powers the admin-managed beneficiary-case category
// CMS (Quick Filter Capsules). A public GET feeds the app's Home capsule
// row; the admin routes (gated in main.go) add/edit/reorder/delete
// categories.
type CaseCategoriesHandler struct {
	Store *casecategories.Store
}

func NewCaseCategoriesHandler(s *casecategories.Store) *CaseCategoriesHandler {
	return &CaseCategoriesHandler{Store: s}
}

// PublicList — GET /api/case-categories (active only, no auth). Feeds the
// app's Home capsule filter row.
func (h *CaseCategoriesHandler) PublicList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/case-categories (all, incl. inactive).
func (h *CaseCategoriesHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/case-categories — body {name_en, name_ar, name_ckb, name_kmr, slug?}.
func (h *CaseCategoriesHandler) Add(c *gin.Context) {
	var req casecategories.Category
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
	c.JSON(http.StatusOK, gin.H{"success": true, "category": saved})
}

// Update — PATCH /api/admin/case-categories/:id — edit names + active (slug is fixed).
func (h *CaseCategoriesHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid category id."})
		return
	}
	var req casecategories.Category
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "category": saved})
}

// Reorder — POST /api/admin/case-categories/reorder — body {ids:[3,1,2]}.
func (h *CaseCategoriesHandler) Reorder(c *gin.Context) {
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

// Delete — DELETE /api/admin/case-categories/:id.
func (h *CaseCategoriesHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid category id."})
		return
	}
	// H15 — to the Trash, not straight out of the table. This is a category authored in four languages,
	// and until now a misclick destroyed it with no way back.
	trashRow(c, h.Store.Pool, "case_categories", id)
}
