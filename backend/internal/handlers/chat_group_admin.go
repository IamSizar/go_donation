// chat_group_admin.go — staff-facing chat-group endpoints: listing every
// group, creating one directly (independent of the connect-request flow,
// which is Phase 3), and managing membership. Split from chat_group.go
// (mobile) from the start — see that file's doc comment for why.
package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

// GET /api/admin/chat-groups
func (h *ChatGroupHandler) AdminList(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListGroupsForStaff(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/chat-groups/:id
func (h *ChatGroupHandler) AdminGetGroup(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	group, err := h.Store.GetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "group": group})
}

type adminGroupMemberReq struct {
	UserID      int64  `json:"user_id"`
	RoleInGroup string `json:"role_in_group"`
	Label       string `json:"label"`
}

type adminCreateGroupReq struct {
	Kind        string                `json:"kind"`
	MemberTitle string                `json:"member_title"`
	Members     []adminGroupMemberReq `json:"members"`
}

// POST /api/admin/chat-groups
func (h *ChatGroupHandler) AdminCreateGroup(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req adminCreateGroupReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}
	if strings.TrimSpace(req.Kind) == "" || len(req.Members) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "kind and at least one member are required."})
		return
	}
	members := make([]chatgroups.MemberInput, len(req.Members))
	for i, m := range req.Members {
		members[i] = chatgroups.MemberInput{UserID: m.UserID, RoleInGroup: m.RoleInGroup, Label: m.Label}
	}
	groupID, err := h.Store.CreateGroup(c.Request.Context(), chatgroups.Kind(req.Kind), req.MemberTitle, user.UserID, members)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "group_id": groupID})
}

// POST /api/admin/chat-groups/:id/members
func (h *ChatGroupHandler) AdminAddMember(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req adminGroupMemberReq
	if err := c.ShouldBindJSON(&req); err != nil || req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required."})
		return
	}
	input := chatgroups.MemberInput{UserID: req.UserID, RoleInGroup: req.RoleInGroup, Label: req.Label}
	if err := h.Store.AddMember(c.Request.Context(), id, input, user.UserID); err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DELETE /api/admin/chat-groups/:id/members/:userId
func (h *ChatGroupHandler) AdminRemoveMember(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	memberUserID, err := strconv.ParseInt(c.Param("userId"), 10, 64)
	if err != nil || memberUserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid user id."})
		return
	}
	if err := h.Store.RemoveMember(c.Request.Context(), id, memberUserID, user.UserID); err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GET /api/admin/chat-groups/:id/messages
func (h *ChatGroupHandler) AdminMessages(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	afterID, limit := parseGroupPageParams(c)
	items, err := h.Store.AdminListMessages(c.Request.Context(), id, afterID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/admin/chat-groups/:id/messages — staff replies, shown as
// "Support" to non-staff members (see groupSenderLabel, chat_group.go).
func (h *ChatGroupHandler) AdminPostMessage(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	group, err := h.Store.GetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	// The pause holds for STAFF too — a pause staff could talk through would
	// not be a pause (see AdminPostMessage's equivalent comment in chat.go).
	if refuseIfNotSendable(c, h.Pool, chatlifecycle.KindGroup, id) {
		return
	}
	var req chatGroupMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	if h.refuseGroupContactDetails(c, group, user, req.Body) {
		return
	}
	msgID, err := h.Store.PostMessageAsStaff(c.Request.Context(), id, user.UserID, req.Body)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	h.notifyGroupMembers(group, user.UserID, req.Body)
	c.JSON(http.StatusOK, gin.H{"success": true, "message_id": msgID})
}

// GET /api/admin/chat-groups/:id/contact-blocks
func (h *ChatGroupHandler) AdminContactBlocks(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	items, err := h.Store.ListContactBlocks(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
