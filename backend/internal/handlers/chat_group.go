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
