// Package volunteers handles volunteer applications + missions + signups.
//
// Ports both percentage/api/volunteers/index.php and the near-duplicate
// percentage/api/volunteer_hub/index.php.
package volunteers

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Mission struct {
	ID                  int64      `json:"id"`
	Title               string     `json:"title"`
	TitleAr             *string    `json:"title_ar"`
	TitleSorani         *string    `json:"title_sorani"`
	TitleBadini         *string    `json:"title_badini"`
	Description         *string    `json:"description"`
	DescriptionAr       *string    `json:"description_ar"`
	DescriptionSorani   *string    `json:"description_sorani"`
	DescriptionBadini   *string    `json:"description_badini"`
	City                *string    `json:"city"`
	MissionDate         *time.Time `json:"mission_date"`
	NeededVolunteers    *int       `json:"needed_volunteers"`
	Status              string     `json:"status"`
	AcceptedVolunteers  int        `json:"accepted_volunteers"`
	PendingVolunteers   int        `json:"pending_volunteers"`
}

type Application struct {
	ID           int64     `json:"id"`
	UserID       int       `json:"user_id"`
	FullName     string    `json:"full_name"`
	Phone        *string   `json:"phone"`
	City         *string   `json:"city"`
	Skills       *string   `json:"skills"`
	Experience   *string   `json:"experience"`
	Availability *string   `json:"availability"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type JoinedMission struct {
	SignupID     int64      `json:"signup_id"`
	SignupStatus string     `json:"signup_status"`
	Notes        *string    `json:"notes"`
	JoinedAt     time.Time  `json:"joined_at"`
	CheckedInAt  *time.Time `json:"checked_in_at"`
	CompletedAt  *time.Time `json:"completed_at"`
	HoursServed  string     `json:"hours_served"`
	Mission
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// GetMission returns a single mission by id (any status), or nil when
// the row doesn't exist. Used by the notification helper after a successful
// JoinMission to put the mission title in the body.
//
// Phase 21b.
func (s *Store) GetMission(ctx context.Context, id int64) (*Mission, error) {
	if id <= 0 {
		return nil, nil
	}
	var m Mission
	err := s.Pool.QueryRow(ctx, `
		SELECT id, title, title_ar, title_sorani, title_badini,
		       description, description_ar, description_sorani, description_badini,
		       city, mission_date, needed_volunteers, status, 0, 0
		  FROM volunteer_missions WHERE id = $1`,
		id,
	).Scan(
		&m.ID, &m.Title, &m.TitleAr, &m.TitleSorani, &m.TitleBadini,
		&m.Description, &m.DescriptionAr, &m.DescriptionSorani, &m.DescriptionBadini,
		&m.City, &m.MissionDate, &m.NeededVolunteers, &m.Status,
		&m.AcceptedVolunteers, &m.PendingVolunteers,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &m, nil
}

// ListOpenMissions returns missions with status='open' plus per-mission signup counts.
func (s *Store) ListOpenMissions(ctx context.Context, limit int) ([]Mission, error) {
	return s.listMissions(ctx, limit, "WHERE m.status = 'open'")
}

// ListAllMissions returns every mission regardless of status. Used by the
// /api/missions endpoint when called with ?status=all. Phase 21b.
func (s *Store) ListAllMissions(ctx context.Context, limit int) ([]Mission, error) {
	return s.listMissions(ctx, limit, "")
}

// listMissions is the shared body of the two public list helpers above.
// `whereClause` is interpolated verbatim — callers MUST pass a literal
// (no user input) to avoid SQL injection.
func (s *Store) listMissions(ctx context.Context, limit int, whereClause string) ([]Mission, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT m.id, m.title, m.title_ar, m.title_sorani, m.title_badini,
		       m.description, m.description_ar, m.description_sorani, m.description_badini,
		       m.city, m.mission_date, m.needed_volunteers, m.status,
		       COALESCE(c.accepted_count, 0),
		       COALESCE(c.pending_count, 0)
		  FROM volunteer_missions m
		  LEFT JOIN (
		    SELECT mission_id,
		           SUM(CASE WHEN status IN ('approved','joined','completed') THEN 1 ELSE 0 END) AS accepted_count,
		           SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_count
		      FROM volunteer_mission_signups
		     GROUP BY mission_id
		  ) c ON c.mission_id = m.id
		 `+whereClause+`
		 ORDER BY COALESCE(m.mission_date, '2999-12-31'::date) ASC, m.id DESC
		 LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Mission{}
	for rows.Next() {
		var m Mission
		if err := rows.Scan(&m.ID, &m.Title, &m.TitleAr, &m.TitleSorani, &m.TitleBadini,
			&m.Description, &m.DescriptionAr, &m.DescriptionSorani, &m.DescriptionBadini,
			&m.City, &m.MissionDate, &m.NeededVolunteers, &m.Status,
			&m.AcceptedVolunteers, &m.PendingVolunteers); err != nil {
			return nil, err
		}
		items = append(items, m)
	}
	return items, rows.Err()
}

// ApplicationsForUser returns the user's volunteer applications, newest first.
func (s *Store) ApplicationsForUser(ctx context.Context, userID int64) ([]Application, error) {
	if userID <= 0 {
		return nil, nil
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT id, user_id, full_name, phone, city, skills, experience, availability,
		       status, created_at, updated_at
		  FROM volunteer_applications
		 WHERE user_id = $1
		 ORDER BY id DESC
		 LIMIT 20`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Application{}
	for rows.Next() {
		var a Application
		if err := rows.Scan(&a.ID, &a.UserID, &a.FullName, &a.Phone, &a.City, &a.Skills,
			&a.Experience, &a.Availability, &a.Status, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, a)
	}
	return items, rows.Err()
}

// JoinedMissionsForUser returns missions the user is still attached to
// (status not in cancelled, rejected).
func (s *Store) JoinedMissionsForUser(ctx context.Context, userID int64) ([]JoinedMission, error) {
	if userID <= 0 {
		return nil, nil
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT s.id, s.status, s.notes, s.created_at,
		       s.checked_in_at, s.completed_at, s.hours_served::text,
		       m.id, m.title, m.title_ar, NULL::text, NULL::text,
		       m.description, m.description_ar, NULL::text, NULL::text,
		       m.city, m.mission_date, m.needed_volunteers, m.status,
		       0, 0
		  FROM volunteer_mission_signups s
		  INNER JOIN volunteer_missions m ON m.id = s.mission_id
		 WHERE s.user_id = $1 AND s.status NOT IN ('cancelled','rejected')
		 ORDER BY COALESCE(m.mission_date, '2999-12-31'::date) ASC, s.id DESC
		 LIMIT 50`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []JoinedMission{}
	for rows.Next() {
		var x JoinedMission
		if err := rows.Scan(&x.SignupID, &x.SignupStatus, &x.Notes, &x.JoinedAt,
			&x.CheckedInAt, &x.CompletedAt, &x.HoursServed,
			&x.Mission.ID, &x.Mission.Title, &x.Mission.TitleAr,
			&x.Mission.TitleSorani, &x.Mission.TitleBadini,
			&x.Mission.Description, &x.Mission.DescriptionAr,
			&x.Mission.DescriptionSorani, &x.Mission.DescriptionBadini,
			&x.Mission.City, &x.Mission.MissionDate, &x.Mission.NeededVolunteers, &x.Mission.Status,
			&x.Mission.AcceptedVolunteers, &x.Mission.PendingVolunteers); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

// JoinResult describes a join_mission outcome.
type JoinResult struct {
	Status   string // "pending" | existing status
	Existing bool
	SignupID int64
}

// JoinMission upserts a (user, mission) signup. If mission is full or not open,
// returns an error with a recognizable message.
func (s *Store) JoinMission(ctx context.Context, userID, missionID int64, notes *string) (*JoinResult, error) {
	if userID <= 0 || missionID <= 0 {
		return nil, errors.New("missing user_id or mission_id")
	}

	// Mission must be open + check capacity in a single roundtrip.
	var needed *int
	var accepted int
	err := s.Pool.QueryRow(ctx, `
		SELECT m.needed_volunteers,
		       COALESCE(SUM(CASE WHEN s.status IN ('approved','joined','completed') THEN 1 ELSE 0 END), 0)
		  FROM volunteer_missions m
		  LEFT JOIN volunteer_mission_signups s ON s.mission_id = m.id
		 WHERE m.id = $1 AND m.status = 'open'
		 GROUP BY m.id, m.needed_volunteers`, missionID,
	).Scan(&needed, &accepted)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("mission not found or not open")
		}
		return nil, err
	}
	if needed != nil && *needed > 0 && accepted >= *needed {
		return nil, errors.New("mission full")
	}

	// Existing signup?
	var existingID int64
	var existingStatus string
	err = s.Pool.QueryRow(ctx,
		`SELECT id, status FROM volunteer_mission_signups
		  WHERE user_id = $1 AND mission_id = $2`,
		userID, missionID,
	).Scan(&existingID, &existingStatus)
	switch {
	case err == nil:
		switch existingStatus {
		case "pending", "approved", "joined", "completed":
			return &JoinResult{Status: existingStatus, Existing: true, SignupID: existingID}, nil
		}
		// rejected / cancelled → reset to pending
		_, err = s.Pool.Exec(ctx,
			`UPDATE volunteer_mission_signups
			    SET status = 'pending', notes = $1
			  WHERE id = $2`, notes, existingID)
		if err != nil {
			return nil, err
		}
		return &JoinResult{Status: "pending", SignupID: existingID}, nil
	case errors.Is(err, pgx.ErrNoRows):
		var id int64
		err := s.Pool.QueryRow(ctx, `
			INSERT INTO volunteer_mission_signups (user_id, mission_id, status, notes)
			VALUES ($1, $2, 'pending', $3)
			RETURNING id`, userID, missionID, notes,
		).Scan(&id)
		if err != nil {
			return nil, err
		}
		return &JoinResult{Status: "pending", SignupID: id}, nil
	default:
		return nil, err
	}
}

// ApplicationInput is what the handler passes to InsertApplication.
// Both the structured fields (SkillTags, Schedule) and the legacy
// free-form fields (Skills, Availability) are kept — the structured
// fields drive admin filters / search; the legacy fields preserve any
// "Other..." text the volunteer typed and stay visible on the admin
// detail screen.
type ApplicationInput struct {
	UserID       int64
	FullName     string
	Phone        string
	City         string
	Skills       string // legacy free-form text (already comma-joined chip labels + "other")
	Availability string // legacy free-form text (already pretty-printed schedule)
	Experience   *string
	SkillTags    []string      // canonical keys (already filtered by FilterSkillKeys)
	Schedule     []DaySchedule // per-day rows (already normalized)
}

// InsertApplication writes a new volunteer application + per-day
// availability rows in a single transaction. Returns the new application
// id. Phase 26.
func (s *Store) InsertApplication(ctx context.Context, in ApplicationInput) (int64, error) {
	if in.UserID <= 0 {
		return 0, errors.New("invalid userID")
	}
	in.FullName = strings.TrimSpace(in.FullName)
	if in.FullName == "" {
		return 0, errors.New("missing full_name")
	}
	if strings.TrimSpace(in.Phone) == "" || strings.TrimSpace(in.City) == "" {
		return 0, errors.New("phone and city are required")
	}
	// One of the two skill channels must be present — structured chips
	// or legacy free-form. Same idea for availability.
	if len(in.SkillTags) == 0 && strings.TrimSpace(in.Skills) == "" {
		return 0, errors.New("at least one skill is required")
	}
	if len(in.Schedule) == 0 && strings.TrimSpace(in.Availability) == "" {
		return 0, errors.New("availability is required")
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx) // no-op if Commit succeeded

	var id int64
	err = tx.QueryRow(ctx, `
		INSERT INTO volunteer_applications
		   (user_id, full_name, phone, city, skills, experience, availability, skill_tags)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		in.UserID, in.FullName, in.Phone, in.City, in.Skills,
		in.Experience, in.Availability, in.SkillTags,
	).Scan(&id)
	if err != nil {
		return 0, err
	}

	// Per-day rows. We could use CopyFrom for bulk but the volunteer
	// picks at most 7 days, so a plain loop is plenty.
	for _, d := range in.Schedule {
		_, err = tx.Exec(ctx, `
			INSERT INTO volunteer_application_availability
			   (application_id, day_of_week, time_from, time_to)
			VALUES ($1, $2, $3, $4)`,
			id, d.Day, d.TimeFrom, d.TimeTo,
		)
		if err != nil {
			return 0, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return id, nil
}
