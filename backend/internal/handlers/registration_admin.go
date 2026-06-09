package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// RegistrationAdminHandler serves the admin "Registrations" page — listing
// pending/rejected signups and acting on them. Mounted under /api/admin/*
// (RequireAdmin).
type RegistrationAdminHandler struct {
	Users    *users.Store
	Notifier *notify.Notifier
}

func NewRegistrationAdminHandler(u *users.Store, n *notify.Notifier) *RegistrationAdminHandler {
	return &RegistrationAdminHandler{Users: u, Notifier: n}
}

// GET /api/admin/registrations?status=pending&page=1&per_page=20&q=
func (h *RegistrationAdminHandler) List(c *gin.Context) {
	status := c.DefaultQuery("status", "pending")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "20"))
	q := c.Query("q")

	res, err := h.Users.ListRegistrations(c.Request.Context(), status, page, perPage, q)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to list registrations."})
		return
	}
	// Flat envelope to match the SPA's AdminPageResp<T> (same shape the other
	// admin list endpoints use).
	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"items":       res.Items,
		"page":        res.Pagination.Page,
		"per_page":    res.Pagination.PerPage,
		"total_items": res.Pagination.TotalItems,
		"total_pages": res.Pagination.TotalPages,
		"has_more":    res.Pagination.HasMore,
	})
}

// POST /api/admin/registrations/:id/approve
func (h *RegistrationAdminHandler) Approve(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid user id."})
		return
	}
	var adminID int64
	if admin, ok := auth.UserFromGin(c); ok && admin != nil {
		adminID = admin.UserID
	}

	ok, err := h.Users.ApproveRegistration(c.Request.Context(), id, adminID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to approve registration."})
		return
	}
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"status": "error", "error": "No pending or rejected registration found for this user."})
		return
	}
	if h.Notifier != nil {
		_, _ = h.Notifier.Send(c.Request.Context(), id, notify.RegistrationApprovedMsg(id))
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "registration_status": "approved"})
}

type rejectReq struct {
	Reason string `json:"reason" form:"reason"`
}

// POST /api/admin/registrations/:id/reject  body: { "reason": "..." }
func (h *RegistrationAdminHandler) Reject(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid user id."})
		return
	}
	var body rejectReq
	_ = bindFlexibleJSON(c, &body)

	var adminID int64
	if admin, ok := auth.UserFromGin(c); ok && admin != nil {
		adminID = admin.UserID
	}

	ok, err := h.Users.RejectRegistration(c.Request.Context(), id, adminID, body.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to reject registration."})
		return
	}
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"status": "error", "error": "No pending registration found for this user."})
		return
	}
	if h.Notifier != nil {
		_, _ = h.Notifier.Send(c.Request.Context(), id, notify.RegistrationRejectedMsg(id, body.Reason))
	}
	c.JSON(http.StatusOK, gin.H{"status": "success", "registration_status": "rejected"})
}
