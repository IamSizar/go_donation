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
	// Section-specific About / Contact. The spec is explicit that the marriage
	// service and the city guide carry DIFFERENT phone numbers and social
	// links from the humanitarian side, so they get their own pages rather
	// than sharing 'about' and 'contact' (migration 099).
	"marriage-about":     true,
	"marriage-contact":   true,
	"city-guide-about":   true,
	"city-guide-contact": true,
}

// PublicContent handles GET /api/content/:slug (no auth) so the app can render
// the page before/without login. 404 for unknown or unseeded slugs.
//
// K12 — the response also carries `sections`: the page's named, ordered
// sub-sections. This is ADDITIVE. `content` keeps every field it had, and
// `content.body_*` still holds the whole page as one blob (composed from the
// sub-sections when there are any), so the installed app renders exactly as
// before while a future build can render the sub-sections as separate titled
// blocks. A page with no sub-sections returns `"sections": []`.
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
	sections, err := h.Store.ListSections(c.Request.Context(), slug)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "content": cont, "sections": sections})
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

// sectionsPayload is the body of AdminUpdateSections: the page's whole
// sub-section list, in the order it should appear.
//
// Replace-all rather than per-row edits because the dashboard edits the list as
// one form with one Save — reorder, rename, add and remove arrive together, and
// applying half of that is a half-rewritten page.
type sectionsPayload struct {
	Sections []content.Section `json:"sections"`
}

// AdminUpdateSections handles PUT /api/admin/content/:slug/sections (K12).
//
// Saves the named, ordered sub-sections of a page and, when there is at least
// one, recomposes `app_content.body_*` from them so the already-installed app
// keeps rendering the current text (see internal/content/sections.go).
//
// Gated exactly like the page editor it sits next to: admin group +
// RequireSuperAdmin, applied at the route.
func (h *ContentHandler) AdminUpdateSections(c *gin.Context) {
	slug := c.Param("slug")
	if !allowedSlugs[slug] {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown content page."})
		return
	}
	var payload sectionsPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	// Validated at the trust boundary rather than in the store, so the caller
	// gets a 400 that names the limit instead of a 500 from a rejected write.
	if len(payload.Sections) > content.MaxSections {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Too many sub-sections on one page.",
		})
		return
	}

	var updatedBy int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		updatedBy = actor.UserID
	}
	if err := h.Store.ReplaceSections(c.Request.Context(), slug, payload.Sections, updatedBy); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "slug": slug, "count": len(payload.Sections)})
}
