package handlers

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// CaseVolunteerChatHandler exposes Note #36's Staff↔Volunteer↔Beneficiary
// chat, auto-opened once a signup is case-linked and approved (see
// casevolchat.EnsureThreadForSignup, called from AssignSignupCase and
// MissionSignup in admin_status.go).
type CaseVolunteerChatHandler struct {
	Store    *casevolchat.Store
	Notifier *notify.Notifier
}

func NewCaseVolunteerChatHandler(s *casevolchat.Store, n *notify.Notifier) *CaseVolunteerChatHandler {
	return &CaseVolunteerChatHandler{Store: s, Notifier: n}
}

func (h *CaseVolunteerChatHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

func (h *CaseVolunteerChatHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, casevolchat.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
	case errors.Is(err, casevolchat.ErrNotParty):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
	case errors.Is(err, casevolchat.ErrAlreadyClaimed):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is already claimed by another staff member."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// ===== Mobile (volunteer or beneficiary — real identities) =====

// GET /api/case-chats
func (h *CaseVolunteerChatHandler) List(c *gin.Context) {
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

// GET /api/case-chats/:id/messages
func (h *CaseVolunteerChatHandler) Messages(c *gin.Context) {
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
	msgs, err := h.Store.ListMessages(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	_ = h.Store.MarkRead(c.Request.Context(), id, user.UserID)
	c.JSON(http.StatusOK, gin.H{"success": true, "items": msgs})
}

type caseVolChatMessageReq struct {
	Body string `json:"body"`
}

// POST /api/case-chats/:id/messages
func (h *CaseVolunteerChatHandler) PostMessage(c *gin.Context) {
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
	var req caseVolChatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, thread.RoleFor(user.UserID), req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	preview := msg.Body
	if len([]rune(preview)) > 80 {
		preview = string([]rune(preview)[:80]) + "…"
	}
	for _, other := range thread.CounterpartIDs(user.UserID) {
		oid := other
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.CaseVolunteerChatNewMessageMsg(preview, id))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}

// ===== Admin =====

// GET /api/admin/case-chats
func (h *CaseVolunteerChatHandler) AdminList(c *gin.Context) {
	items, err := h.Store.ListAllThreads(c.Request.Context(), c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/case-chats/:id/messages
func (h *CaseVolunteerChatHandler) AdminMessages(c *gin.Context) {
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
	c.JSON(http.StatusOK, gin.H{"success": true, "id": thread.ID, "items": msgs})
}

// POST /api/admin/case-chats/:id/messages — admin relays as staff.
func (h *CaseVolunteerChatHandler) AdminPostMessage(c *gin.Context) {
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
	var req caseVolChatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, casevolchat.RoleStaff, req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	preview := msg.Body
	if len([]rune(preview)) > 80 {
		preview = string([]rune(preview)[:80]) + "…"
	}
	for _, uid := range []int64{thread.VolunteerUserID, thread.BeneficiaryUserID} {
		oid := uid
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.CaseVolunteerChatNewMessageMsg(preview, id))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}

// POST /api/admin/case-chats/:id/claim
func (h *CaseVolunteerChatHandler) AdminClaim(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.ClaimThread(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID, "assigned_staff_user_id": thread.AssignedStaffUserID})
}

// POST /api/admin/case-chats/:id/release
func (h *CaseVolunteerChatHandler) AdminRelease(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, err := h.Store.ReleaseThread(c.Request.Context(), id)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID})
}
