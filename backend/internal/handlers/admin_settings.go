package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
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

// defaultSessionTimeoutMinutes matches what AppShell.tsx used as a hardcoded
// constant before this setting existed — the fallback when no admin has set
// a value yet, so behavior doesn't change on first deploy.
const defaultSessionTimeoutMinutes = 20

// Note #5 — the idle-timeout that logs a staff member out of the dashboard
// after inactivity used to be a hardcoded constant (originally 2 minutes per
// the original spec, which logged people out constantly — bumped to 20, but
// still not admin-configurable). Now stored in app_settings so the Main
// Admin can tune it without a code change.
const KeySessionTimeoutMinutes = "session_timeout_minutes"

// GetSessionTimeout handles GET /api/admin/settings/session-timeout. Open to
// any authenticated staff member (everyone needs to know the current value
// to enforce it client-side) — only SetSessionTimeout is Super-Admin-gated.
func (h *SettingsHandler) GetSessionTimeout(c *gin.Context) {
	v, err := h.Store.Get(c.Request.Context(), KeySessionTimeoutMinutes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	minutes := defaultSessionTimeoutMinutes
	if v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			minutes = n
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "minutes": minutes})
}

// SetSessionTimeout handles PUT /api/admin/settings/session-timeout. Body
// {"minutes": 20}. Super-Admin only (route-gated). Clamped to a sane range —
// too low locks staff out constantly (the original complaint), unlimited
// defeats the point of an idle lock at all.
func (h *SettingsHandler) SetSessionTimeout(c *gin.Context) {
	var req struct {
		Minutes int `json:"minutes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if req.Minutes < 5 || req.Minutes > 480 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Session timeout must be between 5 and 480 minutes."})
		return
	}
	if err := h.Store.Set(c.Request.Context(), KeySessionTimeoutMinutes, strconv.Itoa(req.Minutes)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "minutes": req.Minutes})
}

// Note #17 — admin-configurable price per Marriage subscription package tier
// (bronze/silver/gold/diamond/vip — see marriageSubscription in
// admin_edit.go, the single source of truth for valid tier names). Reuses
// the generic app_settings key/value store, one row per tier, keyed
// "marriage_package_price_<tier>".
func marriagePackagePriceKey(tier string) string {
	return "marriage_package_price_" + tier
}

// GetMarriagePackagePrices handles GET /api/admin/settings/marriage-package-prices.
// Returns {"prices": {"bronze": 0, "silver": 0, ...}} — every known tier is
// always present (0 for a tier that's never been set), so the frontend never
// has to handle a missing key.
func (h *SettingsHandler) GetMarriagePackagePrices(c *gin.Context) {
	prices := make(map[string]float64, len(marriageSubscription))
	for _, tier := range marriageSubscription {
		v, err := h.Store.Get(c.Request.Context(), marriagePackagePriceKey(tier))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		n, _ := strconv.ParseFloat(v, 64)
		prices[tier] = n
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "prices": prices})
}

// SetMarriagePackagePrices handles PUT /api/admin/settings/marriage-package-prices.
// Body: {"prices": {"bronze": 10000, "silver": 25000, ...}}. Only recognized
// tier keys are accepted; unknown keys are ignored rather than erroring, so
// the frontend can always send the full map without coordinating on schema.
// A tier OMITTED from the body keeps its current stored value rather than
// being reset to 0 — this endpoint updates, it doesn't replace wholesale.
func (h *SettingsHandler) SetMarriagePackagePrices(c *gin.Context) {
	var req struct {
		Prices map[string]float64 `json:"prices"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved := make(map[string]float64, len(marriageSubscription))
	for _, tier := range marriageSubscription {
		price, ok := req.Prices[tier]
		if !ok {
			existing, err := h.Store.Get(c.Request.Context(), marriagePackagePriceKey(tier))
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
				return
			}
			price, _ = strconv.ParseFloat(existing, 64)
			saved[tier] = price
			continue
		}
		if price < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Price for " + tier + " must be >= 0."})
			return
		}
		if err := h.Store.Set(c.Request.Context(), marriagePackagePriceKey(tier), fmt.Sprintf("%g", price)); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		saved[tier] = price
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "prices": saved})
}

// Note #29 follow-up — lets a Super-Admin reorganize the sidebar itself
// (reorder groups/items, move an item into a different group) instead of the
// grouping being fixed in code. The value is opaque JSON as far as the
// backend is concerned — AppShell.tsx owns the shape (an array of
// {kind:'item',to} / {kind:'group',key,items:[...]} sections) and always
// reconciles it against the real nav-item registry before rendering, so a
// stale or hand-edited value can only ever reorder/regroup — it can never
// hide a page or invent a route that isn't real.
const KeyNavLayout = "nav_layout"

// GetNavLayout handles GET /api/admin/settings/nav-layout. Open to any
// authenticated staff member (everyone needs it to render their own
// sidebar) — only SetNavLayout is Super-Admin-gated. Returns {"layout": null}
// when nobody has customized it yet, so the frontend falls back to its
// built-in default grouping.
func (h *SettingsHandler) GetNavLayout(c *gin.Context) {
	v, err := h.Store.Get(c.Request.Context(), KeyNavLayout)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if v == "" {
		c.JSON(http.StatusOK, gin.H{"success": true, "layout": nil})
		return
	}
	// Stored as a JSON string; decode into a raw message so it round-trips
	// as real JSON in the response instead of a JSON-encoded string.
	var raw json.RawMessage = json.RawMessage(v)
	c.JSON(http.StatusOK, gin.H{"success": true, "layout": raw})
}

// SetNavLayout handles PUT /api/admin/settings/nav-layout. Body
// {"layout": [...]} | {"layout": null} (null resets to the built-in
// default). Only validates that it's a JSON array of plausible-shaped
// section objects — it deliberately does NOT hardcode the set of valid
// routes/groups here (that list already lives once, in AppShell.tsx); the
// frontend is what reconciles against the real registry on load.
func (h *SettingsHandler) SetNavLayout(c *gin.Context) {
	var req struct {
		Layout json.RawMessage `json:"layout"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if len(req.Layout) == 0 || string(req.Layout) == "null" {
		if err := h.Store.Set(c.Request.Context(), KeyNavLayout, ""); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "layout": nil})
		return
	}
	var sections []struct {
		Kind  string   `json:"kind"`
		To    string   `json:"to"`
		Key   string   `json:"key"`
		Items []string `json:"items"`
	}
	if err := json.Unmarshal(req.Layout, &sections); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "layout must be an array of sections."})
		return
	}
	for _, s := range sections {
		if s.Kind != "item" && s.Kind != "group" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Each section's kind must be 'item' or 'group'."})
			return
		}
		if s.Kind == "item" && strings.TrimSpace(s.To) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "An 'item' section requires a non-empty to."})
			return
		}
		if s.Kind == "group" && strings.TrimSpace(s.Key) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "A 'group' section requires a non-empty key."})
			return
		}
	}
	if err := h.Store.Set(c.Request.Context(), KeyNavLayout, string(req.Layout)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "layout": req.Layout})
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
