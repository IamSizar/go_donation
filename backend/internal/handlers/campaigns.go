package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/campaigns"
)

// CampaignsHandler ports percentage/api/campaigns/index.php.
// CSRF token enforcement is intentionally dropped — the mobile client uses
// Bearer auth, which is not vulnerable to CSRF the way cookie-auth is.
type CampaignsHandler struct {
	Store *campaigns.Store
}

func NewCampaignsHandler(s *campaigns.Store) *CampaignsHandler {
	return &CampaignsHandler{Store: s}
}

// GET /api/campaigns?page=N&per_page=M&status=...
//
// Phase 15 — reads from the `campaigns` table (was: beneficiary_project_requests).
// The `status` query param is now a visibility filter — see Store.List for the
// full contract.
//
//	status=""        (default) → donor-visible only (is_active=1)
//	status="approved"          → same as "" (back-compat with the old Flutter param)
//	status="all"               → every row, including hidden (admin diagnostic)
//	status="hidden"            → only hidden rows (admin diagnostic)
func (h *CampaignsHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("page", "1")))
	perPage, _ := strconv.Atoi(strings.TrimSpace(c.DefaultQuery("per_page", "12")))

	// Pass the raw status value through verbatim — Store.List owns the
	// mapping from status string → SQL WHERE clause now.
	statusParam := strings.ToLower(strings.TrimSpace(c.Query("status")))

	res, err := h.Store.List(c.Request.Context(), page, perPage, statusParam)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch campaigns."})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status":     "success",
		"data":       res.Items,
		"pagination": res.Pagination,
	})
}
