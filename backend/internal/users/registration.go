package users

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// ErrRegistrationNotSubmittable is returned by SubmitRegistration when the
// user's row can't move to 'pending' — i.e. it doesn't exist, or it's already
// 'approved' (an approved user re-registering is a no-op the handler maps to
// 409). Submitting from 'incomplete', 'pending' (idempotent) or 'rejected'
// (re-submit after a rejection) all succeed.
var ErrRegistrationNotSubmittable = errors.New("registration not submittable in current status")

// SubmitRegistration is the new-user onboarding write: it stores the profile
// fields the registration form collects (name, date of birth, address),
// assigns the chosen role, and moves the user to 'pending' so an admin can
// review them. It runs in a single transaction so role+status+profile never
// drift apart. gender is left untouched (defaults to '' on first insert) —
// the registration form doesn't collect it.
// Returns the resulting registration_status ("pending" for new/rejected users,
// or "approved" when an already-approved user is just completing their role/
// profile — e.g. a grandfathered account that never picked a role).
func (s *Store) SubmitRegistration(ctx context.Context, userID int64, fullName, dob, address string, roleID int) (string, error) {
	if userID <= 0 {
		return "", errors.New("invalid userID")
	}
	fullName = strings.TrimSpace(fullName)
	address = strings.TrimSpace(address)
	dob = strings.TrimSpace(dob)
	if fullName == "" {
		return "", errors.New("full_name required")
	}
	if roleID < 1 || roleID > 3 {
		return "", errors.New("invalid role_id")
	}

	var dobArg any = nil
	if dob != "" {
		dobArg = dob
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	// Upsert the profile row (name/address/DOB). user_profiles columns are
	// NOT NULL, so a fresh insert seeds gender='' and profile_picture='0'.
	var one int
	err = tx.QueryRow(ctx, `SELECT 1 FROM user_profiles WHERE user_id = $1`, userID).Scan(&one)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		if _, err = tx.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, address, gender, profile_picture, date_of_birth)
			 VALUES ($1, $2, $3, '', '0', $4)`,
			userID, fullName, address, dobArg,
		); err != nil {
			return "", err
		}
	case err != nil:
		return "", err
	default:
		if _, err = tx.Exec(ctx,
			`UPDATE user_profiles SET full_name = $1, address = $2, date_of_birth = $3
			  WHERE user_id = $4`,
			fullName, address, dobArg, userID,
		); err != nil {
			return "", err
		}
	}

	// Assign role + move to pending — UNLESS the user is already approved
	// (a grandfathered account completing its role/profile), in which case the
	// approval is preserved. RETURNING gives us the resulting status; no row
	// means the user id doesn't exist.
	var newStatus string
	err = tx.QueryRow(ctx,
		`UPDATE users
		    SET role_id = $1,
		        registration_status        = CASE WHEN registration_status = 'approved' THEN 'approved' ELSE 'pending' END,
		        registration_submitted_at  = CASE WHEN registration_status = 'approved' THEN registration_submitted_at ELSE NOW() END,
		        registration_reviewed_at   = CASE WHEN registration_status = 'approved' THEN registration_reviewed_at ELSE NULL END,
		        registration_reviewed_by   = CASE WHEN registration_status = 'approved' THEN registration_reviewed_by ELSE NULL END,
		        registration_reject_reason = NULL
		  WHERE id = $2
		  RETURNING registration_status`,
		roleID, userID,
	).Scan(&newStatus)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrRegistrationNotSubmittable
		}
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return newStatus, nil
}

// GetRegistrationState returns the user's current approval status, the reject
// reason (if any), and the chosen role_id (0 when unset).
func (s *Store) GetRegistrationState(ctx context.Context, userID int64) (status string, rejectReason *string, roleID int, err error) {
	var (
		st  string
		rr  *string
		rid *int
	)
	err = s.Pool.QueryRow(ctx,
		`SELECT registration_status, registration_reject_reason, role_id
		   FROM users WHERE id = $1`,
		userID,
	).Scan(&st, &rr, &rid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil, 0, nil
		}
		return "", nil, 0, err
	}
	if rid != nil {
		roleID = *rid
	}
	return st, rr, roleID, nil
}

// RegistrationItem is one row in the admin "pending registrations" list.
type RegistrationItem struct {
	UserID       int64     `json:"user_id"`
	Phone        string    `json:"phone"`
	RoleID       int       `json:"role_id"`
	Status       string    `json:"registration_status"`
	FullName     string    `json:"full_name"`
	Address      string    `json:"address"`
	DateOfBirth  string    `json:"date_of_birth"` // "YYYY-MM-DD" or ""
	SubmittedAt  *string   `json:"submitted_at"`  // ISO8601 or null
	RejectReason *string   `json:"reject_reason"`
	CreatedAt    time.Time `json:"created_at"`
}

// PageRegistrations is the paginated response for the admin registrations list.
type PageRegistrations struct {
	Items      []RegistrationItem `json:"items"`
	Pagination Pagination         `json:"pagination"`
}

// ListRegistrations returns submitted registrations awaiting (or past) review.
// statusFilter: "pending" (default), "rejected", or "all" (pending+rejected).
// 'incomplete' users never appear — they haven't submitted the form yet.
func (s *Store) ListRegistrations(ctx context.Context, statusFilter string, page, perPage int, q string) (*PageRegistrations, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	statusClause := "u.registration_status = 'pending'"
	switch strings.ToLower(strings.TrimSpace(statusFilter)) {
	case "rejected":
		statusClause = "u.registration_status = 'rejected'"
	case "all":
		statusClause = "u.registration_status IN ('pending', 'rejected')"
	}

	args := []any{}
	where := " WHERE " + statusClause
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		where += " AND (u.phone ILIKE $1 OR up.full_name ILIKE $1)"
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id`+where,
		args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limIdx := len(args) + 1
	offIdx := len(args) + 2
	args = append(args, perPage, offset)
	rows, err := s.Pool.Query(ctx,
		`SELECT u.id, u.phone, u.role_id, u.registration_status, u.created_at,
		        to_char(u.registration_submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
		        u.registration_reject_reason,
		        COALESCE(up.full_name, ''), COALESCE(up.address, ''),
		        COALESCE(to_char(up.date_of_birth, 'YYYY-MM-DD'), '')
		   FROM users u
		   LEFT JOIN user_profiles up ON up.user_id = u.id`+where+`
		  ORDER BY u.registration_submitted_at ASC NULLS LAST, u.id ASC
		  LIMIT $`+strconvItoa(limIdx)+` OFFSET $`+strconvItoa(offIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []RegistrationItem{}
	for rows.Next() {
		var (
			it     RegistrationItem
			roleID *int
		)
		if err := rows.Scan(&it.UserID, &it.Phone, &roleID, &it.Status, &it.CreatedAt,
			&it.SubmittedAt, &it.RejectReason, &it.FullName, &it.Address, &it.DateOfBirth); err != nil {
			return nil, err
		}
		if roleID != nil {
			it.RoleID = *roleID
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &PageRegistrations{
		Items: items,
		Pagination: Pagination{
			Page:       page,
			PerPage:    perPage,
			TotalItems: total,
			TotalPages: totalPages,
			HasMore:    page < totalPages,
		},
	}, nil
}

// ApproveRegistration flips a pending/rejected user to 'approved'. Returns
// false (no error) when no such reviewable row exists.
func (s *Store) ApproveRegistration(ctx context.Context, userID, adminID int64) (bool, error) {
	ct, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET registration_status = 'approved',
		        registration_reviewed_at = NOW(),
		        registration_reviewed_by = $2,
		        registration_reject_reason = NULL
		  WHERE id = $1
		    AND registration_status IN ('pending', 'rejected')`,
		userID, adminID,
	)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() > 0, nil
}

// RejectRegistration flips a pending user to 'rejected' with an optional
// reason. The user keeps their submitted details and may edit + re-submit.
func (s *Store) RejectRegistration(ctx context.Context, userID, adminID int64, reason string) (bool, error) {
	var reasonArg any = nil
	if r := strings.TrimSpace(reason); r != "" {
		reasonArg = r
	}
	ct, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET registration_status = 'rejected',
		        registration_reviewed_at = NOW(),
		        registration_reviewed_by = $2,
		        registration_reject_reason = $3
		  WHERE id = $1
		    AND registration_status IN ('pending', 'rejected')`,
		userID, adminID, reasonArg,
	)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() > 0, nil
}
