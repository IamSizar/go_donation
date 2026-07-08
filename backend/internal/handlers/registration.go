package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// RegistrationHandler serves the new-user onboarding endpoints. These are
// mounted under a Bearer-only group (NOT the approval gate), so an
// 'incomplete' or 'rejected' user can still submit/check their registration.
type RegistrationHandler struct {
	Users *users.Store
}

func NewRegistrationHandler(u *users.Store) *RegistrationHandler {
	return &RegistrationHandler{Users: u}
}

type registrationSubmitReq struct {
	FullName    string `json:"full_name" form:"full_name"`
	DateOfBirth string `json:"date_of_birth" form:"date_of_birth"`
	Address     string `json:"address" form:"address"`
	RoleID      int    `json:"role_id" form:"role_id"`
	// #39 — optional fuller sign-up fields (grantor form; reused by #40/#41).
	Gender     string `json:"gender" form:"gender"`
	City       string `json:"city" form:"city"`
	Occupation string `json:"occupation" form:"occupation"`
	// #40 — eligible (beneficiary) fields.
	FamilySize    string `json:"family_size" form:"family_size"`
	HousingStatus string `json:"housing_status" form:"housing_status"`
	MonthlyIncome string `json:"monthly_income" form:"monthly_income"`
	// #41 — volunteer/employee fields.
	Skills       string `json:"skills" form:"skills"`
	Availability string `json:"availability" form:"availability"`
	Experience   string `json:"experience" form:"experience"`
}

// POST /api/registration/submit
// Bearer required. Stores the profile (name/DOB/address), assigns the chosen
// role, and moves the user to 'pending' for admin review.
func (h *RegistrationHandler) Submit(c *gin.Context) {
	tokenUser, ok := auth.UserFromGin(c)
	if !ok || tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}

	var req registrationSubmitReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	fullName := strings.TrimSpace(req.FullName)
	address := strings.TrimSpace(req.Address)
	dob := strings.TrimSpace(req.DateOfBirth)

	if fullName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Full name is required."})
		return
	}
	if address == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Address is required."})
		return
	}
	if req.RoleID < 1 || req.RoleID > 3 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Please select a valid role."})
		return
	}
	if dob != "" && !validDateYMD(dob) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Date of birth must be in YYYY-MM-DD format."})
		return
	}

	newStatus, err := h.Users.SubmitRegistration(c.Request.Context(), tokenUser.UserID, fullName, dob, address, req.RoleID, users.RegistrationExtras{
		Gender:        strings.TrimSpace(req.Gender),
		City:          strings.TrimSpace(req.City),
		Occupation:    strings.TrimSpace(req.Occupation),
		FamilySize:    strings.TrimSpace(req.FamilySize),
		HousingStatus: strings.TrimSpace(req.HousingStatus),
		MonthlyIncome: strings.TrimSpace(req.MonthlyIncome),
		Skills:        strings.TrimSpace(req.Skills),
		Availability:  strings.TrimSpace(req.Availability),
		Experience:    strings.TrimSpace(req.Experience),
	})
	if err != nil {
		if errors.Is(err, users.ErrRegistrationNotSubmittable) {
			c.JSON(http.StatusConflict, gin.H{"status": "error", "error": "Registration cannot be submitted in its current state."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to submit registration."})
		return
	}

	msg := "Registration submitted for approval."
	if newStatus == "approved" {
		msg = "Profile saved." // grandfathered user just completing their role/profile
	}
	c.JSON(http.StatusOK, gin.H{
		"status":              "success",
		"message":             msg,
		"registration_status": newStatus,
	})
}

// GET /api/registration/status
// Bearer required. Lets the pending-approval screen poll the current decision.
func (h *RegistrationHandler) Status(c *gin.Context) {
	tokenUser, ok := auth.UserFromGin(c)
	if !ok || tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}
	ctx := c.Request.Context()
	status, reason, roleID, err := h.Users.GetRegistrationState(ctx, tokenUser.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to read registration status."})
		return
	}
	if status == "" {
		status = "approved" // legacy / grandfathered safety
	}
	// Include the submitted profile so the pending/rejected screen can show the
	// real name/address/DOB the user entered (robust across devices/reinstalls,
	// not dependent on a local pref).
	fullName, address, dob := "", "", ""
	if pr, _ := h.Users.GetProfileRow(ctx, tokenUser.UserID); pr != nil {
		fullName, address, dob = pr.FullName, pr.Address, pr.DateOfBirth
	}
	c.JSON(http.StatusOK, gin.H{
		"status":              "success",
		"registration_status": status,
		"reject_reason":       reason,
		"role_id":             roleID,
		"has_role":            roleID > 0,
		"full_name":           fullName,
		"address":             address,
		"date_of_birth":       dob,
	})
}

// validDateYMD reports whether s parses as a calendar date "YYYY-MM-DD".
func validDateYMD(s string) bool {
	_, err := time.Parse("2006-01-02", s)
	return err == nil
}
