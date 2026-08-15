package auth

import (
	"context"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

const contextUserKey = "auth.user"

// ─── A15 · who may reach the dashboard ──────────────────────────────────
//
// `staff_tier` is THE authoritative field. `users.is_admin` is a legacy
// SMALLINT that migration 015 already folded into `staff_tier` ("legacy
// is_admin=1 accounts become the 'admin' tier"), but the gates below kept
// honouring it as an INDEPENDENT grant — `if user.IsAdmin != 1 && !tierCheck`.
// Two problems followed:
//
//  1. The two fields drifted. Production holds a row with is_admin = 1 and
//     staff_tier = 'user' — an ordinary app user — plus a genuine super_admin
//     with is_admin = 0. The legacy flag says the opposite of the truth in
//     both directions.
//  2. The mobile app and the dashboard share ONE token store, so the flag was
//     honoured on a token minted by the ordinary phone login. An app user
//     carrying is_admin = 1 reached /api/admin/* straight from the app —
//     the hole the client reported.
//
// So the flag is no longer consulted for authorisation anywhere. It survives
// only as a display/legacy column. Every gate funnels through the two
// predicates below, so "who is staff" has exactly one answer in one place.

// IsDashboardStaff reports whether a resolved user may reach /api/admin/* at
// all: super_admin, admin, supervisor or employee. Everyone else — every
// donor, beneficiary and volunteer using the app — is not staff.
func IsDashboardStaff(u *ResolvedUser) bool {
	return u != nil && permissions.CanAccessDashboard(permissions.TierFrom(u.StaffTier))
}

// IsAdminLevel reports whether a resolved user holds an ADMIN-level tier
// (super_admin or admin) — the bar for the most sensitive writes: trash
// restore, catalogue CRUD, payment methods, global settings.
func IsAdminLevel(u *ResolvedUser) bool {
	if u == nil {
		return false
	}
	tier := permissions.TierFrom(u.StaffTier)
	return tier == permissions.TierSuperAdmin || tier == permissions.TierAdmin
}

// denyAuthz writes a refusal and records it server-side.
//
// Two rules the dashboard depends on:
//   - `code` is a STABLE machine key; the SPA's describeError() maps it through
//     its `error.*` namespace, so the operator reads the refusal in their own
//     language instead of the English prose in `error` (which is a fallback for
//     non-SPA callers and the logs).
//   - every refusal is logged. A silent 403 is invisible to whoever is trying
//     to work out why a staff account cannot do its job — and equally invisible
//     when someone is probing the admin API with an app token.
func denyAuthz(c *gin.Context, status int, code, message string) {
	uid := int64(0)
	tier := ""
	if u, ok := UserFromGin(c); ok && u != nil {
		uid, tier = u.UserID, u.StaffTier
	}
	log.Printf("[authz] denied %s %s — code=%s user_id=%d staff_tier=%q ip=%s",
		c.Request.Method, c.Request.URL.Path, code, uid, tier, c.ClientIP())
	c.AbortWithStatusJSON(status, gin.H{
		"status": "error",
		"error":  message,
		"code":   code,
	})
}

// RequireBearer is a Gin middleware that validates the Authorization: Bearer
// header against api_access_tokens and attaches the resolved user.
// Aborts with 401 if missing/invalid/expired.
func RequireBearer(store *TokenStore) gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := extractBearer(c)
		if raw == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"status": "error",
				"error":  "Missing or malformed Authorization header.",
			})
			return
		}
		user, err := store.ResolveToken(c.Request.Context(), raw)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"status": "error",
				"error":  "Failed to validate token.",
			})
			return
		}
		if user == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"status": "error",
				"error":  "Invalid or expired token.",
			})
			return
		}
		c.Set(contextUserKey, user)
		c.Next()
	}
}

// RequireApproved gates routes behind the new-user registration approval flow.
// It MUST run AFTER RequireBearer (it reads the user RequireBearer attached).
//
//   - staff always pass — they're trusted, and a staff account must never be
//     stuck behind the app's own onboarding queue. A15 — this used to key off
//     `is_admin`; it now uses the same IsDashboardStaff() predicate as every
//     other gate, so "who is staff" cannot mean two different things in two
//     middlewares. (Verified against production: every privileged row is
//     already `approved`, so no account changes behaviour.)
//   - empty status is treated as approved (legacy/grandfathered rows).
//   - any non-approved status (incomplete/pending/rejected) → 403 with the
//     status echoed back so the app can route to the registration or
//     pending-approval screen.
//
// The registration submit/status endpoints and /auth/{me,logout} deliberately
// do NOT use this gate, so a not-yet-approved user can still finish or check
// their registration and sign out.
func RequireApproved() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := UserFromGin(c)
		if !ok || u == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"status": "error",
				"error":  "Unauthorized.",
			})
			return
		}
		if !IsDashboardStaff(u) && u.RegistrationStatus != "" && u.RegistrationStatus != "approved" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status":              "error",
				"error":               "Your account is awaiting approval.",
				"registration_status": u.RegistrationStatus,
			})
			return
		}
		c.Next()
	}
}

// RequireNotGuest gates a route behind full-account status (Note #40). MUST
// run after RequireBearer. Guests are rejected with a distinguishable
// "guest_restricted" code so the client can show its Upgrade Account prompt
// instead of a generic error. Use on: messaging (marriage chat, donor/
// beneficiary chat, assistant chat) and any purchase/service-request-creation
// route (donations, marketplace orders, beneficiary cases/project requests,
// sponsorships, in-kind donations, marriage profile submission/meeting
// requests, community submissions).
func RequireNotGuest() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := UserFromGin(c)
		if !ok || u == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"status": "error",
				"error":  "Unauthorized.",
			})
			return
		}
		if u.IsGuest {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status": "error",
				"error":  "This action requires a full account. Please upgrade your account.",
				"code":   "guest_restricted",
			})
			return
		}
		c.Next()
	}
}

// BlockGuestOptional pairs with OptionalBearer on routes that stay public for
// anonymous callers but must still block a signed-in guest account (Note #40
// — City Directory). Requests with no token, or a non-guest token, pass
// through unchanged; only a resolved guest is rejected.
func BlockGuestOptional() gin.HandlerFunc {
	return func(c *gin.Context) {
		if u, ok := UserFromGin(c); ok && u != nil && u.IsGuest {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status": "error",
				"error":  "Full registration is required to view this section.",
				"code":   "guest_restricted",
			})
			return
		}
		c.Next()
	}
}

// RequireGuest gates a route behind CURRENTLY-guest status — the inverse of
// RequireNotGuest. MUST run after RequireBearer. Used only by the guest
// upgrade-phone endpoint, so a full account can't accidentally re-run the
// guest-upgrade flow against itself.
func RequireGuest() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := UserFromGin(c)
		if !ok || u == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"status": "error",
				"error":  "Unauthorized.",
			})
			return
		}
		if !u.IsGuest {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status": "error",
				"error":  "This account is not a guest account.",
			})
			return
		}
		c.Next()
	}
}

// UserFromContext returns the user attached by RequireBearer.
func UserFromContext(ctx context.Context) (*ResolvedUser, bool) {
	if c, ok := ctx.(*gin.Context); ok {
		if v, exists := c.Get(contextUserKey); exists {
			u, ok := v.(*ResolvedUser)
			return u, ok
		}
	}
	return nil, false
}

// OptionalBearer attaches a *ResolvedUser to the context if a valid Bearer
// token is supplied, but does NOT reject requests that have no token (or an
// invalid one). Use this for endpoints that behave differently based on
// auth presence (e.g. dual-mode GETs).
func OptionalBearer(store *TokenStore) gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := extractBearer(c)
		if raw == "" {
			c.Next()
			return
		}
		user, err := store.ResolveToken(c.Request.Context(), raw)
		if err == nil && user != nil {
			c.Set(contextUserKey, user)
		}
		c.Next()
	}
}

// RequireAdmin enforces that the request carries a valid Bearer token AND that
// the resolved user holds a STAFF tier. Run this as the gate on /api/admin/*.
//
// Behavior:
//   - missing/malformed Authorization header  → 401
//   - invalid / expired / revoked token        → 401
//   - valid token but staff_tier = 'user'      → 403
//   - valid staff token                        → handler runs (user attached)
//
// We deliberately do NOT delegate to RequireBearer here — that middleware ends
// with c.Next() which advances past us to the route handler, so the admin
// check would run after the response has already been sent.
//
// A15 — the legacy `is_admin` flag is NOT consulted (see the note at the top of
// this file). This is the ONLY control: the SPA hides nav for UX, but a token
// is a token, and the mobile app mints the same kind, so an app user pointing
// curl at /api/admin/* has to be stopped right here.
func RequireAdmin(store *TokenStore) gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := extractBearer(c)
		if raw == "" {
			denyAuthz(c, http.StatusUnauthorized, "auth_required",
				"Missing or malformed Authorization header.")
			return
		}
		user, err := store.ResolveToken(c.Request.Context(), raw)
		if err != nil {
			log.Printf("[authz] token resolution failed on %s %s: %v",
				c.Request.Method, c.Request.URL.Path, err)
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"status": "error",
				"error":  "Failed to validate token.",
				"code":   "server_error",
			})
			return
		}
		if user == nil {
			denyAuthz(c, http.StatusUnauthorized, "auth_required",
				"Invalid or expired token.")
			return
		}
		// Attach BEFORE the authorisation check so a refusal is logged with the
		// identity that attempted it — that log line is the only trace of an
		// app token probing the dashboard.
		c.Set(contextUserKey, user)
		if !IsDashboardStaff(user) {
			denyAuthz(c, http.StatusForbidden, "dashboard_access_required",
				"Dashboard access is limited to staff accounts.")
			return
		}
		c.Next()
	}
}

// RequirePermission gates a route on a (module, action) permission for the
// resolved user's staff tier. Run it AFTER RequireAdmin (which attaches the
// user to the context). Phase 6 (6b).
func RequirePermission(perms *permissions.Store, module, action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		user, ok := UserFromGin(c)
		if !ok || user == nil {
			denyAuthz(c, http.StatusUnauthorized, "auth_required", "Not authenticated.")
			return
		}
		allowed, err := perms.Allowed(c.Request.Context(),
			permissions.TierFrom(user.StaffTier), module, action)
		if err != nil {
			log.Printf("[authz] permission lookup failed for user_id=%d %s/%s: %v",
				user.UserID, module, action, err)
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"status": "error", "error": "Permission check failed.", "code": "server_error",
			})
			return
		}
		if !allowed {
			denyAuthz(c, http.StatusForbidden, "permission_denied",
				"You don't have permission for this action.")
			return
		}
		c.Next()
	}
}

// RequireAdminTier gates a route to admin-level staff only (super_admin or
// admin) — used for the most sensitive actions like the raw DB export.
// Run AFTER RequireAdmin. Phase 7 (M-60 / G-07).
//
// A15 — the legacy `is_admin` grandfather clause is gone here too. It was the
// wider of the two holes: is_admin=1 skipped the tier check on every catalogue
// CRUD, payment-method, trash-restore and settings write, so a row flagged
// is_admin=1 held admin-level authority no matter what tier said.
func RequireAdminTier() gin.HandlerFunc {
	return func(c *gin.Context) {
		user, ok := UserFromGin(c)
		if !ok || user == nil {
			denyAuthz(c, http.StatusUnauthorized, "auth_required", "Not authenticated.")
			return
		}
		if !IsAdminLevel(user) {
			denyAuthz(c, http.StatusForbidden, "admin_level_required",
				"Admin-level access required for this action.")
			return
		}
		c.Next()
	}
}

// RequireSuperAdmin gates a route to the Primary Administrator (super_admin)
// ONLY — stricter than RequireAdminTier, which also lets plain admins through.
// Used for the raw DB (JSON) export, which must be exclusive to the
// super-admin (legacy is_admin=1 accounts do NOT qualify). Run AFTER
// RequireAdmin. A grant path via the Permissions-Management module can extend
// this later; for now tier is the sole gate, matching the frontend
// isSuperAdmin() check.
func RequireSuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		user, ok := UserFromGin(c)
		if !ok || user == nil {
			denyAuthz(c, http.StatusUnauthorized, "auth_required", "Not authenticated.")
			return
		}
		if permissions.TierFrom(user.StaffTier) != permissions.TierSuperAdmin {
			denyAuthz(c, http.StatusForbidden, "super_admin_required",
				"Super-admin access required for this action.")
			return
		}
		c.Next()
	}
}

// UserFromGin is the Gin-typed convenience accessor used by handlers.
func UserFromGin(c *gin.Context) (*ResolvedUser, bool) {
	if v, exists := c.Get(contextUserKey); exists {
		u, ok := v.(*ResolvedUser)
		return u, ok
	}
	return nil, false
}

func extractBearer(c *gin.Context) string {
	h := c.GetHeader("Authorization")
	if h == "" {
		return ""
	}
	parts := strings.Fields(h)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}
