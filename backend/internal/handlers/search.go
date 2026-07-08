package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/search"
)

// SearchHandler powers the app-wide global search box (#33).
type SearchHandler struct {
	Store *search.Store
}

func NewSearchHandler(s *search.Store) *SearchHandler {
	return &SearchHandler{Store: s}
}

// GET /api/search?q=... — public. Returns a flat, typed result list.
func (h *SearchHandler) Search(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	perType, _ := strconv.Atoi(strings.TrimSpace(c.Query("per_type")))
	items, err := h.Store.Search(c.Request.Context(), q, perType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
