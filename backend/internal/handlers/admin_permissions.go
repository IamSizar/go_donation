package handlers

import (
	"context"
	"log"
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
	// H1 — "phone OR email". The mailer is nil when SMTP_* is unset, which is
	// every environment today; sendSecondFactor treats that as "email is not a
	// real channel" and says so rather than pretending otherwise.
	Mail *auth.Mailer
}

func NewAdminPermissionsHandler(
	p *permissions.Store, otps *auth.OTPStore, otpiq *auth.OTPIQClient, mailer *auth.Mailer,
) *AdminPermissionsHandler {
	return &AdminPermissionsHandler{Perms: p, OTPs: otps, OTPIQ: otpiq, Mail: mailer}
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
	Otp     string `json:"otp"` // Section 24 — the second factor (phone or email)
	// H1 — the FIRST factor. It used to be checked only by the page that asked
	// for it (POST /admin/verify-password), so any caller that skipped that
	// call skipped the password entirely. Verified here now.
	Password string `json:"password"`
}

// maskPhone hides all but the last 4 digits (e.g. "•••••••2031").
func maskPhone(p string) string {
	p = strings.TrimSpace(p)
	if len(p) <= 4 {
		return p
	}
	return strings.Repeat("•", len(p)-4) + p[len(p)-4:]
}

// requestOTPReq lets the operator pick which channel the code should travel on.
// Empty means "whichever is real", which is the right default while only one of
// the two gateways is ever configured.
type requestOTPReq struct {
	Channel string `json:"channel"` // "phone" | "email" | ""
}

// POST /api/admin/permissions/otp — issue the second factor for a permission
// change to the acting Super Admin, on their phone OR their email (H1).
//
// Delivery, and how honest it is, is decided entirely by sendSecondFactor; this
// handler only reports what happened. In particular `degraded: true` means the
// code came back in this response instead of travelling out of band, and the
// dashboard is expected to say so on screen rather than draw a padlock.
func (h *AdminPermissionsHandler) RequestOTP(c *gin.Context) {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "code": "auth_required", "error": "Not authenticated."})
		return
	}
	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		// The code is stored keyed by phone even when it is DELIVERED by email,
		// because that is the row VerifyAndConsume reads. An account with no
		// number therefore cannot use this factor at all.
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false, "code": "factor_no_phone",
			"error": "Your account has no phone number to receive a code.",
		})
		return
	}
	ctx := c.Request.Context()

	var req requestOTPReq
	_ = c.ShouldBindJSON(&req) // body is optional; an absent one means "either"

	delivery, err := h.sendSecondFactor(ctx, phone, h.actorEmail(ctx, actor.UserID), strings.TrimSpace(req.Channel))
	if err != nil {
		log.Printf("[security] H1: could not deliver the permission second factor to actor %d: %v",
			actor.UserID, err)
		c.JSON(http.StatusBadGateway, gin.H{
			"success": false, "code": "factor_send_failed",
			"error": "The verification code could not be sent.",
		})
		return
	}

	resp := gin.H{
		"success":  true,
		"mode":     delivery.Mode,
		"channel":  delivery.Channel,
		"degraded": delivery.Degraded,
	}
	// phone_hint is kept under its original name: the dashboard has read it
	// since Section 24 and an un-updated tab must not break on this deploy.
	if delivery.Channel == "email" {
		resp["email_hint"] = delivery.Hint
	} else {
		resp["phone_hint"] = delivery.Hint
	}
	if delivery.Degraded {
		// Same field name the SPA already reads, so nothing regresses; the
		// meaning is now stated alongside it rather than implied.
		resp["demo_code"] = delivery.InBand
	}
	c.JSON(http.StatusOK, resp)
}

// POST /api/admin/permissions — set one (tier, module, action) → allowed and
// append an audit record.
//
// H1 — requires BOTH factors, and BOTH are now enforced HERE. The password used
// to be checked only by the page that asked for it, so a caller that never
// called /admin/verify-password never met it; see admin_permissions_2fa.go.
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

	// H14 — is this actor frozen out of the section after a burst? Checked
	// first, before any factor is spent: a blocked actor must not be able to
	// burn a single-use code, and must not be told anything about the change
	// they attempted beyond "this section is locked".
	if h.refuseBlocked(c, actor.UserID) {
		return
	}

	// Section 24 — suspicious-activity guard: throttle rapid permission changes
	// (defense-in-depth atop the per-change OTP). No-op unless PERM_CHANGE_MAX_
	// PER_MIN is configured. Checked before the OTP so a throttled request does
	// not burn the admin's single-use code.
	if !permLimiter.allow(actor.UserID, time.Now()) {
		c.JSON(http.StatusTooManyRequests, gin.H{"success": false, "code": "perm_change_throttled", "error": "Too many permission changes in a short time. Please wait a minute and try again."})
		return
	}

	// H1 — FIRST factor: the acting admin's own password. Checked before the
	// OTP so a wrong password does not burn the single-use code.
	refused, passwordOutcome := h.checkPasswordFactor(c, actor.UserID, req.Password)
	if refused {
		return
	}

	// Section 24 — SECOND factor, verified BEFORE applying anything. The code is
	// single-use (consumed on success), so each change needs a fresh one.
	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "code": "factor_no_phone", "error": "Your account has no phone number for 2FA."})
		return
	}
	if okOtp, reason := h.OTPs.VerifyAndConsume(ctx, phone, req.Otp); !okOtp {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "code": "factor_code_rejected", "error": reason})
		return
	}

	// Capture the effective value BEFORE the change for the audit trail.
	oldAllowed, _ := h.Perms.Allowed(ctx, permissions.TierFrom(req.Tier), req.Module, req.Action)

	if err := h.Perms.SetOverride(ctx, req.Tier, req.Module, req.Action, req.Allowed); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	// H11 — "force logout the instant permissions are reduced". A tier demotion,
	// a suspend, a ban and an archive all already end the affected sessions;
	// this screen did not, so a staff member kept the dashboard the SPA had
	// already rendered for them and only met the change on their next gated
	// click. Charged ONLY on a reduction: being granted something must not sign
	// anyone out, or operators learn to avoid this screen.
	//
	// Skipped for the `user` tier on purpose. That tier cannot reach the
	// dashboard at all (permissions.CanAccessDashboard) and the matrix governs
	// nothing else for it, so revoking there would mass-log-out every app user
	// on the platform for a change that does not affect them — a far worse
	// outcome than the bug being fixed.
	if oldAllowed && !req.Allowed && permissions.CanAccessDashboard(permissions.TierFrom(req.Tier)) {
		if n, err := revokeSessionsForTierPermission(ctx, h.Perms.Pool, req.Tier, req.Module, req.Action); err != nil {
			// Best-effort, like every other force-logout call site: the
			// permission change itself has already been written and audited,
			// and refusing it now would leave the operator worse off. Logged so
			// a session that outlived its permission is traceable.
			log.Printf("[security] permission reduced (%s) but force-logout failed: %v", req.Tier+"/"+req.Module+"/"+req.Action, err)
		} else if n > 0 {
			log.Printf("[security] permission reduced (%s) — ended %d session(s)", req.Tier+"/"+req.Module+"/"+req.Action, n)
		}
	}

	id := actor.UserID
	target := req.Tier + "/" + req.Module + "/" + req.Action
	_ = h.Perms.LogAudit(ctx, &id, "permission_set", target,
		boolWord(oldAllowed), boolWord(req.Allowed), c.ClientIP())

	// H14 — count what just landed in the audit trail and, if this actor is
	// bursting, freeze the section and end their sessions. Runs AFTER the audit
	// write because the audit trail IS the counter.
	h.tripBlockIfBursting(c, actor.UserID, phone)

	c.JSON(http.StatusOK, gin.H{
		"success": true, "tier": req.Tier, "module": req.Module,
		"action": req.Action, "allowed": req.Allowed,
		"factors": factorReport(passwordOutcome, h.secondFactorDegraded()),
	})
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
	Allowed  *bool  `json:"allowed"`
	Otp      string `json:"otp"`
	Password string `json:"password"` // H1 — see setPermissionReq
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

	// H14 — the per-employee screen writes to the same section, so it counts
	// toward the same burst and obeys the same freeze.
	if h.refuseBlocked(c, actor.UserID) {
		return
	}

	if !permLimiter.allow(actor.UserID, time.Now()) {
		c.JSON(http.StatusTooManyRequests, gin.H{"success": false, "code": "perm_change_throttled", "error": "Too many permission changes in a short time. Please wait a minute and try again."})
		return
	}

	// H1 — the same two factors as the tier matrix. A per-employee override is
	// just as sensitive, only narrower in blast radius, so it gets the identical
	// treatment rather than a relaxed copy that would drift.
	refused, passwordOutcome := h.checkPasswordFactor(c, actor.UserID, req.Password)
	if refused {
		return
	}

	phone := strings.TrimSpace(actor.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "code": "factor_no_phone", "error": "Your account has no phone number for 2FA."})
		return
	}
	if okOtp, reason := h.OTPs.VerifyAndConsume(ctx, phone, req.Otp); !okOtp {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "code": "factor_code_rejected", "error": reason})
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
		// H11 — clearing an override can REDUCE this employee just as surely as
		// setting one to false: if their personal grant was the only reason they
		// held the permission, removing it drops them back to a tier that does
		// not. Compared on the EFFECTIVE value before and after, not on the
		// override's presence, because only the effective value is what they
		// could actually do.
		h.forceLogoutIfReduced(ctx, targetID, oldAllowed, newAllowed, target)
		id := actor.UserID
		_ = h.Perms.LogAudit(ctx, &id, "user_permission_cleared", target, boolWord(oldAllowed), boolWord(newAllowed), c.ClientIP())
		h.tripBlockIfBursting(c, actor.UserID, phone) // H14 — same section, same burst
		c.JSON(http.StatusOK, gin.H{
			"success": true, "user_id": targetID, "module": req.Module, "action": req.Action,
			"allowed": newAllowed, "source": "tier",
			"factors": factorReport(passwordOutcome, h.secondFactorDegraded()),
		})
		return
	}

	if err := h.Perms.SetUserOverride(ctx, targetID, tier, req.Module, req.Action, *req.Allowed); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	// H11 — the narrow half of the same rule. Only this employee's sessions end,
	// because only this employee's authority changed.
	h.forceLogoutIfReduced(ctx, targetID, oldAllowed, *req.Allowed, target)
	id := actor.UserID
	_ = h.Perms.LogAudit(ctx, &id, "user_permission_set", target, boolWord(oldAllowed), boolWord(*req.Allowed), c.ClientIP())
	h.tripBlockIfBursting(c, actor.UserID, phone) // H14 — same section, same burst
	c.JSON(http.StatusOK, gin.H{
		"success": true, "user_id": targetID, "module": req.Module, "action": req.Action,
		"allowed": *req.Allowed, "source": "user",
		"factors": factorReport(passwordOutcome, h.secondFactorDegraded()),
	})
}

// forceLogoutIfReduced ends one employee's sessions when their effective
// permission went from allowed to denied, and does nothing otherwise.
//
// H11 — factored out because BOTH per-user paths need it (setting an override
// to false, and clearing an override that was the only thing granting it), and
// duplicating the comparison is how the two would drift apart.
//
// Best-effort, matching every other force-logout call site: the permission
// change is already written and audited by the time this runs, so a failure
// here is logged rather than turned into an error the operator cannot act on.
func (h *AdminPermissionsHandler) forceLogoutIfReduced(
	ctx context.Context, userID int64, oldAllowed, newAllowed bool, target string,
) {
	if !oldAllowed || newAllowed {
		return
	}
	if _, err := revokeSessionsForUser(ctx, h.Perms.Pool, userID); err != nil {
		log.Printf("[security] permission reduced (%s) but force-logout failed: %v", target, err)
		return
	}
	log.Printf("[security] permission reduced (%s) — ended user %d's sessions", target, userID)
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
