// chat_group.go exposes OPOS #25284's staff-created group chats over HTTP:
// masked donor/beneficiary/volunteer coordination and real-name volunteer
// teams. Mobile (participant-facing) endpoints live here; admin
// (staff-facing) endpoints are chat_group_admin.go on the same struct, and
// the K19-style contact filter is chat_group_contact_block.go — split by
// responsibility from the start, matching this codebase's existing
// chat.go / marriage_chat.go convention but before, not after, hitting the
// file-size cap (see
// docs/superpowers/specs/2026-09-12-chat-groups-phase2-routes-design.md §3).
package handlers

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ChatGroupHandler exposes the chat-group endpoints.
type ChatGroupHandler struct {
	Store    *chatgroups.Store
	Notifier *notify.Notifier
	Perms    *permissions.Store
	Pool     *pgxpool.Pool
}

func NewChatGroupHandler(s *chatgroups.Store, n *notify.Notifier, perms *permissions.Store, pool *pgxpool.Pool) *ChatGroupHandler {
	return &ChatGroupHandler{Store: s, Notifier: n, Perms: perms, Pool: pool}
}

func (h *ChatGroupHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

// chatErr maps chatgroups' sentinel errors onto HTTP, mirroring chat.go's
// chatErr (see internal/chatgroups' sentinel doc comments for what each
// means).
func (h *ChatGroupHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, chatgroups.ErrNotMember):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a member of this group."})
	case errors.Is(err, chatgroups.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Group not found."})
	case errors.Is(err, chatgroups.ErrAlreadyDecided):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This request has already been decided."})
	case errors.Is(err, chatgroups.ErrInvalidInput):
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// parseGroupPageParams reads after_id/limit query params, both optional —
// zero values fall back to chatgroups' own defaults.
func parseGroupPageParams(c *gin.Context) (afterID int64, limit int) {
	afterID, _ = strconv.ParseInt(c.Query("after_id"), 10, 64)
	limit, _ = strconv.Atoi(c.Query("limit"))
	return afterID, limit
}

// GET /api/chat-groups
func (h *ChatGroupHandler) List(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListGroupsForUser(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/chat-groups/:id/messages
func (h *ChatGroupHandler) Messages(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	// An ARCHIVED group is treated as gone for a participant, same rule as
	// the donor↔owner chat (see refuseIfArchivedForParticipant's own doc
	// comment for why this is 404, not 403).
	if refuseIfArchivedForParticipant(c, h.Pool, chatlifecycle.KindGroup, id) {
		return
	}
	afterID, limit := parseGroupPageParams(c)
	items, err := h.Store.ListMessagesForMember(c.Request.Context(), id, user.UserID, afterID, limit)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, mergeChatLifecycle(c, h.Pool, chatlifecycle.KindGroup, id, gin.H{
		"success": true,
		"items":   items,
	}))
}

type chatGroupMessageReq struct {
	Body string `json:"body"`
}

// POST /api/chat-groups/:id/messages
func (h *ChatGroupHandler) PostMessage(c *gin.Context) {
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
	// A PAUSED or ENDED group refuses new messages, server-side — same rule
	// as every other chat system (chat_lifecycle_gate.go).
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
	msgID, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, req.Body)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	h.notifyGroupMembers(group, user.UserID, req.Body)
	c.JSON(http.StatusOK, gin.H{"success": true, "message_id": msgID})
}

type chatGroupReadReq struct {
	LastReadMsgID int64 `json:"last_read_msg_id"`
}

// POST /api/chat-groups/:id/read
func (h *ChatGroupHandler) MarkRead(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	var req chatGroupReadReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}
	if err := h.Store.MarkRead(c.Request.Context(), id, user.UserID, req.LastReadMsgID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// groupSenderLabel resolves how senderUserID's messages appear to everyone
// else in group: a masked group shows their own masked_label, or "Support"
// if their role is staff or they have no member row at all (e.g. a staff
// reply via PostMessageAsStaff, Task 8) — the same resolution
// ListMessagesForMember applies at read time, kept consistent rather than
// re-derived differently. A team group shows their real name.
func (h *ChatGroupHandler) groupSenderLabel(ctx context.Context, group chatgroups.GroupDetail, senderUserID int64) string {
	if group.Kind == chatgroups.KindTeam {
		var name string
		_ = h.Pool.QueryRow(ctx, `SELECT full_name FROM user_profiles WHERE user_id = $1`, senderUserID).Scan(&name)
		if strings.TrimSpace(name) == "" {
			return "Member"
		}
		return name
	}
	for _, m := range group.Members {
		if m.UserID == senderUserID {
			if m.RoleInGroup == "staff" {
				return "Support"
			}
			if m.MaskedLabel != "" {
				return m.MaskedLabel
			}
		}
	}
	return "Support"
}

// notifyGroupMembers fans a push out to every OTHER active member of group,
// masked or real depending on group.Kind. Fire-and-forget, matching
// chat.go's bg()/goroutine pattern. The sender's own label is resolved ONCE
// — it depends only on who sent the message, never on who is reading it, so
// there is nothing to batch per recipient (see the design spec §6 for why
// this replaced an earlier, unnecessary per-recipient-label design).
func (h *ChatGroupHandler) notifyGroupMembers(group chatgroups.GroupDetail, senderUserID int64, body string) {
	preview := body
	if r := []rune(preview); len(r) > 80 {
		preview = string(r[:80]) + "…"
	}
	label := h.groupSenderLabel(context.Background(), group, senderUserID)
	for _, m := range group.Members {
		if m.UserID == senderUserID || m.RemovedAt != nil {
			continue
		}
		recipient := m.UserID
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			var msg notify.LocalizedMessage
			if group.Kind == chatgroups.KindMasked {
				msg = notify.GroupMaskedNewMessageMsg(label, preview, group.ID)
			} else {
				msg = notify.ChatNewMessageMsg(label, preview, group.ID)
			}
			_, _ = h.Notifier.Send(ctx, recipient, msg)
		}()
	}
}
