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
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// MarriageChatHandler exposes Note #35's staff-mediated Marriage chat: the
// admin meeting-requests inbox (approve/decline) and the resulting chat
// threads, both mobile-facing (identity-masked) and admin-facing (full
// oversight).
type MarriageChatHandler struct {
	Store    *marriagechat.Store
	Notifier *notify.Notifier
	Pool     *pgxpool.Pool
}

func NewMarriageChatHandler(s *marriagechat.Store, n *notify.Notifier, pool *pgxpool.Pool) *MarriageChatHandler {
	return &MarriageChatHandler{Store: s, Notifier: n, Pool: pool}
}

func (h *MarriageChatHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

func (h *MarriageChatHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, marriagechat.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
	case errors.Is(err, marriagechat.ErrNotParty):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
	case errors.Is(err, marriagechat.ErrNotOwner):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Only the profile owner can accept or decline."})
	case errors.Is(err, marriagechat.ErrNotActive):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is not active yet."})
	case errors.Is(err, marriagechat.ErrRequestGone):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This request was already decided."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// ===== Admin: meeting requests inbox =====

// GET /api/admin/marriage/meeting-requests
func (h *MarriageChatHandler) AdminListMeetingRequests(c *gin.Context) {
	items, err := h.Store.ListMeetingRequests(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/admin/marriage/meeting-requests/:id/approve — opens the chat
// thread and notifies the profile owner they must accept it.
func (h *MarriageChatHandler) AdminApproveMeetingRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, ownerID, err := h.Store.ApproveMeetingRequest(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	tid := thread.ID
	go func() {
		ctx, cancel := h.bg()
		defer cancel()
		_, _ = h.Notifier.Send(ctx, ownerID, notify.MarriageChatRequestMsg(tid))
	}()
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID, "status": thread.Status})
}

// POST /api/admin/marriage/meeting-requests/:id/decline
func (h *MarriageChatHandler) AdminDeclineMeetingRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	fromUserID, err := h.Store.DeclineMeetingRequest(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	go func() {
		ctx, cancel := h.bg()
		defer cancel()
		_, _ = h.Notifier.Send(ctx, fromUserID, notify.MarriageMeetingDeclinedMsg())
	}()
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ===== Mobile: chat threads (identity-masked) =====

// GET /api/marriage/chats — my threads.
func (h *MarriageChatHandler) List(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
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

// POST /api/marriage/chats/:id/accept — profile owner only.
func (h *MarriageChatHandler) Accept(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.AcceptThread(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	tid := thread.ID
	requesterID := thread.RequesterUserID
	go func() {
		ctx, cancel := h.bg()
		defer cancel()
		_, _ = h.Notifier.Send(ctx, requesterID, notify.MarriageChatAcceptedMsg(tid))
	}()
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID, "status": thread.Status})
}

// POST /api/marriage/chats/:id/decline — profile owner only.
func (h *MarriageChatHandler) Decline(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.DeclineThread(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID, "status": thread.Status})
}

// GET /api/marriage/chats/:id/messages — participant only, identity-masked.
func (h *MarriageChatHandler) Messages(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
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
	msgs, err := h.Store.ListMessages(c.Request.Context(), id, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	_ = h.Store.MarkRead(c.Request.Context(), id, user.UserID)
	c.JSON(http.StatusOK, gin.H{"success": true, "status": thread.Status, "items": msgs})
}

type marriageChatMessageReq struct {
	Body string `json:"body"`
}

// POST /api/marriage/chats/:id/messages — participant, active thread only.
func (h *MarriageChatHandler) PostMessage(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
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
	if thread.Status != "active" {
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is not active yet."})
		return
	}
	var req marriageChatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, msgID, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, thread.RoleFor(user.UserID), req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	for _, other := range thread.CounterpartIDs(user.UserID) {
		oid := other
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.MarriageChatNewMessageMsg(msgID))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}

// ===== Admin: chat oversight (full identities) =====

// GET /api/admin/marriage/chats
func (h *MarriageChatHandler) AdminList(c *gin.Context) {
	items, err := h.Store.ListAllThreads(c.Request.Context(), c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/marriage/chats/:id/messages
func (h *MarriageChatHandler) AdminMessages(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.GetThread(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	msgs, err := h.Store.AdminListMessages(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "status": thread.Status, "items": msgs})
}

// POST /api/admin/marriage/chats/:id/messages — admin relays as staff.
func (h *MarriageChatHandler) AdminPostMessage(c *gin.Context) {
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
	if thread.Status != "active" {
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is not active yet."})
		return
	}
	var req marriageChatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, msgID, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, marriagechat.RoleStaff, req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	for _, uid := range []int64{thread.RequesterUserID, thread.OwnerUserID} {
		oid := uid
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.MarriageChatNewMessageMsg(msgID))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}
