package handlers

import (
	"errors"
	"fmt"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
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
	Users     *users.Store
	UploadDir string // absolute path on disk; files are served at /images/*
}

func NewRegistrationHandler(u *users.Store, uploadDir string) *RegistrationHandler {
	return &RegistrationHandler{Users: u, UploadDir: uploadDir}
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
	// Grantor registration spec — additional grantor-only detail fields.
	NationalID      string   `json:"national_id" form:"national_id"`
	NameFirst       string   `json:"name_first" form:"name_first"`
	NameFather      string   `json:"name_father" form:"name_father"`
	NameGrandfather string   `json:"name_grandfather" form:"name_grandfather"`
	NameFamily      string   `json:"name_family" form:"name_family"`
	TitleSurname    string   `json:"title_surname" form:"title_surname"`
	Phone1          string   `json:"phone1" form:"phone1"`
	Phone2          string   `json:"phone2" form:"phone2"`
	Email           string   `json:"email" form:"email"`
	GPSLat          *float64 `json:"gps_lat" form:"gps_lat"`
	GPSLng          *float64 `json:"gps_lng" form:"gps_lng"`
	Governorate     string   `json:"governorate" form:"governorate"`
	EducationLevel  string   `json:"education_level" form:"education_level"`
	// Eligible Recipient registration spec — additional beneficiary-only
	// detail fields.
	TribeClan       string `json:"tribe_clan" form:"tribe_clan"`
	EmergencyPhone  string `json:"emergency_phone" form:"emergency_phone"`
	Nationality     string `json:"nationality" form:"nationality"`
	MaritalStatus   string `json:"marital_status" form:"marital_status"`
	ResidencyStatus string `json:"residency_status" form:"residency_status"`
	// Eligible Recipient registration spec — "Housing Information" section.
	HousingSide     string `json:"housing_side" form:"housing_side"`
	Neighborhood    string `json:"neighborhood" form:"neighborhood"`
	NearestLandmark string `json:"nearest_landmark" form:"nearest_landmark"`
	HousingType     string `json:"housing_type" form:"housing_type"`
	RentalAmount    string `json:"rental_amount" form:"rental_amount"`
	HousingArea     string `json:"housing_area" form:"housing_area"`
	FloorsCount     string `json:"floors_count" form:"floors_count"`
	RoomsCount      string `json:"rooms_count" form:"rooms_count"`
	FamiliesCount   string `json:"families_count" form:"families_count"`
	// Eligible Recipient registration spec — "Educational and Employment
	// Information", "Employment Status", and "Social Information" sections.
	// (education_level/occupation/monthly_income/family_size above are
	// reused as-is for these sections too.)
	OtherCertificate        string `json:"other_certificate" form:"other_certificate"`
	CertificatesCount       string `json:"certificates_count" form:"certificates_count"`
	PreviousOccupation      string `json:"previous_occupation" form:"previous_occupation"`
	JobDescription          string `json:"job_description" form:"job_description"`
	WorkingHours            string `json:"working_hours" form:"working_hours"`
	IsEmployed              string `json:"is_employed" form:"is_employed"`
	Workplace               string `json:"workplace" form:"workplace"`
	WageAmount              string `json:"wage_amount" form:"wage_amount"`
	RegisteredSocialWelfare string `json:"registered_social_welfare" form:"registered_social_welfare"`
	RegisteredUnemployed    string `json:"registered_unemployed" form:"registered_unemployed"`
	HouseholdEmployeesCount string `json:"household_employees_count" form:"household_employees_count"`
	WorkingMembersCount     string `json:"working_members_count" form:"working_members_count"`
	MenCount                string `json:"men_count" form:"men_count"`
	WomenCount              string `json:"women_count" form:"women_count"`
	MaleChildrenCount       string `json:"male_children_count" form:"male_children_count"`
	FemaleChildrenCount     string `json:"female_children_count" form:"female_children_count"`
	Age0To5Count            string `json:"age_0_5_count" form:"age_0_5_count"`
	Age5To10Count           string `json:"age_5_10_count" form:"age_5_10_count"`
	Age10To15Count          string `json:"age_10_15_count" form:"age_10_15_count"`
	Age15To25Count          string `json:"age_15_25_count" form:"age_15_25_count"`
	Age25To40Count          string `json:"age_25_40_count" form:"age_25_40_count"`
	Age40PlusCount          string `json:"age_40_plus_count" form:"age_40_plus_count"`
	StudentsCount           string `json:"students_count" form:"students_count"`
	OrphansCount            string `json:"orphans_count" form:"orphans_count"`
	WidowsCount             string `json:"widows_count" form:"widows_count"`
	DivorcedCount           string `json:"divorced_count" form:"divorced_count"`
	// Eligible Recipient registration spec — "Health Information", "Assets",
	// "Needs", and "Social Media Accounts" sections.
	Height                 string `json:"height" form:"height"`
	Weight                 string `json:"weight" form:"weight"`
	SmokingStatus          string `json:"smoking_status" form:"smoking_status"`
	EyesightCondition      string `json:"eyesight_condition" form:"eyesight_condition"`
	HasDisability          string `json:"has_disability" form:"has_disability"`
	DisabilityType         string `json:"disability_type" form:"disability_type"`
	HouseholdDisabledCount string `json:"household_disabled_count" form:"household_disabled_count"`
	ChronicIllnesses       string `json:"chronic_illnesses" form:"chronic_illnesses"`
	MedicalConditionsCount string `json:"medical_conditions_count" form:"medical_conditions_count"`
	MedicalConditionsDesc  string `json:"medical_conditions_desc" form:"medical_conditions_desc"`
	AvailableFurniture     string `json:"available_furniture" form:"available_furniture"`
	OwnsCar                string `json:"owns_car" form:"owns_car"`
	NeedsDescription       string `json:"needs_description" form:"needs_description"`
	SocialFacebook         string `json:"social_facebook" form:"social_facebook"`
	SocialInstagram        string `json:"social_instagram" form:"social_instagram"`
	SocialTelegram         string `json:"social_telegram" form:"social_telegram"`
	// Eligible Recipient registration spec — "Privacy" consent section.
	ConsentShowRealName string `json:"consent_show_real_name" form:"consent_show_real_name"`
	ConsentShareInfo    string `json:"consent_share_info" form:"consent_share_info"`
	// Volunteer/Employee registration spec — Personal / Housing / Social Media
	// sections. Everything else that spec asks for reuses the fields above.
	Languages   string `json:"languages" form:"languages"`
	District    string `json:"district" form:"district"`
	SocialOther string `json:"social_other" form:"social_other"`
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
		Gender:          strings.TrimSpace(req.Gender),
		City:            strings.TrimSpace(req.City),
		Occupation:      strings.TrimSpace(req.Occupation),
		FamilySize:      strings.TrimSpace(req.FamilySize),
		HousingStatus:   strings.TrimSpace(req.HousingStatus),
		MonthlyIncome:   strings.TrimSpace(req.MonthlyIncome),
		Skills:          strings.TrimSpace(req.Skills),
		Availability:    strings.TrimSpace(req.Availability),
		Experience:      strings.TrimSpace(req.Experience),
		NationalID:      strings.TrimSpace(req.NationalID),
		NameFirst:       strings.TrimSpace(req.NameFirst),
		NameFather:      strings.TrimSpace(req.NameFather),
		NameGrandfather: strings.TrimSpace(req.NameGrandfather),
		NameFamily:      strings.TrimSpace(req.NameFamily),
		TitleSurname:    strings.TrimSpace(req.TitleSurname),
		Phone1:          strings.TrimSpace(req.Phone1),
		Phone2:          strings.TrimSpace(req.Phone2),
		Email:           strings.TrimSpace(req.Email),
		GPSLat:          req.GPSLat,
		GPSLng:          req.GPSLng,
		Governorate:     strings.TrimSpace(req.Governorate),
		EducationLevel:  strings.TrimSpace(req.EducationLevel),
		TribeClan:       strings.TrimSpace(req.TribeClan),
		EmergencyPhone:  strings.TrimSpace(req.EmergencyPhone),
		Nationality:     strings.TrimSpace(req.Nationality),
		MaritalStatus:   strings.TrimSpace(req.MaritalStatus),
		ResidencyStatus: strings.TrimSpace(req.ResidencyStatus),
		HousingSide:     strings.TrimSpace(req.HousingSide),
		Neighborhood:    strings.TrimSpace(req.Neighborhood),
		NearestLandmark: strings.TrimSpace(req.NearestLandmark),
		HousingType:     strings.TrimSpace(req.HousingType),
		RentalAmount:    strings.TrimSpace(req.RentalAmount),
		HousingArea:     strings.TrimSpace(req.HousingArea),
		FloorsCount:     strings.TrimSpace(req.FloorsCount),
		RoomsCount:      strings.TrimSpace(req.RoomsCount),
		FamiliesCount:   strings.TrimSpace(req.FamiliesCount),
	})
	if err != nil {
		if errors.Is(err, users.ErrRegistrationNotSubmittable) {
			c.JSON(http.StatusConflict, gin.H{"status": "error", "error": "Registration cannot be submitted in its current state."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to submit registration."})
		return
	}

	// Eligible Recipient registration spec — "Educational and Employment
	// Information" / "Employment Status" / "Social Information" sections.
	// Recipient-only, and kept as a separate write (see SetRecipientDetails)
	// so this large field set can't risk the core registration write above.
	if req.RoleID == 2 {
		if err := h.Users.SetRecipientDetails(c.Request.Context(), tokenUser.UserID, users.RecipientDetailsExtras{
			OtherCertificate:        strings.TrimSpace(req.OtherCertificate),
			CertificatesCount:       strings.TrimSpace(req.CertificatesCount),
			PreviousOccupation:      strings.TrimSpace(req.PreviousOccupation),
			JobDescription:          strings.TrimSpace(req.JobDescription),
			WorkingHours:            strings.TrimSpace(req.WorkingHours),
			IsEmployed:              strings.TrimSpace(req.IsEmployed),
			Workplace:               strings.TrimSpace(req.Workplace),
			WageAmount:              strings.TrimSpace(req.WageAmount),
			RegisteredSocialWelfare: strings.TrimSpace(req.RegisteredSocialWelfare),
			RegisteredUnemployed:    strings.TrimSpace(req.RegisteredUnemployed),
			HouseholdEmployeesCount: strings.TrimSpace(req.HouseholdEmployeesCount),
			WorkingMembersCount:     strings.TrimSpace(req.WorkingMembersCount),
			MenCount:                strings.TrimSpace(req.MenCount),
			WomenCount:              strings.TrimSpace(req.WomenCount),
			MaleChildrenCount:       strings.TrimSpace(req.MaleChildrenCount),
			FemaleChildrenCount:     strings.TrimSpace(req.FemaleChildrenCount),
			Age0To5Count:            strings.TrimSpace(req.Age0To5Count),
			Age5To10Count:           strings.TrimSpace(req.Age5To10Count),
			Age10To15Count:          strings.TrimSpace(req.Age10To15Count),
			Age15To25Count:          strings.TrimSpace(req.Age15To25Count),
			Age25To40Count:          strings.TrimSpace(req.Age25To40Count),
			Age40PlusCount:          strings.TrimSpace(req.Age40PlusCount),
			StudentsCount:           strings.TrimSpace(req.StudentsCount),
			OrphansCount:            strings.TrimSpace(req.OrphansCount),
			WidowsCount:             strings.TrimSpace(req.WidowsCount),
			DivorcedCount:           strings.TrimSpace(req.DivorcedCount),
		}); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save additional details."})
			return
		}
		// "Health Information" / "Assets" / "Needs" / "Social Media Accounts".
		if err := h.Users.SetRecipientHealthDetails(c.Request.Context(), tokenUser.UserID, users.RecipientHealthExtras{
			Height:                 strings.TrimSpace(req.Height),
			Weight:                 strings.TrimSpace(req.Weight),
			SmokingStatus:          strings.TrimSpace(req.SmokingStatus),
			EyesightCondition:      strings.TrimSpace(req.EyesightCondition),
			HasDisability:          strings.TrimSpace(req.HasDisability),
			DisabilityType:         strings.TrimSpace(req.DisabilityType),
			HouseholdDisabledCount: strings.TrimSpace(req.HouseholdDisabledCount),
			ChronicIllnesses:       strings.TrimSpace(req.ChronicIllnesses),
			MedicalConditionsCount: strings.TrimSpace(req.MedicalConditionsCount),
			MedicalConditionsDesc:  strings.TrimSpace(req.MedicalConditionsDesc),
			AvailableFurniture:     strings.TrimSpace(req.AvailableFurniture),
			OwnsCar:                strings.TrimSpace(req.OwnsCar),
			NeedsDescription:       strings.TrimSpace(req.NeedsDescription),
			SocialFacebook:         strings.TrimSpace(req.SocialFacebook),
			SocialInstagram:        strings.TrimSpace(req.SocialInstagram),
			SocialTelegram:         strings.TrimSpace(req.SocialTelegram),
		}); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save additional details."})
			return
		}
		// "Privacy" — consent to show the real name / share information with
		// a grantor.
		if err := h.Users.SetRecipientConsent(c.Request.Context(), tokenUser.UserID,
			strings.TrimSpace(req.ConsentShowRealName), strings.TrimSpace(req.ConsentShareInfo)); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save privacy consent."})
			return
		}
	}

	// H23 — the donor's auto-generated identification code, assigned once on
	// first registration for role 1. Recipients (ER-) and volunteers (VL-,
	// just below) already had one; the donor did not, so a donor could only be
	// referred to by their real name. Same shape as the volunteer branch.
	if req.RoleID == 1 {
		if err := h.Users.EnsureGrantorCode(c.Request.Context(), tokenUser.UserID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to assign grantor code."})
			return
		}
	}

	// Volunteer/Employee spec — auto-generated identification code (assigned
	// once on first registration for that role) plus the volunteer-only
	// Personal/Housing/Social Media columns.
	if req.RoleID == 3 {
		if err := h.Users.EnsureVolunteerCode(c.Request.Context(), tokenUser.UserID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to assign volunteer code."})
			return
		}
		if err := h.Users.SetVolunteerProfile(c.Request.Context(), tokenUser.UserID, users.VolunteerProfileExtras{
			Languages:   strings.TrimSpace(req.Languages),
			District:    strings.TrimSpace(req.District),
			SocialOther: strings.TrimSpace(req.SocialOther),
		}); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save volunteer details."})
			return
		}
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

// POST /api/registration/photos
// multipart/form-data, Bearer required (pre-approval group, same as Submit).
// Optional file fields: personal_photo, id_photo. Grantor Registration spec
// — both attachments are optional, so a request with neither is a no-op
// success rather than an error.
func (h *RegistrationHandler) UploadPhotos(c *gin.Context) {
	tokenUser, ok := auth.UserFromGin(c)
	if !ok || tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}

	var personalPath, idPath string
	if fh, _ := c.FormFile("personal_photo"); fh != nil {
		p, err := h.savePhoto(tokenUser.UserID, "personal", fh)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Failed to save personal photo: " + err.Error()})
			return
		}
		personalPath = p
	}
	if fh, _ := c.FormFile("id_photo"); fh != nil {
		p, err := h.savePhoto(tokenUser.UserID, "idcard", fh)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Failed to save ID card photo: " + err.Error()})
			return
		}
		idPath = p
	}

	if err := h.Users.SetGrantorPhotos(c.Request.Context(), tokenUser.UserID, personalPath, idPath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save photos."})
		return
	}

	// Eligible Recipient spec — "Attachments" section. Each is optional, so a
	// request carrying none of them stays a no-op success (same as above).
	type attachment struct {
		formKey string
		kind    string
		dest    *string
	}
	var rationCard, propertyProof, medicalReport string
	var houseFacade, houseInside, houseOutside string
	// Volunteer/Employee spec — "Attachments".
	var goldenSquare, residenceCard, passport, graduationCert, cv string
	for _, f := range []attachment{
		{"ration_card_photo", "rationcard", &rationCard},
		{"property_proof_photo", "propertyproof", &propertyProof},
		{"medical_report_photo", "medicalreport", &medicalReport},
		{"house_facade_photo", "housefacade", &houseFacade},
		{"house_inside_photo", "houseinside", &houseInside},
		{"house_outside_photo", "houseoutside", &houseOutside},
		{"golden_square_photo", "goldensquare", &goldenSquare},
		{"residence_card_photo", "residencecard", &residenceCard},
		{"passport_photo", "passport", &passport},
		{"graduation_cert_photo", "graduationcert", &graduationCert},
		{"cv_photo", "cv", &cv},
	} {
		fh, _ := c.FormFile(f.formKey)
		if fh == nil {
			continue
		}
		p, err := h.savePhoto(tokenUser.UserID, f.kind, fh)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Failed to save " + f.formKey + ": " + err.Error()})
			return
		}
		*f.dest = p
	}
	if err := h.Users.SetRecipientAttachments(c.Request.Context(), tokenUser.UserID,
		rationCard, propertyProof, medicalReport, houseFacade, houseInside, houseOutside); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save attachments."})
		return
	}
	if err := h.Users.SetVolunteerAttachments(c.Request.Context(), tokenUser.UserID,
		goldenSquare, residenceCard, passport, graduationCert, cv); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to save attachments."})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":                    "success",
		"personal_photo_set":        personalPath != "",
		"id_photo_set":              idPath != "",
		"ration_card_photo_set":     rationCard != "",
		"property_proof_photo_set":  propertyProof != "",
		"medical_report_photo_set":  medicalReport != "",
		"house_facade_photo_set":    houseFacade != "",
		"house_inside_photo_set":    houseInside != "",
		"house_outside_photo_set":   houseOutside != "",
		"golden_square_photo_set":   goldenSquare != "",
		"residence_card_photo_set":  residenceCard != "",
		"passport_photo_set":        passport != "",
		"graduation_cert_photo_set": graduationCert != "",
		"cv_photo_set":              cv != "",
	})
}

// savePhoto writes an uploaded file to UploadDir using a
// "<kind>_<userID>_<unix>.<ext>" convention and returns the relative path
// stored in the DB (served at /images/<name>).
func (h *RegistrationHandler) savePhoto(userID int64, kind string, fh *multipart.FileHeader) (string, error) {
	if err := os.MkdirAll(h.UploadDir, 0o755); err != nil {
		return "", err
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fh.Filename), "."))
	if ext == "" {
		ext = "jpg"
	}
	unique := fmt.Sprintf("%s_%d_%d.%s", kind, userID, time.Now().Unix(), ext)
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
	if _, err := dst.ReadFrom(src); err != nil {
		return "", err
	}
	return "images/" + unique, nil
}
