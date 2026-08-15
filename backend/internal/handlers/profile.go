package handlers

import (
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/profilechanges"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ProfileHandler ports percentage/api/profile/{get,set}/index.php.
type ProfileHandler struct {
	Users     *users.Store
	UploadDir string // absolute path on disk; files are served at /images/*
	// Name and photo changes are reviewed by staff before they apply
	// (migration 093); nil disables review and writes straight through.
	Changes *profilechanges.Store
}

func NewProfileHandler(u *users.Store, uploadDir string, ch *profilechanges.Store) *ProfileHandler {
	return &ProfileHandler{Users: u, UploadDir: uploadDir, Changes: ch}
}

// GET /api/profile/notifications (#31) — the current user's notification switch.
func (h *ProfileHandler) GetNotificationSetting(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	enabled, err := h.Users.GetNotificationsEnabled(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "enabled": enabled})
}

// GET /api/profile/notification-categories (K7) — the categories of alert the
// user can switch on or off individually, each with THIS user's current
// answer, so the Settings screen renders from one response.
//
// The list is data-driven (notification_categories, migration 108), the same
// arrangement the privacy screen already has: staff can retire a category
// without an app release.
func (h *ProfileHandler) GetNotificationCategories(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	items, err := h.Users.NotificationCategories(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/profile/notification-categories (K7) — body {disabled: [...]}.
// Replaces the whole set of per-category choices, deliberately mirroring the
// shape of /api/profile/privacy so the app has one pattern to follow.
//
// The response echoes the categories that actually ended up switched off, so
// the screen can show real state rather than assume its request landed;
// categories the catalogue does not list are dropped rather than stored.
func (h *ProfileHandler) SetNotificationCategories(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req struct {
		Disabled []string `json:"disabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	saved, err := h.Users.SetNotificationCategories(c.Request.Context(), user.UserID, req.Disabled)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "disabled": saved})
}

// GET /api/profile/privacy-options — Privacy Settings spec ("Future
// Development"): the admin-managed catalogue of fields a user may show or
// hide. The app renders whatever this returns, so adding an option is a DB
// insert rather than a code change.
func (h *ProfileHandler) GetPrivacyOptions(c *gin.Context) {
	opts, err := h.Users.PrivacyFieldOptions(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": opts})
}

// GET /api/profile/privacy (#32) — the current user's hidden profile fields.
func (h *ProfileHandler) GetFieldPrivacy(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	hidden, err := h.Users.GetFieldPrivacy(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "hidden": hidden})
}

// POST /api/profile/privacy (#32) — body {hidden: ["phone","address"]}. Replaces
// the current user's hidden-field list.
func (h *ProfileHandler) SetFieldPrivacy(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req struct {
		Hidden []string `json:"hidden"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Users.SetFieldPrivacy(c.Request.Context(), user.UserID, req.Hidden); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "hidden": req.Hidden})
}

// GET /api/profile/privacy-extras — Privacy Settings spec: the current
// display-name choice (real name vs. alias) and social media links.
func (h *ProfileHandler) GetPrivacyExtras(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	extras, err := h.Users.GetPrivacyExtras(c.Request.Context(), user.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "extras": extras})
}

// POST /api/profile/privacy-extras — body {display_name_mode, alias_name,
// social_facebook, social_instagram, social_telegram}. Replaces the current
// user's display-name choice and social links.
func (h *ProfileHandler) SetPrivacyExtras(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req users.PrivacyExtras
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Users.SetPrivacyExtras(c.Request.Context(), user.UserID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "extras": req})
}

// POST /api/profile/notifications (#31) — body {enabled: bool}. Toggles the
// current user's notification switch.
func (h *ProfileHandler) SetNotificationSetting(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	if err := h.Users.SetNotificationsEnabled(c.Request.Context(), user.UserID, req.Enabled); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "enabled": req.Enabled})
}

// GET /api/profile/get?user_id=N
// Bearer required; user_id MUST match the resolved user.
func (h *ProfileHandler) Get(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"status": "error",
			"error":  "Unauthorized request. Please sign in again.",
		})
		return
	}

	uidRaw := c.Query("user_id")
	uid, err := strconv.ParseInt(strings.TrimSpace(uidRaw), 10, 64)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"status": "error",
			"error":  "Missing or invalid user_id.",
		})
		return
	}
	if uid != user.UserID {
		c.JSON(http.StatusForbidden, gin.H{
			"status": "error",
			"error":  "User mismatch for this request.",
		})
		return
	}

	account, err := h.Users.GetAccountForClient(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error",
			"error":  "Database error.",
		})
		return
	}
	if account == nil {
		c.JSON(http.StatusNotFound, gin.H{
			"status": "error",
			"error":  "User not found.",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "account": account})
}

// POST /api/profile/set
// multipart/form-data fields: user_id, full_name, address, gender,
//
//	remove_profile_picture, [file: profile_picture]
//
// Bearer required; user_id MUST match the resolved user.
func (h *ProfileHandler) Set(c *gin.Context) {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Unauthorized request. Please sign in again.",
		})
		return
	}

	uidRaw := c.PostForm("user_id")
	uid, err := strconv.ParseInt(strings.TrimSpace(uidRaw), 10, 64)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "User ID missing or invalid.",
		})
		return
	}
	if uid != user.UserID {
		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "User mismatch for this request.",
		})
		return
	}

	// Collect optional text fields; only set those the client actually sent.
	upd := users.ProfileUpdate{}
	// Name and photo are staff-reviewed (migration 093): the proposal is
	// queued and the live profile is left alone, so a rejected change never
	// shows anywhere. Everything else on this form still applies immediately.
	var queuedName, queuedPicture bool
	if v, exists := getOptionalForm(c, "full_name"); exists {
		if h.Changes != nil {
			cur, _ := h.Users.CurrentFullName(c.Request.Context(), uid)
			if strings.TrimSpace(v) != "" && v != cur {
				if err := h.Changes.Submit(c.Request.Context(),
					uid, profilechanges.FieldFullName, cur, v); err == nil {
					queuedName = true
				}
			}
		} else {
			upd.FullName = &v
		}
	}
	if v, exists := getOptionalForm(c, "address"); exists {
		upd.Address = &v
	}
	if v, exists := getOptionalForm(c, "gender"); exists {
		// Gender is set once, at sign-up, and is not user-editable afterwards.
		// Silently ignoring a change (rather than 400ing) keeps an older app
		// build — which still sends the field on every profile save — working
		// instead of failing every update. Staff can still correct a wrong
		// value from the Admin Panel, which goes through admin_edit, not here.
		current, _ := h.Users.CurrentGender(c.Request.Context(), uid)
		if strings.TrimSpace(current) == "" {
			upd.Gender = &v
		}
	}
	removeRaw := strings.TrimSpace(c.PostForm("remove_profile_picture"))
	upd.RemovePicture = removeRaw == "1" || strings.EqualFold(removeRaw, "true") || strings.EqualFold(removeRaw, "yes")

	// Handle uploaded file (optional). Skip if remove flag is on.
	if !upd.RemovePicture {
		fileHeader, _ := c.FormFile("profile_picture")
		if fileHeader != nil {
			path, err := h.savePicture(uid, fileHeader)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{
					"success": false,
					"error":   "Failed to save profile picture: " + err.Error(),
				})
				return
			}
			if h.Changes != nil {
				cur, _ := h.Users.CurrentPicture(c.Request.Context(), uid)
				if err := h.Changes.Submit(c.Request.Context(),
					uid, profilechanges.FieldPicture, cur, path); err == nil {
					queuedPicture = true
				}
			} else {
				upd.PicturePathSet = &path
			}
		}
	}

	row, err := h.Users.UpsertProfile(c.Request.Context(), uid, upd, "user", uid,
		map[string]any{
			"entry_point":    "api/profile/set",
			"request_method": c.Request.Method,
		})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Failed to update profile. Please check data and try again.",
		})
		return
	}

	resp := gin.H{
		"success":    true,
		"profile_id": row.ProfileID,
		"full_name":  row.FullName,
		"address":    row.Address,
		"gender":     emptyToNil(row.Gender),
	}
	if row.ProfilePicture == "" || row.ProfilePicture == "0" {
		resp["profile_picture"] = nil
	} else {
		resp["profile_picture"] = row.ProfilePicture
	}
	// So the app can say "waiting for approval" instead of appearing to have
	// silently ignored the edit.
	pending := []string{}
	if queuedName {
		pending = append(pending, profilechanges.FieldFullName)
	}
	if queuedPicture {
		pending = append(pending, profilechanges.FieldPicture)
	}
	resp["pending_review"] = pending
	c.JSON(http.StatusOK, resp)
}

// savePicture writes the uploaded file to UploadDir using the
// "profile_<userID>_<unix>.<ext>" convention from PHP, and returns the
// relative path stored in the DB (e.g. "images/profile_3_1776...jpg").
func (h *ProfileHandler) savePicture(userID int64, fh *multipart.FileHeader) (string, error) {
	if err := os.MkdirAll(h.UploadDir, 0o755); err != nil {
		return "", err
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fh.Filename), "."))
	if ext == "" {
		ext = "jpg"
	}
	unique := fmt.Sprintf("profile_%d_%d.%s", userID, time.Now().Unix(), ext)
	abs := filepath.Join(h.UploadDir, unique)

	src, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()
	dst, err := os.OpenFile(abs, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		return "", err
	}
	return "images/" + unique, nil
}

// getOptionalForm returns (value, true) if the form actually included the field,
// (zero, false) otherwise. Distinguishes "field absent" from "field empty".
func getOptionalForm(c *gin.Context, key string) (string, bool) {
	if c.Request.MultipartForm != nil && c.Request.MultipartForm.Value != nil {
		if vals, ok := c.Request.MultipartForm.Value[key]; ok && len(vals) > 0 {
			return strings.TrimSpace(vals[0]), true
		}
	}
	if c.Request.PostForm != nil {
		if vals, ok := c.Request.PostForm[key]; ok && len(vals) > 0 {
			return strings.TrimSpace(vals[0]), true
		}
	}
	return "", false
}

func emptyToNil(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}
