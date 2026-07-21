// Package sponsorships handles sponsorships (recurring giving).
package sponsorships

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Sponsorship struct {
	ID                int64     `json:"id"`
	DonorUserID       *int      `json:"donor_user_id"`
	DonorPhone        *string   `json:"donor_phone"`
	DonorFullName     *string   `json:"donor_full_name"`
	BeneficiaryCaseID *int64    `json:"beneficiary_case_id"`
	ProjectRequestID  *int64    `json:"project_request_id"`
	SponsorshipType   string    `json:"sponsorship_type"`
	Amount            string    `json:"amount"`
	Currency          string    `json:"currency"`
	ScheduleInterval  string    `json:"schedule_interval"`
	NextDueDate       *time.Time `json:"next_due_date"`
	Status            string    `json:"status"`
	Notes             *string   `json:"notes"`
	CreatedAt         time.Time `json:"created_at"`
	ProjectTitle      string    `json:"project_title"`
	ProjectTitleAr    string    `json:"project_title_ar"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns sponsorships, optionally filtered to a single donor.
// Sort: active first, then by next_due_date asc, id desc.
func (s *Store) List(ctx context.Context, donorUserID int64, q string, limit int) ([]Sponsorship, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	args := []any{}
	where := []string{"1=1"}
	if donorUserID > 0 {
		args = append(args, donorUserID)
		where = append(where, "s.donor_user_id = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		where = append(where, "(s.sponsorship_type ILIKE $"+idx+" OR s.notes ILIKE $"+idx+" OR p.project_title ILIKE $"+idx+")")
	}
	sqlStr := `
		SELECT s.id, s.donor_user_id, u.phone, up.full_name,
		       s.beneficiary_case_id, s.project_request_id,
		       s.sponsorship_type, s.amount::text, s.currency, s.schedule_interval,
		       s.next_due_date, s.status, s.notes, s.created_at,
		       COALESCE(p.project_title, 'General support') AS project_title,
		       COALESCE(p.project_title_ar, 'الدعم العام')  AS project_title_ar
		  FROM sponsorships s
		  LEFT JOIN beneficiary_project_requests p ON p.id = s.project_request_id
		  LEFT JOIN users u ON u.id = s.donor_user_id
		  LEFT JOIN user_profiles up ON up.user_id = s.donor_user_id
		 WHERE ` + strings.Join(where, " AND ") + `
		 ORDER BY
		   CASE s.status
		     WHEN 'active' THEN 1 WHEN 'pending' THEN 2 WHEN 'paused' THEN 3
		     WHEN 'delayed' THEN 4 WHEN 'stopped' THEN 5 WHEN 'completed' THEN 6
		     WHEN 'cancelled' THEN 7 ELSE 8
		   END ASC,
		   s.next_due_date ASC NULLS LAST,
		   s.id DESC
		 LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, sqlStr, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Sponsorship{}
	for rows.Next() {
		var x Sponsorship
		if err := rows.Scan(&x.ID, &x.DonorUserID, &x.DonorPhone, &x.DonorFullName,
			&x.BeneficiaryCaseID, &x.ProjectRequestID,
			&x.SponsorshipType, &x.Amount, &x.Currency, &x.ScheduleInterval,
			&x.NextDueDate, &x.Status, &x.Notes, &x.CreatedAt,
			&x.ProjectTitle, &x.ProjectTitleAr); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

// ListByBeneficiary returns sponsorships that BENEFIT the given user — i.e.
// sponsorships whose beneficiary_case_id points at a case the user owns (#21,
// the beneficiary "My Entitlements" view). Distinct from List, which is the
// donor-side view (filtered by donor_user_id). Active/pending/delayed/paused
// only — the ones the beneficiary is still entitled to receive.
func (s *Store) ListByBeneficiary(ctx context.Context, userID int64) ([]Sponsorship, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT s.id, s.donor_user_id, s.beneficiary_case_id, s.project_request_id,
		       s.sponsorship_type, s.amount::text, s.currency, s.schedule_interval,
		       s.next_due_date, s.status, s.notes, s.created_at,
		       COALESCE(p.project_title, 'General support') AS project_title,
		       COALESCE(p.project_title_ar, 'الدعم العام')  AS project_title_ar
		  FROM sponsorships s
		  JOIN beneficiary_cases bc ON bc.id = s.beneficiary_case_id
		  LEFT JOIN beneficiary_project_requests p ON p.id = s.project_request_id
		 WHERE bc.user_id = $1
		   AND s.status IN ('active','pending','delayed','paused')
		 ORDER BY
		   CASE s.status WHEN 'active' THEN 1 WHEN 'delayed' THEN 2
		     WHEN 'pending' THEN 3 WHEN 'paused' THEN 4 ELSE 5 END ASC,
		   s.next_due_date ASC NULLS LAST,
		   s.id DESC`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Sponsorship{}
	for rows.Next() {
		var x Sponsorship
		if err := rows.Scan(&x.ID, &x.DonorUserID, &x.BeneficiaryCaseID, &x.ProjectRequestID,
			&x.SponsorshipType, &x.Amount, &x.Currency, &x.ScheduleInterval,
			&x.NextDueDate, &x.Status, &x.Notes, &x.CreatedAt,
			&x.ProjectTitle, &x.ProjectTitleAr); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

// ProjectRow is a tiny row used for sponsorship notifications.
type ProjectRow struct {
	ID             int64
	ProjectTitle   string
	ProjectTitleAr string
}

// GetApprovedProject looks up an approved project for sponsorship targeting.
func (s *Store) GetApprovedProject(ctx context.Context, id int64) (*ProjectRow, error) {
	if id <= 0 {
		return nil, nil
	}
	var p ProjectRow
	err := s.Pool.QueryRow(ctx,
		`SELECT id, project_title, COALESCE(project_title_ar,'')
		   FROM beneficiary_project_requests
		  WHERE id = $1 AND status = 'approved'`,
		id,
	).Scan(&p.ID, &p.ProjectTitle, &p.ProjectTitleAr)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}

// IntervalToDuration maps the schedule_interval to a Duration for "next due" math.
func IntervalToDuration(interval string) time.Duration {
	switch interval {
	case "weekly":
		return 7 * 24 * time.Hour
	case "quarterly":
		return 90 * 24 * time.Hour
	case "yearly":
		return 365 * 24 * time.Hour
	default: // monthly
		return 30 * 24 * time.Hour
	}
}

// Insert writes a new sponsorship row in 'pending' status.
func (s *Store) Insert(ctx context.Context,
	donorUserID int64, beneficiaryCaseID, projectRequestID *int64,
	sponsorshipType string, amount float64, currency, interval string,
	nextDueDate *time.Time, notes *string,
) (int64, error) {
	if donorUserID <= 0 {
		return 0, errors.New("invalid donorUserID")
	}
	sponsorshipType = strings.TrimSpace(sponsorshipType)
	if sponsorshipType == "" || amount <= 0 {
		return 0, errors.New("missing sponsorship_type or amount")
	}
	switch interval {
	case "weekly", "monthly", "quarterly", "yearly":
	default:
		interval = "monthly"
	}
	currency = strings.ToUpper(strings.TrimSpace(currency))
	if currency == "" {
		currency = "IQD"
	}
	if len(currency) > 3 {
		currency = currency[:3]
	}
	if nextDueDate == nil {
		t := time.Now().UTC().Add(IntervalToDuration(interval))
		nextDueDate = &t
	}

	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO sponsorships
		   (donor_user_id, beneficiary_case_id, project_request_id,
		    sponsorship_type, amount, currency, schedule_interval,
		    next_due_date, status, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending', $9)
		RETURNING id`,
		donorUserID, beneficiaryCaseID, projectRequestID,
		sponsorshipType, amount, currency, interval,
		nextDueDate.Format("2006-01-02"), notes,
	).Scan(&id)
	return id, err
}

// DueReminderRow is one active sponsorship whose payment is due within the
// reminder window and hasn't been reminded for this cycle yet. Everything the
// scheduler needs to build + address a localized "payment due" reminder.
type DueReminderRow struct {
	ID               int64
	DonorUserID      int64
	Amount           string
	Currency         string
	NextDueDate      time.Time
	ScheduleInterval string
	ProjectTitle     string
	ProjectTitleAr   string
}

// DueForReminder returns active sponsorships whose next_due_date falls on or
// before (today + daysBefore) and which haven't already been reminded for the
// current cycle (last_reminder_due_date IS DISTINCT FROM next_due_date). This
// naturally covers overdue rows too (next_due_date in the past). The
// per-cycle marker is what stops the same reminder re-firing every tick.
func (s *Store) DueForReminder(ctx context.Context, daysBefore, limit int) ([]DueReminderRow, error) {
	if daysBefore < 0 {
		daysBefore = 0
	}
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT s.id, s.donor_user_id, s.amount::text, s.currency,
		       s.next_due_date, s.schedule_interval,
		       COALESCE(p.project_title, 'General support') AS project_title,
		       COALESCE(p.project_title_ar, 'الدعم العام')  AS project_title_ar
		  FROM sponsorships s
		  LEFT JOIN beneficiary_project_requests p ON p.id = s.project_request_id
		 WHERE s.status = 'active'
		   AND s.donor_user_id IS NOT NULL
		   AND s.next_due_date IS NOT NULL
		   AND s.next_due_date <= (CURRENT_DATE + ($1 * INTERVAL '1 day'))
		   AND s.last_reminder_due_date IS DISTINCT FROM s.next_due_date
		 ORDER BY s.next_due_date ASC, s.id ASC
		 LIMIT `+itoa(limit),
		daysBefore,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []DueReminderRow{}
	for rows.Next() {
		var r DueReminderRow
		if err := rows.Scan(&r.ID, &r.DonorUserID, &r.Amount, &r.Currency,
			&r.NextDueDate, &r.ScheduleInterval, &r.ProjectTitle, &r.ProjectTitleAr); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// MarkReminded stamps last_reminder_due_date so this cycle won't be reminded
// again. Guarded on the due date to avoid clobbering a marker if the row's
// due date advanced (payment recorded) between the scan and this write.
func (s *Store) MarkReminded(ctx context.Context, id int64, dueDate time.Time) error {
	_, err := s.Pool.Exec(ctx,
		`UPDATE sponsorships
		    SET last_reminder_due_date = $2
		  WHERE id = $1 AND next_due_date = $2`,
		id, dueDate.Format("2006-01-02"),
	)
	return err
}

// CancelResult is the outcome of Cancel().
type CancelResult int

const (
	CancelOK CancelResult = iota
	CancelNotFound
)

// Cancel marks the sponsorship cancelled (only if active/pending/paused/delayed).
// Returns the project_request_id (if any) so the handler can produce a meaningful notification.
func (s *Store) Cancel(ctx context.Context, id, userID int64) (CancelResult, *int64, error) {
	if id <= 0 || userID <= 0 {
		return CancelNotFound, nil, errors.New("invalid args")
	}
	var projectRequestID *int64
	err := s.Pool.QueryRow(ctx,
		`SELECT project_request_id FROM sponsorships
		  WHERE id = $1 AND donor_user_id = $2`,
		id, userID,
	).Scan(&projectRequestID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return CancelNotFound, nil, nil
		}
		return CancelNotFound, nil, err
	}
	_, err = s.Pool.Exec(ctx,
		`UPDATE sponsorships
		    SET status = 'cancelled', next_due_date = NULL
		  WHERE id = $1 AND donor_user_id = $2
		    AND status IN ('pending','active','paused','delayed')`,
		id, userID,
	)
	if err != nil {
		return CancelNotFound, nil, err
	}
	return CancelOK, projectRequestID, nil
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
