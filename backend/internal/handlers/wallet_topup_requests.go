package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// Wallet top-up REQUESTS (R2 #67). A user asks for money to be added; nothing
// changes in their wallet until staff approve the request in the dashboard.

type topUpRequestBody struct {
	AmountIQD     int64  `json:"amount_iqd"`
	PaymentMethod string `json:"payment_method"`
	Note          string `json:"note"`
	ProofPath     string `json:"proof_path"`
}

// POST /api/wallet/topup-requests — the signed-in user asks for a top-up.
func (h *WalletHandler) CreateTopUpRequest(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	var req topUpRequestBody
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	if strings.TrimSpace(req.PaymentMethod) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Choose the payment method you used."})
		return
	}
	var proof *string
	if p := strings.TrimSpace(req.ProofPath); p != "" {
		proof = &p
	}
	id, err := h.Wallet.CreateTopUpRequest(c.Request.Context(), user.UserID, req.AmountIQD, req.PaymentMethod, req.Note, proof)
	switch {
	case errors.Is(err, wallet.ErrInvalidTopUpInput):
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Enter a valid amount."})
		return
	case errors.Is(err, wallet.ErrTooManyPending):
		c.JSON(http.StatusConflict, gin.H{"status": "error", "code": "too_many_pending",
			"error": "You already have several requests waiting for approval."})
		return
	case err != nil:
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to save the request."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "id": id, "request_status": "pending"})
}

// GET /api/wallet/topup-requests — the user's own requests, newest first.
func (h *WalletHandler) ListMyTopUpRequests(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	items, err := h.Wallet.ListTopUpRequestsForUser(c.Request.Context(), user.UserID, 50)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to load your requests."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "items": items})
}

// GET /api/admin/wallet/topup-requests?status= — staff queue.
func (h *WalletHandler) AdminListTopUpRequests(c *gin.Context) {
	status := strings.TrimSpace(c.Query("status"))
	if status == "all" {
		status = ""
	}
	items, err := h.Wallet.AdminListTopUpRequests(c.Request.Context(), status, 200)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items, "total_items": len(items)})
}

type topUpDecisionBody struct {
	Reason string `json:"reason"`
}

// POST /api/admin/wallet/topup-requests/:id/approve|reject
func (h *WalletHandler) AdminDecideTopUpRequest(approve bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil || id <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request id."})
			return
		}
		var body topUpDecisionBody
		_ = c.ShouldBindJSON(&body)
		admin, _ := auth.UserFromGin(c)
		var adminID int64
		if admin != nil {
			adminID = admin.UserID
		}
		req, newBalance, err := h.Wallet.DecideTopUpRequest(c.Request.Context(), id, adminID, approve, body.Reason)
		switch {
		case errors.Is(err, wallet.ErrRequestNotFound):
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Request not found."})
			return
		case errors.Is(err, wallet.ErrAlreadyDecided):
			c.JSON(http.StatusConflict, gin.H{"success": false, "code": "already_decided",
				"error": "This request was already decided."})
			return
		case err != nil:
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Unable to save the decision."})
			return
		}
		if approve {
			// Same attributed audit entry as an admin crediting a wallet by hand.
			h.logWalletTopUp(c, req.UserID, req.AmountIQD, newBalance)
		}
		if h.Notifier != nil {
			uid, amt, bal := req.UserID, req.AmountIQD, newBalance
			go func() {
				bg, cancel := context.WithTimeout(context.Background(), 15*time.Second)
				defer cancel()
				msg := notify.WalletTopUpRejectedMsg(amt)
				if approve {
					msg = notify.WalletToppedUpMsg(amt, bal)
				}
				if _, err := h.Notifier.Send(bg, uid, msg); err != nil {
					log.Printf("[notify] wallet top-up decision alert failed: %v", err)
				}
			}()
		}
		c.JSON(http.StatusOK, gin.H{"success": true, "status": req.Status, "balance_iqd": newBalance})
	}
}
