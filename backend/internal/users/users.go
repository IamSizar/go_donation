package users

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
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
	// Note #6 — the rest of the registration profile, previously only
	// readable via the generic Detail view, now also surfaced on the Users
	// list so the Edit User form can pre-populate them.
	City          *string `json:"city"`
	Occupation    *string `json:"occupation"`
	FamilySize    *int    `json:"family_size"`
	HousingStatus *string `json:"housing_status"`
	MonthlyIncome *string `json:"monthly_income"`
	Skills        *string `json:"skills"`
	Availability  *string `json:"availability"`
	Experience    *string `json:"experience"`
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
	// AccountStatus is the lifecycle status (Section 25): active | suspended |
	// banned.
	AccountStatus string `json:"account_status"`
	// FieldPrivacy (#32) is the list of profile field keys the user hides.
	FieldPrivacy []string `json:"field_privacy"`
	// IsGuest (#40) — a lightweight username/password browsing account,
	// restricted server-side until upgraded to a full phone account.
	IsGuest bool `json:"is_guest"`
	// Username (#40) — set for guest accounts (and admin-login accounts,
	// Phase 30); empty for a normal phone/OTP or Google account.
	Username string `json:"username,omitempty"`
	// WalletBalanceIQD (#42) — test-phase internal app wallet balance, whole
	// Iraqi Dinars.
	WalletBalanceIQD int64 `json:"wallet_balance_iqd"`
	// HasPassword — whether this account currently has a password_hash set.
	// Never exposes the hash itself; only lets the admin dashboard tell a
	// "changing an existing password" action (needs the PIN step-up) apart
	// from a "setting the very first password" bootstrap action (which has
	// nothing to confirm against yet, so it must skip the PIN step).
	HasPassword bool `json:"has_password"`
	// IdentityCode (K21) — this account's own auto-generated identity code
	// (GR-/ER-/VL-), chosen from the profile's three columns by pickIdentityCode.
	// The registration form promises the code is generated automatically; until
	// this field existed, nothing ever showed it to the person it belongs to,
	// so they could not quote it and could not search by it. Empty for accounts
	// that have none (staff, guests).
	IdentityCode string `json:"identity_code"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// GetNotificationsEnabled returns the user's notification switch (#31). Missing
// user or column defaults to true so nothing is silently muted.
func (s *Store) GetNotificationsEnabled(ctx context.Context, userID int64) (bool, error) {
	var v int
	err := s.Pool.QueryRow(ctx,
		`SELECT notifications_enabled FROM users WHERE id = $1`, userID).Scan(&v)
	if err != nil {
		return true, err
	}
	return v != 0, nil
}

// SetNotificationsEnabled flips the user's notification switch (#31).
func (s *Store) SetNotificationsEnabled(ctx context.Context, userID int64, enabled bool) error {
	v := 0
	if enabled {
		v = 1
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE users SET notifications_enabled = $2 WHERE id = $1`, userID, v)
	return err
}

// ─── Per-category notification preferences (K7) ─────────────────────────

// NotificationCategory is one switch on the Settings screen's notification
// section: a category of alert the user can turn off on its own, rather than
// the single all-or-nothing switch that used to be the only option.
//
// The catalogue is data-driven (notification_categories, migration 108), and
// Enabled is THIS user's effective answer, so the app can render the whole
// screen from one response.
type NotificationCategory struct {
	Category     string `json:"category"`
	LabelKey     string `json:"label_key"`
	DisplayOrder int    `json:"display_order"`
	Enabled      bool   `json:"enabled"`
}

// NotificationCategories returns every enabled category with this user's
// choice applied. A category the user has never touched comes back enabled —
// absence of a row means "on", the same rule GetNotificationsEnabled uses, so
// nothing is ever silently muted.
func (s *Store) NotificationCategories(ctx context.Context, userID int64) ([]NotificationCategory, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT c.category, c.label_key, c.display_order,
		       COALESCE(p.enabled, TRUE)
		  FROM notification_categories c
		  LEFT JOIN notification_preferences p
		         ON p.category = c.category AND p.user_id = $1
		 WHERE c.enabled = true
		 ORDER BY c.display_order, c.category`, userID)
	if err != nil {
		return nil, fmt.Errorf("list notification categories for user %d: %w", userID, err)
	}
	defer rows.Close()
	out := []NotificationCategory{}
	for rows.Next() {
		var c NotificationCategory
		if err := rows.Scan(&c.Category, &c.LabelKey, &c.DisplayOrder, &c.Enabled); err != nil {
			return nil, fmt.Errorf("scan notification category: %w", err)
		}
		// A row can be inserted with no label_key; the app falls back to the
		// category name so it is usable immediately.
		if c.LabelKey == "" {
			c.LabelKey = c.Category
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// SetNotificationCategories replaces the user's per-category choices: every
// category in the catalogue is written as enabled, except those named in
// disabled. Returns the categories that ended up switched off.
//
// It writes the full picture rather than a delta so the stored state always
// matches what the screen showed — a partial update is how a switch ends up
// disagreeing with the server about its own position. Unknown category names
// are dropped: the catalogue is the contract, and keeping a preference nothing
// will ever read is how a switch starts lying about what it does.
func (s *Store) SetNotificationCategories(ctx context.Context, userID int64, disabled []string) ([]string, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	known, err := s.NotificationCategories(ctx, userID)
	if err != nil {
		return nil, err
	}
	off := map[string]bool{}
	for _, d := range disabled {
		off[strings.TrimSpace(strings.ToLower(d))] = true
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin notification preference write: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	saved := []string{}
	for _, c := range known {
		enabled := !off[c.Category]
		if !enabled {
			saved = append(saved, c.Category)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO notification_preferences (user_id, category, enabled)
			VALUES ($1, $2, $3)
			ON CONFLICT (user_id, category)
			DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = CURRENT_TIMESTAMP`,
			userID, c.Category, enabled,
		); err != nil {
			return nil, fmt.Errorf("save notification preference %q for user %d: %w", c.Category, userID, err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit notification preferences: %w", err)
	}
	return saved, nil
}

// PrivacyFieldOption is one toggleable entry in the Privacy Settings screen.
// The catalogue is data-driven (privacy_field_options, migration 083) so new
// options can be added without an app change — see that migration's note.
type PrivacyFieldOption struct {
	FieldKey      string `json:"field_key"`
	LabelKey      string `json:"label_key"`
	DefaultHidden bool   `json:"default_hidden"`
	DisplayOrder  int    `json:"display_order"`
}

// PrivacyFieldOptions returns the enabled options in display order.
func (s *Store) PrivacyFieldOptions(ctx context.Context) ([]PrivacyFieldOption, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT field_key, label_key, default_hidden, display_order
		   FROM privacy_field_options
		  WHERE enabled = true
		  ORDER BY display_order, field_key`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []PrivacyFieldOption{}
	for rows.Next() {
		var o PrivacyFieldOption
		if err := rows.Scan(&o.FieldKey, &o.LabelKey, &o.DefaultHidden, &o.DisplayOrder); err != nil {
			return nil, err
		}
		// A brand-new row can be inserted with no label_key; the app falls
		// back to the field key so it is still usable immediately.
		if o.LabelKey == "" {
			o.LabelKey = o.FieldKey
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// GetFieldPrivacy returns the profile field keys the user hides (#32).
func (s *Store) GetFieldPrivacy(ctx context.Context, userID int64) ([]string, error) {
	var hidden []string
	err := s.Pool.QueryRow(ctx,
		`SELECT COALESCE(field_privacy, '{}') FROM user_profiles WHERE user_id = $1`, userID).Scan(&hidden)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return []string{}, nil
		}
		return nil, err
	}
	if hidden == nil {
		hidden = []string{}
	}
	return hidden, nil
}

// SetFieldPrivacy stores the profile field keys the user hides (#32).
//
// AUDITED, and this is the field where the audit matters most. field_privacy
// decides what other people can see; a wrong or unauthorised change is
// invisible to its victim, because nothing about their own screen looks
// different. When the fail-open bug raised "did this already happen to
// anyone?", current state could show that nothing is wrong NOW and could not
// show that nothing had ever been wiped. These rows are what answer that.
func (s *Store) SetFieldPrivacy(ctx context.Context, userID int64, hidden []string) error {
	if hidden == nil {
		hidden = []string{}
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Read the previous value inside the transaction, so a concurrent write
	// cannot leave the audit row describing a transition that never happened.
	var before []string
	if err := tx.QueryRow(ctx,
		`SELECT COALESCE(field_privacy, '{}') FROM user_profiles WHERE user_id = $1`,
		userID).Scan(&before); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE user_profiles SET field_privacy = $2 WHERE user_id = $1`,
		userID, hidden); err != nil {
		return err
	}

	// Sorted on both sides so that reordering the same set is not recorded as
	// a change — recordAudit skips writes where old equals new, and a spurious
	// row is worse than none: it teaches the reader to distrust the log.
	s.recordAudit(ctx, tx, userID, "user", userID, nil,
		"field_privacy", sortedCSV(before), sortedCSV(hidden))

	return tx.Commit(ctx)
}

// sortedCSV renders a field-key set for the audit log: order-independent, and
// readable by a human reading the row rather than a program parsing it.
func sortedCSV(keys []string) string {
	if len(keys) == 0 {
		return ""
	}
	cp := append([]string(nil), keys...)
	sort.Strings(cp)
	return strings.Join(cp, ",")
}

// PrivacyExtras — Privacy Settings spec: real name vs. alias display choice
// plus optional social media links.
type PrivacyExtras struct {
	DisplayNameMode string `json:"display_name_mode"` // "real" | "alias"
	AliasName       string `json:"alias_name"`
	Facebook        string `json:"social_facebook"`
	Instagram       string `json:"social_instagram"`
	Telegram        string `json:"social_telegram"`
}

// GetPrivacyExtras returns the current display-name choice and social links.
func (s *Store) GetPrivacyExtras(ctx context.Context, userID int64) (PrivacyExtras, error) {
	var p PrivacyExtras
	err := s.Pool.QueryRow(ctx,
		`SELECT display_name_mode, alias_name, social_facebook, social_instagram, social_telegram
		   FROM user_profiles WHERE user_id = $1`, userID,
	).Scan(&p.DisplayNameMode, &p.AliasName, &p.Facebook, &p.Instagram, &p.Telegram)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return PrivacyExtras{DisplayNameMode: "real"}, nil
		}
		return PrivacyExtras{}, err
	}
	if p.DisplayNameMode == "" {
		p.DisplayNameMode = "real"
	}
	return p, nil
}

// SetPrivacyExtras stores the display-name choice and social links.
func (s *Store) SetPrivacyExtras(ctx context.Context, userID int64, p PrivacyExtras) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	mode := strings.TrimSpace(p.DisplayNameMode)
	if mode != "alias" {
		mode = "real"
	}
	alias := strings.TrimSpace(p.AliasName)

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Previous values, read in-transaction for the same reason as above.
	var beforeMode, beforeAlias string
	if err := tx.QueryRow(ctx,
		`SELECT COALESCE(display_name_mode, ''), COALESCE(alias_name, '')
		   FROM user_profiles WHERE user_id = $1`,
		userID).Scan(&beforeMode, &beforeAlias); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE user_profiles
		    SET display_name_mode = $2, alias_name = $3,
		        social_facebook = $4, social_instagram = $5, social_telegram = $6
		  WHERE user_id = $1`,
		userID, mode, alias,
		strings.TrimSpace(p.Facebook), strings.TrimSpace(p.Instagram), strings.TrimSpace(p.Telegram),
	); err != nil {
		return err
	}

	// display_name_mode decides whether other people see a real name or an
	// alias, so it belongs in the same audit as field_privacy.
	s.recordAudit(ctx, tx, userID, "user", userID, nil,
		"display_name_mode", beforeMode, mode)
	// alias_name too: a CLEARED alias is otherwise indistinguishable from one
	// that was never set, which is exactly the question an investigation asks.
	s.recordAudit(ctx, tx, userID, "user", userID, nil,
		"alias_name", beforeAlias, alias)

	return tx.Commit(ctx)
}

// GetIDByPhone returns the user id for a phone, or 0 if not found.
// CurrentFullName / CurrentPicture return what the live profile holds, so a
// change request can record the before-value for the reviewer.
func (s *Store) CurrentFullName(ctx context.Context, userID int64) (string, error) {
	var v string
	err := s.Pool.QueryRow(ctx,
		`SELECT COALESCE(full_name, '') FROM user_profiles WHERE user_id = $1`, userID).Scan(&v)
	return v, err
}

func (s *Store) CurrentPicture(ctx context.Context, userID int64) (string, error) {
	var v string
	err := s.Pool.QueryRow(ctx,
		`SELECT COALESCE(profile_picture, '') FROM user_profiles WHERE user_id = $1`, userID).Scan(&v)
	return v, err
}

// CurrentGender returns the profile's stored gender, or "" when unset.
// Used to enforce that gender is written once, at sign-up, and not changed
// afterwards from the app.
func (s *Store) CurrentGender(ctx context.Context, userID int64) (string, error) {
	var g string
	err := s.Pool.QueryRow(ctx,
		`SELECT COALESCE(gender, '') FROM user_profiles WHERE user_id = $1`,
		userID).Scan(&g)
	if err != nil {
		return "", err
	}
	return g, nil
}

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

// SetPasswordIfUnset writes a bcrypt hash to an account that currently has
// NONE, and reports whether it did. It never overwrites an existing password.
//
// A16 — this is the whole bound on the OTP bridge. 36 of 46 production accounts
// hold no password, so an OTP-verified "choose a password" step is the only way
// they can ever sign in again; but while demo OTP delivery is the only delivery
// there is, a code proves nothing, so that step must be able to happen AT MOST
// ONCE per account. The `WHERE password_hash IS NULL OR is empty` clause makes
// that true, and it lives in the UPDATE rather than in a read-then-write so two
// racing claims cannot both see "no password" and both succeed: exactly one of
// them gets RowsAffected() == 1.
//
// Returns (false, nil) when the account already had a password or does not
// exist — the caller refuses in both cases. A non-nil error means the write may
// or may not have happened; callers must fail closed.
func (s *Store) SetPasswordIfUnset(ctx context.Context, userID int64, passwordHash string) (bool, error) {
	if userID <= 0 || strings.TrimSpace(passwordHash) == "" {
		return false, errors.New("user id and password hash are required")
	}
	ct, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET password_hash = $2
		  WHERE id = $1
		    AND (password_hash IS NULL OR password_hash = '')`,
		userID, passwordHash)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() == 1, nil
}

// StaffTierByPhone returns the id and staff_tier of the account holding this
// phone. Returns (0, "", nil) when no account has the number — an unknown
// phone is not staff, which is the only "not staff" answer this function is
// allowed to give without an error.
//
// A16 — backs the sign-in gates that must know whether a phone number belongs
// to a STAFF account BEFORE any token is minted for it. The caller is expected
// to fail CLOSED on a non-nil error: "we could not tell" must never be read as
// "not staff", or a database flap re-opens the hole this gate exists to close.
func (s *Store) StaffTierByPhone(ctx context.Context, phone string) (int64, string, error) {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return 0, "", nil
	}
	var id int64
	var tier *string
	err := s.Pool.QueryRow(ctx,
		`SELECT id, staff_tier FROM users WHERE phone = $1 LIMIT 1`, phone,
	).Scan(&id, &tier)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, "", nil
		}
		return 0, "", err
	}
	if tier == nil {
		return id, "", nil
	}
	return id, strings.TrimSpace(*tier), nil
}

// GetByUsername looks up an account by username and returns its id, bcrypt
// password hash, is_admin flag, and is_guest flag. Returns id=0 (and nil
// error) when no such username exists, so callers can map that to a generic
// auth failure.
//
// Phase 30 — backs POST /api/auth/admin/login.
// Note #40 — also backs POST /api/auth/guest/login (isGuest lets that
// endpoint refuse to authenticate a non-guest account through the guest
// door, even if the username/password happen to match).
func (s *Store) GetByUsername(ctx context.Context, username string) (id int64, passwordHash string, isAdmin int, isGuest bool, err error) {
	username = strings.TrimSpace(username)
	if username == "" {
		return 0, "", 0, false, nil
	}
	// Matched case-insensitively. A sign-in name is typed by a person, often on
	// a phone keyboard that capitalises the first letter unasked, and an exact
	// match turned that into "Invalid username or password" with nothing on
	// screen to suggest the case was the problem.
	//
	// New names are stored folded (normalizeUsername in the admin handler), so
	// a case-only pair cannot be created — but rows predating that are not
	// covered by the partial UNIQUE index, which is over the raw column. So ask
	// for two and refuse to guess if two come back: picking either would decide
	// whose password is being checked by row order. Fail closed; the operator
	// sees the same message as a wrong password, and the log line below says
	// which name was ambiguous.
	var hash *string
	var admin *int
	rows, err := s.Pool.Query(ctx,
		`SELECT id, password_hash, is_admin, is_guest FROM users
		 WHERE LOWER(username) = LOWER($1) ORDER BY id LIMIT 2`, username,
	)
	if err != nil {
		return 0, "", 0, false, err
	}
	defer rows.Close()
	matches := 0
	for rows.Next() {
		matches++
		if matches > 1 {
			log.Printf("[authz] username %q matches %d accounts case-insensitively; refusing to guess", username, matches)
			return 0, "", 0, false, nil
		}
		if scanErr := rows.Scan(&id, &hash, &admin, &isGuest); scanErr != nil {
			return 0, "", 0, false, scanErr
		}
	}
	if err := rows.Err(); err != nil {
		return 0, "", 0, false, err
	}
	if matches == 0 {
		return 0, "", 0, false, nil
	}
	if hash != nil {
		passwordHash = *hash
	}
	if admin != nil {
		isAdmin = *admin
	}
	return id, passwordHash, isAdmin, isGuest, nil
}

// GetPhoneByID returns a user's phone (empty string if none/unknown). Used by
// the admin-login 2FA step to decide where to send the OTP.
func (s *Store) GetPhoneByID(ctx context.Context, id int64) (string, error) {
	var phone *string
	err := s.Pool.QueryRow(ctx, `SELECT phone FROM users WHERE id = $1 LIMIT 1`, id).Scan(&phone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	if phone == nil {
		return "", nil
	}
	return strings.TrimSpace(*phone), nil
}

// GetEmailByID returns a user's email (empty string if none/unknown). H1 — the
// admin-login and permission second factors may be delivered to it instead of
// the phone, so the sender needs a way to ask for one.
func (s *Store) GetEmailByID(ctx context.Context, id int64) (string, error) {
	var email *string
	err := s.Pool.QueryRow(ctx, `SELECT email FROM users WHERE id = $1 LIMIT 1`, id).Scan(&email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	if email == nil {
		return "", nil
	}
	return strings.TrimSpace(*email), nil
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

// ErrUsernameTaken is returned by InsertGuest when the chosen username
// already belongs to another account (guest or otherwise — username is a
// single shared namespace, see migration 014).
var ErrUsernameTaken = errors.New("username already taken")

// ErrNotGuest is returned by UpgradeGuestPhone when the target row isn't
// (or is no longer) a guest account.
var ErrNotGuest = errors.New("account is not a guest")

// ErrPhoneTaken is returned by UpgradeGuestPhone when the phone being
// attached already belongs to a different account.
var ErrPhoneTaken = errors.New("phone already in use")

// InsertGuest creates a new lightweight guest account (Note #40): username +
// bcrypt password hash, no phone, registration_status 'approved' (self-serve,
// no admin review needed to browse), role_id NULL until upgraded. Returns
// ErrUsernameTaken if the username is already in use.
//
// fullName is the optional name the guest typed at sign-up (J1); pass "" when
// the client did not collect one.
//
// It also creates the account's `user_profiles` row, in the same transaction.
// That row is NOT a nicety for the name — it is the fix for a silent
// data-loss bug. Guests used to have no profile row at all, so every writer
// that does `UPDATE user_profiles … WHERE user_id = $1` (SetFieldPrivacy,
// SetPrivacyExtras, and the profile setters) updated ZERO rows and still
// returned a nil error: the guest's privacy switches appeared to save and
// stored nothing. Creating the row up front makes those writers real.
//
// The NOT NULL columns are seeded with the empty string rather than the
// legacy PHP "1" placeholder used by UpdateProfile — empty reads as blank
// everywhere, whereas "1" would render as if the person were named "1". This matches
// what the newer admin create/edit paths already do (admin_status.go,
// admin_edit.go). A guest who later attaches a phone flows through
// SubmitRegistration, which detects the existing row and takes its UPDATE
// branch, so no duplicate row is ever created.
func (s *Store) InsertGuest(ctx context.Context, username, passwordHash, fullName string) (int64, error) {
	username = strings.TrimSpace(username)
	fullName = strings.TrimSpace(fullName)
	if username == "" || passwordHash == "" {
		return 0, errors.New("username and password_hash are required")
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("begin guest insert: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var id int64
	err = tx.QueryRow(ctx,
		`INSERT INTO users (username, password_hash, is_guest, role_id, registration_status)
		 VALUES ($1, $2, TRUE, NULL, 'approved') RETURNING id`,
		username, passwordHash,
	).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return 0, ErrUsernameTaken
		}
		return 0, fmt.Errorf("insert guest user %q: %w", username, err)
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address)
		 VALUES ($1, $2, '', '')`,
		id, fullName,
	); err != nil {
		return 0, fmt.Errorf("insert guest profile for user %d: %w", id, err)
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("commit guest insert: %w", err)
	}
	return id, nil
}

// UpgradeGuestPhone attaches a verified phone number to an existing guest
// account, converting it into a normal phone-identified account: is_guest
// flips to false and registration_status resets to 'incomplete' so the
// account flows through the SAME "complete your registration" form as any
// other brand-new phone signup (Note #40 — Account Upgrade and Conversion).
// The username/password_hash are left in place (harmless — GuestLogin
// refuses non-guest rows via is_guest, so the old guest credentials simply
// stop being a valid entry point once this runs).
func (s *Store) UpgradeGuestPhone(ctx context.Context, userID int64, phone string) error {
	phone = strings.TrimSpace(phone)
	if userID <= 0 || phone == "" {
		return errors.New("userID and phone are required")
	}
	tag, err := s.Pool.Exec(ctx,
		`UPDATE users
		    SET phone = $1, is_guest = FALSE, registration_status = 'incomplete'
		  WHERE id = $2 AND is_guest = TRUE`,
		phone, userID,
	)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return ErrPhoneTaken
		}
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotGuest
	}
	return nil
}

// GetAccountForClient returns the user + joined profile, mirroring the PHP shape.
func (s *Store) GetAccountForClient(ctx context.Context, userID int64) (*Account, error) {
	if userID <= 0 {
		return nil, nil
	}
	var (
		acc        Account
		roleID     *int
		active     *int
		isAdmin    *int
		regStatus  *string
		staffTier  *string
		profileID  *int64
		fullName   *string
		gender     *string
		address    *string
		picture    *string
		dob        *string
		acctStatus *string
		privacy    []string
	)
	var username *string
	// K21 — the three identity-code columns, COALESCEd because the LEFT JOIN
	// yields NULL for an account with no profile row at all.
	var recipientCode, volunteerCode, grantorCode string
	err := s.Pool.QueryRow(ctx,
		`SELECT u.id, COALESCE(u.phone, '') AS phone, u.role_id, u.active, u.is_admin, u.created_at, u.registration_status, u.staff_tier, u.account_status, u.is_guest, u.username, u.wallet_balance_iqd,
		        (u.password_hash IS NOT NULL AND u.password_hash <> ''),
		        up.id, up.full_name, up.gender, up.address, up.profile_picture,
		        to_char(up.date_of_birth, 'YYYY-MM-DD'), COALESCE(up.field_privacy, '{}'),
		        COALESCE(up.recipient_code, ''), COALESCE(up.volunteer_code, ''),
		        COALESCE(up.grantor_code, '')
		   FROM users u
		   LEFT JOIN user_profiles up ON up.user_id = u.id
		  WHERE u.id = $1
		  LIMIT 1`,
		userID,
	).Scan(&acc.UserID, &acc.Phone, &roleID, &active, &isAdmin, &acc.CreatedAt, &regStatus, &staffTier, &acctStatus, &acc.IsGuest, &username, &acc.WalletBalanceIQD, &acc.HasPassword,
		&profileID, &fullName, &gender, &address, &picture, &dob, &privacy,
		&recipientCode, &volunteerCode, &grantorCode)
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
	if acctStatus != nil {
		acc.AccountStatus = *acctStatus
	}
	if username != nil {
		acc.Username = *username
	}
	if privacy == nil {
		privacy = []string{}
	}
	acc.FieldPrivacy = privacy
	acc.IdentityCode = pickIdentityCode(acc.RoleID, recipientCode, volunteerCode, grantorCode)
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
	Items      []Account  `json:"items"`
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
// status filters by account_status: "" (the default) hides archived accounts
// so they leave the main list once archived; "archived" shows only those (the
// dashboard's Archived view); "all" shows everything. Suspended and banned
// accounts stay in the default list — they still need attention.
func (s *Store) PaginatedList(ctx context.Context, page, perPage int, q, status string) (*PageUsers, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	conds := []string{}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		i := strconv.Itoa(len(args))
		// "Allow searches by identification code." recipient_code and
		// volunteer_code exist precisely so a person can be referred to
		// without their name — but the staff lookup matched only phone and
		// full_name, so the one identifier that is safe to quote in a
		// conversation was the one thing you could not search by.
		//
		// H23 — grantor_code joins them. Adding the column without adding it
		// here would have shipped a donor code that no one could look a donor
		// up by, which is most of the point of having one.
		conds = append(conds, "(u.phone ILIKE $"+i+
			" OR up.full_name ILIKE $"+i+
			" OR up.recipient_code ILIKE $"+i+
			" OR up.volunteer_code ILIKE $"+i+
			" OR up.grantor_code ILIKE $"+i+")")
	}
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "all":
		// no status predicate
	case "archived":
		conds = append(conds, "COALESCE(u.account_status, 'active') = 'archived'")
	default:
		conds = append(conds, "COALESCE(u.account_status, 'active') <> 'archived'")
	}
	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
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
		SELECT u.id, COALESCE(u.phone, '') AS phone, u.role_id, u.active, u.is_admin, u.created_at, u.registration_status, u.staff_tier, u.account_status, u.is_guest, u.username, u.wallet_balance_iqd,
		       (u.password_hash IS NOT NULL AND u.password_hash <> ''),
		       up.id, up.full_name, up.gender, up.address, up.profile_picture,
		       to_char(up.date_of_birth, 'YYYY-MM-DD'),
		       up.city, up.occupation, up.family_size, up.housing_status,
		       up.monthly_income, up.skills, up.availability, up.experience,
		       -- K21 — the same identity code the account itself reports, so a
		       -- staff member who searched by a code can also SEE it on the row
		       -- rather than only matching it. An always-empty field here would
		       -- read as "this person has no code", which is not true.
		       COALESCE(up.recipient_code, ''), COALESCE(up.volunteer_code, ''),
		       COALESCE(up.grantor_code, '')
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
			acc           Account
			roleID        *int
			active        *int
			isAdmin       *int
			regStatus     *string
			staffTier     *string
			profileID     *int64
			fullName      *string
			gender        *string
			address       *string
			picture       *string
			dob           *string
			acctStatus    *string
			city          *string
			occupation    *string
			familySize    *int
			housingStatus *string
			monthlyIncome *string
			skills        *string
			availability  *string
			experience    *string
			username      *string
			recipientCode string
			volunteerCode string
			grantorCode   string
		)
		err := rows.Scan(&acc.UserID, &acc.Phone, &roleID, &active, &isAdmin, &acc.CreatedAt, &regStatus, &staffTier, &acctStatus, &acc.IsGuest, &username, &acc.WalletBalanceIQD, &acc.HasPassword,
			&profileID, &fullName, &gender, &address, &picture, &dob,
			&city, &occupation, &familySize, &housingStatus, &monthlyIncome, &skills, &availability, &experience,
			&recipientCode, &volunteerCode, &grantorCode)
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
		if staffTier != nil {
			acc.StaffTier = *staffTier
		}
		if acctStatus != nil {
			acc.AccountStatus = *acctStatus
		}
		if username != nil {
			acc.Username = *username
		}
		acc.IdentityCode = pickIdentityCode(acc.RoleID, recipientCode, volunteerCode, grantorCode)
		if profileID != nil && *profileID > 0 {
			acc.Profile = &Profile{
				ProfileID:      *profileID,
				FullName:       nilIfEmpty(fullName),
				Gender:         nilIfEmpty(gender),
				Address:        nilIfEmpty(address),
				ProfilePicture: nilIfEmpty(picture),
				DateOfBirth:    nilIfEmpty(dob),
				City:           nilIfEmpty(city),
				Occupation:     nilIfEmpty(occupation),
				FamilySize:     familySize,
				HousingStatus:  nilIfEmpty(housingStatus),
				MonthlyIncome:  nilIfEmpty(monthlyIncome),
				Skills:         nilIfEmpty(skills),
				Availability:   nilIfEmpty(availability),
				Experience:     nilIfEmpty(experience),
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
