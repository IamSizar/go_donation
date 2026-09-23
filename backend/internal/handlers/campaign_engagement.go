package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/campaigns"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/postengagement"
)

// CampaignEngagementHandler powers like/comment/save on donation campaigns.
// Mirrors MarriageEngagementHandler's shape — see internal/campaigns/
// engagement.go's header for why like/comment are a separate store. Save
// is the one exception: it reuses postengagement.Store's saved_items table
// directly (the same one media posts use) rather than adding a duplicate
// campaign-scoped table — that table was already generic (user_id,
// item_type, item_id), so a new savable kind costs a constant, not a
// migration.
type CampaignEngagementHandler struct {
	Store  *campaigns.EngagementStore
	Saved  *postengagement.Store
	Banned *moderation.Store
}

func NewCampaignEngagementHandler(s *campaigns.EngagementStore, saved *postengagement.Store, b *moderation.Store) *CampaignEngagementHandler {
	return &CampaignEngagementHandler{Store: s, Saved: saved, Banned: b}
}

// Save — POST /api/campaigns/:id/save — toggles "save for later".
func (h *CampaignEngagementHandler) Save(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	campaignID, ok := campaignEngagementID(c)
	if !ok {
		return
	}
	if err := h.Store.Exists(c.Request.Context(), campaignID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Campaign not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	savedNow, err := h.Saved.ToggleSave(c.Request.Context(), user.UserID, postengagement.ItemTypeCampaign, campaignID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "saved": savedNow})
}

func campaignEngagementID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid campaign id."})
		return 0, false
	}
	return id, true
}

// Like — POST /api/campaigns/:id/like — toggles the current user's like.
func (h *CampaignEngagementHandler) Like(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	campaignID, ok := campaignEngagementID(c)
	if !ok {
		return
	}
	if err := h.Store.Exists(c.Request.Context(), campaignID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Campaign not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	liked, count, err := h.Store.ToggleLike(c.Request.Context(), campaignID, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "liked": liked, "like_count": count})
}

// Comments — GET /api/campaigns/:id/comments — approved comments only.
func (h *CampaignEngagementHandler) Comments(c *gin.Context) {
	campaignID, ok := campaignEngagementID(c)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.Store.ListCommentsApproved(c.Request.Context(), campaignID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Comment — POST /api/campaigns/:id/comments — submit a comment. A comment
// matching a banned word is held for review (status 'pending', flagged)
// rather than rejected outright, same as the News & Activities feed.
func (h *CampaignEngagementHandler) Comment(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	campaignID, ok := campaignEngagementID(c)
	if !ok {
		return
	}
	if err := h.Store.Exists(c.Request.Context(), campaignID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Campaign not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	data := collectBody(c)
	body := asStr(data["body"])
	if body == "" {
		body = asStr(data["comment"])
	}

	status, flagged := "approved", false
	if bad, _ := h.Banned.Contains(c.Request.Context(), body); bad {
		status, flagged = "pending", true
	}

	cmt, err := h.Store.AddComment(c.Request.Context(), campaignID, user.UserID, body, status, flagged)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "comment": cmt, "held": flagged})
}

// AdminComments — GET /api/admin/campaign-comments?status=pending — moderation queue.
func (h *CampaignEngagementHandler) AdminComments(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.Store.AdminListComments(c.Request.Context(), c.Query("status"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminDeleteComment — DELETE /api/admin/campaign-comments/:id. To the Trash,
// not straight out of the table — same reasoning as media/marriage comments:
// this is a real person's words, removed by a moderator who might misclick.
func (h *CampaignEngagementHandler) AdminDeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid comment id."})
		return
	}
	trashRow(c, h.Store.Pool, "campaign_comments", id)
}
