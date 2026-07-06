package handlers

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
)

// DonationCodesHandler manages the per-section transaction-code namespaces (#14):
// list the sections and edit each section's code prefix. Reference numbers are
// then issued as {PREFIX}-{seq} per section (e.g. CAM-000042).
type DonationCodesHandler struct {
	Store *sectioncodes.Store
}

func NewDonationCodesHandler(s *sectioncodes.Store) *DonationCodesHandler {
	return &DonationCodesHandler{Store: s}
}

// prefixPattern bounds a prefix to 1–16 uppercase letters/digits so generated
// references stay clean and predictable.
var prefixPattern = regexp.MustCompile(`^[A-Z0-9]{1,16}$`)

// List handles GET /api/admin/donation-codes — every section's prefix + next #.
func (h *DonationCodesHandler) List(c *gin.Context) {
	codes, err := h.Store.List(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "codes": codes})
}

type updatePrefixReq struct {
	Prefix        string `json:"prefix"`
	NotifyPhone   string `json:"notify_phone"`
	NotifyEnabled bool   `json:"notify_enabled"`
}

// UpdatePrefix handles PUT /api/admin/donation-codes/:kind — set a section's
// prefix. The kind must be one of the known donation kinds.
func (h *DonationCodesHandler) UpdatePrefix(c *gin.Context) {
	kind := c.Param("kind")
	if !inSet(kind, donationKinds) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Unknown donation section."})
		return
	}
	var req updatePrefixReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
		return
	}
	prefix := strings.ToUpper(strings.TrimSpace(req.Prefix))
	if !prefixPattern.MatchString(prefix) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Prefix must be 1–16 letters or digits."})
		return
	}
	phone := digitsOnly(req.NotifyPhone)
	if phone != "" && (len(phone) < 7 || len(phone) > 20) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Notify phone must be 7–20 digits."})
		return
	}

	var updatedBy int64
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		updatedBy = actor.UserID
	}
	if err := h.Store.UpdateSection(c.Request.Context(), kind, prefix, phone, req.NotifyEnabled, updatedBy); err != nil {
		if errors.Is(err, sectioncodes.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Donation section not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "kind": kind, "prefix": prefix, "notify_phone": phone, "notify_enabled": req.NotifyEnabled})
}
