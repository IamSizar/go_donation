// auth_password_setup.go — the ONE thing a verified OTP is allowed to do.
//
// # THE DESIGN THIS IMPLEMENTS
//
// The owner's decision: "OTP for account creation only, password will be used
// for sign in to the app later." So a code proves a phone number once, at
// signup, and every sign-in after that is POST /api/auth/login with a password.
//
// # THE PROBLEM THAT DECIDED THE SHAPE
//
// 36 of the 46 accounts in production hold no password_hash at all — 34
// ordinary users plus ids 1 (admin) and 34 (super_admin), neither of which has
// a username either, so the dashboard's username+password door is not an answer
// for them. Under "password to sign in" every one of those 36 is locked out
// unless something lets them set a first password.
//
// The obvious bridge — phone, code, choose a password — re-opens the exact hole
// 389fbe4 closed, because the only OTP delivery configured in production is
// DEMO delivery, and demo mode returns the code to the caller in the
// /auth/otp/request response body. A factor that hands you the factor is not
// one. Bounded badly, "verify your number and set a password" means anyone who
// knows your phone number owns your account.
//
// # THE BOUND
//
// A verified code can do exactly one thing and no other:
//
//	give a password to an account that HAS NONE.
//
// Everything follows from that single sentence:
//
//   - It mints no session by itself. /auth/otp/verify hands back a setup ticket,
//     not a token (see auth.go OTPVerify).
//   - It cannot touch an account that already has a password — not to replace
//     one, not to reset one. users.SetPasswordIfUnset enforces that in the
//     UPDATE itself, so two racing claims cannot both win.
//   - It is therefore ONE-TIME PER ACCOUNT, and the window closes for good the
//     moment the legitimate owner uses it. A standing hole ("36 accounts are
//     seizable by phone number, repeatedly, forever") becomes a race that each
//     account runs once and that shrinks every time someone signs up.
//   - A STAFF account's claim is not available on the public demo code at all.
//     staffDemoCodeFor / staffDemoVerifyRefused already require
//     OTP_STAFF_DEMO_CODE — a code the server never prints — before a staff
//     phone can spend a demo OTP, and that gate runs before any ticket exists.
//
// There is deliberately NO self-service forgot-password. It is the same flow
// with the bound removed, and without real delivery it would make every account
// on the platform permanently seizable rather than once. Until OTPIQ_API_KEY is
// configured, a forgotten password is reset by staff through the existing
// POST /api/admin/users/:id/password. This is stated for the owner in the A16
// notes in CLIENT_NOTES_CHECKLIST.md.
//
// Every refusal below carries a stable translatable `code`, is logged
// server-side with the phone hint and IP, and fails CLOSED. No handler in this
// file logs or returns a password or a hash.
package handlers

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// passwordSetReq is the body for POST /api/auth/password/set.
//
// SetupTicket is what /auth/otp/verify returned for this number. The password
// is never echoed back in any response.
type passwordSetReq struct {
	Phone       string `json:"phone"`
	SetupTicket string `json:"setup_ticket"`
	Password    string `json:"password"`
}

// POST /api/auth/password/set
//
// Body: {phone, setup_ticket, password}. Gives a first password to the account
// behind a phone number that has just answered an OTP, creating the account if
// the number is new, and signs the caller in with the same response shape as
// /auth/login so the app can treat signup and sign-in identically.
//
// Refuses — always without setting anything — when the ticket is missing,
// stale, wrong or spent; when the password breaks the server-side rules; and
// when the account already has a password, which is the bound described in the
// file header.
func (h *AuthHandler) SetPassword(c *gin.Context) {
	var req passwordSetReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{
			"status": "error", "error": "Invalid request body.", "code": "invalid_request",
		})
		return
	}

	ctx := c.Request.Context()
	ip := auth.ClientIP(c.Request.RemoteAddr)

	phone := auth.NormalizePhone(req.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"status": "error", "error": "A valid mobile number is required.", "code": "invalid_phone",
		})
		return
	}
	ticket := strings.TrimSpace(req.SetupTicket)
	if ticket == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"status": "error",
			"error":  "Verify your number again before choosing a password.",
			"code":   "setup_ticket_invalid",
		})
		return
	}

	// Password rules are checked BEFORE the ticket is spent, so a typo'd
	// password does not cost the user their verification and send them back to
	// the code screen. Nothing is written either way, so this leaks nothing.
	password := auth.NormalizeNewPassword(req.Password)
	if err := auth.ValidateNewPassword(password); err != nil {
		code := "password_too_short"
		message := "Choose a password of at least 8 characters."
		if errors.Is(err, auth.ErrPasswordTooLong) {
			code = "password_too_long"
			message = "That password is too long. Use 72 characters or fewer."
		}
		// The value is never logged — only the fact that it was refused.
		log.Printf("[authn] password set refused: %s phone_hint=%s ip=%s", code, maskPhone(phone), ip)
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": message, "code": code})
		return
	}

	// ─── Spend the proof ────────────────────────────────────────────────
	if h.SetupTickets == nil {
		// Cannot happen through NewAuthHandler, which derives the store. A
		// handler that cannot check a ticket must never write a password.
		log.Printf("[authn] password set: ticket store unavailable phone_hint=%s ip=%s", maskPhone(phone), ip)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Could not verify this number.", "code": "server_error",
		})
		return
	}
	result, attemptsLeft, err := h.SetupTickets.Consume(ctx, phone, ticket)
	if err != nil {
		// We could not tell whether this number proved anything. Fail CLOSED.
		log.Printf("[authn] password set: ticket check failed phone_hint=%s ip=%s: %v",
			maskPhone(phone), ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Could not verify this number.", "code": "server_error",
		})
		return
	}
	if result != auth.SetupTicketOK {
		status, code, message := http.StatusUnauthorized, "setup_ticket_invalid",
			"Verify your number again before choosing a password."
		switch result {
		case auth.SetupTicketExpired:
			status, code, message = http.StatusGone, "setup_ticket_expired",
				"That verification expired. Request a new code and try again."
		case auth.SetupTicketExhausted:
			status, code, message = http.StatusTooManyRequests, "setup_ticket_exhausted",
				"Too many failed attempts. Request a new code and try again."
		}
		log.Printf("[authn] password set refused: %s phone_hint=%s ip=%s", code, maskPhone(phone), ip)
		body := gin.H{"status": "error", "error": message, "code": code}
		if result == auth.SetupTicketMismatch {
			body["attempts_left"] = attemptsLeft
		}
		c.JSON(status, body)
		return
	}

	// ─── Resolve the account the proof belongs to ───────────────────────
	existingID, err := h.Users.GetIDByPhone(ctx, phone)
	if err != nil {
		log.Printf("[authn] password set: phone lookup failed phone_hint=%s ip=%s: %v",
			maskPhone(phone), ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Database error (lookup).", "code": "server_error",
		})
		return
	}
	returning := existingID > 0

	// The account is created HERE rather than at verify time, so a signup the
	// user abandoned at the password screen leaves no empty row behind.
	uid := existingID
	if uid == 0 {
		uid, err = h.Users.InsertWithPhone(ctx, phone)
		if err != nil || uid <= 0 {
			log.Printf("[authn] password set: account creation failed phone_hint=%s ip=%s: %v",
				maskPhone(phone), ip, err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"status": "error", "error": "Unable to create your account.", "code": "server_error",
			})
			return
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("[authn] password set: hashing failed user_id=%d ip=%s: %v", uid, ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Could not save your password.", "code": "server_error",
		})
		return
	}

	// The bound, enforced by the database: this writes only if the account
	// still has no password.
	claimed, err := h.Users.SetPasswordIfUnset(ctx, uid, string(hash))
	if err != nil {
		log.Printf("[authn] password set: write failed user_id=%d ip=%s: %v", uid, ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Could not save your password.", "code": "server_error",
		})
		return
	}
	if !claimed {
		// Either the account already had a password (OTPVerify normally catches
		// that and never issues a ticket) or a concurrent claim won the race.
		// Both answers are the same: this account signs in with its password.
		log.Printf("[authn] password set refused: account already has a password user_id=%d ip=%s", uid, ip)
		c.JSON(http.StatusConflict, gin.H{
			"status": "error",
			"error":  "This number already has a password. Sign in with it instead.",
			"code":   "password_already_set",
		})
		return
	}
	log.Printf("[authn] password set: first password stored user_id=%d returning=%t ip=%s", uid, returning, ip)

	// ─── Sign them in ───────────────────────────────────────────────────
	role, _ := h.Users.GetRoleID(ctx, uid)
	account, _ := h.Users.GetAccountForClient(ctx, uid)
	session, err := h.Tokens.IssueToken(ctx, uid, c.Request.UserAgent(), ip)
	if err != nil {
		// The password IS saved; only the session failed. Say so plainly rather
		// than implying the whole step must be repeated — the caller can sign in
		// with the password they just chose.
		log.Printf("[authn] password set: token issue failed user_id=%d ip=%s: %v", uid, ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error",
			"error":  "Your password was saved, but signing you in failed. Try signing in.",
			"code":   "session_failed",
		})
		return
	}

	var roleField any = nil
	if role > 0 {
		roleField = role
	}
	regStatus := ""
	if account != nil {
		regStatus = account.RegistrationStatus
	}
	c.JSON(http.StatusOK, gin.H{
		"status":              "success",
		"user_id":             uid,
		"returning_user":      returning,
		"has_role":            role > 0,
		"role_id":             roleField,
		"registration_status": regStatus,
		"account":             account,
		"session":             session,
		"access_token":        session.AccessToken,
		"token_type":          session.TokenType,
		"expires_at":          session.ExpiresAt,
		"expires_in":          session.ExpiresIn,
	})
}
