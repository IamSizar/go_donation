// Package sponsorshipschedule implements "Eighth: Sponsorship Schedule and
// Calendar" — the per-occurrence schedule behind a recurring sponsorship, the
// upcoming/due/overdue/history tracking it feeds, and the reminder sweep that
// alerts the grantor and the eligible recipient before a due date.
//
// A sponsorship already carries its recurrence rule (schedule_interval) and
// its next date (next_due_date); this package turns those into concrete rows
// so dates can be tracked, settled and reported on individually.
package sponsorshipschedule

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Occurrence is one scheduled due date on a sponsorship.
type Occurrence struct {
	ID             int64      `json:"id"`
	SponsorshipID  int64      `json:"sponsorship_id"`
	DueDate        string     `json:"due_date"` // YYYY-MM-DD
	Amount         float64    `json:"amount"`
	Currency       string     `json:"currency"`
	Status         string     `json:"status"`
	PaidAt         *time.Time `json:"paid_at"`
	Notes          string     `json:"notes"`
	SponsorshipTyp string     `json:"sponsorship_type"`
	DonorUserID    *int64     `json:"donor_user_id"`
	BeneficiaryID  *int64     `json:"beneficiary_case_id"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// advance returns d moved forward by one interval step.
func advance(d time.Time, interval string) time.Time {
	switch interval {
	case "weekly":
		return d.AddDate(0, 0, 7)
	case "quarterly":
		return d.AddDate(0, 3, 0)
	case "yearly":
		return d.AddDate(1, 0, 0)
	default: // monthly
		return d.AddDate(0, 1, 0)
	}
}

// Generate materialises up to `count` future occurrences for one sponsorship,
// starting at its next_due_date and stepping by its schedule_interval. Rows
// that already exist are left untouched (UNIQUE on sponsorship_id+due_date),
// so calling this repeatedly is safe and idempotent — it simply tops the
// schedule back up.
//
// Returns the number of rows newly created.
func (s *Store) Generate(ctx context.Context, sponsorshipID int64, count int) (int, error) {
	if sponsorshipID <= 0 {
		return 0, errors.New("invalid sponsorshipID")
	}
	if count <= 0 || count > 60 {
		count = 12
	}
	var (
		interval string
		amount   float64
		currency string
		status   string
		next     *time.Time
	)
	err := s.Pool.QueryRow(ctx,
		`SELECT schedule_interval, amount, currency, status, next_due_date
		   FROM sponsorships WHERE id = $1`, sponsorshipID,
	).Scan(&interval, &amount, &currency, &status, &next)
	if err != nil {
		return 0, err
	}
	// Only live sponsorships accrue a schedule.
	if status != "active" && status != "pending" {
		return 0, nil
	}
	start := time.Now().UTC().Truncate(24 * time.Hour)
	if next != nil {
		start = *next
	}

	created := 0
	d := start
	for i := 0; i < count; i++ {
		ct, err := s.Pool.Exec(ctx,
			`INSERT INTO sponsorship_schedule (sponsorship_id, due_date, amount, currency)
			 VALUES ($1, $2, $3, $4)
			 ON CONFLICT (sponsorship_id, due_date) DO NOTHING`,
			sponsorshipID, d.Format("2006-01-02"), amount, currency,
		)
		if err != nil {
			return created, err
		}
		created += int(ct.RowsAffected())
		d = advance(d, interval)
	}
	return created, nil
}

// RefreshStatuses reclassifies unsettled occurrences against today: anything
// past its due date becomes overdue, anything due today (or inside the grace
// window) becomes due, everything later stays upcoming. Settled rows (paid /
// skipped) are never touched. Returns rows changed.
func (s *Store) RefreshStatuses(ctx context.Context) (int64, error) {
	ct, err := s.Pool.Exec(ctx,
		`UPDATE sponsorship_schedule
		    SET status = CASE
		          WHEN due_date <  CURRENT_DATE THEN 'overdue'
		          WHEN due_date =  CURRENT_DATE THEN 'due'
		          ELSE 'upcoming'
		        END
		  WHERE status IN ('upcoming','due','overdue')
		    AND status <> CASE
		          WHEN due_date <  CURRENT_DATE THEN 'overdue'
		          WHEN due_date =  CURRENT_DATE THEN 'due'
		          ELSE 'upcoming'
		        END`)
	if err != nil {
		return 0, err
	}
	return ct.RowsAffected(), nil
}

// MarkPaid settles one occurrence and rolls the parent sponsorship's
// next_due_date forward to the following unsettled date, keeping the existing
// next_due_date field meaningful for callers that only read it.
func (s *Store) MarkPaid(ctx context.Context, occurrenceID int64) error {
	if occurrenceID <= 0 {
		return errors.New("invalid occurrenceID")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var sponsorshipID int64
	if err := tx.QueryRow(ctx,
		`UPDATE sponsorship_schedule
		    SET status = 'paid', paid_at = now()
		  WHERE id = $1 AND status <> 'paid'
		  RETURNING sponsorship_id`, occurrenceID,
	).Scan(&sponsorshipID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE sponsorships
		    SET next_due_date = (
		          SELECT MIN(due_date) FROM sponsorship_schedule
		           WHERE sponsorship_id = $1 AND status IN ('upcoming','due','overdue')
		        ),
		        updated_at = CURRENT_TIMESTAMP
		  WHERE id = $1`, sponsorshipID,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// List returns occurrences for the tracking screen. userID scopes to that
// person's sponsorships (as grantor or as the case's beneficiary); status is
// optional ("" = all). Ordered by due date.
func (s *Store) List(ctx context.Context, userID int64, status string, limit int) ([]Occurrence, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	args := []any{userID, limit}
	statusClause := ""
	if status != "" {
		args = append(args, status)
		statusClause = " AND sc.status = $3"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT sc.id, sc.sponsorship_id, to_char(sc.due_date,'YYYY-MM-DD'),
		        sc.amount, sc.currency, sc.status, sc.paid_at, COALESCE(sc.notes,''),
		        sp.sponsorship_type, sp.donor_user_id, sp.beneficiary_case_id
		   FROM sponsorship_schedule sc
		   JOIN sponsorships sp ON sp.id = sc.sponsorship_id
		   LEFT JOIN beneficiary_cases bc ON bc.id = sp.beneficiary_case_id
		  WHERE (sp.donor_user_id = $1 OR bc.user_id = $1)`+statusClause+`
		  ORDER BY sc.due_date ASC, sc.id ASC
		  LIMIT $2`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []Occurrence{}
	for rows.Next() {
		var o Occurrence
		if err := rows.Scan(&o.ID, &o.SponsorshipID, &o.DueDate, &o.Amount,
			&o.Currency, &o.Status, &o.PaidAt, &o.Notes, &o.SponsorshipTyp,
			&o.DonorUserID, &o.BeneficiaryID); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// DueReminder is one occurrence needing a reminder, with the two people to
// tell and the phone numbers to SMS.
type DueReminder struct {
	OccurrenceID    int64
	DueDate         string
	Amount          float64
	Currency        string
	SponsorshipType string
	GrantorUserID   *int64
	GrantorPhone    string
	RecipientUserID *int64
	RecipientPhone  string
}

// PendingReminders returns unsettled occurrences falling due within
// daysBefore days that haven't been reminded yet.
func (s *Store) PendingReminders(ctx context.Context, daysBefore int) ([]DueReminder, error) {
	if daysBefore < 0 {
		daysBefore = 0
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT sc.id, to_char(sc.due_date,'YYYY-MM-DD'), sc.amount, sc.currency,
		        sp.sponsorship_type,
		        sp.donor_user_id, COALESCE(du.phone,''),
		        bc.user_id,       COALESCE(bu.phone,'')
		   FROM sponsorship_schedule sc
		   JOIN sponsorships sp ON sp.id = sc.sponsorship_id
		   LEFT JOIN users du ON du.id = sp.donor_user_id
		   LEFT JOIN beneficiary_cases bc ON bc.id = sp.beneficiary_case_id
		   LEFT JOIN users bu ON bu.id = bc.user_id
		  WHERE sc.status IN ('upcoming','due','overdue')
		    AND sc.due_date <= CURRENT_DATE + ($1::int)
		    AND (sc.reminded_grantor_at IS NULL OR sc.reminded_recipient_at IS NULL)
		  ORDER BY sc.due_date ASC
		  LIMIT 500`, daysBefore)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []DueReminder{}
	for rows.Next() {
		var r DueReminder
		if err := rows.Scan(&r.OccurrenceID, &r.DueDate, &r.Amount, &r.Currency,
			&r.SponsorshipType, &r.GrantorUserID, &r.GrantorPhone,
			&r.RecipientUserID, &r.RecipientPhone); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// MarkReminded records that a side has been notified, so the sweep never
// double-sends for the same occurrence.
func (s *Store) MarkReminded(ctx context.Context, occurrenceID int64, side string) error {
	col := "reminded_grantor_at"
	if side == "recipient" {
		col = "reminded_recipient_at"
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE sponsorship_schedule SET `+col+` = now() WHERE id = $1`, occurrenceID)
	return err
}
