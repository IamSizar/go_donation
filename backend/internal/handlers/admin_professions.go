package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/volunteers"
)

// AdminProfessionsHandler powers Section 13's admin-added volunteer
// professions. GET lists them (used to extend the skill dropdown); POST adds a
// new one (admin-gated in main.go).
type AdminProfessionsHandler struct {
	Store *volunteers.ProfessionStore
}

func NewAdminProfessionsHandler(s *volunteers.ProfessionStore) *AdminProfessionsHandler {
	return &AdminProfessionsHandler{Store: s}
}

// GET /api/admin/professions
func (h *AdminProfessionsHandler) List(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/admin/professions — body {label_en, label_ar, label_ckb, label_kmr, category}
func (h *AdminProfessionsHandler) Add(c *gin.Context) {
	var req volunteers.Profession
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
	c.JSON(http.StatusOK, gin.H{"success": true, "profession": saved})
}
