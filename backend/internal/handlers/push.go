package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// PushHandler exposes admin-only push composition.
type PushHandler struct {
	Notifier *notify.Notifier
}

func NewPushHandler(n *notify.Notifier) *PushHandler {
	return &PushHandler{Notifier: n}
}

type pushReq struct {
	DeviceToken string `json:"device_token"`
	UserID      int64  `json:"user_id"`
	RoleID      int    `json:"role_id"`     // 1=donor, 2=beneficiary, 3=volunteer
	AllUsers    bool   `json:"all_users"`   // broadcast — every active device
	Title       string `json:"title"`
	Body        string `json:"body"`
	ImageURL    string `json:"image_url"`
}

// GET /api/admin/push/status — quick check from the SPA before showing the form.
// Phase 27.4 — also returns active_devices so the admin sees how many devices
// a broadcast would actually reach BEFORE clicking Send. Catches the "I
// chose all_users but got 0 sends" mystery early.
func (h *PushHandler) Status(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	count, err := h.Notifier.ActiveDeviceCount(c.Request.Context())
	if err != nil {
		// Don't 500 — the form still works without the count.
		count = -1
	}
	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"fcm_enabled":    h.Notifier.FCMConfigured(),
		"active_devices": count,
	})
}

// POST /api/admin/push/send — send a push to a specific device or to all
// active devices of a user_id.
func (h *PushHandler) Send(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	var req pushReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON."})
		return
	}
	req.DeviceToken = strings.TrimSpace(req.DeviceToken)
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	req.ImageURL = strings.TrimSpace(req.ImageURL)

	if req.Title == "" || req.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "title and body are required."})
		return
	}
	if req.DeviceToken == "" && req.UserID <= 0 && req.RoleID <= 0 && !req.AllUsers {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Provide one of: device_token, user_id, role_id, or all_users.",
		})
		return
	}

	results, err := h.Notifier.SendPushDirect(
		c.Request.Context(), req.DeviceToken, req.UserID, req.RoleID, req.AllUsers,
		req.Title, req.Body, req.ImageURL,
	)
	if err != nil {
		if errors.Is(err, notify.ErrFCMDisabled) {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"success": false,
				"error":   "FCM is not configured on the server. Drop your service-account JSON at backend/firebase-credentials.json (or set FIREBASE_CREDENTIALS_FILE) and restart.",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}
	okCount := 0
	for _, r := range results {
		if r.OK {
			okCount++
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"sent":     okCount,
		"attempts": len(results),
		"results":  results,
	})
}
