package handlers

import (
	"encoding/json"
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

// GetSupportUserID handles GET /api/admin/settings/support-user-id — the staff
// account that "Message the staff team" chats (marriage, volunteer, ...) land
// on. Returns 0 when unset.
func (h *SettingsHandler) GetSupportUserID(c *gin.Context) {
	v, err := h.Store.Get(c.Request.Context(), appsettings.KeySupportUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	userID, _ := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
	c.JSON(http.StatusOK, gin.H{"success": true, "user_id": userID})
}

// SetSupportUserID handles PUT /api/admin/settings/support-user-id.
// Body: {"user_id": N}. N=0 clears it. Must reference an existing staff
// account (staff_tier <> 'user') so a chat request never lands on a dead end.
func (h *SettingsHandler) SetSupportUserID(c *gin.Context) {
	var req struct {
		UserID int64 `json:"user_id"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.UserID != 0 {
		var staffTier string
		err := h.Store.Pool.QueryRow(c.Request.Context(),
			`SELECT staff_tier FROM users WHERE id = $1`, req.UserID).Scan(&staffTier)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "User not found."})
			return
		}
		if staffTier == "" || staffTier == "user" {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Selected account is not a staff member."})
			return
		}
	}
	value := ""
	if req.UserID != 0 {
		value = strconv.FormatInt(req.UserID, 10)
	}
	if err := h.Store.Set(c.Request.Context(), appsettings.KeySupportUserID, value); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "user_id": req.UserID})
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

// Client note — Marriage "Subscription": the old fixed-tier admin-settings
// price mechanism (GetMarriagePackagePrices/SetMarriagePackagePrices) was
// replaced by a real, dynamic packages table — see
// internal/marriage/subscription.go and internal/handlers/marriage_subscription.go.

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

// GetAssistantSettings handles GET /api/admin/settings/assistant — the AI
// Support Assistant's admin-configurable enable toggle and extra system-
// prompt instructions.
func (h *SettingsHandler) GetAssistantSettings(c *gin.Context) {
	enabledStr, err := h.Store.Get(c.Request.Context(), appsettings.KeyAssistantEnabled)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	extra, err := h.Store.Get(c.Request.Context(), appsettings.KeyAssistantExtraInstructions)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":            true,
		"enabled":            enabledStr != "false", // default on when unset
		"extra_instructions": extra,
	})
}

// SetAssistantSettings handles PUT /api/admin/settings/assistant.
// Body: {"enabled": bool, "extra_instructions": "..."}. Disabling routes
// every chat through the deterministic keyword engine instead of the LLM —
// the feature stays usable, just without free-form understanding.
func (h *SettingsHandler) SetAssistantSettings(c *gin.Context) {
	var req struct {
		Enabled           bool   `json:"enabled"`
		ExtraInstructions string `json:"extra_instructions"`
	}
	_ = c.ShouldBindJSON(&req)
	enabledStr := "true"
	if !req.Enabled {
		enabledStr = "false"
	}
	if err := h.Store.Set(c.Request.Context(), appsettings.KeyAssistantEnabled, enabledStr); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	extra := strings.TrimSpace(req.ExtraInstructions)
	if err := h.Store.Set(c.Request.Context(), appsettings.KeyAssistantExtraInstructions, extra); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "enabled": req.Enabled, "extra_instructions": extra})
}

// GetAssistantStats handles GET /api/admin/assistant/stats — lightweight
// usage metadata (message counts, ai vs local, tool usage) so staff can see
// the assistant is being used without storing full conversation transcripts.
func (h *SettingsHandler) GetAssistantStats(c *gin.Context) {
	ctx := c.Request.Context()
	var total, today, last7, aiCount, localCount, toolCount int
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log`).Scan(&total)
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log WHERE created_at >= CURRENT_DATE`).Scan(&today)
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log WHERE created_at >= now() - interval '7 days'`).Scan(&last7)
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log WHERE source = 'ai'`).Scan(&aiCount)
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log WHERE source = 'local'`).Scan(&localCount)
	_ = h.Store.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_chat_log WHERE used_tool = true`).Scan(&toolCount)
	c.JSON(http.StatusOK, gin.H{
		"success":         true,
		"total_messages":  total,
		"messages_today":  today,
		"messages_7d":     last7,
		"ai_answered":     aiCount,
		"local_fallback":  localCount,
		"tool_calls_used": toolCount,
	})
}
