// chat_group_connect.go — the mobile half of the connect-request flow: a
// donor/beneficiary/volunteer asks staff to open a chat. The admin half
// (inbox, approve, decline) is in chat_group_admin_connect.go.
package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

type submitConnectRequestReq struct {
	ContextType string `json:"context_type"`
	ContextID   int64  `json:"context_id"`
	TargetHint  *int64 `json:"target_hint"`
	Message     string `json:"message"`
}

// POST /api/chat-groups/connect-requests
//
// SubmitConnectRequest records a member's request that staff connect them
// about one donation or beneficiary case. It answers 200 with request_id, and
// 400 when the body is malformed or the message blank, when context_type is
// not "donation" or "case", or — with code connect_context_not_found — when
// no case or donation has that id (OPOS #26351). Existence is the only rule:
// the app offers this on every case and donation whatever its status or
// owner, and the server refuses nothing else. See
// chatgroups.Store.SubmitConnectRequest.
func (h *ChatGroupHandler) SubmitConnectRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req submitConnectRequestReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Message) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "context_type, context_id, and message are required."})
		return
	}
	id, err := h.Store.SubmitConnectRequest(c.Request.Context(), user.UserID, req.ContextType, req.ContextID, req.TargetHint, req.Message)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "request_id": id})
}

// myConnectRequestItem is the requester-facing view of a
// chatgroups.ConnectRequest. It deliberately drops DecidedByStaff (and
// RequesterID, which the caller already knows from being logged in) —
// design spec §9 says members see every staff reply under the collective
// "Support" label, never a specific admin's name, and echoing back WHICH
// staff member approved or declined a request would break that guarantee
// just as surely as leaking a name in a chat message would. Map every
// chatgroups.ConnectRequest through this type before it reaches JSON; never
// serialize the store type directly from this endpoint.
type myConnectRequestItem struct {
	ID            int64                           `json:"id"`
	ContextType   string                          `json:"context_type"`
	ContextID     int64                           `json:"context_id"`
	Message       string                          `json:"message"`
	GroupID       *int64                          `json:"group_id,omitempty"`
	Status        chatgroups.ConnectRequestStatus `json:"status"`
	DeclineReason string                          `json:"decline_reason,omitempty"`
	CreatedAt     time.Time                       `json:"created_at"`
}

// GET /api/chat-groups/connect-requests/mine
func (h *ChatGroupHandler) MyConnectRequests(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	requests, err := h.Store.ListConnectRequestsForUser(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	items := make([]myConnectRequestItem, 0, len(requests))
	for _, r := range requests {
		items = append(items, myConnectRequestItem{
			ID:            r.ID,
			ContextType:   r.ContextType,
			ContextID:     r.ContextID,
			Message:       r.Message,
			GroupID:       r.GroupID,
			Status:        r.Status,
			DeclineReason: r.DeclineReason,
			CreatedAt:     r.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
