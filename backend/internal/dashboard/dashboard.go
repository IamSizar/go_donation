// Package dashboard builds the role-aware summary for /api/dashboard.
package dashboard

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Stats map[string]any

type RecentNotification struct {
	ID                   int64     `json:"id"`
	Title                string    `json:"title"`
	TitleAr              *string   `json:"title_ar"`
	Body                 string    `json:"body"`
	BodyAr               *string   `json:"body_ar"`
	NotificationType     *string   `json:"notification_type"`
	NotificationCategory string    `json:"notification_category"`
	Priority             int       `json:"priority"`
	CreatedAt            time.Time `json:"created_at"`
}

type Donation struct {
	ID              int64     `json:"id"`
	Amount          string    `json:"amount"`
	PaymentStatus   int       `json:"payment_status"`
	PaymentMethod   string    `json:"payment_method"`
	TransactionDate time.Time `json:"transaction_date"`
	DonationKind    string    `json:"donation_kind"`
	CampaignTitle   string    `json:"campaign_title"`
}

type Case struct {
	ID            int64   `json:"id"`
	CaseCode      string  `json:"case_code"`
	PublicTitle   string  `json:"public_title"`
	PublicTitleAr *string `json:"public_title_ar"`
	PriorityLevel string  `json:"priority_level"`
	// Note #15 — nullable, same reason as beneficiary.Case.VerificationStatus:
	// the column has no NOT NULL/DEFAULT, and legacy self-submitted rows can
	// have SQL NULL here.
	VerificationStatus *string   `json:"verification_status"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type Request struct {
	ID             int64     `json:"id"`
	ProjectTitle   string    `json:"project_title"`
	ProjectTitleAr *string   `json:"project_title_ar"`
	Status         string    `json:"status"`
	AmountNeeded   string    `json:"amount_needed"`
	Currency       string    `json:"currency"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type Application struct {
	ID           int64     `json:"id"`
	Status       string    `json:"status"`
	City         *string   `json:"city"`
	Availability *string   `json:"availability"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type UpcomingMission struct {
	SignupStatus string     `json:"signup_status"`
	HoursServed  string     `json:"hours_served"`
	UpdatedAt    time.Time  `json:"updated_at"`
	ID           int64      `json:"id"`
	Title        string     `json:"title"`
	TitleAr      *string    `json:"title_ar"`
	City         *string    `json:"city"`
	MissionDate  *time.Time `json:"mission_date"`
	Status       string     `json:"status"`
}

type Summary struct {
	Stats               Stats                `json:"stats"`
	RecentDonations     []Donation           `json:"recent_donations,omitempty"`
	RecentCases         []Case               `json:"recent_cases,omitempty"`
	RecentRequests      []Request            `json:"recent_requests,omitempty"`
	Application         *Application         `json:"application,omitempty"`
	UpcomingMissions    []UpcomingMission    `json:"upcoming_missions,omitempty"`
	RecentNotifications []RecentNotification `json:"recent_notifications"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// RoleKey maps role_id to a stable string for the response.
func RoleKey(roleID int) string {
	switch roleID {
	case 1:
		return "donor"
	case 2:
		return "beneficiary"
	case 3:
		return "volunteer"
	default:
		return "guest"
	}
}

// Compute returns the role-aware summary for the user.
func (s *Store) Compute(ctx context.Context, userID int64, roleID int) (*Summary, error) {
	switch roleID {
	case 1:
		return s.donorSummary(ctx, userID)
	case 2:
		return s.beneficiarySummary(ctx, userID)
	case 3:
		return s.volunteerSummary(ctx, userID)
	default:
		recent, _ := s.recentNotifications(ctx, userID)
		return &Summary{Stats: Stats{}, RecentNotifications: recent}, nil
	}
}

func (s *Store) recentNotifications(ctx context.Context, userID int64) ([]RecentNotification, error) {
	if userID <= 0 {
		return []RecentNotification{}, nil
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT id, title, title_ar, body, body_ar, notification_type,
		       notification_category, priority, created_at
		  FROM app_notifications
		 WHERE user_id = $1
		 ORDER BY is_read ASC, priority DESC, id DESC
		 LIMIT 3`, userID)
	if err != nil {
		return []RecentNotification{}, nil
	}
	defer rows.Close()
	items := []RecentNotification{}
	for rows.Next() {
		var n RecentNotification
		if err := rows.Scan(&n.ID, &n.Title, &n.TitleAr, &n.Body, &n.BodyAr,
			&n.NotificationType, &n.NotificationCategory, &n.Priority, &n.CreatedAt); err != nil {
			return items, nil
		}
		items = append(items, n)
	}
	return items, nil
}

func (s *Store) donorSummary(ctx context.Context, userID int64) (*Summary, error) {
	stats := Stats{
		"successful_amount":    "0",
		"successful_count":     0,
		"pending_count":        0,
		"active_sponsorships":  0,
		"pending_sponsorships": 0,
		"active_campaigns":     0,
	}

	// Donation rollup
	var totalCount, successCount, pendingCount int
	var successAmt string
	_ = s.Pool.QueryRow(ctx, `
		SELECT COUNT(*),
		       COALESCE(SUM(CASE WHEN payment_status = 1 THEN 1 ELSE 0 END), 0),
		       COALESCE(SUM(CASE WHEN payment_status = 2 THEN 1 ELSE 0 END), 0),
		       COALESCE(SUM(CASE WHEN payment_status = 1 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::text
		  FROM donations
		 WHERE user_id = $1`, userID,
	).Scan(&totalCount, &successCount, &pendingCount, &successAmt)
	stats["successful_count"] = successCount
	stats["pending_count"] = pendingCount
	stats["successful_amount"] = successAmt

	// Recent donations
	recent := []Donation{}
	rows, err := s.Pool.Query(ctx, `
		SELECT d.id, d.amount, d.payment_status, d.payment_method, d.transaction_date,
		       d.donation_kind,
		       COALESCE(c.title, 'General support')
		  FROM donations d
		  LEFT JOIN campaigns c ON c.id = d.campaign_id
		 WHERE d.user_id = $1
		 ORDER BY d.transaction_date DESC, d.id DESC
		 LIMIT 4`, userID)
	if err == nil {
		for rows.Next() {
			var d Donation
			if err := rows.Scan(&d.ID, &d.Amount, &d.PaymentStatus, &d.PaymentMethod,
				&d.TransactionDate, &d.DonationKind, &d.CampaignTitle); err == nil {
				recent = append(recent, d)
			}
		}
		rows.Close()
	}

	// Sponsorships rollup
	var spActive, spPending int
	_ = s.Pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END), 0),
		       COALESCE(SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END), 0)
		  FROM sponsorships
		 WHERE donor_user_id = $1`, userID).Scan(&spActive, &spPending)
	stats["active_sponsorships"] = spActive
	stats["pending_sponsorships"] = spPending

	// Active "campaigns" — approved beneficiary_project_requests
	var activeCampaigns int
	_ = s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM beneficiary_project_requests WHERE status = 'approved'`,
	).Scan(&activeCampaigns)
	stats["active_campaigns"] = activeCampaigns

	notifs, _ := s.recentNotifications(ctx, userID)
	return &Summary{Stats: stats, RecentDonations: recent, RecentNotifications: notifs}, nil
}

func (s *Store) beneficiarySummary(ctx context.Context, userID int64) (*Summary, error) {
	stats := Stats{
		"active_cases":         0,
		"approved_cases":       0,
		"needs_changes_cases":  0,
		"pending_requests":     0,
		"approved_requests":    0,
		"open_support_tickets": 0,
	}
	var act, app, ncc int
	_ = s.Pool.QueryRow(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN verification_status IN ('submitted','under_review') THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN verification_status = 'approved' THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN verification_status = 'needs_changes' THEN 1 ELSE 0 END), 0)
		FROM beneficiary_cases WHERE user_id = $1`, userID).Scan(&act, &app, &ncc)
	stats["active_cases"] = act
	stats["approved_cases"] = app
	stats["needs_changes_cases"] = ncc

	recentCases := []Case{}
	rows, err := s.Pool.Query(ctx, `
		SELECT id, case_code, public_title, public_title_ar, priority_level, verification_status, updated_at
		  FROM beneficiary_cases WHERE user_id = $1
		 ORDER BY updated_at DESC, id DESC LIMIT 4`, userID)
	if err == nil {
		for rows.Next() {
			var x Case
			if err := rows.Scan(&x.ID, &x.CaseCode, &x.PublicTitle, &x.PublicTitleAr,
				&x.PriorityLevel, &x.VerificationStatus, &x.UpdatedAt); err == nil {
				recentCases = append(recentCases, x)
			}
		}
		rows.Close()
	}

	var pr, ap int
	_ = s.Pool.QueryRow(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN status IN ('submitted','pending','under_review') THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END), 0)
		FROM beneficiary_project_requests WHERE user_id = $1`, userID).Scan(&pr, &ap)
	stats["pending_requests"] = pr
	stats["approved_requests"] = ap

	recentRequests := []Request{}
	rows, err = s.Pool.Query(ctx, `
		SELECT id, project_title, project_title_ar, status, amount_needed::text, currency, updated_at
		  FROM beneficiary_project_requests WHERE user_id = $1
		 ORDER BY updated_at DESC, id DESC LIMIT 4`, userID)
	if err == nil {
		for rows.Next() {
			var x Request
			if err := rows.Scan(&x.ID, &x.ProjectTitle, &x.ProjectTitleAr, &x.Status,
				&x.AmountNeeded, &x.Currency, &x.UpdatedAt); err == nil {
				recentRequests = append(recentRequests, x)
			}
		}
		rows.Close()
	}

	var openTickets int
	_ = s.Pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(CASE WHEN status IN ('open','in_progress') THEN 1 ELSE 0 END), 0)
		   FROM support_tickets WHERE user_id = $1`, userID,
	).Scan(&openTickets)
	stats["open_support_tickets"] = openTickets

	notifs, _ := s.recentNotifications(ctx, userID)
	return &Summary{
		Stats: stats, RecentCases: recentCases, RecentRequests: recentRequests,
		RecentNotifications: notifs,
	}, nil
}

func (s *Store) volunteerSummary(ctx context.Context, userID int64) (*Summary, error) {
	stats := Stats{
		"application_status": "",
		"active_missions":    0,
		"completed_missions": 0,
		"hours_served":       "0",
		"available_missions": 0,
	}

	var app *Application
	{
		var x Application
		err := s.Pool.QueryRow(ctx, `
			SELECT id, status, city, availability, created_at, updated_at
			  FROM volunteer_applications WHERE user_id = $1
			 ORDER BY id DESC LIMIT 1`, userID,
		).Scan(&x.ID, &x.Status, &x.City, &x.Availability, &x.CreatedAt, &x.UpdatedAt)
		if err == nil {
			app = &x
			stats["application_status"] = x.Status
		}
	}

	var active, completed int
	var hours string
	_ = s.Pool.QueryRow(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN status IN ('approved','joined','pending') THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(hours_served), 0)::text
		FROM volunteer_mission_signups WHERE user_id = $1`, userID,
	).Scan(&active, &completed, &hours)
	stats["active_missions"] = active
	stats["completed_missions"] = completed
	stats["hours_served"] = hours

	upcoming := []UpcomingMission{}
	rows, err := s.Pool.Query(ctx, `
		SELECT s.status, s.hours_served::text, s.updated_at,
		       m.id, m.title, m.title_ar, m.city, m.mission_date, m.status
		  FROM volunteer_mission_signups s
		  INNER JOIN volunteer_missions m ON m.id = s.mission_id
		 WHERE s.user_id = $1 AND s.status NOT IN ('cancelled','rejected')
		 ORDER BY COALESCE(m.mission_date, '2999-12-31'::date) ASC, s.id DESC
		 LIMIT 4`, userID)
	if err == nil {
		for rows.Next() {
			var x UpcomingMission
			if err := rows.Scan(&x.SignupStatus, &x.HoursServed, &x.UpdatedAt,
				&x.ID, &x.Title, &x.TitleAr, &x.City, &x.MissionDate, &x.Status); err == nil {
				upcoming = append(upcoming, x)
			}
		}
		rows.Close()
	}

	var avail int
	_ = s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM volunteer_missions WHERE status = 'open'`,
	).Scan(&avail)
	stats["available_missions"] = avail

	notifs, _ := s.recentNotifications(ctx, userID)
	return &Summary{
		Stats: stats, Application: app, UpcomingMissions: upcoming,
		RecentNotifications: notifs,
	}, nil
}
