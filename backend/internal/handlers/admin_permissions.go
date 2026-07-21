package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// AdminPermissionsHandler powers the Super-Admin "Permissions Management"
// module (Section 24). It exposes the role × module × action matrix, a
// setter that records every change in the immutable permission_audit_log, a
// read-only audit feed, and an "effective permissions for me" endpoint the SPA
// uses to hide modules a tier may not view.
//
// Security: the mutating + audit endpoints are mounted under RequireSuperAdmin
// in main.go. The /me endpoint is available to any authenticated staff.
type AdminPermissionsHandler struct {
	Perms *permissions.Store
	// Section 24 — second factor for permission changes: a phone OTP sent to
	// the acting Super Admin. OTPs stores/verifies the code; OTPIQ sends the
	// real SMS (nil when OTPIQ_API_KEY isn't set — demo mode still works).
	OTPs  *auth.OTPStore
	OTPIQ *auth.OTPIQClient
}

func NewAdminPermissionsHandler(p *permissions.Store, otps *auth.OTPStore, otpiq *auth.OTPIQClient) *AdminPermissionsHandler {
	return &AdminPermissionsHandler{Perms: p, OTPs: otps, OTPIQ: otpiq}
}

// GET /api/admin/permissions — the full matrix the UI renders: the axis lists,
// the built-in default for every tier×action, and the stored overrides.
func (h *AdminPermissionsHandler) Matrix(c *gin.Context) {
	overrides, err := h.Perms.ListOverrides(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// defaults[tier][action] = built-in baseline (module-agnostic).
	defaults := map[string]map[string]bool{}
	for _, t := range permissions.AllTiers {
		row := map[string]bool{}
		for _, a := range permissions.AllActions {
			row[a] = permissions.DefaultAllowed(permissions.TierFrom(t), a)
		}
		defaults[t] = row
	}
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"tiers":     permissions.AllTiers,
		"modules":   permissions.Modules,
		"actions":   permissions.AllActions,
		"defaults":  defaults,
		"overrides": overrides,
	})
}

type setPermissionReq struct {
	Tier    string `json:"tier"`
	Module  string `json:"module"`
	Action  string `json:"action"`
	Allowed bool   `json:"allowed"`
	Otp     string `json:"otp"` // Section 24 — phone OTP second factor
}

// maskPhone hides all but the last 4 digits (e.g. "•••••••2031").
func maskPhone(p string) string {
	p = strings.TrimSpace(p)
	if len(p) <= 4 {
		return p
	}
	return strings.Repeat("•", len(p)-4) + p[len(p)-4:]
}

// POST /api/admin/permissions/otp — issue a phone OTP to the acting Super
// Admin's number (the second factor for a permission change). In demo mode
// (OTP_DEMO_ENABLED) it returns the code for local testing; otherwise it sends
// a real SMS via OTPIQ.
func (h *AdminPermissionsHandler) RequestOTP(c *gin.Context) {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Your account has no phone number to receive a code."})
		return
	}
	ctx := c.Request.Context()

	// Demo mode (local/testing) — store the fixed demo code and return it.
	if auth.DemoEnabled() {
		code := auth.DemoCode()
		if err := h.OTPs.StoreCode(ctx, phone, code, "demo"); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to store the code."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "mode": "demo", "phone_hint": maskPhone(phone), "demo_code": code})
		return
	}

	// Real mode — send via OTPIQ (persist before sending so a flake doesn't
	// accept-but-lose the code).
	if h.OTPIQ == nil {
		c.JSON(http.StatusBadGateway, gin.H{"success": false, "error": "OTP delivery is not configured (OTPIQ_API_KEY)."})
		return
	}
	code, err := auth.GenerateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to generate the code."})
		return
	}
	if err := h.OTPs.StoreCode(ctx, phone, code, "real"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to store the code."})
		return
	}
	if _, err := h.OTPIQ.SendVerification(ctx, phone, code); err != nil {
		_ = h.OTPs.ClearRecord(ctx, phone)
		c.JSON(http.StatusBadGateway, gin.H{"success": false, "error": "Failed to send the verification code."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "mode": "real", "phone_hint": maskPhone(phone)})
}

// POST /api/admin/permissions — set one (tier, module, action) → allowed and
// append an audit record. Requires BOTH factors: the PIN (checked separately
// by the SPA via /admin/verify-password) and a valid phone OTP in `otp`.
func (h *AdminPermissionsHandler) SetPermission(c *gin.Context) {
	var req setPermissionReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if !validIn(req.Tier, permissions.AllTiers) ||
		!validIn(req.Module, permissions.Modules) ||
		!validIn(req.Action, permissions.AllActions) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown tier, module, or action."})
		return
	}

	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	ctx := c.Request.Context()

	// Section 24 — suspicious-activity guard: throttle rapid permission changes
	// (defense-in-depth atop the per-change OTP). No-op unless PERM_CHANGE_MAX_
	// PER_MIN is configured. Checked before the OTP so a throttled request does
	// not burn the admin's single-use code.
	if !permLimiter.allow(actor.UserID, time.Now()) {
		c.JSON(http.StatusTooManyRequests, gin.H{"success": false, "error": "Too many permission changes in a short time. Please wait a minute and try again."})
		return
	}

	// Section 24 — verify the phone OTP second factor BEFORE applying anything.
	// The code is single-use (consumed on success), so each change needs a
	// fresh OTP.
	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Your account has no phone number for 2FA."})
		return
	}
	if okOtp, reason := h.OTPs.VerifyAndConsume(ctx, phone, req.Otp); !okOtp {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": reason})
		return
	}

	// Capture the effective value BEFORE the change for the audit trail.
	oldAllowed, _ := h.Perms.Allowed(ctx, permissions.TierFrom(req.Tier), req.Module, req.Action)

	if err := h.Perms.SetOverride(ctx, req.Tier, req.Module, req.Action, req.Allowed); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	id := actor.UserID
	target := req.Tier + "/" + req.Module + "/" + req.Action
	_ = h.Perms.LogAudit(ctx, &id, "permission_set", target,
		boolWord(oldAllowed), boolWord(req.Allowed), c.ClientIP())

	c.JSON(http.StatusOK, gin.H{"success": true, "tier": req.Tier, "module": req.Module, "action": req.Action, "allowed": req.Allowed})
}

// GET /api/admin/permissions/audit — read-only, immutable permission audit log.
func (h *AdminPermissionsHandler) Audit(c *gin.Context) {
	entries, err := h.Perms.ListAudit(c.Request.Context(), 200)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": entries})
}

// GET /api/admin/permissions/audit/verify — Requirement 6c. Recomputes the
// audit ledger's hash chain and reports whether it is intact, so a Super-Admin
// can prove no row was silently altered or removed.
func (h *AdminPermissionsHandler) VerifyAudit(c *gin.Context) {
	status, err := h.Perms.VerifyChain(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "chain": status})
}

// GET /api/admin/permissions/me — the effective permission map for the
// calling user: their own per-employee overrides (Note 31) first, then
// their tier's override/default. { module: { action: bool } }. The SPA uses
// the "view" flag per module to hide unauthorized menu entries — so a
// per-employee override here is what actually hides/shows a sidebar section
// for just that one account.
func (h *AdminPermissionsHandler) Effective(c *gin.Context) {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	tier := permissions.TierFrom(actor.StaffTier)
	ctx := c.Request.Context()
	perms := map[string]map[string]bool{}
	for _, m := range permissions.Modules {
		row := map[string]bool{}
		for _, a := range permissions.AllActions {
			allowed, err := h.Perms.AllowedForUser(ctx, int64(actor.UserID), tier, m, a)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Permission check failed."})
				return
			}
			row[a] = allowed
		}
		perms[m] = row
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "tier": string(tier), "permissions": perms})
}

// ── Note 31 — per-employee permission overrides ─────────────────────────

// GET /api/admin/permissions/user/:id — the effective matrix for one
// specific employee, with each cell tagged by where its value comes from
// (their own override vs their tier), so the UI can show "this is
// customized for this person" distinctly from "this is just their tier".
func (h *AdminPermissionsHandler) UserMatrix(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	var tierStr string
	if err := h.Perms.Pool.QueryRow(ctx, "SELECT staff_tier FROM users WHERE id = $1", id).Scan(&tierStr); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
		return
	}
	tier := permissions.TierFrom(tierStr)

	userOverrides, err := h.Perms.ListUserOverrides(ctx, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	overrideSet := map[string]bool{}
	for _, o := range userOverrides {
		overrideSet[o.Module+"|"+o.Action] = true
	}

	cells := map[string]map[string]gin.H{}
	for _, m := range permissions.Modules {
		row := map[string]gin.H{}
		for _, a := range permissions.AllActions {
			allowed, err := h.Perms.AllowedForUser(ctx, id, tier, m, a)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Permission check failed."})
				return
			}
			source := "tier"
			if overrideSet[m+"|"+a] {
				source = "user"
			}
			row[a] = gin.H{"allowed": allowed, "source": source}
		}
		cells[m] = row
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true, "user_id": id, "tier": string(tier),
		"modules": permissions.Modules, "actions": permissions.AllActions, "cells": cells,
	})
}

type setUserPermissionReq struct {
	Module string `json:"module"`
	Action string `json:"action"`
	// Allowed is nil to CLEAR the override (revert to the tier's own
	// override/default) rather than set a value.
	Allowed *bool  `json:"allowed"`
	Otp     string `json:"otp"`
}

// POST /api/admin/permissions/user/:id — set or clear one per-employee
// (module, action) override. Same two-factor rigor as the tier matrix's
// SetPermission (PIN checked client-side via /admin/verify-password, OTP
// verified here), same rate limit, same immutable audit trail — this is
// just as sensitive as a tier-wide change, only narrower in blast radius.
func (h *AdminPermissionsHandler) SetUserPermission(c *gin.Context) {
	targetID, ok := parseID(c)
	if !ok {
		return
	}
	var req setUserPermissionReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if !validIn(req.Module, permissions.Modules) || !validIn(req.Action, permissions.AllActions) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown module or action."})
		return
	}

	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return
	}
	ctx := c.Request.Context()

	if !permLimiter.allow(actor.UserID, time.Now()) {
		c.JSON(http.StatusTooManyRequests, gin.H{"success": false, "error": "Too many permission changes in a short time. Please wait a minute and try again."})
		return
	}

	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Your account has no phone number for 2FA."})
		return
	}
	if okOtp, reason := h.OTPs.VerifyAndConsume(ctx, phone, req.Otp); !okOtp {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": reason})
		return
	}

	var tierStr string
	if err := h.Perms.Pool.QueryRow(ctx, "SELECT staff_tier FROM users WHERE id = $1", targetID).Scan(&tierStr); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "User not found."})
		return
	}
	tier := permissions.TierFrom(tierStr)

	oldAllowed, _ := h.Perms.AllowedForUser(ctx, targetID, tier, req.Module, req.Action)
	target := "user#" + strconv.FormatInt(targetID, 10) + "/" + req.Module + "/" + req.Action

	if req.Allowed == nil {
		if err := h.Perms.ClearUserOverride(ctx, targetID, req.Module, req.Action); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
			return
		}
		newAllowed, _ := h.Perms.AllowedForUser(ctx, targetID, tier, req.Module, req.Action)
		id := actor.UserID
		_ = h.Perms.LogAudit(ctx, &id, "user_permission_cleared", target, boolWord(oldAllowed), boolWord(newAllowed), c.ClientIP())
		c.JSON(http.StatusOK, gin.H{"success": true, "user_id": targetID, "module": req.Module, "action": req.Action, "allowed": newAllowed, "source": "tier"})
		return
	}

	if err := h.Perms.SetUserOverride(ctx, targetID, tier, req.Module, req.Action, *req.Allowed); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	id := actor.UserID
	_ = h.Perms.LogAudit(ctx, &id, "user_permission_set", target, boolWord(oldAllowed), boolWord(*req.Allowed), c.ClientIP())
	c.JSON(http.StatusOK, gin.H{"success": true, "user_id": targetID, "module": req.Module, "action": req.Action, "allowed": *req.Allowed, "source": "user"})
}

func validIn(v string, set []string) bool {
	for _, s := range set {
		if s == v {
			return true
		}
	}
	return false
}

func boolWord(b bool) string {
	if b {
		return "allowed"
	}
	return "denied"
}
