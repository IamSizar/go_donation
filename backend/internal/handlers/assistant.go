package handlers

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/assistant"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// AssistantHandler exposes the in-app AI Support Assistant (Phase 29).
type AssistantHandler struct {
	Svc  *assistant.Service
	Pool *pgxpool.Pool
}

func NewAssistantHandler(svc *assistant.Service, pool *pgxpool.Pool) *AssistantHandler {
	return &AssistantHandler{Svc: svc, Pool: pool}
}

type assistantChatRequest struct {
	Messages []assistant.Message `json:"messages"`
	// Message is a convenience for single-shot callers that don't track history.
	Message string `json:"message"`
	// Lang is the app locale code ("en", "ar", "ckb", "kmr"). Tells the
	// assistant which language to reply in. Defaults to "en" when absent.
	Lang string `json:"lang"`
	// IntentID is the stable chip id (e.g. "d_donate") for chip taps.
	// Allows the local fallback to resolve an intent without keyword matching.
	IntentID string `json:"intent_id"`
}

// Chat answers a conversation turn for the authenticated user.
//
// POST /api/assistant/chat
//
//	{ "messages": [ {"role":"user","content":"how do I donate?"} ] }
//
// Response:
//
//	{ "success": true, "reply": "...", "action": {"label":"...","route":"donate"}, "source": "ai" }
func (h *AssistantHandler) Chat(c *gin.Context) {
	user, _ := auth.UserFromGin(c)

	var req assistantChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request body."})
		return
	}

	history := req.Messages
	// Accept a bare {message:"..."} too.
	if len(history) == 0 && strings.TrimSpace(req.Message) != "" {
		history = []assistant.Message{{Role: "user", Content: req.Message}}
	}
	if len(history) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Provide a message."})
		return
	}

	roleID := 1
	userName := ""
	if user != nil {
		roleID = user.RoleID
		userName = h.fullName(user.UserID)
	}

	lang := strings.TrimSpace(req.Lang)
	if lang == "" {
		lang = "en"
	}
	intentID := strings.TrimSpace(req.IntentID)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 35*time.Second)
	defer cancel()

	reply := h.Svc.Answer(ctx, roleID, userName, history, lang, intentID)

	resp := gin.H{
		"success": true,
		"reply":   reply.Text,
		"source":  reply.Source,
	}
	if reply.Action != nil {
		resp["action"] = gin.H{
			"label": reply.Action.Label,
			"route": string(reply.Action.Route),
		}
	}
	c.JSON(http.StatusOK, resp)
}

func (h *AssistantHandler) fullName(userID int64) string {
	if h.Pool == nil {
		return ""
	}
	var name *string
	_ = h.Pool.QueryRow(context.Background(),
		`SELECT full_name FROM user_profiles WHERE user_id = $1`, userID).Scan(&name)
	if name != nil {
		return strings.TrimSpace(*name)
	}
	return ""
}
