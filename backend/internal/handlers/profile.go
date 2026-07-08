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
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ProfileHandler ports percentage/api/profile/{get,set}/index.php.
type ProfileHandler struct {
	Users     *users.Store
	UploadDir string // absolute path on disk; files are served at /images/*
}

func NewProfileHandler(u *users.Store, uploadDir string) *ProfileHandler {
	return &ProfileHandler{Users: u, UploadDir: uploadDir}
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
//                              remove_profile_picture, [file: profile_picture]
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
	if v, exists := getOptionalForm(c, "full_name"); exists {
		upd.FullName = &v
	}
	if v, exists := getOptionalForm(c, "address"); exists {
		upd.Address = &v
	}
	if v, exists := getOptionalForm(c, "gender"); exists {
		upd.Gender = &v
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
			upd.PicturePathSet = &path
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
