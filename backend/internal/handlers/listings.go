package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/appsettings"
	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/listings"
)

// ListingsHandler covers GET /api/partners, /api/media, /api/community.
type ListingsHandler struct {
	Store *listings.Store
	// Settings is optional; nil means "no settings store wired", in which case
	// ratings stay visible — the pre-existing behaviour.
	Settings *appsettings.Store
}

func NewListingsHandler(s *listings.Store) *ListingsHandler {
	return &ListingsHandler{Store: s}
}

// WithSettings attaches the settings store used by the partner-ratings toggle.
func (h *ListingsHandler) WithSettings(s *appsettings.Store) *ListingsHandler {
	h.Settings = s
	return h
}

// PartnerActivities — GET /api/partners/:id/activities.
// "Eleventh: Partners Section" — the Partner Page's history of activities
// carried out in cooperation with this partner.
func (h *ListingsHandler) PartnerActivities(c *gin.Context) {
	id, _ := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid partner id."})
		return
	}
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.PartnerActivities(c.Request.Context(), id, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
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
	// "Interactive 1-5 star rating with an option to hide it." When hidden the
	// scores are stripped here rather than left to the client to ignore, so no
	// consumer of this endpoint can surface a rating the admin turned off.
	// The rows themselves are untouched — turning it back on restores
	// everything staff have already scored.
	ratingsVisible := true
	if h.Settings != nil {
		if v, err := h.Settings.Get(c.Request.Context(), appsettings.KeyPartnerRatingsVisible); err == nil {
			ratingsVisible = !strings.EqualFold(strings.TrimSpace(v), "false")
		}
	}
	if !ratingsVisible {
		for i := range items {
			items[i].AvgRating = nil
			items[i].RatingCount = 0
			items[i].AdminRating = nil
			items[i].ScoreActivities = nil
			items[i].ScoreDonations = nil
			items[i].ScoreCooperation = nil
			items[i].ScoreContinuity = nil
			items[i].AdminRatingNote = ""
			items[i].MyRating = 0
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"success":         true,
		"items":           items,
		"ratings_visible": ratingsVisible,
	})
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
	// ?saved=1 returns only what this user saved — the app's "Saved" screen.
	saved := c.Query("saved") == "1" || strings.EqualFold(c.Query("saved"), "true")
	items, err := h.Store.ListMediaPosts(c.Request.Context(), status, c.Query("type"), c.Query("q"), limit, userID, saved)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

func (h *ListingsHandler) Community(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.ListCommunity(c.Request.Context(), c.Query("category"), c.Query("city"), c.Query("q"), c.Query("sector"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// CommunityAdmin — GET /api/admin/community (#30). Lists directory entries incl.
// pending user submissions, optionally filtered by ?status=pending|approved|…
func (h *ListingsHandler) CommunityAdmin(c *gin.Context) {
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))
	items, err := h.Store.ListCommunityAdmin(c.Request.Context(), c.Query("status"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// communitySubmitReq is the body an app user posts to suggest a new place (#30).
type communitySubmitReq struct {
	Name         string   `json:"name"`
	NameAr       string   `json:"name_ar"`
	NameSorani   string   `json:"name_sorani"`
	NameBadini   string   `json:"name_badini"`
	Category     string   `json:"category"`
	City         string   `json:"city"`
	Address      string   `json:"address"`
	Phone        string   `json:"phone"`
	Website      string   `json:"website"`
	Latitude     string   `json:"latitude"`
	Longitude    string   `json:"longitude"`
	Sectors      []string `json:"sectors"`
	OpeningHours string   `json:"opening_hours"`
}

// SubmitCommunity — POST /api/community/submit (#30). An approved app user
// suggests a place; it enters the admin queue as 'pending'.
func (h *ListingsHandler) SubmitCommunity(c *gin.Context) {
	var req communitySubmitReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "name is required."})
		return
	}
	if strings.TrimSpace(req.Category) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "category is required."})
		return
	}
	// A coordinate off the Earth is not a place. Rejected here so it never
	// reaches the map, which centres on the average of its pins and was
	// blanked entirely by one row carrying latitude 500, longitude 700.
	if msg := validateCoordinate(req.Latitude, req.Longitude); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": msg})
		return
	}
	var submittedBy *int64
	if user, ok := auth.UserFromGin(c); ok && user != nil {
		id := user.UserID
		submittedBy = &id
	}
	id, err := h.Store.SubmitCommunity(c.Request.Context(), listings.CommunitySubmission{
		Name: strings.TrimSpace(req.Name), NameAr: req.NameAr, NameSorani: req.NameSorani, NameBadini: req.NameBadini,
		Category: strings.TrimSpace(req.Category), City: req.City, Address: req.Address, Phone: req.Phone,
		Website: req.Website, Latitude: req.Latitude, Longitude: req.Longitude,
		Sectors: req.Sectors, OpeningHours: req.OpeningHours, SubmittedBy: submittedBy,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "status": "pending"})
}
