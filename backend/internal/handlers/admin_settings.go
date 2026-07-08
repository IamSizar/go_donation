package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
)

// SettingsHandler powers the admin-editable app settings (#36: support WhatsApp
// number). Reads/writes the app_settings key/value table.
type SettingsHandler struct {
	Store *appsettings.Store
}

func NewSettingsHandler(s *appsettings.Store) *SettingsHandler {
	return &SettingsHandler{Store: s}
}

// digitsOnlyStr strips everything but 0-9 so the stored number is clean
// (no "+", spaces or dashes) — matches how the env var is normalized.
func digitsOnlyStr(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, s)
}

// GetSupportWhatsApp handles GET /api/admin/settings/support-whatsapp.
func (h *SettingsHandler) GetSupportWhatsApp(c *gin.Context) {
	v, err := h.Store.Get(c.Request.Context(), appsettings.KeySupportWhatsApp)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "number": v})
}

// SetSupportWhatsApp handles PUT /api/admin/settings/support-whatsapp.
// Body: {"number": "9647..."}. An empty value disables the handoff offer.
func (h *SettingsHandler) SetSupportWhatsApp(c *gin.Context) {
	var req struct {
		Number string `json:"number"`
	}
	_ = c.ShouldBindJSON(&req)
	number := digitsOnlyStr(req.Number)
	if err := h.Store.Set(c.Request.Context(), appsettings.KeySupportWhatsApp, number); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "number": number})
}

// GetFibNumber handles GET /api/admin/settings/fib-number. This is a convenience
// alias that reads the FIB payment method's account number (single source of
// truth — the same value shown on the donate screen), so staff can update it
// from the same settings card as the WhatsApp number.
func (h *SettingsHandler) GetFibNumber(c *gin.Context) {
	var n string
	err := h.Store.Pool.QueryRow(c.Request.Context(),
		`SELECT COALESCE(account_number, '') FROM payment_methods WHERE slug = 'fib' LIMIT 1`).Scan(&n)
	if err != nil {
		// No FIB row yet → treat as empty rather than an error.
		c.JSON(http.StatusOK, gin.H{"success": true, "number": ""})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "number": n})
}

// SetFibNumber handles PUT /api/admin/settings/fib-number. Body {"number": ...}.
// Writes straight to the FIB payment method so the donate screen reflects it.
func (h *SettingsHandler) SetFibNumber(c *gin.Context) {
	var req struct {
		Number string `json:"number"`
	}
	_ = c.ShouldBindJSON(&req)
	number := strings.TrimSpace(req.Number)
	if _, err := h.Store.Pool.Exec(c.Request.Context(),
		`UPDATE payment_methods SET account_number = $1 WHERE slug = 'fib'`, number); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "number": number})
}
