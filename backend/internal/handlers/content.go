package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/content"
)

// ContentHandler serves editable static pages (Terms & Conditions now; About /
// Contact later). Public GET renders them; admin PUT edits them.
type ContentHandler struct {
	Store *content.Store
}

func NewContentHandler(s *content.Store) *ContentHandler {
	return &ContentHandler{Store: s}
}

// allowedSlugs bounds which content pages can be read/written, so the endpoint
// can't be used to stuff arbitrary rows.
var allowedSlugs = map[string]bool{
	"terms":             true,
	"about":             true,
	"contact":           true,
	"humanitarian-work": true,
}

// PublicContent handles GET /api/content/:slug (no auth) so the app can render
// the page before/without login. 404 for unknown or unseeded slugs.
func (h *ContentHandler) PublicContent(c *gin.Context) {
	slug := c.Param("slug")
	if !allowedSlugs[slug] {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Unknown content page."})
		return
	}
	cont, err := h.Store.Get(c.Request.Context(), slug)
	if errors.Is(err, content.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Content not found."})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "content": cont})
}

// AdminUpdateContent handles PUT /api/admin/content/:slug (admin group + super
// admin). Upserts the page's title+body in all four locales.
func (h *ContentHandler) AdminUpdateContent(c *gin.Context) {
	slug := c.Param("slug")
	if !allowedSlugs[slug] {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown content page."})
		return
	}
	var body content.Content
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	body.Slug = slug

	var updatedBy int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		updatedBy = actor.UserID
	}
	if err := h.Store.Upsert(c.Request.Context(), body, updatedBy); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "slug": slug})
}
