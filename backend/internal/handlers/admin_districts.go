package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/districts"
)

// DistrictsHandler powers the admin-managed district/neighborhood CMS (OPOS
// #25271). A public GET feeds the registration form's Nineveh district and
// neighborhood pickers; the admin routes (gated in main.go) add/edit/
// reorder/delete entries.
type DistrictsHandler struct {
	Store *districts.Store
}

func NewDistrictsHandler(s *districts.Store) *DistrictsHandler {
	return &DistrictsHandler{Store: s}
}

// PublicList — GET /api/districts?group=nineveh_district (active only, no
// auth). group is required: the three pickers are meaningfully different
// lists, and an unscoped request returning all of them would silently mix
// districts into a neighborhood dropdown or vice versa.
func (h *DistrictsHandler) PublicList(c *gin.Context) {
	group := c.Query("group")
	if group == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "group is required."})
		return
	}
	items, err := h.Store.List(c.Request.Context(), group, true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// AdminList — GET /api/admin/districts (all groups, incl. inactive). The
// manager UI filters client-side by group so staff can see all three lists
// without three separate requests.
func (h *DistrictsHandler) AdminList(c *gin.Context) {
	items, err := h.Store.List(c.Request.Context(), "", false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// Add — POST /api/admin/districts — body {group_key, name_en, name_ar, name_ckb, name_kmr, slug?}.
func (h *DistrictsHandler) Add(c *gin.Context) {
	var req districts.District
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	var actorID *int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		id := actor.UserID
		actorID = &id
	}
	saved, err := h.Store.Add(c.Request.Context(), req, actorID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "district": saved})
}

// Update — PATCH /api/admin/districts/:id — edit names + active (slug/group fixed).
func (h *DistrictsHandler) Update(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid district id."})
		return
	}
	var req districts.District
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Store.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": clientMessage(err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "district": saved})
}

// Reorder — POST /api/admin/districts/reorder — body {ids:[3,1,2]}.
func (h *DistrictsHandler) Reorder(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.Reorder(c.Request.Context(), req.IDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// Delete — DELETE /api/admin/districts/:id. Goes to the Trash, not straight
// out of the table — same reasoning as city_categories (H15): this is a
// place name authored in up to four languages, and a misclick should not
// destroy that with no way back.
func (h *DistrictsHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid district id."})
		return
	}
	trashRow(c, h.Store.Pool, "districts", id)
}
