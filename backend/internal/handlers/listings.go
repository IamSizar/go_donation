package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/listings"
)

// ListingsHandler covers GET /api/partners, /api/media, /api/community.
type ListingsHandler struct {
	Store *listings.Store
}

func NewListingsHandler(s *listings.Store) *ListingsHandler {
	return &ListingsHandler{Store: s}
}

func (h *ListingsHandler) Partners(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	// Default to 'active' for the public contract; ?status=all disables the filter,
	// any other value matches exactly.
	status := strings.TrimSpace(c.Query("status"))
	switch {
	case status == "":
		status = "active"
	case strings.EqualFold(status, "all"):
		status = ""
	}
	// #27 — optional user_id so the list can flag the viewer's own rating.
	userID, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	items, err := h.Store.ListPartners(c.Request.Context(), status, c.Query("q"), limit, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func (h *ListingsHandler) Media(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	status := strings.TrimSpace(c.Query("status"))
	switch {
	case status == "":
		status = "published"
	case strings.EqualFold(status, "all"):
		status = ""
	}
	// #24 — optional user_id so the feed can flag which posts the viewer liked.
	userID, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	items, err := h.Store.ListMediaPosts(c.Request.Context(), status, c.Query("type"), c.Query("q"), limit, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func (h *ListingsHandler) Community(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.ListCommunity(c.Request.Context(), c.Query("category"), c.Query("city"), c.Query("q"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
