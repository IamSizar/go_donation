package beneficiary

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Case mirrors the JSON shape returned by the PHP /beneficiary_cases GET.
type Case struct {
	ID                 int64   `json:"id"`
	UserID             *int    `json:"user_id"`
	CaseCode           string  `json:"case_code"`
	PublicTitle        string  `json:"public_title"`
	PublicTitleAr      *string `json:"public_title_ar"`
	PublicTitleSorani  *string `json:"public_title_sorani"`
	PublicTitleBadini  *string `json:"public_title_badini"`
	FullName           *string `json:"full_name"`
	NationalID         *string `json:"national_id"`
	Phone              *string `json:"phone"`
	Gender             *string `json:"gender"`
	DateOfBirth        *string `json:"date_of_birth"`
	MaritalStatus      *string `json:"marital_status"`
	City               *string `json:"city"`
	District           *string `json:"district"`
	Address            *string `json:"address"`
	FamilyMembersCount *int    `json:"family_members_count"`
	IncomeAmount       *string `json:"income_amount"`
	HousingStatus      *string `json:"housing_status"`
	WorkStatus         *string `json:"work_status"`
	HealthStatus       *string `json:"health_status"`
	EducationStatus    *string `json:"education_status"`
	ActualNeeds        *string `json:"actual_needs"`
	PriorityLevel      string  `json:"priority_level"`
	// Note #15 — nullable: the column has no NOT NULL/DEFAULT (migrations/
	// 001_full_v2.sql), and InsertCase below didn't set it, so self-submitted
	// rows (mobile app) could land with SQL NULL here. Scanning NULL into a
	// non-pointer string is a hard error that used to abort the ENTIRE list
	// query — one such row broke the admin Cases screen for every row, not
	// just itself, surfacing as a generic "Database error."
	VerificationStatus *string   `json:"verification_status"`
	PublicVisibility   string    `json:"public_visibility"`
	ReviewNotes        *string   `json:"review_notes"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// ProjectRequest matches the GET /beneficiary_project_requests response shape.
type ProjectRequest struct {
	ID                             int64     `json:"id"`
	UserID                         int       `json:"user_id"`
	ProjectTitle                   string    `json:"project_title"`
	ProjectTitleAr                 *string   `json:"project_title_ar"`
	ProjectTitleSorani             *string   `json:"project_title_sorani"`
	ProjectTitleBadini             *string   `json:"project_title_badini"`
	Category                       string    `json:"category"`
	CategoryAr                     *string   `json:"category_ar"`
	CategorySorani                 *string   `json:"category_sorani"`
	CategoryBadini                 *string   `json:"category_badini"`
	Summary                        string    `json:"summary"`
	SummaryAr                      *string   `json:"summary_ar"`
	SummarySorani                  *string   `json:"summary_sorani"`
	SummaryBadini                  *string   `json:"summary_badini"`
	AmountNeeded                   string    `json:"amount_needed"`
	RaisedAmount                   int       `json:"raised_amount"`
	Currency                       string    `json:"currency"`
	Location                       string    `json:"location"`
	LocationAr                     *string   `json:"location_ar"`
	LocationSorani                 *string   `json:"location_sorani"`
	LocationBadini                 *string   `json:"location_badini"`
	BeneficiaryCommunityName       string    `json:"beneficiary_community_name"`
	BeneficiaryCommunityNameAr     *string   `json:"beneficiary_community_name_ar"`
	BeneficiaryCommunityNameSorani *string   `json:"beneficiary_community_name_sorani"`
	BeneficiaryCommunityNameBadini *string   `json:"beneficiary_community_name_badini"`
	PeopleAffectedTotal            *int      `json:"people_affected_total"`
	Status                         string    `json:"status"`
	LikeCount                      int       `json:"like_count"`
	CommentCount                   int       `json:"comment_count"`
	CreatedAt                      time.Time `json:"created_at"`
	UpdatedAt                      time.Time `json:"updated_at"`
}

// CaseInput is the validated payload for POST /api/beneficiary_cases.
type CaseInput struct {
	UserID             int64
	CaseCode           string // optional; auto-generated if empty
	PublicTitle        string
	PublicTitleAr      *string
	FullName           *string
	NationalID         *string
	Phone              *string
	Gender             *string
	DateOfBirth        *string
	MaritalStatus      *string
	City               *string
	District           *string
	Address            *string
	FamilyMembersCount *int
	IncomeAmount       *float64
	HousingStatus      *string
	WorkStatus         *string
	HealthStatus       *string
	EducationStatus    *string
	ActualNeeds        *string
	PriorityLevel      string // "low","medium","high","urgent" (default "medium")
}

// RequestInput is the validated payload for POST /api/beneficiary_project_requests.
type RequestInput struct {
	UserID                     int64
	ProjectTitle               string
	ProjectTitleAr             *string
	Category                   string
	CategoryAr                 *string
	Summary                    string
	SummaryAr                  *string
	DescriptionLong            string
	DescriptionLongAr          *string
	AmountNeeded               float64
	Currency                   string
	Location                   string
	LocationAr                 *string
	BeneficiaryCommunityName   string
	BeneficiaryCommunityNameAr *string
	PeopleAffectedTotal        *int
	MaleCount                  *int
	FemaleCount                *int
	VolunteerAgeProfile        *string
	VolunteerSkillsKnowledge   *string
	PeopleVolunteersExtraDesc  *string
	TimelineTarget             *string
	ContactPersonName          *string
	ContactPhone               *string
	ContactEmail               *string
	OtherNotes                 *string
	Status                     string // default "submitted"
}

type Store struct {
	Pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// priorityOrderClause returns the ORDER BY snippet that mirrors PHP's
// FIELD(priority_level, 'urgent','high','medium','low') ordering in Postgres.
const priorityOrderClause = `
  CASE priority_level
    WHEN 'urgent' THEN 1
    WHEN 'high'   THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low'    THEN 4
    ELSE 5
  END, id DESC`

// ListCasesForUser returns the cases owned by the given user (optionally
// filtered by verification_status).
func (s *Store) ListCasesForUser(ctx context.Context, userID int64, status string, limit int) ([]Case, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	args := []any{userID}
	q := `SELECT id, user_id, case_code, public_title, public_title_ar,
	             NULL::text, NULL::text,
	             full_name, national_id, phone, gender, date_of_birth::text, marital_status,
	             city, district, address, family_members_count,
	             income_amount::text, housing_status, work_status,
	             health_status, education_status, actual_needs,
	             priority_level, verification_status, public_visibility,
	             review_notes, created_at, updated_at
	        FROM beneficiary_cases
	       WHERE user_id = $1`
	if status != "" {
		args = append(args, status)
		q += ` AND verification_status = $2`
	}
	q += ` ORDER BY` + priorityOrderClause + ` LIMIT ` + itoa(limit)

	return s.queryCases(ctx, q, args...)
}

// ListPublicCases returns cases visible publicly (visibility != 'hidden')
// filtered by verification_status (defaults to 'approved').
func (s *Store) ListPublicCases(ctx context.Context, status string, limit int) ([]Case, error) {
	if status == "" {
		status = "approved"
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	q := `SELECT id, user_id, case_code, public_title, public_title_ar,
	             NULL::text, NULL::text,
	             full_name, national_id, phone, gender, date_of_birth::text, marital_status,
	             city, district, address, family_members_count,
	             income_amount::text, housing_status, work_status,
	             health_status, education_status, actual_needs,
	             priority_level, verification_status, public_visibility,
	             review_notes, created_at, updated_at
	        FROM beneficiary_cases
	       WHERE verification_status = $1
	         AND public_visibility <> 'hidden'
	       ORDER BY` + priorityOrderClause + ` LIMIT ` + itoa(limit)
	return s.queryCases(ctx, q, status)
}

func (s *Store) queryCases(ctx context.Context, q string, args ...any) ([]Case, error) {
	rows, err := s.Pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Case{}
	for rows.Next() {
		var c Case
		err := rows.Scan(
			&c.ID, &c.UserID, &c.CaseCode, &c.PublicTitle, &c.PublicTitleAr,
			&c.PublicTitleSorani, &c.PublicTitleBadini,
			&c.FullName, &c.NationalID, &c.Phone, &c.Gender, &c.DateOfBirth, &c.MaritalStatus,
			&c.City, &c.District, &c.Address, &c.FamilyMembersCount,
			&c.IncomeAmount, &c.HousingStatus, &c.WorkStatus,
			&c.HealthStatus, &c.EducationStatus, &c.ActualNeeds,
			&c.PriorityLevel, &c.VerificationStatus, &c.PublicVisibility,
			&c.ReviewNotes, &c.CreatedAt, &c.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, c)
	}
	return items, rows.Err()
}

// InsertCase writes a new beneficiary_cases row. Generates a case_code if the
// input didn't supply one. Defaults priority_level to "medium" when invalid.
func (s *Store) InsertCase(ctx context.Context, in CaseInput) (int64, string, error) {
	if in.UserID <= 0 {
		return 0, "", errors.New("invalid userID")
	}
	title := strings.TrimSpace(in.PublicTitle)
	if title == "" {
		return 0, "", errors.New("missing public_title")
	}
	caseCode := strings.TrimSpace(in.CaseCode)
	if caseCode == "" {
		rh, err := randHex(3)
		if err != nil {
			return 0, "", err
		}
		caseCode = "CASE-" + time.Now().UTC().Format("20060102") + "-" + strings.ToUpper(rh)
	}
	priority := in.PriorityLevel
	switch priority {
	case "low", "medium", "high", "urgent":
	default:
		priority = "medium"
	}

	var id int64
	// Note #15 — verification_status is now included explicitly (defaulted to
	// "submitted", matching the admin-created path in admin_create.go). It
	// used to be omitted here entirely, and with no DB default that left it
	// SQL NULL — which crashed the admin list query's Scan (see the
	// VerificationStatus field comment above).
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO beneficiary_cases (
		  user_id, case_code, public_title, public_title_ar,
		  full_name, national_id, phone, gender, date_of_birth, marital_status,
		  city, district, address,
		  family_members_count, income_amount, housing_status,
		  work_status, health_status, education_status, actual_needs,
		  priority_level, verification_status
		) VALUES (
		  $1, $2, $3, $4,
		  $5, $6, $7, $8, $9, $10,
		  $11, $12, $13,
		  $14, $15, $16,
		  $17, $18, $19, $20,
		  $21, 'submitted'
		) RETURNING id`,
		in.UserID, caseCode, title, in.PublicTitleAr,
		in.FullName, in.NationalID, in.Phone, in.Gender, in.DateOfBirth, in.MaritalStatus,
		in.City, in.District, in.Address,
		in.FamilyMembersCount, in.IncomeAmount, in.HousingStatus,
		in.WorkStatus, in.HealthStatus, in.EducationStatus, in.ActualNeeds,
		priority,
	).Scan(&id)
	if err != nil {
		return 0, "", err
	}
	return id, caseCode, nil
}

// ListRequestsForUser returns the project requests submitted by the user
// (optionally filtered by status).
func (s *Store) ListRequestsForUser(ctx context.Context, userID int64, status string, limit int) ([]ProjectRequest, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	args := []any{userID}
	q := `SELECT id, user_id, project_title, project_title_ar,
	             NULL::text, NULL::text,
	             category, category_ar,
	             NULL::text, NULL::text,
	             summary, summary_ar,
	             NULL::text, NULL::text,
	             amount_needed::text, raised_amount, currency,
	             location, location_ar,
	             NULL::text, NULL::text,
	             beneficiary_community_name, beneficiary_community_name_ar,
	             NULL::text, NULL::text,
	             people_affected_total, status, like_count, comment_count,
	             created_at, updated_at
	        FROM beneficiary_project_requests
	       WHERE user_id = $1`
	if status != "" {
		args = append(args, status)
		q += ` AND status = $2`
	}
	q += ` ORDER BY id DESC LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []ProjectRequest{}
	for rows.Next() {
		var r ProjectRequest
		err := rows.Scan(
			&r.ID, &r.UserID, &r.ProjectTitle, &r.ProjectTitleAr,
			&r.ProjectTitleSorani, &r.ProjectTitleBadini,
			&r.Category, &r.CategoryAr,
			&r.CategorySorani, &r.CategoryBadini,
			&r.Summary, &r.SummaryAr,
			&r.SummarySorani, &r.SummaryBadini,
			&r.AmountNeeded, &r.RaisedAmount, &r.Currency,
			&r.Location, &r.LocationAr,
			&r.LocationSorani, &r.LocationBadini,
			&r.BeneficiaryCommunityName, &r.BeneficiaryCommunityNameAr,
			&r.BeneficiaryCommunityNameSorani, &r.BeneficiaryCommunityNameBadini,
			&r.PeopleAffectedTotal, &r.Status, &r.LikeCount, &r.CommentCount,
			&r.CreatedAt, &r.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, r)
	}
	return items, rows.Err()
}

// InsertRequest validates & inserts a new project request.
// Returns the new id and the normalized status that was actually stored.
func (s *Store) InsertRequest(ctx context.Context, in RequestInput) (int64, string, error) {
	in.ProjectTitle = strings.TrimSpace(in.ProjectTitle)
	in.Category = strings.TrimSpace(in.Category)
	in.Summary = strings.TrimSpace(in.Summary)
	in.DescriptionLong = strings.TrimSpace(in.DescriptionLong)
	in.Location = strings.TrimSpace(in.Location)
	in.BeneficiaryCommunityName = strings.TrimSpace(in.BeneficiaryCommunityName)
	in.Currency = strings.ToUpper(strings.TrimSpace(in.Currency))

	if in.UserID <= 0 ||
		in.ProjectTitle == "" || in.Category == "" || in.Summary == "" ||
		in.DescriptionLong == "" || in.Location == "" || in.BeneficiaryCommunityName == "" ||
		in.AmountNeeded <= 0 || in.Currency == "" {
		return 0, "", errors.New("invalid or incomplete data")
	}

	switch strings.ToLower(strings.TrimSpace(in.Status)) {
	case "pending", "submitted", "approved", "rejected", "under_review":
		in.Status = strings.ToLower(strings.TrimSpace(in.Status))
	default:
		in.Status = "submitted"
	}

	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO beneficiary_project_requests (
		  user_id,
		  project_title, project_title_ar,
		  category, category_ar,
		  summary, summary_ar,
		  description_long, description_long_ar,
		  amount_needed, raised_amount, currency,
		  location, location_ar,
		  beneficiary_community_name, beneficiary_community_name_ar,
		  people_affected_total, male_count, female_count,
		  volunteer_age_profile, volunteer_skills_knowledge,
		  people_volunteers_extra_description,
		  timeline_target,
		  contact_person_name, contact_phone, contact_email,
		  other_notes, status
		) VALUES (
		  $1,
		  $2, $3,
		  $4, $5,
		  $6, $7,
		  $8, $9,
		  $10, 0, $11,
		  $12, $13,
		  $14, $15,
		  $16, $17, $18,
		  $19, $20,
		  $21,
		  $22,
		  $23, $24, $25,
		  $26, $27
		) RETURNING id`,
		in.UserID,
		in.ProjectTitle, in.ProjectTitleAr,
		in.Category, in.CategoryAr,
		in.Summary, in.SummaryAr,
		in.DescriptionLong, in.DescriptionLongAr,
		in.AmountNeeded, in.Currency,
		in.Location, in.LocationAr,
		in.BeneficiaryCommunityName, in.BeneficiaryCommunityNameAr,
		in.PeopleAffectedTotal, in.MaleCount, in.FemaleCount,
		in.VolunteerAgeProfile, in.VolunteerSkillsKnowledge,
		in.PeopleVolunteersExtraDesc,
		in.TimelineTarget,
		in.ContactPersonName, in.ContactPhone, in.ContactEmail,
		in.OtherNotes, in.Status,
	).Scan(&id)
	if err != nil {
		return 0, "", err
	}
	return id, in.Status, nil
}

// AdminPage is a paginated admin list response.
type AdminPage[T any] struct {
	Items      []T  `json:"items"`
	Page       int  `json:"page"`
	PerPage    int  `json:"per_page"`
	TotalItems int  `json:"total_items"`
	TotalPages int  `json:"total_pages"`
	HasMore    bool `json:"has_more"`
}

// AdminListCases returns a paginated list of beneficiary_cases across all
// users, optionally filtered by verification_status and a free-text search.
func (s *Store) AdminListCases(ctx context.Context, page, perPage int, status, q string) (*AdminPage[Case], error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 200 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	conds := []string{}
	if status != "" {
		args = append(args, status)
		conds = append(conds, "verification_status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		conds = append(conds, "(case_code ILIKE $"+idx+" OR public_title ILIKE $"+idx+" OR full_name ILIKE $"+idx+" OR phone ILIKE $"+idx+" OR city ILIKE $"+idx+")")
	}
	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM beneficiary_cases"+where, args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	sqlStr := `SELECT id, user_id, case_code, public_title, public_title_ar,
	             NULL::text, NULL::text,
	             full_name, national_id, phone, gender, date_of_birth::text, marital_status,
	             city, district, address, family_members_count,
	             income_amount::text, housing_status, work_status,
	             health_status, education_status, actual_needs,
	             priority_level, verification_status, public_visibility,
	             review_notes, created_at, updated_at
	        FROM beneficiary_cases` + where + `
	       ORDER BY` + priorityOrderClause + ` LIMIT $` + itoa(limitIdx) + ` OFFSET $` + itoa(offsetIdx)
	args = append(args, perPage, offset)

	items, err := s.queryCases(ctx, sqlStr, args...)
	if err != nil {
		return nil, err
	}
	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &AdminPage[Case]{
		Items:      items,
		Page:       page,
		PerPage:    perPage,
		TotalItems: total,
		TotalPages: totalPages,
		HasMore:    page < totalPages,
	}, nil
}

// AdminListRequests returns a paginated list of beneficiary_project_requests
// across all users, optionally filtered by status and a free-text search.
func (s *Store) AdminListRequests(ctx context.Context, page, perPage int, status, q string) (*AdminPage[ProjectRequest], error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 200 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	conds := []string{}
	if status != "" {
		args = append(args, status)
		conds = append(conds, "status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		conds = append(conds, "(project_title ILIKE $"+idx+" OR category ILIKE $"+idx+" OR location ILIKE $"+idx+" OR beneficiary_community_name ILIKE $"+idx+")")
	}
	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM beneficiary_project_requests"+where, args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	sqlStr := `SELECT id, user_id, project_title, project_title_ar,
	             NULL::text, NULL::text,
	             category, category_ar,
	             NULL::text, NULL::text,
	             summary, summary_ar,
	             NULL::text, NULL::text,
	             amount_needed::text, raised_amount, currency,
	             location, location_ar,
	             NULL::text, NULL::text,
	             beneficiary_community_name, beneficiary_community_name_ar,
	             NULL::text, NULL::text,
	             people_affected_total, status, like_count, comment_count,
	             created_at, updated_at
	        FROM beneficiary_project_requests` + where + `
	       ORDER BY id DESC LIMIT $` + itoa(limitIdx) + ` OFFSET $` + itoa(offsetIdx)
	args = append(args, perPage, offset)

	rows, err := s.Pool.Query(ctx, sqlStr, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []ProjectRequest{}
	for rows.Next() {
		var r ProjectRequest
		err := rows.Scan(
			&r.ID, &r.UserID, &r.ProjectTitle, &r.ProjectTitleAr,
			&r.ProjectTitleSorani, &r.ProjectTitleBadini,
			&r.Category, &r.CategoryAr,
			&r.CategorySorani, &r.CategoryBadini,
			&r.Summary, &r.SummaryAr,
			&r.SummarySorani, &r.SummaryBadini,
			&r.AmountNeeded, &r.RaisedAmount, &r.Currency,
			&r.Location, &r.LocationAr,
			&r.LocationSorani, &r.LocationBadini,
			&r.BeneficiaryCommunityName, &r.BeneficiaryCommunityNameAr,
			&r.BeneficiaryCommunityNameSorani, &r.BeneficiaryCommunityNameBadini,
			&r.PeopleAffectedTotal, &r.Status, &r.LikeCount, &r.CommentCount,
			&r.CreatedAt, &r.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &AdminPage[ProjectRequest]{
		Items:      items,
		Page:       page,
		PerPage:    perPage,
		TotalItems: total,
		TotalPages: totalPages,
		HasMore:    page < totalPages,
	}, nil
}

func randHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
