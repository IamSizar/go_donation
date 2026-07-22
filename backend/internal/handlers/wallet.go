package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// WalletHandler — Note #42, "Financial Wallet" (test phase). A stored IQD
// balance per real user; the only way to add funds right now is an admin
// crediting the user from the dashboard (AdminTopUp) — there is no
// payment-gateway top-up flow yet. The balance is then spendable via the
// donation/marketplace handlers' "app_wallet" payment method.
type WalletHandler struct {
	Wallet   *wallet.Store
	Notifier *notify.Notifier
}

func NewWalletHandler(w *wallet.Store, n *notify.Notifier) *WalletHandler {
	return &WalletHandler{Wallet: w, Notifier: n}
}

// GET /api/wallet — the current user's balance. Always 0 for a guest (never
// credited, and the frontend doesn't surface a wallet card for guests
// anyway — Note #40's browsing-only scope).
func (h *WalletHandler) GetBalance(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	balance, err := h.Wallet.GetBalance(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to load wallet balance."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status":      "success",
		"balance_iqd": balance,
		"currency":    "IQD",
	})
}

// GET /api/wallet/transactions — the current user's own ledger, newest first.
func (h *WalletHandler) ListTransactions(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	page, _ := strconv.Atoi(c.Query("page"))
	perPage, _ := strconv.Atoi(c.Query("per_page"))
	txs, err := h.Wallet.ListTransactions(c.Request.Context(), user.UserID, page, perPage)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to load wallet history."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "transactions": txs})
}

type adminWalletTopUpReq struct {
	AmountIQD int64  `json:"amount_iqd"`
	Note      string `json:"note"`
}

// POST /api/admin/users/:id/wallet/topup — body {amount_iqd, note}. Credits
// the target user's wallet and sends them a notification. Admin-gated by the
// same "users"/"edit" permission as the other per-user admin actions.
func (h *WalletHandler) AdminTopUp(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || targetID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid user id."})
		return
	}
	var req adminWalletTopUpReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	if req.AmountIQD <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "amount_iqd must be a positive whole number."})
		return
	}

	admin, _ := auth.UserFromGin(c)
	var adminID int64
	if admin != nil {
		adminID = admin.UserID
	}

	newBalance, err := h.Wallet.TopUp(c.Request.Context(), targetID, req.AmountIQD, adminID, req.Note)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to top up wallet."})
		return
	}

	if h.Notifier != nil {
		amount, balance := req.AmountIQD, newBalance
		go func() {
			bg, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			if _, err := h.Notifier.Send(bg, targetID, notify.WalletToppedUpMsg(amount, balance)); err != nil {
				log.Printf("[notify] wallet topup alert failed: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"status":      "success",
		"user_id":     targetID,
		"balance_iqd": newBalance,
	})
}
