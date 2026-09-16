// phone_identity.go — OPOS #26636. One place for the rule "no phone number can
// be on 2 accounts", as it applies to the dashboard's two user-write routes.
//
// WHAT IT CONTAINS
//   - normalizeIdentityPhone(): reduce a typed number to the ONE form
//     `users.phone` stores, or refuse the request with a translatable code.
//   - isUniqueViolation(): recognise Postgres' 23505 on a write.
//
// WHY IT EXISTS
// `users.phone` is the sign-in identity and has been UNIQUE since migration
// 001. A UNIQUE index compares STRINGS, so it only means "one account per
// number" while every writer agrees on how a number is spelled. The app-side
// paths did agree — sign-in, OTP and the guest upgrade all run the typed number
// through auth.NormalizePhone first — but the dashboard's POST /api/admin/users
// and PATCH /api/admin/users/:id stored it after a bare strings.TrimSpace. So
// "0750 858 2031" and "9647508582031" were two different index keys for one
// human number, and the constraint waved the second account through.
//
// auth.NormalizePhone is the single authority for the canonical form (its
// vectors live in internal/auth/phone_test.go, and admin-web/src/lib/phone.ts
// mirrors it on the client so the operator SEES what will be stored). This file
// is only the HTTP-shaped wrapper around it, so both handlers refuse in exactly
// the same words with exactly the same code.
//
// RACE SAFETY
// Nothing here serialises anything, and nothing needs to: once both writers
// normalise, two simultaneous creates of one number are two INSERTs of the SAME
// key, and the UNIQUE index refuses one of them inside the database. That is
// why the conflict is caught from the write's own error rather than from a
// check-then-insert, which two requests can both pass.
package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// pgUniqueViolation is Postgres' SQLSTATE for "duplicate key value violates
// unique constraint".
const pgUniqueViolation = "23505"

// normalizeIdentityPhone reduces `raw` to the canonical form stored in
// `users.phone` and returns (canonical, true).
//
// When the value cannot be read as a phone number at all — empty, a stray word,
// too few digits — it writes a 400 carrying the `phone_invalid` code and
// returns ("", false); the caller must return immediately, as with the
// rejectMaskedContactWrite guard beside it.
//
// The refusal carries a `code` rather than only prose because that is this
// project's localisation contract for a server refusal: the dashboard's
// describeError (admin-web/src/lib/api.ts) resolves `code` through the
// `error.<code>` namespace, so the operator reads it in their own language. The
// English `error` string stays as the fallback for any client that does not.
func normalizeIdentityPhone(c *gin.Context, raw string) (string, bool) {
	canonical := auth.NormalizePhone(raw)
	if canonical == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false, "code": "phone_invalid",
			"error": "That is not a valid phone number.",
		})
		return "", false
	}
	return canonical, true
}

// refusePhoneTaken writes the answer for "this number already belongs to
// another account" — 409, with the code the dashboard translates.
func refusePhoneTaken(c *gin.Context) {
	c.JSON(http.StatusConflict, gin.H{
		"success": false, "code": "phone_taken",
		"error": "This phone number is already on another account.",
	})
}

// isUniqueViolation reports whether a write failed because it duplicated a
// UNIQUE key.
//
// It unwraps to pgconn.PgError rather than matching on the message text, which
// is what the two call sites did before: err.Error() carries the code today
// only because pgx happens to print it, and a substring search for "duplicate"
// would also match an unrelated error that merely used the word.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == pgUniqueViolation
	}
	// Belt and braces for an error that lost its type on the way up (a wrapped
	// string, a driver in between): the SQLSTATE is still in the text.
	return strings.Contains(err.Error(), pgUniqueViolation)
}
