package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
)

// MarriageEngagementHandler powers like/comment/share on marriage-seeker
// profile cards. All routes sit under the authed group, so auth.UserFromGin
// is always set. Mirrors MediaEngagementHandler's shape — see
// internal/marriage/engagement.go's header for why this is a separate store
// rather than a reuse of postengagement.
type MarriageEngagementHandler struct {
	Store  *marriage.EngagementStore
	Banned *moderation.Store
	Events *events.Store // new comments reach the admin alerts (nil = off)
}

func NewMarriageEngagementHandler(s *marriage.EngagementStore, b *moderation.Store, ev *events.Store) *MarriageEngagementHandler {
	return &MarriageEngagementHandler{Store: s, Banned: b, Events: ev}
}

func marriageProfileID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid profile id."})
		return 0, false
	}
	return id, true
}

// Like — POST /api/marriage/:id/like — toggles the current user's like.
func (h *MarriageEngagementHandler) Like(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	profileID, ok := marriageProfileID(c)
	if !ok {
		return
	}
	if err := h.Store.ProfileExists(c.Request.Context(), profileID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Profile not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	liked, count, err := h.Store.ToggleLike(c.Request.Context(), profileID, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "liked": liked, "like_count": count})
}

// Comments — GET /api/marriage/:id/comments — approved comments only (app view).
func (h *MarriageEngagementHandler) Comments(c *gin.Context) {
	profileID, ok := marriageProfileID(c)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	var viewerID int64
	if u, _ := auth.UserFromGin(c); u != nil {
		viewerID = u.UserID
	}
	items, err := h.Store.ListCommentsForViewer(c.Request.Context(), profileID, viewerID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Comment — POST /api/marriage/:id/comments — submit a comment. A comment
// matching a banned word is held for review (status 'pending', flagged)
// rather than rejected outright, same as the News & Activities feed.
func (h *MarriageEngagementHandler) Comment(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	profileID, ok := marriageProfileID(c)
	if !ok {
		return
	}
	if err := h.Store.ProfileExists(c.Request.Context(), profileID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Profile not found."})
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

	cmt, err := h.Store.AddComment(c.Request.Context(), profileID, user.UserID, body, status, flagged)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}

	// Surface the comment on the admin alerts / activity feed, like media
	// comments (#24). Its own event type so the link opens the Comments page
	// on the right source — comment ids are per-table and would collide.
	if h.Events != nil {
		uid := user.UserID
		cid := cmt.ID
		tid := profileID
		_, _ = h.Events.Insert(c.Request.Context(), events.Event{
			EventType:  "marriage_comment_submit",
			EventLabel: "New comment",
			Module:     "marriage",
			Action:     "submit",
			Status:     status,
			Source:     "app",
			UserID:     &uid,
			EntityID:   &cid,
			TargetID:   &tid,
			Note:       snippet(body, 80),
			Metadata:   map[string]interface{}{"profile_id": tid, "flagged": flagged},
		})
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "comment": cmt, "held": flagged})
}

// Share — POST /api/marriage/:id/share — bumps the profile's share count.
func (h *MarriageEngagementHandler) Share(c *gin.Context) {
	profileID, ok := marriageProfileID(c)
	if !ok {
		return
	}
	count, err := h.Store.IncrementShare(c.Request.Context(), profileID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Profile not found."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "share_count": count})
}

// AdminComments — GET /api/admin/marriage-comments?status=pending — moderation queue.
func (h *MarriageEngagementHandler) AdminComments(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.Store.AdminListComments(c.Request.Context(), c.Query("status"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminDeleteComment — DELETE /api/admin/marriage-comments/:id. To the Trash,
// not straight out of the table — same reasoning as media comments (H15):
// this is a real person's words, removed by a moderator who might misclick.
func (h *MarriageEngagementHandler) AdminDeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid comment id."})
		return
	}
	trashRow(c, h.Store.Pool, "marriage_profile_comments", id)
}
