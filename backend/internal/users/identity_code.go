// Identity codes (K21) — showing an account its own code, and resolving a code
// back to the person it names.
//
// WHY THIS FILE EXISTS
// The client asked to look up a donation / support history by identity code.
// The codes themselves already existed — recipient_code ER-%06d (073),
// volunteer_code VL-%06d (077), grantor_code GR-%06d (105) — but nothing joined
// them up:
//
//   - The account the app receives carried none of them, so the registration
//     form's promise that a code "يتم إنشاؤه تلقائياً بعد التسجيل" was never
//     followed by showing it to anybody.
//   - The only thing that matched a code was the admin user search, a
//     leading-wildcard ILIKE across all three columns. That is the right query
//     for a search box and the wrong one for a lookup: "ER-0001" would match
//     "ER-000123", and a lookup that matches loosely hands out the wrong
//     person's aid history.
//
// So this file adds the two exact operations K21 needs, and nothing wider.
// WHOSE history a resolved code may reveal is decided in
// internal/handlers/history_code.go, deliberately not here — this layer answers
// "who is this code", never "may you see it".
package users

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
)

// ErrCodeNotFound is returned by UserIDByIdentityCode when no profile carries
// the code. It is a distinct error rather than (0, nil) so a caller cannot
// mistake "nobody" for user zero.
var ErrCodeNotFound = errors.New("no account carries that identity code")

// pickIdentityCode chooses which of a profile's three codes IS this account's
// code.
//
// A profile can carry more than one — a recipient who later volunteers keeps
// both — so this has to be a decision rather than an accident of column order.
// The role's own code wins, so the code shown matches the role the account is
// acting in. When that column is empty the others are offered in turn, because
// somebody whose role changed still has a code written on their paperwork and
// showing them nothing would be worse than showing the old one.
func pickIdentityCode(roleID int, recipientCode, volunteerCode, grantorCode string) string {
	var preferred string
	switch roleID {
	case 1:
		preferred = grantorCode
	case 2:
		preferred = recipientCode
	case 3:
		preferred = volunteerCode
	}
	if preferred = strings.TrimSpace(preferred); preferred != "" {
		return preferred
	}
	for _, code := range []string{grantorCode, recipientCode, volunteerCode} {
		if c := strings.TrimSpace(code); c != "" {
			return c
		}
	}
	return ""
}

// identityCodePrefixForRole reports which identity-code scheme a role belongs
// to, or "" when the role has no scheme at all.
//
// This is deliberately a plain function over an int rather than a database
// lookup, because the decision it makes is the whole of the bug fixed here and
// it has to be testable on a bare checkout (the DB-backed tests in this package
// skip themselves without TEST_DATABASE_URL). Same reasoning as
// normalizeUsername in internal/handlers/admin_status.go.
//
// The three schemes are the three roles the client asked for codes for:
//
//	role 1, grantor / donor      -> GR-  (migration 105)
//	role 2, eligible recipient   -> ER-  (migration 073)
//	role 3, volunteer            -> VL-  (migration 077)
//
// ROLES 0, 4 AND 5 GET NOTHING, AND THAT IS INTENTIONAL. Role 0 is the guest /
// unassigned state a user sits in before choosing anything and can step back
// into (choose_role.go); role 4 is an employee; role 5 is the marriage /
// engagement account type. None of the three has a column on user_profiles, a
// prefix, or a migration minting one, so there is no code to assign and no
// honest way to invent one. A user moved into one of those roles keeps whatever
// code an earlier role already gave them — pickIdentityCode above still shows
// it via its fallback arm — and a user who never had one continues to have
// none. Returning "" here is what makes EnsureIdentityCodeForRole a no-op for
// them rather than an error, because moving somebody to employee is a perfectly
// ordinary thing to do and must not look like a failure.
func identityCodePrefixForRole(roleID int) string {
	switch roleID {
	case 1:
		return "GR-"
	case 2:
		return "ER-"
	case 3:
		return "VL-"
	default:
		return ""
	}
}

// EnsureIdentityCodeForRole mints the identity code that a role implies, once,
// for an account that does not already carry it.
//
// WHY THIS EXISTS
// Every mint used to sit on the registration path and be keyed on the role the
// account had at THAT moment: ER- inline in SubmitRegistration, GR- and VL- in
// the two branches at the end of internal/handlers/registration.go. Nothing
// minted anything when a role CHANGED afterwards, and roles do change — staff
// move an account with POST /api/admin/users/:id/role, and a user can move
// themselves with POST /api/choose_role. The result was an account whose
// reported role and whose code disagreed: user 58 in production reports role 2
// with an empty recipient_code and a GR-000058 left over from registering as a
// donor, so the app shows a recipient a donor's code and no ER- search will
// ever find them.
//
// So the role writers call this, and every account carries the code its current
// role implies.
//
// It never overwrites: each Ensure* helper it delegates to carries the
// `AND <col> = ”` guard, so a code already printed on somebody's paperwork
// survives. An account that has held two roles ends up carrying two codes,
// which is the case pickIdentityCode was written for.
//
// Returns nil for a role with no code scheme (see identityCodePrefixForRole)
// and for a user with no user_profiles row yet — the UPDATE simply matches
// nothing, and the registration path will mint the code when the profile is
// created.
func (s *Store) EnsureIdentityCodeForRole(ctx context.Context, userID int64, roleID int) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	switch identityCodePrefixForRole(roleID) {
	case "GR-":
		return s.EnsureGrantorCode(ctx, userID)
	case "ER-":
		return s.EnsureRecipientCode(ctx, userID)
	case "VL-":
		return s.EnsureVolunteerCode(ctx, userID)
	default:
		return nil
	}
}

// UserIDByIdentityCode resolves one whole identity code to the single user who
// holds it.
//
// EXACT match, case-insensitively, on the trimmed input — never a prefix and
// never a wildcard. A code is copied off a receipt or a screen and typed back
// by hand, so case and stray spaces are the caller's typing rather than a
// different code; anything else is a different code and must not match.
// Migration 113 indexes UPPER(col) on each of the three columns so this is an
// index probe rather than a scan of every profile.
//
// Returns ErrCodeNotFound for an empty, blank or unmatched code. The SQL is
// parameterized, so a value like "%" or "' OR 1=1 --" is compared as the text
// it is.
func (s *Store) UserIDByIdentityCode(ctx context.Context, code string) (int64, error) {
	trimmed := strings.TrimSpace(code)
	if trimmed == "" {
		return 0, ErrCodeNotFound
	}

	var userID int64
	err := s.Pool.QueryRow(ctx,
		`SELECT user_id
		   FROM user_profiles
		  WHERE (recipient_code <> '' AND UPPER(recipient_code) = UPPER($1))
		     OR (volunteer_code <> '' AND UPPER(volunteer_code) = UPPER($1))
		     OR (grantor_code   <> '' AND UPPER(grantor_code)   = UPPER($1))
		  LIMIT 1`, trimmed,
	).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrCodeNotFound
	}
	if err != nil {
		// The code is NOT echoed into the error: it identifies a person, and
		// this string ends up in the logs.
		return 0, fmt.Errorf("resolving identity code: %w", err)
	}
	return userID, nil
}
