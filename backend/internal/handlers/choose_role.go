package handlers

import (
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
	if req.UserID <= 0 || req.RoleID <= 0 {
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
	if current > 0 {
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
	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"role_unchanged": false,
		"role_id":        req.RoleID,
		"message":        "User role updated successfully.",
	})
}
