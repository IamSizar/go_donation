package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

const contextUserKey = "auth.user"

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
//   - admins (is_admin=1) always pass — they're trusted and grandfathered.
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
		if u.IsAdmin != 1 && u.RegistrationStatus != "" && u.RegistrationStatus != "approved" {
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
// the resolved user has `is_admin = 1`. Run this as the gate on /api/admin/*.
//
// Behavior:
//   - missing/malformed Authorization header  → 401
//   - invalid / expired / revoked token        → 401
//   - valid token but is_admin = 0             → 403
//   - valid admin token                        → handler runs (user attached)
//
// We deliberately do NOT delegate to RequireBearer here — that middleware ends
// with c.Next() which advances past us to the route handler, so the admin
// check would run after the response has already been sent.
//
// Pair this with the SPA-side gate that hides admin pages from non-admins.
// Defense in depth: the SPA gate is for UX; this is the actual security.
func RequireAdmin(store *TokenStore) gin.HandlerFunc {
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
		if user.IsAdmin != 1 {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status": "error",
				"error":  "Admin access required.",
			})
			return
		}
		c.Set(contextUserKey, user)
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
