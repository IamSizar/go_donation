// Package marriage handles marriage_profiles.
package marriage

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/sectioncodes"
)

type Profile struct {
	ID int64 `json:"id"`
	// Note #18 — exposed so "my own profile" responses (OwnedByUser filter)
	// can be told apart from another user's; omitted from nothing (it was
	// always selected, just never scanned/exposed before).
	UserID        int64   `json:"user_id"`
	ProfileCode   string  `json:"profile_code"`
	Gender        *string `json:"gender"`
	Age           *int    `json:"age"`
	City          *string `json:"city"`
	SocialSummary *string `json:"social_summary"`
	// Client note — Marriage "Search" filters: marital status/employment
	// status are small fixed sets (see MaritalStatuses/EmploymentStatuses);
	// religion stays free text rather than a hardcoded taxonomy.
	MaritalStatus    *string `json:"marital_status"`
	Religion         *string `json:"religion"`
	EmploymentStatus *string `json:"employment_status"`
	WeightKg         *int    `json:"weight_kg"`
	HeightCm         *int    `json:"height_cm"`
	// Marriage Posts — the feed is these profiles themselves; PhotoUrl is the
	// owner-uploaded picture shown on its card (nil → the app shows a
	// placeholder, same as any other optional profile field).
	PhotoUrl           *string   `json:"photo_url"`
	VisibilityLevel    string    `json:"visibility_level"`
	SubscriptionStatus string    `json:"subscription_status"`
	Status             string    `json:"status"`
	CreatedAt          time.Time `json:"created_at"`
}

// MaritalStatuses mirrors the beneficiary case module's set (§ admin_edit.go
// caseMaritalStatuses) for consistency across the app.
var MaritalStatuses = []string{"single", "married", "widowed", "divorced"}

// EmploymentStatuses — a small fixed set; no existing precedent elsewhere in
// the app to mirror, so kept minimal and easy to extend later.
var EmploymentStatuses = []string{"employed", "unemployed", "self_employed", "student"}

type Store struct {
	Pool *pgxpool.Pool
	// "Sixth/Seventh: Donations Page" — issues this section's Transaction
	// Code and alerts its configured phone. Optional: when unset, purchases
	// behave exactly as before, just without a code.
	Arrivals sectioncodes.ArrivalNotifier
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns marriage profiles. statusFilter="public" (default) means
// active/under_review/submitted; "all" means no filter; anything else is an
// exact match.
// SearchFilters drives List (#46 adds gender/age filters + saved-only mode).
type SearchFilters struct {
	Status           string
	Q                string
	Gender           string
	MinAge           int
	MaxAge           int
	MaritalStatus    string
	Religion         string // partial match (ILIKE), same as Q
	EmploymentStatus string
	MinWeight        int
	MaxWeight        int
	MinHeight        int
	MaxHeight        int
	SavedByUser      int64 // when >0, only profiles this user saved
	OwnedByUser      int64 // Note #18 — when >0, only profiles this user submitted
	Limit            int
	// Marriage Posts — cursor pagination for the continuous feed. Rows are
	// always ORDER BY id DESC, so "older than the last card I saw" is simply
	// id < BeforeID; 0 means "from the start" (first page).
	BeforeID int64
}

func (s *Store) List(ctx context.Context, f SearchFilters) ([]Profile, error) {
	limit := f.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	args := []any{}
	conds := []string{}
	switch f.Status {
	case "", "public":
		conds = append(conds, "status IN ('active','under_review','submitted')")
	case "all":
		// no status filter
	default:
		args = append(args, f.Status)
		conds = append(conds, "status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(f.Q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		conds = append(conds, "(profile_code ILIKE $"+idx+" OR city ILIKE $"+idx+" OR social_summary ILIKE $"+idx+")")
	}
	if g := strings.TrimSpace(f.Gender); g != "" {
		args = append(args, g)
		conds = append(conds, "gender = $"+itoa(len(args)))
	}
	if f.MinAge > 0 {
		args = append(args, f.MinAge)
		conds = append(conds, "age >= $"+itoa(len(args)))
	}
	if f.MaxAge > 0 {
		args = append(args, f.MaxAge)
		conds = append(conds, "age <= $"+itoa(len(args)))
	}
	if ms := strings.TrimSpace(f.MaritalStatus); ms != "" {
		args = append(args, ms)
		conds = append(conds, "marital_status = $"+itoa(len(args)))
	}
	if r := strings.TrimSpace(f.Religion); r != "" {
		args = append(args, "%"+r+"%")
		conds = append(conds, "religion ILIKE $"+itoa(len(args)))
	}
	if es := strings.TrimSpace(f.EmploymentStatus); es != "" {
		args = append(args, es)
		conds = append(conds, "employment_status = $"+itoa(len(args)))
	}
	if f.MinWeight > 0 {
		args = append(args, f.MinWeight)
		conds = append(conds, "weight_kg >= $"+itoa(len(args)))
	}
	if f.MaxWeight > 0 {
		args = append(args, f.MaxWeight)
		conds = append(conds, "weight_kg <= $"+itoa(len(args)))
	}
	if f.MinHeight > 0 {
		args = append(args, f.MinHeight)
		conds = append(conds, "height_cm >= $"+itoa(len(args)))
	}
	if f.MaxHeight > 0 {
		args = append(args, f.MaxHeight)
		conds = append(conds, "height_cm <= $"+itoa(len(args)))
	}
	if f.SavedByUser > 0 {
		args = append(args, f.SavedByUser)
		conds = append(conds, "id IN (SELECT profile_id FROM marriage_saved WHERE user_id = $"+itoa(len(args))+")")
	}
	if f.OwnedByUser > 0 {
		args = append(args, f.OwnedByUser)
		conds = append(conds, "user_id = $"+itoa(len(args)))
	}
	if f.BeforeID > 0 {
		args = append(args, f.BeforeID)
		conds = append(conds, "id < $"+itoa(len(args)))
	}
	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}
	args = append(args, limit)
	limitIdx := len(args)
	sqlStr := `SELECT id, user_id, profile_code, gender, age, city, social_summary,
	             marital_status, religion, employment_status, weight_kg, height_cm,
	             photo_url, visibility_level, subscription_status, status, created_at
	        FROM marriage_profiles ` + where + `
	       ORDER BY id DESC
	       LIMIT $` + itoa(limitIdx)
	rows, err := s.Pool.Query(ctx, sqlStr, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Profile{}
	for rows.Next() {
		var p Profile
		if err := rows.Scan(&p.ID, &p.UserID, &p.ProfileCode, &p.Gender, &p.Age, &p.City, &p.SocialSummary,
			&p.MaritalStatus, &p.Religion, &p.EmploymentStatus, &p.WeightKg, &p.HeightCm,
			&p.PhotoUrl, &p.VisibilityLevel, &p.SubscriptionStatus, &p.Status, &p.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
}

// ToggleSaved bookmarks/un-bookmarks a profile for a user (#46). Returns the
// resulting saved state.
func (s *Store) ToggleSaved(ctx context.Context, userID, profileID int64) (bool, error) {
	ct, err := s.Pool.Exec(ctx,
		`DELETE FROM marriage_saved WHERE user_id = $1 AND profile_id = $2`, userID, profileID)
	if err != nil {
		return false, err
	}
	if ct.RowsAffected() > 0 {
		return false, nil // was saved → now removed
	}
	if _, err := s.Pool.Exec(ctx,
		`INSERT INTO marriage_saved (user_id, profile_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`, userID, profileID); err != nil {
		return false, err
	}
	return true, nil
}

// RequestMeeting records a meeting request about a profile (#46). Staff mediate.
// RequestType filters the contact method down to the three the spec offers, so
// a bad value from a client is a 'meeting' rather than a constraint violation:
//
//	meeting      — an in-person meeting
//	intermediary — contact handled by a staff member
//	visit        — a visit request
//
// Anything else, including the empty string an older client sends, means the
// single generic button that existed before, which was an in-person meeting.
func RequestType(v string) string {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "intermediary":
		return "intermediary"
	case "visit":
		return "visit"
	}
	return "meeting"
}

func (s *Store) RequestMeeting(ctx context.Context, fromUserID, profileID int64, message, requestType string) (int64, error) {
	var msg any
	if strings.TrimSpace(message) != "" {
		msg = message
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id, message, request_type)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		fromUserID, profileID, msg, RequestType(requestType)).Scan(&id)
	return id, err
}

// Insert creates a marriage_profiles row and returns id + profile_code.
func (s *Store) Insert(ctx context.Context, userID int64,
	gender *string, age *int, city, socialSummary, privateNotes *string,
	maritalStatus, religion, employmentStatus *string, weightKg, heightCm *int,
	subscriptionStatus, visibilityLevel string, photoUrl *string) (int64, string, error) {
	if userID <= 0 {
		return 0, "", errors.New("invalid userID")
	}
	// Note #17 — was free/paid/waived; bronze is the new entry tier.
	// Client note — Marriage "Subscription": tiers are a dynamic table now,
	// not a fixed 5-value enum. A profile starts on whichever active package
	// has the lowest display_order (its "entry tier") — actually upgrading
	// happens later through the purchase flow, not at registration.
	if strings.TrimSpace(subscriptionStatus) == "" {
		var entrySlug string
		err := s.Pool.QueryRow(ctx,
			`SELECT slug FROM marriage_subscription_packages WHERE active = 1 ORDER BY display_order, id LIMIT 1`,
		).Scan(&entrySlug)
		if err == nil && entrySlug != "" {
			subscriptionStatus = entrySlug
		} else {
			subscriptionStatus = "bronze"
		}
	}
	// #42 — privacy: who can see the profile. Falls back to the DB default.
	switch visibilityLevel {
	case "private", "employee_only", "matched_summary":
	default:
		visibilityLevel = "employee_only"
	}
	rh, err := randHex(3)
	if err != nil {
		return 0, "", err
	}
	code := "M-" + time.Now().UTC().Format("20060102") + "-" + strings.ToUpper(rh)
	var id int64
	err = s.Pool.QueryRow(ctx, `
		INSERT INTO marriage_profiles
		   (user_id, profile_code, gender, age, city, social_summary, private_notes,
		    marital_status, religion, employment_status, weight_kg, height_cm,
		    subscription_status, visibility_level, photo_url)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
		RETURNING id`,
		userID, code, gender, age, city, socialSummary, privateNotes,
		maritalStatus, religion, employmentStatus, weightKg, heightCm,
		subscriptionStatus, visibilityLevel, photoUrl,
	).Scan(&id)
	if err != nil {
		return 0, "", err
	}
	return id, code, nil
}

// MarriageIdentification carries the "My Engagement" spec's "Identification
// Information" section. profile_code is generated by Insert and is not part
// of this struct. Empty strings never overwrite an existing value.
type MarriageIdentification struct {
	NationalID      string
	NameFirst       string
	NameFather      string
	NameGrandfather string
	NameFamily      string
	TribeClan       string
	TitleSurname    string
	DateOfBirth     string // "YYYY-MM-DD" or "" for unset
	Email           string
	Phone1          string
	Phone2          string
	// "Personal Information" section — gender and marital status are set by
	// Insert; these two are new in migration 080.
	Nationality     string
	ResidencyStatus string
}

// SetIdentification stores the Identification Information section for a
// marriage profile. Kept separate from Insert (already 15 positional
// parameters) so this section can't destabilise the core create path.
func (s *Store) SetIdentification(ctx context.Context, profileID int64, idn MarriageIdentification) error {
	if profileID <= 0 {
		return errors.New("invalid profileID")
	}
	var dobArg any = nil
	if d := strings.TrimSpace(idn.DateOfBirth); d != "" {
		dobArg = d
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET national_id      = COALESCE(NULLIF($2, ''), national_id),
		        name_first       = COALESCE(NULLIF($3, ''), name_first),
		        name_father      = COALESCE(NULLIF($4, ''), name_father),
		        name_grandfather = COALESCE(NULLIF($5, ''), name_grandfather),
		        name_family      = COALESCE(NULLIF($6, ''), name_family),
		        tribe_clan       = COALESCE(NULLIF($7, ''), tribe_clan),
		        title_surname    = COALESCE(NULLIF($8, ''), title_surname),
		        date_of_birth    = COALESCE($9::date, date_of_birth),
		        email            = COALESCE(NULLIF($10, ''), email),
		        phone1           = COALESCE(NULLIF($11, ''), phone1),
		        phone2           = COALESCE(NULLIF($12, ''), phone2),
		        nationality      = COALESCE(NULLIF($13, ''), nationality),
		        residency_status = COALESCE(NULLIF($14, ''), residency_status)
		  WHERE id = $1`,
		profileID, idn.NationalID, idn.NameFirst, idn.NameFather,
		idn.NameGrandfather, idn.NameFamily, idn.TribeClan, idn.TitleSurname,
		dobArg, idn.Email, idn.Phone1, idn.Phone2,
		idn.Nationality, idn.ResidencyStatus,
	)
	return err
}

// MarriageHousing carries the "My Engagement" spec's "Housing Information"
// and "Housing Type" sections. Empty strings never overwrite an existing
// value; nil GPS coordinates leave the stored pair untouched.
type MarriageHousing struct {
	Governorate            string
	HousingSide            string
	Neighborhood           string
	NearestLandmark        string
	GPSLat                 *float64
	GPSLng                 *float64
	YearsCurrentResidence  string
	PreviousResidence      string
	YearsPreviousResidence string
	HousingType            string
	RentalAmount           string
	HousingArea            string
	FloorsCount            string
	RoomsCount             string
	FamiliesCount          string
}

// SetHousing stores the Housing Information / Housing Type sections for a
// marriage profile. Separate from Insert for the same reason as
// SetIdentification.
func (s *Store) SetHousing(ctx context.Context, profileID int64, h MarriageHousing) error {
	if profileID <= 0 {
		return errors.New("invalid profileID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET governorate              = COALESCE(NULLIF($2, ''), governorate),
		        housing_side             = COALESCE(NULLIF($3, ''), housing_side),
		        neighborhood             = COALESCE(NULLIF($4, ''), neighborhood),
		        nearest_landmark         = COALESCE(NULLIF($5, ''), nearest_landmark),
		        gps_lat                  = COALESCE($6, gps_lat),
		        gps_lng                  = COALESCE($7, gps_lng),
		        years_current_residence  = COALESCE(NULLIF($8, ''), years_current_residence),
		        previous_residence       = COALESCE(NULLIF($9, ''), previous_residence),
		        years_previous_residence = COALESCE(NULLIF($10, ''), years_previous_residence),
		        housing_type             = COALESCE(NULLIF($11, ''), housing_type),
		        rental_amount            = COALESCE(NULLIF($12, ''), rental_amount),
		        housing_area             = COALESCE(NULLIF($13, ''), housing_area),
		        floors_count             = COALESCE(NULLIF($14, ''), floors_count),
		        rooms_count              = COALESCE(NULLIF($15, ''), rooms_count),
		        families_count           = COALESCE(NULLIF($16, ''), families_count)
		  WHERE id = $1`,
		profileID, h.Governorate, h.HousingSide, h.Neighborhood, h.NearestLandmark,
		h.GPSLat, h.GPSLng, h.YearsCurrentResidence, h.PreviousResidence,
		h.YearsPreviousResidence, h.HousingType, h.RentalAmount, h.HousingArea,
		h.FloorsCount, h.RoomsCount, h.FamiliesCount,
	)
	return err
}

// MarriageProfileDetails carries the "My Engagement" spec's remaining
// sections: Educational and Employment, Personal and Health, Assets, Needs
// and Requirements, Attachments, and Social Media Accounts. Empty strings
// never overwrite an existing value.
type MarriageProfileDetails struct {
	// Educational and Employment Information.
	EducationLevel     string
	OtherCertificate   string
	CertificatesCount  string
	Occupation         string
	PreviousOccupation string
	JobDescription     string
	WorkingHours       string
	MonthlyIncome      string
	// Personal and Health Information.
	SkinTone           string
	FamilyMembersCount string
	ChildrenCount      string
	SmokingStatus      string
	EyesightCondition  string
	HasDisability      string
	DisabilityType     string
	ChronicIllnesses   string
	Ethnicity          string
	Skills             string
	// Assets.
	OwnsCar     string
	OwnsHouse   string
	OwnsShop    string
	OwnsCompany string
	OwnsLand    string
	OtherAssets string
	// Needs and Requirements.
	PartnerRequirements string
	// Attachments (personal photo is photo_url, set by Insert).
	GoldenSquareURL   string
	GraduationCertURL string
	CVURL             string
	// Social Media Accounts.
	SocialFacebook  string
	SocialInstagram string
	SocialTelegram  string
	SocialOther     string
}

// SetProfileDetails stores the sections above. Separate from Insert for the
// same reason as SetIdentification / SetHousing.
func (s *Store) SetProfileDetails(ctx context.Context, profileID int64, d MarriageProfileDetails) error {
	if profileID <= 0 {
		return errors.New("invalid profileID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET education_level      = COALESCE(NULLIF($2, ''), education_level),
		        other_certificate    = COALESCE(NULLIF($3, ''), other_certificate),
		        certificates_count   = COALESCE(NULLIF($4, ''), certificates_count),
		        occupation           = COALESCE(NULLIF($5, ''), occupation),
		        previous_occupation  = COALESCE(NULLIF($6, ''), previous_occupation),
		        job_description      = COALESCE(NULLIF($7, ''), job_description),
		        working_hours        = COALESCE(NULLIF($8, ''), working_hours),
		        monthly_income       = COALESCE(NULLIF($9, ''), monthly_income),
		        skin_tone            = COALESCE(NULLIF($10, ''), skin_tone),
		        family_members_count = COALESCE(NULLIF($11, ''), family_members_count),
		        children_count       = COALESCE(NULLIF($12, ''), children_count),
		        smoking_status       = COALESCE(NULLIF($13, ''), smoking_status),
		        eyesight_condition   = COALESCE(NULLIF($14, ''), eyesight_condition),
		        has_disability       = COALESCE(NULLIF($15, ''), has_disability),
		        disability_type      = COALESCE(NULLIF($16, ''), disability_type),
		        chronic_illnesses    = COALESCE(NULLIF($17, ''), chronic_illnesses),
		        ethnicity            = COALESCE(NULLIF($18, ''), ethnicity),
		        skills               = COALESCE(NULLIF($19, ''), skills),
		        owns_car             = COALESCE(NULLIF($20, ''), owns_car),
		        owns_house           = COALESCE(NULLIF($21, ''), owns_house),
		        owns_shop            = COALESCE(NULLIF($22, ''), owns_shop),
		        owns_company         = COALESCE(NULLIF($23, ''), owns_company),
		        owns_land            = COALESCE(NULLIF($24, ''), owns_land),
		        other_assets         = COALESCE(NULLIF($25, ''), other_assets),
		        partner_requirements = COALESCE(NULLIF($26, ''), partner_requirements),
		        golden_square_url    = COALESCE(NULLIF($27, ''), golden_square_url),
		        graduation_cert_url  = COALESCE(NULLIF($28, ''), graduation_cert_url),
		        cv_url               = COALESCE(NULLIF($29, ''), cv_url),
		        social_facebook      = COALESCE(NULLIF($30, ''), social_facebook),
		        social_instagram     = COALESCE(NULLIF($31, ''), social_instagram),
		        social_telegram      = COALESCE(NULLIF($32, ''), social_telegram),
		        social_other         = COALESCE(NULLIF($33, ''), social_other)
		  WHERE id = $1`,
		profileID, d.EducationLevel, d.OtherCertificate, d.CertificatesCount,
		d.Occupation, d.PreviousOccupation, d.JobDescription, d.WorkingHours,
		d.MonthlyIncome, d.SkinTone, d.FamilyMembersCount, d.ChildrenCount,
		d.SmokingStatus, d.EyesightCondition, d.HasDisability, d.DisabilityType,
		d.ChronicIllnesses, d.Ethnicity, d.Skills, d.OwnsCar, d.OwnsHouse,
		d.OwnsShop, d.OwnsCompany, d.OwnsLand, d.OtherAssets,
		d.PartnerRequirements, d.GoldenSquareURL, d.GraduationCertURL, d.CVURL,
		d.SocialFacebook, d.SocialInstagram, d.SocialTelegram, d.SocialOther,
	)
	return err
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

func randHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
