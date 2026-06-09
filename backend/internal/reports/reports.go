// Package reports computes the admin system snapshot shown on /api/reports.
package reports

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DonationSummary mirrors the PHP shape: one row of counts/amounts.
type DonationSummary struct {
	TotalCount      int    `json:"total_count"`
	CompletedAmount string `json:"completed_amount"`
	PendingAmount   string `json:"pending_amount"`
	FailedAmount    string `json:"failed_amount"`
}

// Bucket is a (label, total) pair used for status / category breakdowns.
type Bucket struct {
	Label string `json:"label"`
	Total int    `json:"total"`
}

// ExpenseBucket pairs an expense_type with summed amount.
type ExpenseBucket struct {
	ExpenseType string `json:"expense_type"`
	Amount      string `json:"amount"`
}

// VolunteerOverview is the system-wide volunteer rollup.
type VolunteerOverview struct {
	ApplicationsTotal    int    `json:"applications_total"`
	ApplicationsApproved int    `json:"applications_approved"`
	MissionsOpen         int    `json:"missions_open"`
	MissionsCompleted    int    `json:"missions_completed"`
	SignupsPending       int    `json:"signups_pending"`
	SignupsActive        int    `json:"signups_active"`
	SignupsCompleted     int    `json:"signups_completed"`
	AttendedTotal        int    `json:"attended_total"`
	HoursServed          string `json:"hours_served"`
}

// Report is the full payload returned by GET /api/reports.
type Report struct {
	Donations              DonationSummary   `json:"donations"`
	BeneficiaryCases       []Bucket          `json:"beneficiary_cases"`
	ProjectRequests        []Bucket          `json:"project_requests"`
	Expenses               []ExpenseBucket   `json:"expenses"`
	Volunteers             VolunteerOverview `json:"volunteers"`
	VolunteerSignupStatuses []Bucket         `json:"volunteer_signup_statuses"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

func (s *Store) Compute(ctx context.Context) (*Report, error) {
	r := &Report{
		Donations: DonationSummary{
			CompletedAmount: "0", PendingAmount: "0", FailedAmount: "0",
		},
		Volunteers: VolunteerOverview{HoursServed: "0"},
		BeneficiaryCases:        []Bucket{},
		ProjectRequests:         []Bucket{},
		Expenses:                []ExpenseBucket{},
		VolunteerSignupStatuses: []Bucket{},
	}

	// Donations summary (amount stored as VARCHAR, cast to NUMERIC).
	err := s.Pool.QueryRow(ctx, `
		SELECT
		  COUNT(*),
		  COALESCE(SUM(CASE WHEN payment_status = 1 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::text,
		  COALESCE(SUM(CASE WHEN payment_status = 2 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::text,
		  COALESCE(SUM(CASE WHEN payment_status = 3 THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::text
		FROM donations`,
	).Scan(&r.Donations.TotalCount, &r.Donations.CompletedAmount, &r.Donations.PendingAmount, &r.Donations.FailedAmount)
	if err != nil {
		return nil, err
	}

	// Beneficiary cases by verification_status.
	rows, err := s.Pool.Query(ctx,
		`SELECT verification_status, COUNT(*) FROM beneficiary_cases GROUP BY verification_status`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var b Bucket
		if err := rows.Scan(&b.Label, &b.Total); err != nil {
			rows.Close()
			return nil, err
		}
		r.BeneficiaryCases = append(r.BeneficiaryCases, b)
	}
	rows.Close()

	// Project requests by status.
	rows, err = s.Pool.Query(ctx,
		`SELECT status, COUNT(*) FROM beneficiary_project_requests GROUP BY status`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var b Bucket
		if err := rows.Scan(&b.Label, &b.Total); err != nil {
			rows.Close()
			return nil, err
		}
		r.ProjectRequests = append(r.ProjectRequests, b)
	}
	rows.Close()

	// Expenses by type.
	rows, err = s.Pool.Query(ctx,
		`SELECT expense_type, COALESCE(SUM(amount), 0)::text FROM financial_expenses GROUP BY expense_type`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var b ExpenseBucket
		if err := rows.Scan(&b.ExpenseType, &b.Amount); err != nil {
			rows.Close()
			return nil, err
		}
		r.Expenses = append(r.Expenses, b)
	}
	rows.Close()

	// Volunteer overview (all scalars in one row).
	err = s.Pool.QueryRow(ctx, `
		SELECT
		  (SELECT COUNT(*) FROM volunteer_applications),
		  (SELECT COUNT(*) FROM volunteer_applications WHERE status = 'approved'),
		  (SELECT COUNT(*) FROM volunteer_missions WHERE status = 'open'),
		  (SELECT COUNT(*) FROM volunteer_missions WHERE status = 'completed'),
		  (SELECT COUNT(*) FROM volunteer_mission_signups WHERE status = 'pending'),
		  (SELECT COUNT(*) FROM volunteer_mission_signups WHERE status IN ('approved','joined')),
		  (SELECT COUNT(*) FROM volunteer_mission_signups WHERE status = 'completed'),
		  (SELECT COUNT(*) FROM volunteer_mission_signups WHERE checked_in_at IS NOT NULL),
		  (SELECT COALESCE(SUM(hours_served), 0) FROM volunteer_mission_signups)::text`,
	).Scan(
		&r.Volunteers.ApplicationsTotal, &r.Volunteers.ApplicationsApproved,
		&r.Volunteers.MissionsOpen, &r.Volunteers.MissionsCompleted,
		&r.Volunteers.SignupsPending, &r.Volunteers.SignupsActive,
		&r.Volunteers.SignupsCompleted, &r.Volunteers.AttendedTotal, &r.Volunteers.HoursServed,
	)
	if err != nil {
		return nil, err
	}

	// Volunteer signup status breakdown.
	rows, err = s.Pool.Query(ctx,
		`SELECT status, COUNT(*) FROM volunteer_mission_signups GROUP BY status`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var b Bucket
		if err := rows.Scan(&b.Label, &b.Total); err != nil {
			rows.Close()
			return nil, err
		}
		r.VolunteerSignupStatuses = append(r.VolunteerSignupStatuses, b)
	}
	rows.Close()

	return r, nil
}
