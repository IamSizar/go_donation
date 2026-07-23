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
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/wallet"
)

// Client note — Marriage "Subscription": a real, admin-manageable package
// list (replacing the old fixed 5-tier + admin-settings-price mechanism)
// plus a real purchase flow — wallet payments activate instantly, cash/bank
// payments stay pending until staff confirms them (same shape as donations'
// payment_status).

// GetSubscriptionPackages — GET /api/marriage/subscription-packages (public,
// active only).
func (h *MarriageHandler) GetSubscriptionPackages(c *gin.Context) {
	items, err := h.Store.ListPackages(c.Request.Context(), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

type subscriptionPurchaseReq struct {
	PaymentMethod string `json:"payment_method"`
}

// PurchaseSubscription — POST /api/marriage/subscription-packages/:id/purchase
// — body {payment_method}. The caller must already have their own marriage
// profile (subscription tiers live on a profile, not a bare account).
func (h *MarriageHandler) PurchaseSubscription(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	pkgID, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || pkgID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid package id."})
		return
	}
	var req subscriptionPurchaseReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request body."})
		return
	}
	paymentMethod := strings.TrimSpace(req.PaymentMethod)
	if paymentMethod == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "payment_method is required."})
		return
	}

	ctx := c.Request.Context()
	pkg, err := h.Store.GetPackage(ctx, pkgID)
	if err != nil || !pkg.Active {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Package not found."})
		return
	}

	profiles, err := h.Store.List(ctx, marriage.SearchFilters{Status: "all", OwnedByUser: user.UserID, Limit: 1})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if len(profiles) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Submit a marriage profile before subscribing."})
		return
	}
	profileID := profiles[0].ID

	if paymentMethod == "app_wallet" {
		if h.Wallet == nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Wallet unavailable."})
			return
		}
		if pkg.PriceIQD > 0 {
			if err := h.Wallet.Debit(ctx, user.UserID, pkg.PriceIQD, "purchase",
				"marriage_subscription_purchases", 0, "Marriage subscription: "+pkg.NameEn); err != nil {
				if errors.Is(err, wallet.ErrInsufficientBalance) {
					c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Insufficient wallet balance."})
					return
				}
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Unable to debit wallet."})
				return
			}
		}
		purchaseID, err := h.Store.CreatePaidPurchase(ctx, profileID, user.UserID, pkg.ID, pkg.PriceIQD, paymentMethod, pkg.Slug)
		if err != nil {
			// The debit succeeded but activating the purchase failed — refund so
			// the user isn't charged for nothing (same debit-then-refund-on-
			// failure pattern used by donations/marketplace's wallet payments).
			if pkg.PriceIQD > 0 {
				_, _ = h.Wallet.Refund(ctx, user.UserID, pkg.PriceIQD, "marriage_subscription_purchases", 0,
					"Refund: marriage subscription purchase failed")
			}
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Unable to complete purchase."})
			return
		}
		h.notifySubscriptionInBackground(user.UserID, notify.MarriageSubscriptionActivatedMsg(pkg.NameEn))
		c.JSON(http.StatusOK, gin.H{"success": true, "id": purchaseID, "status": "paid"})
		return
	}

	// Cash/bank — stays pending until staff confirms the payment arrived.
	purchaseID, err := h.Store.CreatePendingPurchase(ctx, profileID, user.UserID, pkg.ID, pkg.PriceIQD, paymentMethod)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Unable to record purchase."})
		return
	}
	h.notifySubscriptionInBackground(user.UserID, notify.MarriageSubscriptionPendingMsg(pkg.NameEn))
	h.notifyStaffInBackground(notify.NewMarriageSubscriptionPendingAdminMsg(pkg.NameEn, purchaseID))
	c.JSON(http.StatusOK, gin.H{"success": true, "id": purchaseID, "status": "pending"})
}

func (h *MarriageHandler) notifySubscriptionInBackground(userID int64, m notify.LocalizedMessage) {
	if h.Notifier == nil {
		return
	}
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if _, err := h.Notifier.Send(bg, userID, m); err != nil {
			log.Printf("[notify] marriage subscription alert failed: %v", err)
		}
	}()
}

// ============================================================
// Admin: package CRUD (mirrors payment methods' shape exactly).
// ============================================================

// AdminListSubscriptionPackages — GET /api/admin/marriage/subscription-packages
// (all, including inactive, so they can be reactivated).
func (h *MarriageHandler) AdminListSubscriptionPackages(c *gin.Context) {
	items, err := h.Store.ListPackages(c.Request.Context(), false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func packageFromBody(c *gin.Context) (marriage.SubscriptionPackage, bool) {
	var body marriage.SubscriptionPackage
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return body, false
	}
	return body, true
}

// AdminAddSubscriptionPackage — POST /api/admin/marriage/subscription-packages.
func (h *MarriageHandler) AdminAddSubscriptionPackage(c *gin.Context) {
	body, ok := packageFromBody(c)
	if !ok {
		return
	}
	id, err := h.Store.AddPackage(c.Request.Context(), body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

// AdminUpdateSubscriptionPackage — PATCH /api/admin/marriage/subscription-packages/:id.
func (h *MarriageHandler) AdminUpdateSubscriptionPackage(c *gin.Context) {
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid package id."})
		return
	}
	body, ok := packageFromBody(c)
	if !ok {
		return
	}
	if err := h.Store.UpdatePackage(c.Request.Context(), id, body); err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, marriage.ErrPackageNotFound) {
			status = http.StatusNotFound
		}
		c.JSON(status, gin.H{"success": false, "error": "Unable to update package."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id})
}

type reorderReq struct {
	IDs []int64 `json:"ids"`
}

// AdminReorderSubscriptionPackages — POST /api/admin/marriage/subscription-packages/reorder.
func (h *MarriageHandler) AdminReorderSubscriptionPackages(c *gin.Context) {
	var req reorderReq
	if err := c.ShouldBindJSON(&req); err != nil || len(req.IDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid request body."})
		return
	}
	if err := h.Store.ReorderPackages(c.Request.Context(), req.IDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Unable to reorder packages."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// AdminDeleteSubscriptionPackage — DELETE /api/admin/marriage/subscription-packages/:id.
func (h *MarriageHandler) AdminDeleteSubscriptionPackage(c *gin.Context) {
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid package id."})
		return
	}
	if err := h.Store.DeletePackage(c.Request.Context(), id); err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, marriage.ErrPackageNotFound) {
			status = http.StatusNotFound
		}
		c.JSON(status, gin.H{"success": false, "error": "Unable to delete package."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ============================================================
// Admin: purchase confirmation queue (cash/bank payments).
// ============================================================

// AdminListSubscriptionPurchases — GET /api/admin/marriage/subscription-purchases
// (optionally ?status=pending).
func (h *MarriageHandler) AdminListSubscriptionPurchases(c *gin.Context) {
	items, err := h.Store.ListPurchases(c.Request.Context(), strings.TrimSpace(c.Query("status")))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminConfirmSubscriptionPurchase — POST /api/admin/marriage/subscription-purchases/:id/confirm
// — staff confirms a cash/bank payment actually arrived; activates the tier.
func (h *MarriageHandler) AdminConfirmSubscriptionPurchase(c *gin.Context) {
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid purchase id."})
		return
	}
	userID, packageName, err := h.Store.ConfirmPurchase(c.Request.Context(), id)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, marriage.ErrPurchaseNotFound) || errors.Is(err, marriage.ErrPackageNotFound) {
			status = http.StatusNotFound
		}
		c.JSON(status, gin.H{"success": false, "error": err.Error()})
		return
	}
	h.notifySubscriptionInBackground(userID, notify.MarriageSubscriptionActivatedMsg(packageName))
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// AdminRejectSubscriptionPurchase — POST /api/admin/marriage/subscription-purchases/:id/reject
// — staff marks a pending purchase as never-paid (e.g. cash never arrived).
func (h *MarriageHandler) AdminRejectSubscriptionPurchase(c *gin.Context) {
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid purchase id."})
		return
	}
	userID, err := h.Store.RejectPurchase(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Purchase not found or already resolved."})
		return
	}
	h.notifySubscriptionInBackground(userID, notify.MarriageSubscriptionRejectedMsg())
	c.JSON(http.StatusOK, gin.H{"success": true})
}
