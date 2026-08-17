package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ChooseRoleHandler ports percentage/api/choose_role/index.php.
type ChooseRoleHandler struct {
	Users *users.Store
}

func NewChooseRoleHandler(u *users.Store) *ChooseRoleHandler {
	return &ChooseRoleHandler{Users: u}
}

// roleMarriage is the marriage/engagement account type; roleGuest (0) is the
// unassigned/browsing state. Both are self-selectable — see Post.
const (
	roleGuest    = 0
	roleMarriage = 5
)

// selfSelectableRole reports whether a user may switch themselves INTO this
// role after already having one.
func selfSelectableRole(roleID int) bool {
	return roleID == roleMarriage || roleID == roleGuest
}

type chooseRoleReq struct {
	UserID int64 `json:"user_id" form:"user_id"`
	RoleID int   `json:"role_id" form:"role_id"`
}

// POST /api/choose_role
// Bearer required. user_id MUST match the token's user. If the user already
// has a role_id set (>0), returns role_unchanged:true without writing.
func (h *ChooseRoleHandler) Post(c *gin.Context) {
	tokenUser, ok := auth.UserFromGin(c)
	if !ok || tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}

	var req chooseRoleReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body."})
		return
	}
	if req.UserID <= 0 || req.RoleID < 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Missing or invalid user_id or role_id",
		})
		return
	}
	if req.UserID != tokenUser.UserID {
		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "User mismatch for this request.",
		})
		return
	}

	ctx := c.Request.Context()
	current, err := h.Users.GetRoleID(ctx, req.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error.",
		})
		return
	}
	// Picking a role is normally one-time — a user can't promote themselves
	// into Recipient or Volunteer, which gate features and are granted by
	// staff after vetting.
	//
	// The two exceptions a user MAY switch to on their own are the account
	// types that carry no such privilege: the marriage/engagement service,
	// and stepping back to guest. Anything else still returns unchanged.
	if current > 0 && !selfSelectableRole(req.RoleID) {
		c.JSON(http.StatusOK, gin.H{
			"success":        true,
			"role_unchanged": true,
			"role_id":        current,
			"message":        "User already has a role; it was kept unchanged.",
		})
		return
	}

	if err := h.Users.UpdateRoleID(ctx, req.UserID, req.RoleID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to update user role.",
		})
		return
	}
	// The chosen role's identity code, minted here for the same reason it is
	// minted after the admin role write (admin_status.go, UserRole): until now
	// every code was assigned on the registration path only, keyed on the role
	// the account had at that moment, so an account whose role changed
	// afterwards reported the new role while carrying only the old role's code.
	// pickIdentityCode then shows the stale one and no search for the new
	// role's prefix can find the person, because that column is empty.
	//
	// In practice this path assigns a code far less often than the admin one:
	// the gate above means the roles reachable here are a FIRST role (any of
	// 1/2/3, from role 0), or a self-selectable switch to marriage (5) or back
	// to guest (0). Neither 5 nor 0 has a code scheme, so those are no-ops by
	// construction — see identityCodePrefixForRole. It is wired anyway because
	// the first-role case is real and because leaving one of the two role
	// writers unwired is exactly how the original gap survived.
	//
	// Assign-once: the helpers behind this carry `AND <col> = ''`, so a code
	// already written on paperwork is never overwritten and a user who has held
	// two roles keeps both.
	//
	// Logged rather than returned: the role write above already succeeded, and
	// failing the response now would tell the user their role did not change
	// when it did. A missing code is recoverable; a confusing refusal is not.
	if err := h.Users.EnsureIdentityCodeForRole(ctx, req.UserID, req.RoleID); err != nil {
		log.Printf("[identity-code] choose_role to %d for user %d: code not assigned: %v",
			req.RoleID, req.UserID, err)
	}
	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"role_unchanged": false,
		"role_id":        req.RoleID,
		"message":        "User role updated successfully.",
	})
}
