// profile_full.go — the signed-in user's own complete profile.
//
// WHY THIS EXISTS
// `/profile/get` returns eight columns: name, gender, address, picture, date
// of birth, the identity codes and the privacy blob. That was enough while
// the app's Edit Profile screen was a four-field form.
//
// It is not enough now. The app prompts a user whose registration has gained
// a newly-required field ("A few details are still missing") and sends them
// to edit their profile — and the form it sends them to has to be able to
// SHOW the fields it is asking them to fill in, which means every field their
// role's registration form asks for, prefilled with what they already
// entered. Eight columns cannot prefill a hundred.
//
// So this returns the same profile row the dashboard's detail page reads —
// literally the same loader and the same allow-list, so the two surfaces
// cannot disagree about what a profile contains.
//
// ─── WHY IT IS SAFE TO HAND A USER THIS MUCH ────────────────────────────────
// It is their own data, and the identity of the row is not negotiable: the id
// comes from the bearer token via auth.UserFromGin and is never read from the
// request, so there is no id to tamper with and no IDOR to have. The
// allow-list it shares with the admin page already excludes every credential
// (password_hash and google_sub live on `users`, not `user_profiles`).
//
// The privacy blob is deliberately NOT included. `field_privacy` is the list
// of fields this person asked other USERS not to see — it is a setting, owned
// by the Privacy screen, and echoing it here would invite a second place to
// edit it. The dashboard re-emits it as `_privacy_hidden` for badging; this
// endpoint has no badges to draw.
package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// GetFull handles GET /api/profile/full.
//
// Returns `{"status":"success","profile":{...}}`. A user with no profile row
// yet — a brand-new account that has not submitted a registration — gets an
// EMPTY OBJECT rather than a 404: "you have not filled anything in" is a
// legitimate state for the edit form to prefill from, and 404 would make the
// client treat a normal case as a failure.
func (h *ProfileHandler) GetFull(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"status": "error",
			"error":  "Unauthorized request. Please sign in again.",
		})
		return
	}

	prof, err := loadUserProfile(c.Request.Context(), h.Users.Pool, user.UserID)
	if err != nil {
		// Not swallowed: the client cannot prefill a form from a profile it
		// failed to read, and silently showing an empty one would invite the
		// user to overwrite everything they had entered with blanks.
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error",
			"error":  "Database error.",
		})
		return
	}
	if prof == nil {
		prof = map[string]any{}
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "profile": prof})
}
