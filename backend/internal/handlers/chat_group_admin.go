// chat_group_admin.go — staff-facing chat-group endpoints: listing every
// group, creating one directly (independent of the connect-request flow,
// which is Phase 3), managing membership, reading a group's roster, messages
// and contact blocks, and the connect-request inbox. Split from chat_group.go
// (mobile) from the start — see that file's doc comment for why.
//
// The roster, messages and contact-block reads name the real people behind a
// masked group's labels, so for a MASKED group they also require
// sensitive_data per user (refuseMaskedWithoutSensitive, OPOS #26409).
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

// ─── Masked-group identity gate (OPOS #26409, user decision D1) ─────────

// sensitiveDataRequiredCode is the machine-readable code on the 403 that the
// roster, messages and contact-block reads return for a masked group when the
// caller may not see sensitive data. The dashboard keys its restricted state
// on this value, so it is a contract: never reword it.
const sensitiveDataRequiredCode = "sensitive_data_required"

// refuseMaskedWithoutSensitive writes the refusal and returns true when the
// caller must not read this group's roster, messages or contact blocks.
//
// Those three responses put a real user id and real name next to every masked
// label, which is the key that de-masks the group. For a MASKED group the
// caller must therefore hold sensitive_data:view, resolved PER USER by
// canViewContact: the per-employee override first, then the tier. That is
// what GET /api/admin/permissions/me tells the dashboard. main.go used to gate
// these routes with perm("sensitive_data", "view"), which resolves by tier
// only, so an admin revoked for themselves alone kept reading real names and
// an employee granted it for themselves alone was refused.
//
// A TEAM group is a real-name group whose members already see each other, so
// the route's messages:view is enough. Any kind other than team is treated as
// masked, failing closed the same way groupSenderLabel does.
//
// The group must exist first: a missing id answers chatErr's 404 before any
// permission question. Staff holding messages:view already list every group
// and its kind at GET /api/admin/chat-groups, so the order discloses nothing.
func (h *ChatGroupHandler) refuseMaskedWithoutSensitive(c *gin.Context, groupID int64) bool {
	kind, err := h.Store.GroupKind(c.Request.Context(), groupID)
	if err != nil {
		if !errors.Is(err, chatgroups.ErrNotFound) {
			log.Printf("[chat-group] could not read the kind of group %d: %v", groupID, err)
		}
		h.chatErr(c, err)
		return true
	}
	if kind == chatgroups.KindTeam || canViewContact(c, h.Perms) {
		return false
	}
	c.JSON(http.StatusForbidden, gin.H{
		"success": false,
		"error":   "You need permission to view sensitive data to read this masked group.",
		"code":    sensitiveDataRequiredCode,
	})
	return true
}

// ─── Group reads ────────────────────────────────────────────────────────

// GET /api/admin/chat-groups/:id — the group row and its full roster,
// including removed members, each member with their real name (full_name,
// null when they have no profile). A masked group also needs sensitive_data
// per user (refuseMaskedWithoutSensitive).
//
// The top-level lifecycle, lifecycle_reason and is_archived come from
// mergeChatLifecycle, the same triple every other thread read carries, so the
// dashboard's lifecycle controls can show why a group is paused or ended and
// whether it is archived (part of OPOS #26410).
func (h *ChatGroupHandler) AdminGetGroup(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.refuseMaskedWithoutSensitive(c, id) {
		return
	}
	group, err := h.Store.AdminGetGroup(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, mergeChatLifecycle(c, h.Pool, chatlifecycle.KindGroup, id, gin.H{
		"success": true,
		"group":   group,
	}))
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

// GET /api/admin/chat-groups/:id/messages — the unmasked history, real sender
// id and name on every message. A masked group also needs sensitive_data per
// user (refuseMaskedWithoutSensitive); a missing group is 404.
func (h *ChatGroupHandler) AdminMessages(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.refuseMaskedWithoutSensitive(c, id) {
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

// GET /api/admin/chat-groups/:id/contact-blocks — every refused attempt to
// pass contact details, with the real sender named. A masked group also needs
// sensitive_data per user (refuseMaskedWithoutSensitive); a missing group is
// 404.
func (h *ChatGroupHandler) AdminContactBlocks(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	if h.refuseMaskedWithoutSensitive(c, id) {
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

// adminConnectRequestItem is one connect request as the admin inbox receives
// it: the list's items, and the detail's `request`, so both screens read one
// shape. context_label is resolveConnectContext's human-readable label.
//
// requester_name is present only for a caller who may view sensitive data,
// resolved per user by canViewContact (user decision D6, part of OPOS
// #26410). It is omitted otherwise, and also when the requester has no
// profile name. The store type tags its own RequesterName json:"-", so this
// field — which shadows it — is the only way the name reaches the wire.
type adminConnectRequestItem struct {
	chatgroups.ConnectRequest
	ContextLabel  string  `json:"context_label"`
	RequesterName *string `json:"requester_name,omitempty"`
}

// adminConnectRequestItems maps store rows to the inbox shape. The
// sensitive-data answer is asked once for the whole batch, as canViewContact's
// doc comment requires, and the requester's name is copied in only when it is
// yes.
func (h *ChatGroupHandler) adminConnectRequestItems(c *gin.Context, requests []chatgroups.ConnectRequest) []adminConnectRequestItem {
	canSeeNames := canViewContact(c, h.Perms)
	out := make([]adminConnectRequestItem, len(requests))
	for i, r := range requests {
		out[i] = adminConnectRequestItem{
			ConnectRequest: r,
			ContextLabel:   h.resolveConnectContext(c.Request.Context(), r.ContextType, r.ContextID),
		}
		if canSeeNames {
			out[i].RequesterName = r.RequesterName
		}
	}
	return out
}

// GET /api/admin/chat-groups/connect-requests — the inbox, newest first,
// optionally filtered by ?status=pending|approved|declined. Every item is an
// adminConnectRequestItem.
func (h *ChatGroupHandler) AdminListConnectRequests(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListConnectRequests(c.Request.Context(), c.Query("status"))
	if err != nil {
		log.Printf("[chat-group] could not list connect requests: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": h.adminConnectRequestItems(c, items)})
}

// GET /api/admin/chat-groups/connect-requests/:id — one request as `request`,
// an adminConnectRequestItem (the list item's shape), plus the top-level
// context_label existing callers already read.
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
	item := h.adminConnectRequestItems(c, []chatgroups.ConnectRequest{req})[0]
	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"request":       item,
		"context_label": item.ContextLabel,
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
