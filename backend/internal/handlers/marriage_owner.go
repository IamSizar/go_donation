// marriage_owner.go — K14: the owner-scoped خطوبتي endpoints.
//
// The client asked for "a profile with edit / activate / delete-account". None
// of the three had a route: POST /api/marriage inserts a NEW row with a fresh
// profile_code, and there was no PATCH, no PUT and no DELETE a profile's owner
// could call. The app carries a written decision not to call its button "edit"
// because of exactly that.
//
// These four handlers are thin on purpose. Ownership is not checked here — it
// is checked inside each UPDATE in internal/marriage/owner.go, so there is no
// window between a check and a write, and "not yours" and "does not exist"
// answer identically. What lives here is parsing, and turning the store's
// errors into a status code and a sentence a user can act on.
package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
)

// ownerProfileID resolves the authenticated caller and the :id, or writes the
// error response itself and reports false.
func ownerProfileID(c *gin.Context) (userID, profileID int64, ok bool) {
	user, _ := auth.UserFromGin(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return 0, 0, false
	}
	pid, _ := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if pid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid profile id."})
		return 0, 0, false
	}
	return user.UserID, pid, true
}

// writeOwnerError maps a store error onto a response.
//
// ErrNotOwner is 403 with one wording for "somebody else's" and "does not
// exist" alike — telling them apart would make this endpoint an id-enumeration
// tool. ErrNotPausable is 409 and says what the state actually is, because the
// owner already knows the profile is theirs and "not yours" would be a lie.
func writeOwnerError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, marriage.ErrNotOwner):
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"code": "not_owner", "error": "This engagement profile is not yours."})
	case errors.Is(err, marriage.ErrNotPausable):
		c.JSON(http.StatusConflict, gin.H{"success": false,
			"code": "not_pausable", "error": "This engagement profile cannot be switched on or off while it is in its current state."})
	case errors.Is(err, marriage.ErrInvalidVisibility):
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"code": "invalid_visibility", "error": "Choose one of the offered privacy options."})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
	}
}

// ─── تعديل — PATCH /api/marriage/:id ────────────────────────────────────

// ownerProfileReq is the patch body. Every field is a pointer so "absent" and
// "cleared" stay different things: without that, a form sending only the field
// it changed would blank everything else, and a form sending everything could
// never remove a value.
type ownerProfileReq struct {
	Gender           *string `json:"gender"`
	Age              *int    `json:"age"`
	City             *string `json:"city"`
	SocialSummary    *string `json:"social_summary"`
	MaritalStatus    *string `json:"marital_status"`
	Religion         *string `json:"religion"`
	EmploymentStatus *string `json:"employment_status"`
	WeightKg         *int    `json:"weight_kg"`
	HeightCm         *int    `json:"height_cm"`
	PhotoUrl         *string `json:"photo_url"`
	VisibilityLevel  *string `json:"visibility_level"`
}

// UpdateMine — PATCH /api/marriage/:id. The owner's own edit.
//
// Only the fields on the profile card are editable here; the deeper
// registration sections (identification, housing, assets, health) still change
// through staff, which is what the app already tells users. They are not
// accepted-and-dropped: a key that is not in ownerProfileReq is simply not part
// of this endpoint's contract, and the response echoes the profile so the app
// shows what was actually stored rather than what it hoped it sent.
func (h *MarriageHandler) UpdateMine(c *gin.Context) {
	userID, profileID, ok := ownerProfileID(c)
	if !ok {
		return
	}
	var req ownerProfileReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Store.UpdateOwnProfile(c.Request.Context(), profileID, userID, marriage.OwnerProfilePatch{
		Gender:           req.Gender,
		Age:              req.Age,
		City:             req.City,
		SocialSummary:    req.SocialSummary,
		MaritalStatus:    req.MaritalStatus,
		Religion:         req.Religion,
		EmploymentStatus: req.EmploymentStatus,
		WeightKg:         req.WeightKg,
		HeightCm:         req.HeightCm,
		PhotoUrl:         req.PhotoUrl,
		VisibilityLevel:  req.VisibilityLevel,
	}); err != nil {
		writeOwnerError(c, err)
		return
	}
	h.respondWithOwnProfile(c, userID, profileID)
}

// ─── إيقاف / تفعيل — POST /api/marriage/:id/pause | /resume ─────────────

// PauseMine takes the profile out of the browse feed, remembering what to put
// it back to.
func (h *MarriageHandler) PauseMine(c *gin.Context) {
	userID, profileID, ok := ownerProfileID(c)
	if !ok {
		return
	}
	if err := h.Store.PauseOwnProfile(c.Request.Context(), profileID, userID); err != nil {
		writeOwnerError(c, err)
		return
	}
	h.respondWithOwnProfile(c, userID, profileID)
}

// ResumeMine puts it back into the status it was paused from — NOT into
// 'active', which would let an owner approve a profile staff never reviewed.
func (h *MarriageHandler) ResumeMine(c *gin.Context) {
	userID, profileID, ok := ownerProfileID(c)
	if !ok {
		return
	}
	if err := h.Store.ResumeOwnProfile(c.Request.Context(), profileID, userID); err != nil {
		writeOwnerError(c, err)
		return
	}
	h.respondWithOwnProfile(c, userID, profileID)
}

// ─── حذف — DELETE /api/marriage/:id ─────────────────────────────────────

// DeleteMine removes the profile from every surface of the app.
//
// It is a recoverable delete, and the response says so rather than claiming the
// record is gone: the row and its children — the mediated chat history and the
// subscription purchase record — are all kept, because marriage_profiles'
// children cascade and this repo's Trash archives only the row it deletes. See
// marriage.Store.DeleteOwnProfile. Staff restore it by making any status
// decision on the profile.
func (h *MarriageHandler) DeleteMine(c *gin.Context) {
	userID, profileID, ok := ownerProfileID(c)
	if !ok {
		return
	}
	if err := h.Store.DeleteOwnProfile(c.Request.Context(), profileID, userID); err != nil {
		writeOwnerError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true, "id": profileID,
		// Named for what actually happened. "deleted: true" would tell the app
		// the row is gone when staff can still see and reinstate it.
		"removed": true, "recoverable": true,
	})
}

// respondWithOwnProfile re-reads the caller's own profile and returns it, so a
// successful write answers with the stored truth instead of an echo of the
// request. Falls back to a bare success if the read fails — the write already
// landed, and reporting an error for it would be worse than a thinner response.
func (h *MarriageHandler) respondWithOwnProfile(c *gin.Context, userID, profileID int64) {
	items, err := h.Store.List(c.Request.Context(), marriage.SearchFilters{
		Status: "all", OwnedByUser: userID, ViewerUserID: userID,
	})
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "id": profileID})
		return
	}
	for _, p := range items {
		if p.ID == profileID {
			c.JSON(http.StatusOK, gin.H{"success": true, "id": profileID, "profile": p})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": profileID})
}
