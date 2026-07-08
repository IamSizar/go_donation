package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/postengagement"
)

// MediaEngagementHandler powers the app-facing like / comment / share actions
// on media posts (#24) and applies the banned-words gate on comments (#25).
// All routes sit under the authed group, so auth.UserFromGin is always set.
type MediaEngagementHandler struct {
	Store    *postengagement.Store
	Banned   *moderation.Store
	Notifier *notify.Notifier
	Events   *events.Store // #24 — surface new comments on the admin activity feed
}

func NewMediaEngagementHandler(s *postengagement.Store, b *moderation.Store, n *notify.Notifier, ev *events.Store) *MediaEngagementHandler {
	return &MediaEngagementHandler{Store: s, Banned: b, Notifier: n, Events: ev}
}

// mediaPostID parses the :id path param. Writes a 400 and returns ok=false when
// it's missing/invalid.
func mediaPostID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid post id."})
		return 0, false
	}
	return id, true
}

// Like — POST /api/media/:id/like — toggles the current user's like.
func (h *MediaEngagementHandler) Like(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	postID, ok := mediaPostID(c)
	if !ok {
		return
	}
	if _, _, err := h.Store.PostMeta(c.Request.Context(), postID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Post not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	liked, count, err := h.Store.ToggleLike(c.Request.Context(), postID, user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "liked": liked, "like_count": count})
}

// Comments — GET /api/media/:id/comments — approved comments only (app view).
func (h *MediaEngagementHandler) Comments(c *gin.Context) {
	postID, ok := mediaPostID(c)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.Store.ListComments(c.Request.Context(), postID, true, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Comment — POST /api/media/:id/comments — submit a comment. Comments matching
// a banned word are held for review (status 'pending', flagged) rather than
// rejected outright, so the user isn't told which word tripped it.
func (h *MediaEngagementHandler) Comment(c *gin.Context) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	postID, ok := mediaPostID(c)
	if !ok {
		return
	}
	authorID, _, err := h.Store.PostMeta(c.Request.Context(), postID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Post not found."})
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

	cmt, err := h.Store.AddComment(c.Request.Context(), postID, user.UserID, body, status, flagged)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	// Notify the post's author of an approved comment (never self-notify).
	if status == "approved" && authorID > 0 && authorID != user.UserID {
		_, _ = h.Notifier.Send(c.Request.Context(), authorID,
			notify.NewCommentOnYourPostMsg(cmt.UserName, snippet(body, 80), postID))
	}

	// #24 — surface the comment on the admin activity feed. entity_id = comment
	// id, so a click deep-links to the Comments page and highlights the row.
	// Flagged/pending comments especially need a moderator's attention.
	if h.Events != nil {
		uid := user.UserID
		cid := cmt.ID
		pid := postID
		_, _ = h.Events.Insert(c.Request.Context(), events.Event{
			EventType:  "comment_submit",
			EventLabel: "New comment",
			Module:     "media",
			Action:     "submit",
			Status:     status,
			Source:     "app",
			UserID:     &uid,
			EntityID:   &cid,
			TargetID:   &pid,
			Note:       snippet(body, 80),
			Metadata:   map[string]interface{}{"post_id": postID, "flagged": flagged},
		})
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "comment": cmt, "held": flagged})
}

// Share — POST /api/media/:id/share — bumps the post's share count.
func (h *MediaEngagementHandler) Share(c *gin.Context) {
	postID, ok := mediaPostID(c)
	if !ok {
		return
	}
	count, err := h.Store.IncrementShare(c.Request.Context(), postID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Post not found."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "share_count": count})
}

// ---- admin moderation (list + delete; status change goes via AdminStatusHandler) ----

// AdminComments — GET /api/admin/media-comments?status=pending — moderation queue.
func (h *MediaEngagementHandler) AdminComments(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.Store.AdminListComments(c.Request.Context(), c.Query("status"), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminDeleteComment — DELETE /api/admin/media-comments/:id.
func (h *MediaEngagementHandler) AdminDeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid comment id."})
		return
	}
	if err := h.Store.DeleteComment(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// snippet trims text to at most n runes, appending an ellipsis when cut.
func snippet(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
