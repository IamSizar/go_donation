package handlers

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/staffchat"
)

// StaffChatHandler exposes Note #36's internal "Operational Administrative
// Chat" — direct messaging between any two dashboard accounts (Manager ↔
// Staff Member, or any other staff pair). Every route requires a valid
// dashboard session (the `admin` route group already enforces that) but is
// deliberately NOT gated by a business-module permission — every staff
// account, regardless of assigned permissions, can use internal chat.
type StaffChatHandler struct {
	Store    *staffchat.Store
	Notifier *notify.Notifier
	Pool     *pgxpool.Pool
}

func NewStaffChatHandler(s *staffchat.Store, n *notify.Notifier, pool *pgxpool.Pool) *StaffChatHandler {
	return &StaffChatHandler{Store: s, Notifier: n, Pool: pool}
}

func (h *StaffChatHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

func (h *StaffChatHandler) fullName(userID int64) string {
	var name *string
	_ = h.Pool.QueryRow(context.Background(),
		`SELECT full_name FROM user_profiles WHERE user_id = $1`, userID).Scan(&name)
	if name != nil {
		return strings.TrimSpace(*name)
	}
	return ""
}

func (h *StaffChatHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, staffchat.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
	case errors.Is(err, staffchat.ErrNotParty):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
	case errors.Is(err, staffchat.ErrSelf):
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "You cannot message yourself."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// GET /api/admin/staff-directory — every other dashboard account, to start a new chat.
func (h *StaffChatHandler) Directory(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.Directory(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/staff-chats — my threads.
func (h *StaffChatHandler) List(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListThreadsForUser(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

type staffChatStartReq struct {
	UserID int64 `json:"user_id"`
}

// POST /api/admin/staff-chats/start — get-or-create a thread with another staff member.
func (h *StaffChatHandler) Start(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req staffChatStartReq
	if err := c.ShouldBindJSON(&req); err != nil || req.UserID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "user_id is required."})
		return
	}
	thread, err := h.Store.GetOrCreateThread(c.Request.Context(), user.UserID, req.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID})
}

// GET /api/admin/staff-chats/:id/messages
func (h *StaffChatHandler) Messages(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.GetThread(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	if !thread.IsParticipant(user.UserID) {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
		return
	}
	msgs, err := h.Store.ListMessages(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	_ = h.Store.MarkRead(c.Request.Context(), id, user.UserID)
	c.JSON(http.StatusOK, gin.H{"success": true, "items": msgs})
}

type staffChatMessageReq struct {
	Body string `json:"body"`
}

// POST /api/admin/staff-chats/:id/messages
func (h *StaffChatHandler) PostMessage(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.GetThread(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	if !thread.IsParticipant(user.UserID) {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
		return
	}
	var req staffChatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	other := thread.OtherUserID(user.UserID)
	preview := msg.Body
	if len([]rune(preview)) > 80 {
		preview = string([]rune(preview)[:80]) + "…"
	}
	name := h.fullName(user.UserID)
	go func() {
		ctx, cancel := h.bg()
		defer cancel()
		_, _ = h.Notifier.Send(ctx, other, notify.StaffChatNewMessageMsg(name, preview, id))
	}()
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}
