package users

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// strconvItoa is a thin alias so the package's existing SQL builders don't
// need to import strconv inline.
func strconvItoa(n int) string { return strconv.Itoa(n) }

// Profile mirrors the "profile" object in the PHP login/verify response.
type Profile struct {
	ProfileID      int64   `json:"profile_id"`
	FullName       *string `json:"full_name"`
	Gender         *string `json:"gender"`
	Address        *string `json:"address"`
	ProfilePicture *string `json:"profile_picture"`
	DateOfBirth    *string `json:"date_of_birth"` // "YYYY-MM-DD" or null
}

// Account mirrors getUserAccountForClient() in percentage/database/fetch.php.
type Account struct {
	UserID    int64     `json:"user_id"`
	Phone     string    `json:"phone"`
	RoleID    int       `json:"role_id"`
	Active    int       `json:"active"`
	IsAdmin   int       `json:"is_admin"`
	CreatedAt time.Time `json:"created_at"`
	Profile   *Profile  `json:"profile"`
	// RegistrationStatus drives the new-user approval flow:
	// incomplete | pending | approved | rejected.
	RegistrationStatus string `json:"registration_status"`
	// StaffTier is the dashboard access tier (Phase 6): super_admin | admin |
	// supervisor | employee | user.
	StaffTier string `json:"staff_tier"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// GetIDByPhone returns the user id for a phone, or 0 if not found.
func (s *Store) GetIDByPhone(ctx context.Context, phone string) (int64, error) {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return 0, nil
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`SELECT id FROM users WHERE phone = $1 LIMIT 1`, phone,
	).Scan(&id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	return id, nil
}

// GetPasswordHash returns the bcrypt password hash for a user id, or "" if
// no hash is set. Used by /api/auth/login to decide whether to require a
// password from the caller. Returns ("", nil) for unknown users or
// password-less accounts — distinguished by err being non-nil.
//
// Phase 20.
func (s *Store) GetPasswordHash(ctx context.Context, userID int64) (string, error) {
	if userID <= 0 {
		return "", nil
	}
	var hash *string
	err := s.Pool.QueryRow(ctx,
		`SELECT password_hash FROM users WHERE id = $1`, userID,
	).Scan(&hash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	if hash == nil {
		return "", nil
	}
	return *hash, nil
}

// GetByUsername looks up an admin candidate by username and returns its id,
// bcrypt password hash, and is_admin flag. Returns id=0 (and nil error) when no
// such username exists, so callers can map that to a generic auth failure.
//
// Phase 30 — backs POST /api/auth/admin/login.
func (s *Store) GetByUsername(ctx context.Context, username string) (id int64, passwordHash string, isAdmin int, err error) {
	username = strings.TrimSpace(username)
	if username == "" {
		return 0, "", 0, nil
	}
	var hash *string
	var admin *int
	err = s.Pool.QueryRow(ctx,
		`SELECT id, password_hash, is_admin FROM users WHERE username = $1 LIMIT 1`, username,
	).Scan(&id, &hash, &admin)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, "", 0, nil
		}
		return 0, "", 0, err
	}
	if hash != nil {
		passwordHash = *hash
	}
	if admin != nil {
		isAdmin = *admin
	}
	return id, passwordHash, isAdmin, nil
}

// InsertWithPhone returns the existing user id for the phone, or inserts a new
// row (role_id NULL) and returns its id. Matches insertUserWithPhone() in PHP.
func (s *Store) InsertWithPhone(ctx context.Context, phone string) (int64, error) {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return 0, errors.New("empty phone")
	}
	if id, err := s.GetIDByPhone(ctx, phone); err != nil {
		return 0, err
	} else if id > 0 {
		return id, nil
	}
	var id int64
	// New signups start as 'incomplete' — they must submit the registration
	// form (name/DOB/address/role) and be approved by an admin before they
	// can enter the app. (Existing rows were grandfathered to 'approved' by
	// migration 009; the column DEFAULT only applied to them.)
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, registration_status)
		 VALUES ($1, NULL, 'incomplete') RETURNING id`,
		phone,
	).Scan(&id)
	return id, err
}

// GetRoleID returns the current role_id for a user (0 if NULL / not found).
func (s *Store) GetRoleID(ctx context.Context, userID int64) (int, error) {
	if userID <= 0 {
		return 0, nil
	}
	var role *int
	err := s.Pool.QueryRow(ctx,
		`SELECT role_id FROM users WHERE id = $1`, userID,
	).Scan(&role)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	if role == nil {
		return 0, nil
	}
	return *role, nil
}

// UpsertGoogleUser finds a user by google_sub, then by email (linking Google to
// an existing account), otherwise creates a new one with a NULL phone and
// registration_status 'incomplete' so it still passes through the approval
// flow. Returns the user id and whether the account already existed.
// Phase 9 (B-09).
func (s *Store) UpsertGoogleUser(ctx context.Context, sub, email, _name string) (int64, bool, error) {
	sub = strings.TrimSpace(sub)
	if sub == "" {
		return 0, false, errors.New("empty google subject")
	}
	email = strings.ToLower(strings.TrimSpace(email))

	// 1) Existing Google account.
	var id int64
	err := s.Pool.QueryRow(ctx, `SELECT id FROM users WHERE google_sub = $1`, sub).Scan(&id)
	if err == nil {
		return id, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return 0, false, err
	}

	// 2) Existing account with the same email → link the Google subject to it.
	if email != "" {
		err = s.Pool.QueryRow(ctx, `SELECT id FROM users WHERE email = $1`, email).Scan(&id)
		if err == nil {
			if _, e := s.Pool.Exec(ctx, `UPDATE users SET google_sub = $1 WHERE id = $2`, sub, id); e != nil {
				return 0, false, e
			}
			return id, true, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return 0, false, err
		}
	}

	// 3) Brand-new user (no phone). Onboarding is still required.
	var emailArg any = nil
	if email != "" {
		emailArg = email
	}
	err = s.Pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, registration_status, google_sub, email)
		 VALUES (NULL, NULL, 'incomplete', $1, $2) RETURNING id`,
		sub, emailArg,
	).Scan(&id)
	if err != nil {
		return 0, false, err
	}
	return id, false, nil
}

// GetAccountForClient returns the user + joined profile, mirroring the PHP shape.
func (s *Store) GetAccountForClient(ctx context.Context, userID int64) (*Account, error) {
	if userID <= 0 {
		return nil, nil
	}
	var (
		acc       Account
		roleID    *int
		active    *int
		isAdmin   *int
		regStatus *string
		staffTier *string
		profileID *int64
		fullName  *string
		gender    *string
		address   *string
		picture   *string
		dob       *string
	)
	err := s.Pool.QueryRow(ctx,
		`SELECT u.id, COALESCE(u.phone, '') AS phone, u.role_id, u.active, u.is_admin, u.created_at, u.registration_status, u.staff_tier,
		        up.id, up.full_name, up.gender, up.address, up.profile_picture,
		        to_char(up.date_of_birth, 'YYYY-MM-DD')
		   FROM users u
		   LEFT JOIN user_profiles up ON up.user_id = u.id
		  WHERE u.id = $1
		  LIMIT 1`,
		userID,
	).Scan(&acc.UserID, &acc.Phone, &roleID, &active, &isAdmin, &acc.CreatedAt, &regStatus, &staffTier,
		&profileID, &fullName, &gender, &address, &picture, &dob)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if roleID != nil {
		acc.RoleID = *roleID
	}
	if active != nil {
		acc.Active = *active
	}
	if isAdmin != nil {
		acc.IsAdmin = *isAdmin
	}
	if regStatus != nil {
		acc.RegistrationStatus = *regStatus
	}
	if staffTier != nil {
		acc.StaffTier = *staffTier
	}
	if profileID != nil && *profileID > 0 {
		acc.Profile = &Profile{
			ProfileID:      *profileID,
			FullName:       nilIfEmpty(fullName),
			Gender:         nilIfEmpty(gender),
			Address:        nilIfEmpty(address),
			ProfilePicture: nilIfEmpty(picture),
			DateOfBirth:    nilIfEmpty(dob),
		}
	}
	return &acc, nil
}

func nilIfEmpty(s *string) *string {
	if s == nil || strings.TrimSpace(*s) == "" {
		return nil
	}
	return s
}

// PageUsers is the response for the admin users-list endpoint.
type PageUsers struct {
	Items      []Account `json:"items"`
	Pagination Pagination `json:"pagination"`
}

// Pagination meta for paginated lists.
type Pagination struct {
	Page       int  `json:"page"`
	PerPage    int  `json:"per_page"`
	TotalItems int  `json:"total_items"`
	TotalPages int  `json:"total_pages"`
	HasMore    bool `json:"has_more"`
}

// PaginatedList returns a sanitized, paginated users list (admin use).
// Sensitive fields (password, otp, tokens) are not selected at all.
// PaginatedList returns paginated users. q searches by phone or profile full_name.
func (s *Store) PaginatedList(ctx context.Context, page, perPage int, q string) (*PageUsers, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	where := ""
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		where = ` WHERE (u.phone ILIKE $1 OR up.full_name ILIKE $1)`
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
	rows, err := s.Pool.Query(ctx, `
		SELECT u.id, COALESCE(u.phone, '') AS phone, u.role_id, u.active, u.is_admin, u.created_at, u.registration_status,
		       up.id, up.full_name, up.gender, up.address, up.profile_picture,
		       to_char(up.date_of_birth, 'YYYY-MM-DD')
		  FROM users u
		  LEFT JOIN user_profiles up ON up.user_id = u.id`+where+`
		 ORDER BY u.id DESC
		 LIMIT $`+strconvItoa(limIdx)+` OFFSET $`+strconvItoa(offIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []Account{}
	for rows.Next() {
		var (
			acc       Account
			roleID    *int
			active    *int
			isAdmin   *int
			regStatus *string
			profileID *int64
			fullName  *string
			gender    *string
			address   *string
			picture   *string
			dob       *string
		)
		err := rows.Scan(&acc.UserID, &acc.Phone, &roleID, &active, &isAdmin, &acc.CreatedAt, &regStatus,
			&profileID, &fullName, &gender, &address, &picture, &dob)
		if err != nil {
			return nil, err
		}
		if roleID != nil {
			acc.RoleID = *roleID
		}
		if active != nil {
			acc.Active = *active
		}
		if isAdmin != nil {
			acc.IsAdmin = *isAdmin
		}
		if regStatus != nil {
			acc.RegistrationStatus = *regStatus
		}
		if profileID != nil && *profileID > 0 {
			acc.Profile = &Profile{
				ProfileID:      *profileID,
				FullName:       nilIfEmpty(fullName),
				Gender:         nilIfEmpty(gender),
				Address:        nilIfEmpty(address),
				ProfilePicture: nilIfEmpty(picture),
				DateOfBirth:    nilIfEmpty(dob),
			}
		}
		items = append(items, acc)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &PageUsers{
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
