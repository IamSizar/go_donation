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
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// ChatHandler exposes the donor ↔ campaign-owner chat endpoints (Phase 28).
type ChatHandler struct {
	Store    *chat.Store
	Notifier *notify.Notifier
	Pool     *pgxpool.Pool
}

func NewChatHandler(s *chat.Store, n *notify.Notifier, pool *pgxpool.Pool) *ChatHandler {
	return &ChatHandler{Store: s, Notifier: n, Pool: pool}
}

func (h *ChatHandler) bg() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

func (h *ChatHandler) fullName(userID int64) string {
	var name *string
	_ = h.Pool.QueryRow(context.Background(),
		`SELECT full_name FROM user_profiles WHERE user_id = $1`, userID).Scan(&name)
	if name != nil {
		return strings.TrimSpace(*name)
	}
	return ""
}

func (h *ChatHandler) campaignTitle(campaignID *int64) string {
	if campaignID == nil {
		return "your campaign"
	}
	var title string
	if err := h.Pool.QueryRow(context.Background(),
		`SELECT title FROM campaigns WHERE id = $1`, *campaignID).Scan(&title); err != nil || title == "" {
		return "your campaign"
	}
	return title
}

// ===== Mobile endpoints =====

type chatRequestReq struct {
	DonationID  int64 `json:"donation_id"`
	CampaignID  int64 `json:"campaign_id"`
	DonorUserID int64 `json:"donor_user_id"`
}

// POST /api/chats/request
// Two entry styles:
//   • Donor, from a donation's detail:  { "donation_id": N }
//   • Owner, from campaign-donations:   { "donor_user_id": N, "campaign_id": M }
func (h *ChatHandler) Request(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req chatRequestReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}

	var donorID, ownerID int64
	var campaignID *int64

	switch {
	case req.DonationID > 0:
		var dUser int64
		var cID *int64
		err := h.Pool.QueryRow(c.Request.Context(),
			`SELECT user_id, campaign_id FROM donations WHERE id = $1`, req.DonationID,
		).Scan(&dUser, &cID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Donation not found."})
			return
		}
		if cID == nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "This donation is not tied to a campaign."})
			return
		}
		var owner *int64
		_ = h.Pool.QueryRow(c.Request.Context(),
			`SELECT owner_user_id FROM campaigns WHERE id = $1`, *cID).Scan(&owner)
		if owner == nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "This campaign has no owner to chat with."})
			return
		}
		donorID, ownerID, campaignID = dUser, *owner, cID

	case req.DonorUserID > 0 && req.CampaignID > 0:
		var owner *int64
		_ = h.Pool.QueryRow(c.Request.Context(),
			`SELECT owner_user_id FROM campaigns WHERE id = $1`, req.CampaignID).Scan(&owner)
		if owner == nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Campaign has no owner."})
			return
		}
		cid := req.CampaignID
		donorID, ownerID, campaignID = req.DonorUserID, *owner, &cid

	default:
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Provide donation_id, or donor_user_id + campaign_id."})
		return
	}

	if donorID == ownerID {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "You cannot start a chat with yourself."})
		return
	}
	if user.UserID != donorID && user.UserID != ownerID {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not part of this donation."})
		return
	}
	// Owner-initiated: confirm the donor actually donated to one of the owner's
	// campaigns (stops an owner chatting arbitrary users).
	if req.DonationID == 0 {
		var exists bool
		_ = h.Pool.QueryRow(c.Request.Context(), `
			SELECT EXISTS(
			  SELECT 1 FROM donations d JOIN campaigns c ON c.id = d.campaign_id
			   WHERE d.user_id = $1 AND c.owner_user_id = $2)`,
			donorID, ownerID,
		).Scan(&exists)
		if !exists {
			c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "That user has not donated to your campaigns."})
			return
		}
	}

	thread, recipient, isNew, err := h.Store.RequestThread(c.Request.Context(), donorID, ownerID, campaignID, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	if isNew {
		name := h.fullName(user.UserID)
		title := h.campaignTitle(campaignID)
		tid := thread.ID
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, recipient, notify.ChatRequestMsg(name, title, tid))
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"thread_id":   thread.ID,
		"status":      thread.Status,
		"already":     !isNew,
	})
}

// POST /api/chats/:id/accept
func (h *ChatHandler) Accept(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	thread, initiator, err := h.Store.AcceptThread(c.Request.Context(), id, user.UserID)
	if err != nil {
		h.chatErr(c, err)
		return
	}
	name := h.fullName(user.UserID)
	go func() {
		ctx, cancel := h.bg()
		defer cancel()
		_, _ = h.Notifier.Send(ctx, initiator, notify.ChatAcceptedMsg(name, thread.ID))
	}()
	c.JSON(http.StatusOK, gin.H{"success": true, "thread_id": thread.ID, "status": thread.Status})
}

// POST /api/chats/:id/decline
func (h *ChatHandler) Decline(c *gin.Context) {
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

// GET /api/chats — my threads
func (h *ChatHandler) List(c *gin.Context) {
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

// GET /api/chats/:id/messages — messages in a thread (participant only)
func (h *ChatHandler) Messages(c *gin.Context) {
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
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"status":  thread.Status,
		"items":   msgs,
	})
}

type chatMessageReq struct {
	Body string `json:"body"`
}

// POST /api/chats/:id/messages — send a message (participant, active thread)
func (h *ChatHandler) PostMessage(c *gin.Context) {
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
	var req chatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	msg, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, user.RoleID, req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	// Notify the other participant(s).
	name := h.fullName(user.UserID)
	preview := msg.Body
	if len([]rune(preview)) > 80 {
		preview = string([]rune(preview)[:80]) + "…"
	}
	for _, other := range thread.CounterpartIDs(user.UserID) {
		oid := other
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.ChatNewMessageMsg(name, preview, id))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}

func (h *ChatHandler) chatErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, chat.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
	case errors.Is(err, chat.ErrNotParty):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "You are not a participant in this chat."})
	case errors.Is(err, chat.ErrNotRecipient):
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Only the invited party can accept or decline."})
	case errors.Is(err, chat.ErrNotActive):
		c.JSON(http.StatusConflict, gin.H{"success": false, "error": "This chat is not active yet."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// ===== Admin endpoints =====

// GET /api/admin/chats — all threads
func (h *ChatHandler) AdminList(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Store.ListAllThreads(c.Request.Context(), c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// GET /api/admin/chats/:id/messages — view any thread's messages
func (h *ChatHandler) AdminMessages(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
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
	msgs, err := h.Store.ListMessages(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "status": thread.Status, "items": msgs})
}

// POST /api/admin/chats/:id/messages — admin replies as support
func (h *ChatHandler) AdminPostMessage(c *gin.Context) {
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
	var req chatMessageReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Message body is required."})
		return
	}
	// Admin posts as "support" (sender_role = RoleSupport).
	msg, err := h.Store.PostMessage(c.Request.Context(), id, user.UserID, chat.RoleSupport, req.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	// Notify BOTH the donor and owner that support replied.
	preview := msg.Body
	if len([]rune(preview)) > 80 {
		preview = string([]rune(preview)[:80]) + "…"
	}
	for _, uid := range []int64{thread.DonorUserID, thread.OwnerUserID} {
		oid := uid
		go func() {
			ctx, cancel := h.bg()
			defer cancel()
			_, _ = h.Notifier.Send(ctx, oid, notify.ChatNewMessageMsg("Support", preview, id))
		}()
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": msg})
}
