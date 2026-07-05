package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/guest"
)

// GuestHandler serves Section 27 "Guest Mode": the public config the app reads
// to know which screens a signed-out guest may browse, plus the Super-Admin
// endpoints to configure it.
type GuestHandler struct {
	Store *guest.Store
}

func NewGuestHandler(s *guest.Store) *GuestHandler { return &GuestHandler{Store: s} }

// GET /api/guest/config — public (no auth). The mobile app calls this to render
// only the guest-enabled screens.
func (h *GuestHandler) PublicConfig(c *gin.Context) {
	cfg, err := h.Store.Config(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "screens": cfg})
}

// GET /api/admin/guest_settings — Super-Admin. Returns the ordered screen list
// plus the effective config so the dashboard can render a toggle per screen.
func (h *GuestHandler) AdminList(c *gin.Context) {
	cfg, err := h.Store.Config(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	keys := make([]string, 0, len(guest.Screens))
	for _, s := range guest.Screens {
		keys = append(keys, s.Key)
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "screens": keys, "config": cfg})
}

type setGuestScreenReq struct {
	Screen  string `json:"screen"`
	Enabled bool   `json:"enabled"`
}

// POST /api/admin/guest_settings — Super-Admin. Body {screen, enabled}.
func (h *GuestHandler) Set(c *gin.Context) {
	var req setGuestScreenReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.SetScreen(c.Request.Context(), req.Screen, req.Enabled); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "screen": req.Screen, "enabled": req.Enabled})
}
