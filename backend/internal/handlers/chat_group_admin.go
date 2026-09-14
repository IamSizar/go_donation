// chat_group_admin.go — staff-facing chat-group endpoints: listing every
// group, creating one directly (independent of the connect-request flow,
// which is Phase 3), and managing membership. Split from chat_group.go
// (mobile) from the start — see that file's doc comment for why.
package handlers

import (
	"context"
	"errors"
	"fmt"
	"log"
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
	// Best-effort: mirrors refuseGroupContactDetails' RecordContactBlock
	// handling in chat_group_contact_block.go — the group is already
	// created, so a failed audit write is logged, not surfaced to the
	// caller or allowed to roll back the primary action.
	if err := h.Store.RecordAudit(c.Request.Context(), groupID, "created", user.UserID, nil); err != nil {
		log.Printf("[chat-group] could not record audit for group %d creation: %v", groupID, err)
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
	// Best-effort — see AdminCreateGroup's identical comment.
	if err := h.Store.RecordAudit(c.Request.Context(), id, "member_added", user.UserID, &req.UserID); err != nil {
		log.Printf("[chat-group] could not record audit for member %d added to group %d: %v", req.UserID, id, err)
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
	// Best-effort — see AdminCreateGroup's identical comment.
	if err := h.Store.RecordAudit(c.Request.Context(), id, "member_removed", user.UserID, &memberUserID); err != nil {
		log.Printf("[chat-group] could not record audit for member %d removed from group %d: %v", memberUserID, id, err)
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

// resolveConnectContext turns a connect request's raw context_type/context_id
// into a human-readable label for the admin inbox — staff cannot make a
// privacy decision from "context_id: 4471" (design spec §6). Best-effort:
// a resolution failure falls back to the raw id rather than breaking the
// whole inbox listing, matching this file's existing groupSenderLabel
// pattern for a similar best-effort lookup.
func (h *ChatGroupHandler) resolveConnectContext(ctx context.Context, contextType string, contextID int64) string {
	switch contextType {
	case "donation":
		// donations.amount is VARCHAR(200), not numeric (see
		// migrations/001_full_v2.sql:395) — this codebase never parses it to a
		// float (internal/donations/donations.go models Amount as a plain Go
		// string throughout), so it is scanned as a string here too.
		var amount, campaignTitle string
		_ = h.Pool.QueryRow(ctx, `
			SELECT d.amount, COALESCE(c.title, 'General fund')
			  FROM donations d LEFT JOIN campaigns c ON c.id = d.campaign_id
			 WHERE d.id = $1`, contextID).Scan(&amount, &campaignTitle)
		if campaignTitle != "" {
			return fmt.Sprintf("Donation of %s to %q", amount, campaignTitle)
		}
	case "case":
		var caseCode, title string
		_ = h.Pool.QueryRow(ctx, `SELECT case_code, public_title FROM beneficiary_cases WHERE id = $1`, contextID).
			Scan(&caseCode, &title)
		if caseCode != "" {
			return fmt.Sprintf("Case %s — %s", caseCode, title)
		}
	}
	return fmt.Sprintf("%s #%d", contextType, contextID)
}

// GET /api/admin/chat-groups/connect-requests
func (h *ChatGroupHandler) AdminListConnectRequests(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListConnectRequests(c.Request.Context(), c.Query("status"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	type resolvedItem struct {
		chatgroups.ConnectRequest
		ContextLabel string `json:"context_label"`
	}
	out := make([]resolvedItem, len(items))
	for i, r := range items {
		out[i] = resolvedItem{ConnectRequest: r, ContextLabel: h.resolveConnectContext(c.Request.Context(), r.ContextType, r.ContextID)}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": out})
}

// GET /api/admin/chat-groups/connect-requests/:id
func (h *ChatGroupHandler) AdminGetConnectRequest(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	req, err := h.Store.GetConnectRequest(c.Request.Context(), id)
	if err != nil {
		// A missing connect request is not a missing "Group" — chatErr's
		// generic ErrNotFound message is shared by every other chat-group
		// route and stays as-is; only this connect-request-specific case gets
		// a more accurate message.
		if errors.Is(err, chatgroups.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Connect request not found."})
			return
		}
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"request":       req,
		"context_label": h.resolveConnectContext(c.Request.Context(), req.ContextType, req.ContextID),
	})
}

// POST /api/admin/chat-groups/connect-requests/:id/approve
func (h *ChatGroupHandler) AdminApproveConnectRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
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
	groupID, err := h.Store.ApproveConnectRequest(c.Request.Context(), id, chatgroups.Kind(req.Kind), req.MemberTitle, user.UserID, members)
	if err != nil {
		if errors.Is(err, chatgroups.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Connect request not found."})
			return
		}
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "group_id": groupID})
}

type declineConnectRequestReq struct {
	Reason string `json:"reason"`
}

// POST /api/admin/chat-groups/connect-requests/:id/decline
func (h *ChatGroupHandler) AdminDeclineConnectRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req declineConnectRequestReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Reason) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "A decline reason is required."})
		return
	}
	if err := h.Store.DeclineConnectRequest(c.Request.Context(), id, user.UserID, req.Reason); err != nil {
		if errors.Is(err, chatgroups.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Connect request not found."})
			return
		}
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
