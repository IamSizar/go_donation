package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// NotificationsHandler ports percentage/api/notifications/index.php and adds
// device-token register/unregister endpoints that the Flutter app needs.
type NotificationsHandler struct {
	Notifier *notify.Notifier
}

func NewNotificationsHandler(n *notify.Notifier) *NotificationsHandler {
	return &NotificationsHandler{Notifier: n}
}

// GET /api/notifications?user_id=N&role_id=R&category=&type=&read_status=&limit=
// Bearer required; user_id MUST match the token's user.
func (h *NotificationsHandler) List(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	uid, _ := strconv.ParseInt(strings.TrimSpace(c.Query("user_id")), 10, 64)
	if uid > 0 && uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request."})
		return
	}
	if uid == 0 {
		uid = tokenUser.UserID
	}
	roleID, _ := strconv.Atoi(strings.TrimSpace(c.Query("role_id")))
	limit, _ := strconv.Atoi(strings.TrimSpace(c.Query("limit")))

	readStatus := strings.ToLower(strings.TrimSpace(c.Query("read_status")))
	if readStatus == "" && c.Query("unread_only") == "1" {
		readStatus = "unread"
	}

	items, err := h.Notifier.List(c.Request.Context(), notify.ListFilter{
		UserID:     uid,
		RoleID:     roleID,
		Category:   c.Query("category"),
		Type:       c.Query("type"),
		ReadStatus: readStatus,
		Limit:      limit,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}

// POST /api/notifications  (action=mark_read)
// Body fields: action, id (or notification_id), user_id. JSON or form.
// Bearer required; user_id MUST match the token.
func (h *NotificationsHandler) Post(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	action := strings.TrimSpace(asStr(data["action"]))
	notifID := int64(asInt(data["id"]))
	if notifID == 0 {
		notifID = int64(asInt(data["notification_id"]))
	}
	uid := int64(asInt(data["user_id"]))
	if uid <= 0 {
		uid = tokenUser.UserID
	}

	if action != "mark_read" || notifID <= 0 || uid <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing notification read data."})
		return
	}
	if uid != tokenUser.UserID {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized request."})
		return
	}

	res, err := h.Notifier.MarkRead(c.Request.Context(), notifID, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	if res == notify.MarkNotFound {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Notification not found."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// POST /api/notifications/device  — register/upsert an FCM device token for the
// authenticated user. Body: device_token, platform, device_id, app_version.
func (h *NotificationsHandler) RegisterDevice(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	data := collectBody(c)
	deviceToken := strings.TrimSpace(asStr(data["device_token"]))
	if deviceToken == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing device_token."})
		return
	}
	platform := strings.TrimSpace(asStr(data["platform"]))
	deviceID := strings.TrimSpace(asStr(data["device_id"]))
	appVersion := strings.TrimSpace(asStr(data["app_version"]))
	// Phase 27.3 — preferred language for push notifications. The Flutter
	// app sends "en" | "ar" | "ckb" | "kmr"; anything else (or missing)
	// stays NULL in the DB and sendPush falls back to EN.
	localeCode := strings.TrimSpace(asStr(data["locale_code"]))

	if err := h.Notifier.RegisterDevice(
		c.Request.Context(),
		tokenUser.UserID, tokenUser.RoleID,
		deviceToken, platform, deviceID, appVersion, localeCode,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to register device."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DELETE /api/notifications/device  — unregister (mark inactive).
// Body or query: device_token.
func (h *NotificationsHandler) UnregisterDevice(c *gin.Context) {
	tokenUser, _ := auth.UserFromGin(c)
	if tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	deviceToken := strings.TrimSpace(c.Query("device_token"))
	if deviceToken == "" {
		data := collectBody(c)
		deviceToken = strings.TrimSpace(asStr(data["device_token"]))
	}
	if deviceToken == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Missing device_token."})
		return
	}
	_, err := h.Notifier.UnregisterDevice(c.Request.Context(), tokenUser.UserID, deviceToken)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Failed to unregister device."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
