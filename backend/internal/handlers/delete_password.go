// delete_password.go — the one place that asks "is this really you?" before a
// destructive action.
//
// # WHY THIS FILE EXISTS
//
// The client's rule is two sentences: "all delete should go to trash bin, and
// any delete requires entering the password". The Trash half was already built
// (admin_delete.go · trashRow). This file is the second half.
//
// Before it, the password check existed TWICE — copy-pasted into
// AdminTrashHandler.Restore and AdminTrashHandler.Purge — and nowhere else, so
// each of the ~33 admin DELETE routes was a single unconfirmed click. Two
// copies of a security check is how the third one ends up subtly weaker, so
// both call the helper below now and every DELETE runs it as middleware.
//
// # WHAT THE PASSWORD IS
//
// The ACTING staff member's OWN account password, re-entered — not a shared
// PIN, not the target user's password. That is what Restore/Purge already
// meant by "password", so re-using the meaning keeps one mental model.
//
// # PER ACTION, NOT PER SESSION
//
// There is deliberately NO unlock window and NO cached "recently confirmed"
// flag. "Any delete requires entering the password" is read literally, and an
// unlock window is precisely the thing that makes a mis-click destructive again.
//
// # IT FAILS CLOSED
//
// Every path that cannot POSITIVELY verify the password refuses the delete:
// no session, unreadable body, missing/blank field, no password_hash on the
// account, hash mismatch, or a database error while fetching the hash. The
// password itself is never logged, echoed, or included in an error message.
package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// maxPasswordBodyBytes caps how much of a confirmation body is read.
//
// WHY the limit exists: the middleware buffers the body in order to re-serve it
// to the handler behind it, so an unbounded read would let any authenticated
// staff account pin memory by sending a huge DELETE body. 8 KB is far more than
// `{"password":"..."}` ever needs.
const maxPasswordBodyBytes = 8 << 10

// passwordConfirmReq is the body shape every confirmed destructive action
// takes: {"password": "..."}.
type passwordConfirmReq struct {
	Password string `json:"password"`
}

// requireOwnPassword verifies the acting staff member's own password, supplied
// in the JSON request body, and reports whether the caller may proceed.
//
// It writes the HTTP error response itself and returns false on any failure, so
// a caller only has to write:
//
//	if !requireOwnPassword(c, pool, "delete") { return }
//
// `action` is the verb used in the user-facing message ("delete", "restore",
// "purge"), so the operator is told which action is being confirmed.
//
// Returns false — refusing the action — for every case it cannot verify. The
// messages say what to do next, and the submitted password never appears in any
// of them nor in any log line.
func requireOwnPassword(c *gin.Context, pool *pgxpool.Pool, action string) bool {
	user, ok := auth.UserFromGin(c)
	if !ok || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Not authenticated."})
		return false
	}

	// Read the body through a cap, then hand an identical copy back to the
	// request. gin's body is a one-shot stream: without the restore, a handler
	// behind this middleware that binds JSON would receive an empty body.
	raw, err := io.ReadAll(io.LimitReader(c.Request.Body, maxPasswordBodyBytes))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"error": "Could not read the confirmation. Please try again."})
		return false
	}
	c.Request.Body = io.NopCloser(bytes.NewReader(raw))

	var req passwordConfirmReq
	// A body that is absent or unparseable is treated exactly like a missing
	// password: refused. It must never fall through to a successful delete.
	if len(bytes.TrimSpace(raw)) > 0 {
		if err := json.Unmarshal(raw, &req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid JSON body."})
			return false
		}
	}
	pw := strings.TrimSpace(req.Password)
	if pw == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false,
			"error": "Enter your account password to " + action + " this record."})
		return false
	}

	var hash *string
	if err := pool.QueryRow(c.Request.Context(),
		"SELECT password_hash FROM users WHERE id = $1", user.UserID).Scan(&hash); err != nil {
		// Never guess on a DB error — refuse. The technical detail goes to the
		// log; the operator gets a plain sentence.
		log.Printf("delete-confirm: reading password_hash for user %d (%s): %v", user.UserID, action, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false,
			"error": "Could not confirm your password right now. Please try again."})
		return false
	}
	if hash == nil || *hash == "" {
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"error": "No password is set on your account; ask a Super-Admin to set one."})
		return false
	}
	if bcrypt.CompareHashAndPassword([]byte(*hash), []byte(pw)) != nil {
		c.JSON(http.StatusForbidden, gin.H{"success": false,
			"error": "Incorrect password. Nothing was " + pastTense(action) + "."})
		return false
	}
	return true
}

// pastTense renders the confirmation verb for the "nothing was …" reassurance,
// so a wrong password says what did NOT happen rather than only that it failed.
func pastTense(action string) string {
	switch action {
	case "delete":
		return "deleted"
	case "restore":
		return "restored"
	case "purge":
		return "purged"
	default:
		return action + "d"
	}
}

// RequireDeletePassword gates EVERY DELETE request on the group it is mounted
// on behind requireOwnPassword.
//
// WHY IT IS A GROUP-WIDE METHOD FILTER rather than 33 per-route entries: the
// gap being fixed was created by a check that had to be remembered at each call
// site. Mounted on the admin group, a delete route added tomorrow is confirmed
// by default and someone would have to work to exempt it — the fail-closed
// direction. Non-DELETE methods pass straight through untouched.
func RequireDeletePassword(pool *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Method != http.MethodDelete {
			c.Next()
			return
		}
		if !requireOwnPassword(c, pool, "delete") {
			c.Abort()
			return
		}
		c.Next()
	}
}
