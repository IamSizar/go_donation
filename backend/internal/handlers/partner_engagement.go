package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/partnerratings"
)

// PartnerEngagementHandler powers the app-facing partner rating action (#27).
// Sits under the authed group, so auth.UserFromGin is always set.
type PartnerEngagementHandler struct {
	Store *partnerratings.Store
}

func NewPartnerEngagementHandler(s *partnerratings.Store) *PartnerEngagementHandler {
	return &PartnerEngagementHandler{Store: s}
}

// Rate — POST /api/partners/:id/rate — body {stars:1..5}. Returns the updated
// {avg_rating, rating_count, my_rating}.
func (h *PartnerEngagementHandler) Rate(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	partnerID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || partnerID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid partner id."})
		return
	}
	data := collectBody(c)
	stars := asInt(data["stars"])

	res, err := h.Store.Submit(c.Request.Context(), partnerID, user.UserID, stars)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Partner not found."})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"avg_rating":   res.AvgRating,
		"rating_count": res.RatingCount,
		"my_rating":    res.MyRating,
	})
}
