package users

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// ErrRegistrationNotSubmittable is returned by SubmitRegistration when the
// user's row can't move to 'pending' — i.e. it doesn't exist, or it's already
// 'approved' (an approved user re-registering is a no-op the handler maps to
// 409). Submitting from 'incomplete', 'pending' (idempotent) or 'rejected'
// (re-submit after a rejection) all succeed.
var ErrRegistrationNotSubmittable = errors.New("registration not submittable in current status")

// SubmitRegistration is the new-user onboarding write: it stores the profile
// fields the registration form collects (name, date of birth, address),
// assigns the chosen role, and moves the user to 'pending' so an admin can
// review them. It runs in a single transaction so role+status+profile never
// drift apart. gender is left untouched (defaults to ” on first insert) —
// the registration form doesn't collect it.
// Returns the resulting registration_status ("pending" for new/rejected users,
// or "approved" when an already-approved user is just completing their role/
// profile — e.g. a grandfathered account that never picked a role).
// RegistrationExtras carries the optional fuller sign-up fields (#39). Empty
// strings mean "not provided" and never overwrite an existing value.
type RegistrationExtras struct {
	Gender     string
	City       string
	Occupation string
	// #40 — eligible (beneficiary) fields. FamilySize is a numeric string.
	FamilySize    string
	HousingStatus string
	MonthlyIncome string
	// #41 — volunteer/employee fields.
	Skills       string
	Availability string
	Experience   string
	// Grantor registration spec — additional grantor-only detail fields.
	// GPSLat/GPSLng are nil when not provided.
	NationalID      string
	NameFirst       string
	NameFather      string
	NameGrandfather string
	NameFamily      string
	TitleSurname    string
	Phone1          string
	Phone2          string
	Email           string
	GPSLat          *float64
	GPSLng          *float64
	Governorate     string
	EducationLevel  string
	// Eligible Recipient registration spec — additional beneficiary-only
	// detail fields (NationalID, NameFirst/Father/Grandfather/Family,
	// TitleSurname, Phone1/Phone2, Email above are shared with the grantor
	// fields and reused as-is).
	TribeClan       string
	EmergencyPhone  string
	Nationality     string
	MaritalStatus   string
	ResidencyStatus string
	// Eligible Recipient registration spec — "Housing Information" section.
	HousingSide     string
	Neighborhood    string
	NearestLandmark string
	HousingType     string
	RentalAmount    string
	HousingArea     string
	FloorsCount     string
	RoomsCount      string
	FamiliesCount   string
}

func (s *Store) SubmitRegistration(ctx context.Context, userID int64, fullName, dob, address string, roleID int, extras RegistrationExtras) (string, error) {
	if userID <= 0 {
		return "", errors.New("invalid userID")
	}
	fullName = strings.TrimSpace(fullName)
	address = strings.TrimSpace(address)
	dob = strings.TrimSpace(dob)
	gender := strings.TrimSpace(extras.Gender)
	city := strings.TrimSpace(extras.City)
	occupation := strings.TrimSpace(extras.Occupation)
	housingStatus := strings.TrimSpace(extras.HousingStatus)
	monthlyIncome := strings.TrimSpace(extras.MonthlyIncome)
	skills := strings.TrimSpace(extras.Skills)
	availability := strings.TrimSpace(extras.Availability)
	experience := strings.TrimSpace(extras.Experience)
	var familySize *int
	if v := strings.TrimSpace(extras.FamilySize); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			familySize = &n
		}
	}
	nationalID := strings.TrimSpace(extras.NationalID)
	nameFirst := strings.TrimSpace(extras.NameFirst)
	nameFather := strings.TrimSpace(extras.NameFather)
	nameGrandfather := strings.TrimSpace(extras.NameGrandfather)
	nameFamily := strings.TrimSpace(extras.NameFamily)
	titleSurname := strings.TrimSpace(extras.TitleSurname)
	phone1 := strings.TrimSpace(extras.Phone1)
	phone2 := strings.TrimSpace(extras.Phone2)
	email := strings.TrimSpace(extras.Email)
	governorate := strings.TrimSpace(extras.Governorate)
	educationLevel := strings.TrimSpace(extras.EducationLevel)
	tribeClan := strings.TrimSpace(extras.TribeClan)
	emergencyPhone := strings.TrimSpace(extras.EmergencyPhone)
	nationality := strings.TrimSpace(extras.Nationality)
	maritalStatus := strings.TrimSpace(extras.MaritalStatus)
	residencyStatus := strings.TrimSpace(extras.ResidencyStatus)
	housingSide := strings.TrimSpace(extras.HousingSide)
	neighborhood := strings.TrimSpace(extras.Neighborhood)
	nearestLandmark := strings.TrimSpace(extras.NearestLandmark)
	housingType := strings.TrimSpace(extras.HousingType)
	rentalAmount := strings.TrimSpace(extras.RentalAmount)
	housingArea := strings.TrimSpace(extras.HousingArea)
	floorsCount := strings.TrimSpace(extras.FloorsCount)
	roomsCount := strings.TrimSpace(extras.RoomsCount)
	familiesCount := strings.TrimSpace(extras.FamiliesCount)
	// Eligible Recipient spec — auto-generated identification code, assigned
	// once at first registration for the beneficiary role.
	var recipientCode string
	if roleID == 2 {
		recipientCode = fmt.Sprintf("ER-%06d", userID)
	}
	if fullName == "" {
		return "", errors.New("full_name required")
	}
	if roleID < 1 || roleID > 3 {
		return "", errors.New("invalid role_id")
	}

	var dobArg any = nil
	if dob != "" {
		dobArg = dob
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	// Upsert the profile row (name/address/DOB). user_profiles columns are
	// NOT NULL, so a fresh insert seeds gender='' and profile_picture='0'.
	var one int
	err = tx.QueryRow(ctx, `SELECT 1 FROM user_profiles WHERE user_id = $1`, userID).Scan(&one)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		if _, err = tx.Exec(ctx,
			`INSERT INTO user_profiles (
			   user_id, full_name, address, gender, profile_picture, date_of_birth,
			   city, occupation, family_size, housing_status, monthly_income, skills, availability, experience,
			   national_id, name_first, name_father, name_grandfather, name_family, title_surname,
			   phone1, phone2, email, gps_lat, gps_lng, governorate, education_level,
			   tribe_clan, emergency_phone, nationality, marital_status, residency_status, recipient_code,
			   housing_side, neighborhood, nearest_landmark, housing_type, rental_amount, housing_area, floors_count, rooms_count, families_count
			 )
			 VALUES ($1, $2, $3, $4, '0', $5, $6, $7, $8, $9, $10, $11, $12, $13,
			         $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26,
			         $27, $28, $29, $30, $31, $32,
			         $33, $34, $35, $36, $37, $38, $39, $40, $41)`,
			userID, fullName, address, gender, dobArg, city, occupation, familySize, housingStatus, monthlyIncome, skills, availability, experience,
			nationalID, nameFirst, nameFather, nameGrandfather, nameFamily, titleSurname,
			phone1, phone2, email, extras.GPSLat, extras.GPSLng, governorate, educationLevel,
			tribeClan, emergencyPhone, nationality, maritalStatus, residencyStatus, recipientCode,
			housingSide, neighborhood, nearestLandmark, housingType, rentalAmount, housingArea, floorsCount, roomsCount, familiesCount,
		); err != nil {
			return "", err
		}
	case err != nil:
		return "", err
	default:
		// #39 — non-empty extras update; empty values keep the existing value.
		if _, err = tx.Exec(ctx,
			`UPDATE user_profiles
			    SET full_name = $1, address = $2, date_of_birth = $3,
			        gender           = CASE WHEN $5 <> '' THEN $5 ELSE gender END,
			        city             = COALESCE(NULLIF($6, ''), city),
			        occupation       = COALESCE(NULLIF($7, ''), occupation),
			        family_size      = COALESCE($8, family_size),
			        housing_status   = COALESCE(NULLIF($9, ''), housing_status),
			        monthly_income   = COALESCE(NULLIF($10, ''), monthly_income),
			        skills           = COALESCE(NULLIF($11, ''), skills),
			        availability     = COALESCE(NULLIF($12, ''), availability),
			        experience       = COALESCE(NULLIF($13, ''), experience),
			        national_id      = COALESCE(NULLIF($14, ''), national_id),
			        name_first       = COALESCE(NULLIF($15, ''), name_first),
			        name_father      = COALESCE(NULLIF($16, ''), name_father),
			        name_grandfather = COALESCE(NULLIF($17, ''), name_grandfather),
			        name_family      = COALESCE(NULLIF($18, ''), name_family),
			        title_surname    = COALESCE(NULLIF($19, ''), title_surname),
			        phone1           = COALESCE(NULLIF($20, ''), phone1),
			        phone2           = COALESCE(NULLIF($21, ''), phone2),
			        email            = COALESCE(NULLIF($22, ''), email),
			        gps_lat          = COALESCE($23, gps_lat),
			        gps_lng          = COALESCE($24, gps_lng),
			        governorate      = COALESCE(NULLIF($25, ''), governorate),
			        education_level  = COALESCE(NULLIF($26, ''), education_level),
			        tribe_clan       = COALESCE(NULLIF($27, ''), tribe_clan),
			        emergency_phone  = COALESCE(NULLIF($28, ''), emergency_phone),
			        nationality      = COALESCE(NULLIF($29, ''), nationality),
			        marital_status   = COALESCE(NULLIF($30, ''), marital_status),
			        residency_status = COALESCE(NULLIF($31, ''), residency_status),
			        recipient_code   = CASE WHEN recipient_code = '' AND $32 <> '' THEN $32 ELSE recipient_code END,
			        housing_side      = COALESCE(NULLIF($33, ''), housing_side),
			        neighborhood      = COALESCE(NULLIF($34, ''), neighborhood),
			        nearest_landmark  = COALESCE(NULLIF($35, ''), nearest_landmark),
			        housing_type      = COALESCE(NULLIF($36, ''), housing_type),
			        rental_amount     = COALESCE(NULLIF($37, ''), rental_amount),
			        housing_area      = COALESCE(NULLIF($38, ''), housing_area),
			        floors_count      = COALESCE(NULLIF($39, ''), floors_count),
			        rooms_count       = COALESCE(NULLIF($40, ''), rooms_count),
			        families_count    = COALESCE(NULLIF($41, ''), families_count)
			  WHERE user_id = $4`,
			fullName, address, dobArg, userID, gender, city, occupation, familySize, housingStatus, monthlyIncome, skills, availability, experience,
			nationalID, nameFirst, nameFather, nameGrandfather, nameFamily, titleSurname,
			phone1, phone2, email, extras.GPSLat, extras.GPSLng, governorate, educationLevel,
			tribeClan, emergencyPhone, nationality, maritalStatus, residencyStatus, recipientCode,
			housingSide, neighborhood, nearestLandmark, housingType, rentalAmount, housingArea, floorsCount, roomsCount, familiesCount,
		); err != nil {
			return "", err
		}
	}

	// Assign role + move to pending — UNLESS the user is already approved
	// (a grandfathered account completing its role/profile), in which case the
	// approval is preserved. RETURNING gives us the resulting status; no row
	// means the user id doesn't exist.
	var newStatus string
	err = tx.QueryRow(ctx,
		`UPDATE users
		    SET role_id = $1,
		        registration_status        = CASE WHEN registration_status = 'approved' THEN 'approved' ELSE 'pending' END,
		        registration_submitted_at  = CASE WHEN registration_status = 'approved' THEN registration_submitted_at ELSE NOW() END,
		        registration_reviewed_at   = CASE WHEN registration_status = 'approved' THEN registration_reviewed_at ELSE NULL END,
		        registration_reviewed_by   = CASE WHEN registration_status = 'approved' THEN registration_reviewed_by ELSE NULL END,
		        registration_reject_reason = NULL
		  WHERE id = $2
		  RETURNING registration_status`,
		roleID, userID,
	).Scan(&newStatus)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrRegistrationNotSubmittable
		}
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return newStatus, nil
}

// SetGrantorPhotos stores the optional personal/ID-card photos captured
// during grantor registration (Grantor Registration spec). Called after
// SubmitRegistration, once the user_profiles row is guaranteed to exist.
// Only non-empty paths are written; the other column is left untouched.
func (s *Store) SetGrantorPhotos(ctx context.Context, userID int64, personalPhotoPath, idPhotoPath string) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	if personalPhotoPath == "" && idPhotoPath == "" {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET profile_picture = CASE WHEN $2 <> '' THEN $2 ELSE profile_picture END,
		        id_photo_path   = CASE WHEN $3 <> '' THEN $3 ELSE id_photo_path END
		  WHERE user_id = $1`,
		userID, personalPhotoPath, idPhotoPath,
	)
	return err
}

// RecipientDetailsExtras carries the Eligible Recipient "Educational and
// Employment Information", "Employment Status", and "Social Information"
// sections. Empty strings mean "not provided" and never overwrite an
// existing value — same COALESCE(NULLIF(...)) convention as SubmitRegistration.
type RecipientDetailsExtras struct {
	OtherCertificate        string
	CertificatesCount       string
	PreviousOccupation      string
	JobDescription          string
	WorkingHours            string
	IsEmployed              string
	Workplace               string
	WageAmount              string
	RegisteredSocialWelfare string
	RegisteredUnemployed    string
	HouseholdEmployeesCount string
	WorkingMembersCount     string
	MenCount                string
	WomenCount              string
	MaleChildrenCount       string
	FemaleChildrenCount     string
	Age0To5Count            string
	Age5To10Count           string
	Age10To15Count          string
	Age15To25Count          string
	Age25To40Count          string
	Age40PlusCount          string
	StudentsCount           string
	OrphansCount            string
	WidowsCount             string
	DivorcedCount           string
}

// SetRecipientDetails stores the Educational/Employment/Social Information
// sections. Called after SubmitRegistration, once the user_profiles row is
// guaranteed to exist — same pattern as SetGrantorPhotos. Kept as a separate
// UPDATE (rather than folded into SubmitRegistration's own INSERT/UPDATE) so
// this large, recipient-only field set can't risk the already-working
// core registration write.
func (s *Store) SetRecipientDetails(ctx context.Context, userID int64, extras RecipientDetailsExtras) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET other_certificate          = COALESCE(NULLIF($2, ''), other_certificate),
		        certificates_count         = COALESCE(NULLIF($3, ''), certificates_count),
		        previous_occupation        = COALESCE(NULLIF($4, ''), previous_occupation),
		        job_description            = COALESCE(NULLIF($5, ''), job_description),
		        working_hours              = COALESCE(NULLIF($6, ''), working_hours),
		        is_employed                = COALESCE(NULLIF($7, ''), is_employed),
		        workplace                  = COALESCE(NULLIF($8, ''), workplace),
		        wage_amount                = COALESCE(NULLIF($9, ''), wage_amount),
		        registered_social_welfare  = COALESCE(NULLIF($10, ''), registered_social_welfare),
		        registered_unemployed      = COALESCE(NULLIF($11, ''), registered_unemployed),
		        household_employees_count = COALESCE(NULLIF($12, ''), household_employees_count),
		        working_members_count     = COALESCE(NULLIF($13, ''), working_members_count),
		        men_count                  = COALESCE(NULLIF($14, ''), men_count),
		        women_count                = COALESCE(NULLIF($15, ''), women_count),
		        male_children_count       = COALESCE(NULLIF($16, ''), male_children_count),
		        female_children_count     = COALESCE(NULLIF($17, ''), female_children_count),
		        age_0_5_count              = COALESCE(NULLIF($18, ''), age_0_5_count),
		        age_5_10_count             = COALESCE(NULLIF($19, ''), age_5_10_count),
		        age_10_15_count            = COALESCE(NULLIF($20, ''), age_10_15_count),
		        age_15_25_count            = COALESCE(NULLIF($21, ''), age_15_25_count),
		        age_25_40_count            = COALESCE(NULLIF($22, ''), age_25_40_count),
		        age_40_plus_count          = COALESCE(NULLIF($23, ''), age_40_plus_count),
		        students_count             = COALESCE(NULLIF($24, ''), students_count),
		        orphans_count              = COALESCE(NULLIF($25, ''), orphans_count),
		        widows_count               = COALESCE(NULLIF($26, ''), widows_count),
		        divorced_count             = COALESCE(NULLIF($27, ''), divorced_count)
		  WHERE user_id = $1`,
		userID,
		extras.OtherCertificate, extras.CertificatesCount, extras.PreviousOccupation,
		extras.JobDescription, extras.WorkingHours, extras.IsEmployed, extras.Workplace,
		extras.WageAmount, extras.RegisteredSocialWelfare, extras.RegisteredUnemployed,
		extras.HouseholdEmployeesCount, extras.WorkingMembersCount, extras.MenCount,
		extras.WomenCount, extras.MaleChildrenCount, extras.FemaleChildrenCount,
		extras.Age0To5Count, extras.Age5To10Count, extras.Age10To15Count,
		extras.Age15To25Count, extras.Age25To40Count, extras.Age40PlusCount,
		extras.StudentsCount, extras.OrphansCount, extras.WidowsCount, extras.DivorcedCount,
	)
	return err
}

// RecipientHealthExtras carries the Eligible Recipient "Health Information",
// "Assets", "Needs", and "Social Media Accounts" sections. Empty strings mean
// "not provided" and never overwrite an existing value.
type RecipientHealthExtras struct {
	Height                 string
	Weight                 string
	SmokingStatus          string
	EyesightCondition      string
	HasDisability          string
	DisabilityType         string
	HouseholdDisabledCount string
	ChronicIllnesses       string
	MedicalConditionsCount string
	MedicalConditionsDesc  string
	AvailableFurniture     string
	OwnsCar                string
	NeedsDescription       string
	// Social Media Accounts — the same columns the Privacy Settings screen
	// writes (migration 073), reused here rather than duplicated.
	SocialFacebook  string
	SocialInstagram string
	SocialTelegram  string
}

// SetRecipientHealthDetails stores the Health/Assets/Needs/Social sections.
// Called after SubmitRegistration, once the user_profiles row is guaranteed
// to exist — same pattern as SetRecipientDetails and SetGrantorPhotos.
func (s *Store) SetRecipientHealthDetails(ctx context.Context, userID int64, extras RecipientHealthExtras) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET height                    = COALESCE(NULLIF($2, ''), height),
		        weight                    = COALESCE(NULLIF($3, ''), weight),
		        smoking_status            = COALESCE(NULLIF($4, ''), smoking_status),
		        eyesight_condition        = COALESCE(NULLIF($5, ''), eyesight_condition),
		        has_disability            = COALESCE(NULLIF($6, ''), has_disability),
		        disability_type           = COALESCE(NULLIF($7, ''), disability_type),
		        household_disabled_count  = COALESCE(NULLIF($8, ''), household_disabled_count),
		        chronic_illnesses         = COALESCE(NULLIF($9, ''), chronic_illnesses),
		        medical_conditions_count  = COALESCE(NULLIF($10, ''), medical_conditions_count),
		        medical_conditions_desc   = COALESCE(NULLIF($11, ''), medical_conditions_desc),
		        available_furniture       = COALESCE(NULLIF($12, ''), available_furniture),
		        owns_car                  = COALESCE(NULLIF($13, ''), owns_car),
		        needs_description         = COALESCE(NULLIF($14, ''), needs_description),
		        social_facebook           = COALESCE(NULLIF($15, ''), social_facebook),
		        social_instagram          = COALESCE(NULLIF($16, ''), social_instagram),
		        social_telegram           = COALESCE(NULLIF($17, ''), social_telegram)
		  WHERE user_id = $1`,
		userID,
		extras.Height, extras.Weight, extras.SmokingStatus, extras.EyesightCondition,
		extras.HasDisability, extras.DisabilityType, extras.HouseholdDisabledCount,
		extras.ChronicIllnesses, extras.MedicalConditionsCount, extras.MedicalConditionsDesc,
		extras.AvailableFurniture, extras.OwnsCar, extras.NeedsDescription,
		extras.SocialFacebook, extras.SocialInstagram, extras.SocialTelegram,
	)
	return err
}

// SetRecipientAttachments stores the Eligible Recipient "Attachments" section's
// extra document photos. The spec's "Personal photo" and "National Card photo"
// reuse SetGrantorPhotos' profile_picture/id_photo_path columns and are not
// repeated here. Only non-empty paths are written.
func (s *Store) SetRecipientAttachments(
	ctx context.Context,
	userID int64,
	rationCard, propertyProof, medicalReport, houseFacade, houseInside, houseOutside string,
) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	if rationCard == "" && propertyProof == "" && medicalReport == "" &&
		houseFacade == "" && houseInside == "" && houseOutside == "" {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET ration_card_photo_path    = COALESCE(NULLIF($2, ''), ration_card_photo_path),
		        property_proof_photo_path = COALESCE(NULLIF($3, ''), property_proof_photo_path),
		        medical_report_photo_path = COALESCE(NULLIF($4, ''), medical_report_photo_path),
		        house_facade_photo_path   = COALESCE(NULLIF($5, ''), house_facade_photo_path),
		        house_inside_photo_path   = COALESCE(NULLIF($6, ''), house_inside_photo_path),
		        house_outside_photo_path  = COALESCE(NULLIF($7, ''), house_outside_photo_path)
		  WHERE user_id = $1`,
		userID, rationCard, propertyProof, medicalReport, houseFacade, houseInside, houseOutside,
	)
	return err
}

// SetRecipientConsent stores the Eligible Recipient "Privacy" section: whether
// the recipient permits their real name, and some of their information, to be
// shown to a grantor. Empty strings mean "not answered" and never overwrite an
// existing answer.
func (s *Store) SetRecipientConsent(ctx context.Context, userID int64, showRealName, shareInfo string) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	if showRealName == "" && shareInfo == "" {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET consent_show_real_name = COALESCE(NULLIF($2, ''), consent_show_real_name),
		        consent_share_info     = COALESCE(NULLIF($3, ''), consent_share_info)
		  WHERE user_id = $1`,
		userID, showRealName, shareInfo,
	)
	return err
}

// EnsureVolunteerCode assigns the Volunteer/Employee spec's auto-generated
// identification code, once, on first registration for that role. Mirrors the
// recipient's ER-%06d code (assigned inline in SubmitRegistration).
func (s *Store) EnsureVolunteerCode(ctx context.Context, userID int64) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET volunteer_code = $2
		  WHERE user_id = $1 AND volunteer_code = ''`,
		userID, fmt.Sprintf("VL-%06d", userID),
	)
	return err
}

// VolunteerProfileExtras carries the Volunteer/Employee spec's Personal,
// Housing, and Social Media sections. Everything else that section asks for
// (gender, nationality, governorate, marital status, education level, skills,
// …) already flows through SubmitRegistration/SetRecipientDetails and is not
// duplicated here. Empty strings never overwrite an existing value.
type VolunteerProfileExtras struct {
	Languages   string // comma-separated language keys
	District    string
	SocialOther string
}

// SetVolunteerProfile stores the volunteer-only columns added by migration
// 078. Same separate-write pattern as SetRecipientDetails.
func (s *Store) SetVolunteerProfile(ctx context.Context, userID int64, extras VolunteerProfileExtras) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET languages    = COALESCE(NULLIF($2, ''), languages),
		        district     = COALESCE(NULLIF($3, ''), district),
		        social_other = COALESCE(NULLIF($4, ''), social_other)
		  WHERE user_id = $1`,
		userID, extras.Languages, extras.District, extras.SocialOther,
	)
	return err
}

// SetVolunteerAttachments stores the Volunteer/Employee "Attachments" section's
// extra documents. The formal personal photo, unified National Card/ID and
// Ration Card reuse SetGrantorPhotos / SetRecipientAttachments' columns and
// are not repeated here. Only non-empty paths are written.
func (s *Store) SetVolunteerAttachments(
	ctx context.Context,
	userID int64,
	goldenSquare, residenceCard, passport, graduationCert, cv string,
) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	if goldenSquare == "" && residenceCard == "" && passport == "" &&
		graduationCert == "" && cv == "" {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE user_profiles
		    SET golden_square_photo_path   = COALESCE(NULLIF($2, ''), golden_square_photo_path),
		        residence_card_photo_path  = COALESCE(NULLIF($3, ''), residence_card_photo_path),
		        passport_photo_path        = COALESCE(NULLIF($4, ''), passport_photo_path),
		        graduation_cert_photo_path = COALESCE(NULLIF($5, ''), graduation_cert_photo_path),
		        cv_photo_path              = COALESCE(NULLIF($6, ''), cv_photo_path)
		  WHERE user_id = $1`,
		userID, goldenSquare, residenceCard, passport, graduationCert, cv,
	)
	return err
}

// GetRegistrationState returns the user's current approval status, the reject
// reason (if any), and the chosen role_id (0 when unset).
func (s *Store) GetRegistrationState(ctx context.Context, userID int64) (status string, rejectReason *string, roleID int, err error) {
	var (
		st  string
		rr  *string
		rid *int
	)
	err = s.Pool.QueryRow(ctx,
		`SELECT registration_status, registration_reject_reason, role_id
		   FROM users WHERE id = $1`,
		userID,
	).Scan(&st, &rr, &rid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil, 0, nil
		}
		return "", nil, 0, err
	}
	if rid != nil {
		roleID = *rid
	}
	return st, rr, roleID, nil
}

// RegistrationItem is one row in the admin "pending registrations" list.
type RegistrationItem struct {
	UserID       int64     `json:"user_id"`
	Phone        string    `json:"phone"`
	RoleID       int       `json:"role_id"`
	Status       string    `json:"registration_status"`
	FullName     string    `json:"full_name"`
	Address      string    `json:"address"`
	DateOfBirth  string    `json:"date_of_birth"` // "YYYY-MM-DD" or ""
	SubmittedAt  *string   `json:"submitted_at"`  // ISO8601 or null
	RejectReason *string   `json:"reject_reason"`
	CreatedAt    time.Time `json:"created_at"`
}

// PageRegistrations is the paginated response for the admin registrations list.
type PageRegistrations struct {
	Items      []RegistrationItem `json:"items"`
	Pagination Pagination         `json:"pagination"`
}

// ListRegistrations returns submitted registrations awaiting (or past) review.
// statusFilter: "pending" (default), "rejected", or "all" (pending+rejected).
// 'incomplete' users never appear — they haven't submitted the form yet.
func (s *Store) ListRegistrations(ctx context.Context, statusFilter string, page, perPage int, q string) (*PageRegistrations, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	statusClause := "u.registration_status = 'pending'"
	switch strings.ToLower(strings.TrimSpace(statusFilter)) {
	case "rejected":
		statusClause = "u.registration_status = 'rejected'"
	case "all":
		statusClause = "u.registration_status IN ('pending', 'rejected')"
	}

	args := []any{}
	where := " WHERE " + statusClause
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		where += " AND (u.phone ILIKE $1 OR up.full_name ILIKE $1)"
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id`+where,
		args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limIdx := len(args) + 1
	offIdx := len(args) + 2
	args = append(args, perPage, offset)
	rows, err := s.Pool.Query(ctx,
		`SELECT u.id, u.phone, u.role_id, u.registration_status, u.created_at,
		        to_char(u.registration_submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
		        u.registration_reject_reason,
		        COALESCE(up.full_name, ''), COALESCE(up.address, ''),
		        COALESCE(to_char(up.date_of_birth, 'YYYY-MM-DD'), '')
		   FROM users u
		   LEFT JOIN user_profiles up ON up.user_id = u.id`+where+`
		  ORDER BY u.registration_submitted_at ASC NULLS LAST, u.id ASC
		  LIMIT $`+strconvItoa(limIdx)+` OFFSET $`+strconvItoa(offIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []RegistrationItem{}
	for rows.Next() {
		var (
			it     RegistrationItem
			roleID *int
		)
		if err := rows.Scan(&it.UserID, &it.Phone, &roleID, &it.Status, &it.CreatedAt,
			&it.SubmittedAt, &it.RejectReason, &it.FullName, &it.Address, &it.DateOfBirth); err != nil {
			return nil, err
		}
		if roleID != nil {
			it.RoleID = *roleID
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &PageRegistrations{
		Items: items,
		Pagination: Pagination{
			Page:       page,
			PerPage:    perPage,
			TotalItems: total,
			TotalPages: totalPages,
			HasMore:    page < totalPages,
		},
	}, nil
}

// ApproveRegistration flips a pending/rejected user to 'approved'. Returns
// false (no error) when no such reviewable row exists.
func (s *Store) ApproveRegistration(ctx context.Context, userID, adminID int64) (bool, error) {
	ct, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET registration_status = 'approved',
		        registration_reviewed_at = NOW(),
		        registration_reviewed_by = $2,
		        registration_reject_reason = NULL
		  WHERE id = $1
		    AND registration_status IN ('pending', 'rejected')`,
		userID, adminID,
	)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() > 0, nil
}

// RejectRegistration flips a pending user to 'rejected' with an optional
// reason. The user keeps their submitted details and may edit + re-submit.
func (s *Store) RejectRegistration(ctx context.Context, userID, adminID int64, reason string) (bool, error) {
	var reasonArg any = nil
	if r := strings.TrimSpace(reason); r != "" {
		reasonArg = r
	}
	ct, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET registration_status = 'rejected',
		        registration_reviewed_at = NOW(),
		        registration_reviewed_by = $2,
		        registration_reject_reason = $3
		  WHERE id = $1
		    AND registration_status IN ('pending', 'rejected')`,
		userID, adminID, reasonArg,
	)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() > 0, nil
}
