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
)

type Profile struct {
	ID int64 `json:"id"`
	// Note #18 — exposed so "my own profile" responses (OwnedByUser filter)
	// can be told apart from another user's; omitted from nothing (it was
	// always selected, just never scanned/exposed before).
	UserID             int64     `json:"user_id"`
	ProfileCode        string    `json:"profile_code"`
	Gender             *string   `json:"gender"`
	Age                *int      `json:"age"`
	City               *string   `json:"city"`
	SocialSummary      *string   `json:"social_summary"`
	// Client note — Marriage "Search" filters: marital status/employment
	// status are small fixed sets (see MaritalStatuses/EmploymentStatuses);
	// religion stays free text rather than a hardcoded taxonomy.
	MaritalStatus      *string   `json:"marital_status"`
	Religion           *string   `json:"religion"`
	EmploymentStatus   *string   `json:"employment_status"`
	WeightKg           *int      `json:"weight_kg"`
	HeightCm           *int      `json:"height_cm"`
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
	BeforeID         int64
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
func (s *Store) RequestMeeting(ctx context.Context, fromUserID, profileID int64, message string) (int64, error) {
	var msg any
	if strings.TrimSpace(message) != "" {
		msg = message
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id, message)
		 VALUES ($1, $2, $3) RETURNING id`, fromUserID, profileID, msg).Scan(&id)
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
