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
	ID                 int64     `json:"id"`
	ProfileCode        string    `json:"profile_code"`
	Gender             *string   `json:"gender"`
	Age                *int      `json:"age"`
	City               *string   `json:"city"`
	SocialSummary      *string   `json:"social_summary"`
	VisibilityLevel    string    `json:"visibility_level"`
	SubscriptionStatus string    `json:"subscription_status"`
	Status             string    `json:"status"`
	CreatedAt          time.Time `json:"created_at"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns marriage profiles. statusFilter="public" (default) means
// active/under_review/submitted; "all" means no filter; anything else is an
// exact match.
func (s *Store) List(ctx context.Context, statusFilter, q string, limit int) ([]Profile, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	args := []any{}
	conds := []string{}
	switch statusFilter {
	case "", "public":
		conds = append(conds, "status IN ('active','under_review','submitted')")
	case "all":
		// no status filter
	default:
		args = append(args, statusFilter)
		conds = append(conds, "status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		conds = append(conds, "(profile_code ILIKE $"+idx+" OR city ILIKE $"+idx+" OR social_summary ILIKE $"+idx+")")
	}
	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}
	args = append(args, limit)
	limitIdx := len(args)
	sqlStr := `SELECT id, profile_code, gender, age, city, social_summary,
	             visibility_level, subscription_status, status, created_at
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
		if err := rows.Scan(&p.ID, &p.ProfileCode, &p.Gender, &p.Age, &p.City, &p.SocialSummary,
			&p.VisibilityLevel, &p.SubscriptionStatus, &p.Status, &p.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
}

// Insert creates a marriage_profiles row and returns id + profile_code.
func (s *Store) Insert(ctx context.Context, userID int64,
	gender *string, age *int, city, socialSummary, privateNotes *string,
	subscriptionStatus string) (int64, string, error) {
	if userID <= 0 {
		return 0, "", errors.New("invalid userID")
	}
	switch subscriptionStatus {
	case "free", "paid", "waived":
	default:
		subscriptionStatus = "free"
	}
	rh, err := randHex(3)
	if err != nil {
		return 0, "", err
	}
	code := "M-" + time.Now().UTC().Format("20060102") + "-" + strings.ToUpper(rh)
	var id int64
	err = s.Pool.QueryRow(ctx, `
		INSERT INTO marriage_profiles
		   (user_id, profile_code, gender, age, city, social_summary, private_notes, subscription_status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		userID, code, gender, age, city, socialSummary, privateNotes, subscriptionStatus,
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
