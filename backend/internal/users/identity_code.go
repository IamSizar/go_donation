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
