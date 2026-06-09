package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/marketplace"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// MarketplaceHandler ports percentage/api/marketplace/index.php.
type MarketplaceHandler struct {
	Store    *marketplace.Store
	Notifier *notify.Notifier
}

func NewMarketplaceHandler(s *marketplace.Store, n *notify.Notifier) *MarketplaceHandler {
	return &MarketplaceHandler{Store: s, Notifier: n}
}

// GET /api/marketplace
//   - no params (or ?view=products) → public list of approved products
//   - ?view=orders&user_id=N (or ?orders=1&user_id=N) → user's own orders (Bearer required, must match)
func (h *MarketplaceHandler) Get(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	limit, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("limit", "20")))

	view := strings.TrimSpace(c.Query("view"))
	ordersFlag := strings.TrimSpace(c.Query("orders"))
	wantOrders := view == "orders" || ordersFlag == "1"

	if wantOrders {
		uidStr := strings.TrimSpace(c.Query("user_id"))
		if uidStr == "" {
			uidStr = strings.TrimSpace(c.Query("buyer_user_id"))
		}
		uid, err := strconv.ParseInt(uidStr, 10, 64)
		if err != nil || uid <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing user_id."})
			return
		}
		tokenUser, _ := auth.UserFromGin(c)
		if tokenUser == nil || tokenUser.UserID != uid {
			c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request. Please sign in again."})
			return
		}
		items, err := h.Store.ListOrdersForUser(c.Request.Context(), uid, page, limit)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
			return
		}
		hasMore := len(items) >= effectiveLimit(limit)
		c.JSON(http.StatusOK, gin.H{
			"success":  true,
			"items":    items,
			"page":     normalizePage(page),
			"has_more": hasMore,
		})
		return
	}

	items, err := h.Store.ListProducts(c.Request.Context(), page, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	hasMore := len(items) >= effectiveLimit(limit)
	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"items":    items,
		"page":     normalizePage(page),
		"has_more": hasMore,
	})
}

// POST /api/marketplace
// Bearer required; buyer_user_id (or user_id) must match token; role must be 1.
// Body: product_id, quantity (default 1), buyer_note (optional). JSON or form.
func (h *MarketplaceHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	data := collectBody(c)
	buyerID := int64(asInt(data["buyer_user_id"]))
	if buyerID == 0 {
		buyerID = int64(asInt(data["user_id"]))
	}
	if buyerID <= 0 || buyerID != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request. Please sign in again."})
		return
	}
	if tokenUser.RoleID != 1 {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "This action is not available for your role."})
		return
	}

	productID := int64(asInt(data["product_id"]))
	if productID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing product_id."})
		return
	}
	qty := asInt(data["quantity"])
	if qty < 1 {
		qty = 1
	}
	note := strings.TrimSpace(firstNonEmpty(asStr(data["buyer_note"]), asStr(data["note"])))

	id, result, stockLeft, err := h.Store.CreateOrder(c.Request.Context(), buyerID, productID, qty, note)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	switch result {
	case marketplace.OrderProductNotFound:
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Product not found or not approved."})
		return
	case marketplace.OrderOutOfStock:
		c.JSON(http.StatusConflict, gin.H{
			"success": false,
			"error":   "Only " + strconv.Itoa(stockLeft) + " available.",
		})
		return
	}

	// Phase 18 — centralised 4-language template.
	_, _ = h.Notifier.Send(c.Request.Context(), buyerID,
		notify.MarketplaceOrderSubmittedMsg(id))
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"id":      id,
		"status":  "pending",
	})
}

// GET /api/admin/marketplace/products?page=&per_page=&status=
func (h *MarketplaceHandler) AdminProducts(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	status := strings.TrimSpace(c.Query("status"))
	if strings.EqualFold(status, "all") {
		status = ""
	}
	res, err := h.Store.AdminListProducts(c.Request.Context(), page, perPage, status, c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"items":       res.Items,
		"page":        res.Page,
		"per_page":    res.PerPage,
		"total_items": res.TotalItems,
		"total_pages": res.TotalPages,
		"has_more":    res.HasMore,
	})
}

// GET /api/admin/marketplace/orders?page=&per_page=&status=
func (h *MarketplaceHandler) AdminOrders(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "20")))
	status := strings.TrimSpace(c.Query("status"))
	if strings.EqualFold(status, "all") {
		status = ""
	}
	res, err := h.Store.AdminListOrders(c.Request.Context(), page, perPage, status, c.Query("q"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"items":       res.Items,
		"page":        res.Page,
		"per_page":    res.PerPage,
		"total_items": res.TotalItems,
		"total_pages": res.TotalPages,
		"has_more":    res.HasMore,
	})
}

// normalizePage clamps page to >= 1 (handlers may receive 0 from defaulting).
func normalizePage(p int) int {
	if p < 1 {
		return 1
	}
	return p
}

func effectiveLimit(l int) int {
	if l <= 0 || l > 100 {
		return 20
	}
	return l
}
