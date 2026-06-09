// Package history builds the role-aware activity timeline for /api/history.
//
// The PHP version produces a flattened union of events across donations,
// sponsorships, cases, project requests, volunteer applications, and signup
// rows. This Go port mirrors the same shape but keeps each event's `details`
// map concise — Flutter renders the keys directly.
package history

import (
	"context"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Item struct {
	ID         string         `json:"id"`
	Kind       string         `json:"kind"`
	Status     string         `json:"status"`
	Title      string         `json:"title"`
	Subtitle   string         `json:"subtitle"`
	OccurredAt time.Time      `json:"occurred_at"`
	DateLabel  string         `json:"date_label"`
	Amount     *float64       `json:"amount,omitempty"`
	Currency   *string        `json:"currency,omitempty"`
	Details    map[string]any `json:"details"`
}

type Response struct {
	Role          string   `json:"role"`
	Summary       Summary  `json:"summary"`
	KindOptions   []string `json:"kind_options"`
	StatusOptions []string `json:"status_options"`
	Items         []Item   `json:"items"`
}

// Summary is a tiny roll-up shown above the timeline.
type Summary struct {
	TotalEvents int `json:"total_events"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Build returns the timeline (sorted newest-first) for the given user + role.
func (s *Store) Build(ctx context.Context, userID int64, roleID, limit int) (*Response, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	roleKey := mapRoleKey(roleID)

	var items []Item
	switch roleKey {
	case "donor":
		items = append(items, s.donations(ctx, userID, limit)...)
		items = append(items, s.sponsorships(ctx, userID, limit)...)
	case "beneficiary":
		items = append(items, s.cases(ctx, userID, limit)...)
		items = append(items, s.requests(ctx, userID, limit)...)
	case "volunteer":
		items = append(items, s.applications(ctx, userID, limit)...)
		items = append(items, s.signups(ctx, userID, limit)...)
	}

	sort.SliceStable(items, func(i, j int) bool {
		return items[i].OccurredAt.After(items[j].OccurredAt)
	})

	kinds := []string{"all"}
	statuses := []string{"all"}
	seenK := map[string]bool{"all": true}
	seenS := map[string]bool{"all": true}
	for _, it := range items {
		if it.Kind != "" && !seenK[it.Kind] {
			kinds = append(kinds, it.Kind)
			seenK[it.Kind] = true
		}
		if it.Status != "" && !seenS[it.Status] {
			statuses = append(statuses, it.Status)
			seenS[it.Status] = true
		}
	}

	return &Response{
		Role:          roleKey,
		Summary:       Summary{TotalEvents: len(items)},
		KindOptions:   kinds,
		StatusOptions: statuses,
		Items:         items,
	}, nil
}

// ---- event-type collectors ----

func (s *Store) donations(ctx context.Context, userID int64, limit int) []Item {
	// Phase 18c — donations.campaign_id is a FK to `campaigns`, NOT to
	// beneficiary_project_requests. Old join was producing wrong titles
	// because both tables share ids 1 and 2 in the seeded data.
	rows, err := s.Pool.Query(ctx, `
		SELECT d.id, d.reference_number, d.amount, d.payment_status, d.payment_method,
		       d.message, d.impact_note, d.transaction_date,
		       COALESCE(c.title, 'General Support'),
		       'IQD'::text
		  FROM donations d
		  LEFT JOIN campaigns c ON c.id = d.campaign_id
		 WHERE d.user_id = $1
		 ORDER BY d.transaction_date DESC, d.id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var refNum, paymentMethod, message, impactNote *string
		var amount string
		var paymentStatus int
		var txDate time.Time
		var title, currency string
		if err := rows.Scan(&id, &refNum, &amount, &paymentStatus, &paymentMethod,
			&message, &impactNote, &txDate, &title, &currency); err != nil {
			continue
		}
		status := statusFromPayment(paymentStatus)
		amt := parseFloat(amount)
		out = append(out, Item{
			ID:         "donation_" + itoa64(id),
			Kind:       "donation",
			Status:     status,
			Title:      title,
			Subtitle:   label(status) + " payment",
			OccurredAt: txDate,
			DateLabel:  txDate.Format("2006-01-02 15:04:05"),
			Amount:     &amt,
			Currency:   &currency,
			Details: map[string]any{
				"Record type":    "Donation",
				"Campaign":       title,
				"Status":         label(status),
				"Amount":         amount + " " + currency,
				"Payment method": ifEmpty(paymentMethod, "—"),
				"Reference":      ifEmpty(refNum, "—"),
				"Message":        ifEmpty(message, "—"),
				"Impact note":    ifEmpty(impactNote, "—"),
			},
		})
	}
	return out
}

func (s *Store) sponsorships(ctx context.Context, userID int64, limit int) []Item {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, sponsorship_type, amount::text, currency, schedule_interval,
		       next_due_date, status, notes, COALESCE(updated_at, created_at)
		  FROM sponsorships
		 WHERE donor_user_id = $1
		 ORDER BY updated_at DESC, id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var sponsorType, currency, schedule, status string
		var amount string
		var nextDue *time.Time
		var notes *string
		var ts time.Time
		if err := rows.Scan(&id, &sponsorType, &amount, &currency, &schedule, &nextDue,
			&status, &notes, &ts); err != nil {
			continue
		}
		amt := parseFloat(amount)
		ndLabel := "—"
		if nextDue != nil {
			ndLabel = nextDue.Format("2006-01-02")
		}
		out = append(out, Item{
			ID:         "sponsorship_" + itoa64(id),
			Kind:       "sponsorship",
			Status:     status,
			Title:      sponsorType,
			Subtitle:   label(status) + " sponsorship",
			OccurredAt: ts,
			DateLabel:  ts.Format("2006-01-02 15:04:05"),
			Amount:     &amt,
			Currency:   &currency,
			Details: map[string]any{
				"Record type":   "Sponsorship",
				"Plan":          sponsorType,
				"Status":        label(status),
				"Amount":        amount + " " + currency,
				"Schedule":      schedule,
				"Next due date": ndLabel,
				"Notes":         ifEmpty(notes, "—"),
			},
		})
	}
	return out
}

func (s *Store) cases(ctx context.Context, userID int64, limit int) []Item {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, case_code, public_title, priority_level, verification_status,
		       COALESCE(updated_at, created_at)
		  FROM beneficiary_cases
		 WHERE user_id = $1
		 ORDER BY updated_at DESC, id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var code, title, priority, status string
		var ts time.Time
		if err := rows.Scan(&id, &code, &title, &priority, &status, &ts); err != nil {
			continue
		}
		out = append(out, Item{
			ID:         "case_" + itoa64(id),
			Kind:       "case",
			Status:     status,
			Title:      title,
			Subtitle:   label(status) + " case",
			OccurredAt: ts,
			DateLabel:  ts.Format("2006-01-02 15:04:05"),
			Details: map[string]any{
				"Record type": "Beneficiary case",
				"Case code":   code,
				"Title":       title,
				"Priority":    label(priority),
				"Status":      label(status),
			},
		})
	}
	return out
}

func (s *Store) requests(ctx context.Context, userID int64, limit int) []Item {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, project_title, status, amount_needed::text, currency,
		       COALESCE(updated_at, created_at)
		  FROM beneficiary_project_requests
		 WHERE user_id = $1
		 ORDER BY updated_at DESC, id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var title, status, amount, currency string
		var ts time.Time
		if err := rows.Scan(&id, &title, &status, &amount, &currency, &ts); err != nil {
			continue
		}
		amt := parseFloat(amount)
		out = append(out, Item{
			ID:         "request_" + itoa64(id),
			Kind:       "request",
			Status:     status,
			Title:      title,
			Subtitle:   label(status) + " project request",
			OccurredAt: ts,
			DateLabel:  ts.Format("2006-01-02 15:04:05"),
			Amount:     &amt,
			Currency:   &currency,
			Details: map[string]any{
				"Record type": "Project request",
				"Title":       title,
				"Status":      label(status),
				"Amount":      amount + " " + currency,
			},
		})
	}
	return out
}

func (s *Store) applications(ctx context.Context, userID int64, limit int) []Item {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, full_name, phone, city, skills, experience, availability, status,
		       COALESCE(updated_at, created_at)
		  FROM volunteer_applications
		 WHERE user_id = $1
		 ORDER BY updated_at DESC, id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var fullName, status string
		var phone, city, skills, experience, availability *string
		var ts time.Time
		if err := rows.Scan(&id, &fullName, &phone, &city, &skills, &experience,
			&availability, &status, &ts); err != nil {
			continue
		}
		out = append(out, Item{
			ID:         "application_" + itoa64(id),
			Kind:       "application",
			Status:     status,
			Title:      "Volunteer application",
			Subtitle:   label(status),
			OccurredAt: ts,
			DateLabel:  ts.Format("2006-01-02 15:04:05"),
			Details: map[string]any{
				"Record type":  "Volunteer application",
				"Status":       label(status),
				"Full name":    fullName,
				"Phone":        ifEmpty(phone, "—"),
				"City":         ifEmpty(city, "—"),
				"Skills":       ifEmpty(skills, "—"),
				"Experience":   ifEmpty(experience, "—"),
				"Availability": ifEmpty(availability, "—"),
			},
		})
	}
	return out
}

func (s *Store) signups(ctx context.Context, userID int64, limit int) []Item {
	rows, err := s.Pool.Query(ctx, `
		SELECT s.id, s.status, s.notes, s.hours_served::text,
		       s.checked_in_at, s.completed_at,
		       COALESCE(s.updated_at, s.created_at),
		       m.title, m.city, m.mission_date
		  FROM volunteer_mission_signups s
		  LEFT JOIN volunteer_missions m ON m.id = s.mission_id
		 WHERE s.user_id = $1
		 ORDER BY s.updated_at DESC, s.id DESC
		 LIMIT $2`, userID, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		var id int64
		var status, hours string
		var notes *string
		var checkedIn, completed *time.Time
		var ts time.Time
		var title, city *string
		var missionDate *time.Time
		if err := rows.Scan(&id, &status, &notes, &hours, &checkedIn, &completed,
			&ts, &title, &city, &missionDate); err != nil {
			continue
		}
		t := "Mission signup"
		if title != nil && *title != "" {
			t = *title
		}
		out = append(out, Item{
			ID:         "signup_" + itoa64(id),
			Kind:       "signup",
			Status:     status,
			Title:      t,
			Subtitle:   label(status) + " mission signup",
			OccurredAt: ts,
			DateLabel:  ts.Format("2006-01-02 15:04:05"),
			Details: map[string]any{
				"Record type":   "Mission signup",
				"Mission":       t,
				"City":          ifEmpty(city, "—"),
				"Mission date":  formatDate(missionDate),
				"Status":        label(status),
				"Checked in":    formatDate(checkedIn),
				"Completed":     formatDate(completed),
				"Hours served":  hours,
				"Notes":         ifEmpty(notes, "—"),
			},
		})
	}
	return out
}

// ---- helpers ----

func mapRoleKey(roleID int) string {
	switch roleID {
	case 1:
		return "donor"
	case 2:
		return "beneficiary"
	case 3:
		return "volunteer"
	default:
		return "user"
	}
}

func statusFromPayment(p int) string {
	switch p {
	case 1:
		return "success"
	case 3:
		return "failed"
	default:
		return "pending"
	}
}

func label(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return "Unknown"
	}
	parts := strings.Split(strings.ReplaceAll(v, "_", " "), " ")
	for i, p := range parts {
		if p == "" {
			continue
		}
		parts[i] = strings.ToUpper(p[:1]) + p[1:]
	}
	return strings.Join(parts, " ")
}

func ifEmpty(p *string, fallback string) string {
	if p == nil || strings.TrimSpace(*p) == "" {
		return fallback
	}
	return *p
}

func formatDate(t *time.Time) string {
	if t == nil {
		return "—"
	}
	return t.Format("2006-01-02")
}

func parseFloat(s string) float64 {
	var f float64
	for _, c := range s {
		if (c < '0' || c > '9') && c != '.' && c != '-' && c != '+' {
			return 0
		}
	}
	// best-effort parse
	negative := false
	if len(s) > 0 && s[0] == '-' {
		negative = true
		s = s[1:]
	}
	intPart := true
	frac := 1.0
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '.':
			intPart = false
		case c >= '0' && c <= '9':
			if intPart {
				f = f*10 + float64(c-'0')
			} else {
				frac *= 10
				f = f + float64(c-'0')/frac
			}
		}
	}
	if negative {
		f = -f
	}
	return f
}

func itoa64(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [22]byte
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
