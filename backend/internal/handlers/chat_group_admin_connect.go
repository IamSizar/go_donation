// chat_group_admin_connect.go — the staff-facing connect-request inbox: the
// list, the single-request detail, and the approve and decline decisions,
// plus the helpers that shape each request for the dashboard
// (resolveConnectContext's human-readable context label and the
// adminConnectRequestItem DTO, whose requester_name follows sensitive_data per
// user). The mobile half of the flow, where a member files a request, is
// chat_group_connect.go; the rest of the staff chat-group endpoints are
// chat_group_admin.go. Moved out of chat_group_admin.go unchanged to keep that
// file under the 500-line limit.
package handlers

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

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

// connectRequestErr prepares a connect-request store error for chatErr. The
// store reports a missing request with the same ErrNotFound it uses for a
// missing group, which chatErr would answer "Group not found."; a missing
// connect request is not a missing group, so that case is wrapped with
// errConnectRequestNotFound and answers 404 connect_request_not_found with the
// sentence "Connect request not found." (OPOS #26478). The original error
// stays in the chain. Every other error passes through unchanged.
func connectRequestErr(err error) error {
	if errors.Is(err, chatgroups.ErrNotFound) {
		return fmt.Errorf("%w: %w", errConnectRequestNotFound, err)
	}
	return err
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
		h.chatErr(c, connectRequestErr(err))
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
		h.chatErr(c, connectRequestErr(err))
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
		h.chatErr(c, connectRequestErr(err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
