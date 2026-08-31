package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
)

// BannedWordsHandler powers the admin-managed banned-words blocklist (#25).
// Comments containing any listed word are held for review at submit time.
type BannedWordsHandler struct {
	Store *moderation.Store
	// Pool — needed because Delete now routes through trashRow (a package
	// function over the pool) instead of Store.Delete, so a removed word can be
	// restored from المهملات.
	Pool *pgxpool.Pool
}

func NewBannedWordsHandler(s *moderation.Store, pool *pgxpool.Pool) *BannedWordsHandler {
	return &BannedWordsHandler{Store: s, Pool: pool}
}

// List — GET /api/admin/banned-words.
func (h *BannedWordsHandler) List(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/banned-words — body {word}.
func (h *BannedWordsHandler) Add(c *gin.Context) {
	var req struct {
		Word string `json:"word"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	var actorID *int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		id := actor.UserID
		actorID = &id
	}
	saved, err := h.Store.Add(c.Request.Context(), req.Word, actorID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "word": saved})
}

// Delete — DELETE /api/admin/banned-words/:id — moves the word to المهملات.
//
// WHY IT GOES TO THE TRASH NOW. This route used to hard-delete, recorded as a
// deliberate exception in admin_delete_trash_test.go because the blocklist is
// cached in-process with no TTL and only moderation.Store.Delete invalidated
// that cache. The client has since restated the rule with no exceptions, so the
// cache problem is solved rather than used as grounds to skip the Trash:
// moderation.Store.Invalidate is exported, this handler calls it after a
// successful trashing, and AdminTrashHandler calls it after a restore.
func (h *BannedWordsHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid id."})
		return
	}
	// "banned_words" is a package literal, never request input.
	if trashRow(c, h.Pool, "banned_words", id) {
		// Only on a confirmed trashing: the row is gone from banned_words, so
		// the cached list is now stale and would keep enforcing a removed word
		// until the process restarted.
		h.Store.Invalidate()
	}
}
