package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

type AuthHandler struct {
	Tokens *auth.TokenStore
	OTPs   *auth.OTPStore
	Users  *users.Store
	// Phase 19 — OTPIQ delivery client. nil when OTPIQ_API_KEY is not set;
	// the handler then refuses real-mode OTP with a 502 (demo still works).
	OTPIQ *auth.OTPIQClient
	// Requirement 6c — login brute-force throttle. Counts failed password
	// attempts per identity and locks after too many.
	LoginLocks *auth.LoginLockStore
	// Note #40 — alerts staff when a new guest account is created. nil-safe
	// (see notifyStaffInBackground).
	Notifier *notify.Notifier
}

func NewAuthHandler(t *auth.TokenStore, o *auth.OTPStore, u *users.Store, otpiq *auth.OTPIQClient, ll *auth.LoginLockStore, n *notify.Notifier) *AuthHandler {
	return &AuthHandler{Tokens: t, OTPs: o, Users: u, OTPIQ: otpiq, LoginLocks: ll, Notifier: n}
}

// notifyStaffInBackground alerts staff (dashboard) on a detached goroutine, so
// a slow fan-out never blocks the caller's response. Best-effort — errors are
// logged, not returned. Same pattern as BeneficiaryHandler's.
func (h *AuthHandler) notifyStaffInBackground(m notify.LocalizedMessage) {
	if h.Notifier == nil {
		return
	}
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if _, err := h.Notifier.BroadcastToStaff(bg, m); err != nil {
			log.Printf("[notify] staff alert failed: %v", err)
		}
	}()
}

// loginReq accepts both {"phone": "..."} and {"number": "..."} (matches PHP).
// Phase 20 — also accepts optional "password". When the user has a
// password_hash on file, the password is REQUIRED and verified with bcrypt;
// when password_hash is NULL the password (if supplied) is ignored and the
// classic phone-only flow runs.
type loginReq struct {
	Phone    string `json:"phone"`
	Number   string `json:"number"`
	Password string `json:"password"`
}

// POST /api/auth/login
// Mirrors percentage/api/auth/login/index.php — accept a phone, create user
// if new or return the existing one, then issue an access token.
func (h *AuthHandler) Login(c *gin.Context) {
	var req loginReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}

	raw := req.Phone
	if raw == "" {
		raw = req.Number
	}
	phone := auth.NormalizePhone(raw)
	if phone == "" {
		phone = strings.TrimSpace(raw)
	}
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Missing phone number."})
		return
	}

	ctx := c.Request.Context()

	existingID, err := h.Users.GetIDByPhone(ctx, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Database error (lookup)."})
		return
	}
	returning := existingID > 0

	// Phase 20 — password gate. If the existing user has a password_hash,
	// the caller MUST supply a matching password. This is checked BEFORE
	// we issue any tokens. New users (no row yet) skip this step — they
	// flow through the regular auto-create path below.
	if existingID > 0 {
		hash, err := h.Users.GetPasswordHash(ctx, existingID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"status": "error",
				"error":  "Database error (password lookup).",
			})
			return
		}
		if hash != "" {
			// Requirement 6c — brute-force throttle. Password accounts are
			// locked after too many failed attempts within the window.
			lockID := "p:" + phone
			if h.LoginLocks != nil {
				if locked, retryAfter := h.LoginLocks.Status(ctx, lockID); locked {
					c.JSON(http.StatusTooManyRequests, gin.H{
						"status":      "error",
						"error":       "Too many failed attempts. Try again later.",
						"retry_after": retryAfter,
					})
					return
				}
			}
			provided := strings.TrimSpace(req.Password)
			if provided == "" {
				// Tell the client a password is required so the SPA can
				// re-prompt without having to guess. (Not counted as a failed
				// attempt — no password was submitted to verify.)
				c.JSON(http.StatusUnauthorized, gin.H{
					"status":            "error",
					"error":             "Password required for this account.",
					"password_required": true,
				})
				return
			}
			if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(provided)); err != nil {
				if h.LoginLocks != nil {
					if locked, retryAfter := h.LoginLocks.RegisterFailure(ctx, lockID); locked {
						c.JSON(http.StatusTooManyRequests, gin.H{
							"status":      "error",
							"error":       "Too many failed attempts. Try again later.",
							"retry_after": retryAfter,
						})
						return
					}
				}
				c.JSON(http.StatusUnauthorized, gin.H{
					"status": "error",
					"error":  "Incorrect phone or password.",
				})
				return
			}
			// Correct password — clear any accumulated failed-attempt counter.
			if h.LoginLocks != nil {
				h.LoginLocks.Reset(ctx, lockID)
			}
		}
	}

	uid, err := h.Users.InsertWithPhone(ctx, phone)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to create user."})
		return
	}

	role, _ := h.Users.GetRoleID(ctx, uid)
	account, _ := h.Users.GetAccountForClient(ctx, uid)

	session, err := h.Tokens.IssueToken(ctx, uid, c.Request.UserAgent(), auth.ClientIP(c.Request.RemoteAddr))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to issue token."})
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

// googleLoginReq is the body for POST /api/auth/google.
type googleLoginReq struct {
	IDToken string `json:"id_token"`
}

// POST /api/auth/google — sign in / sign up with a Google ID token (Phase 9,
// B-09). Verifies the token with Google, find-or-creates the user, then issues
// an app access token using the SAME response shape as phone login so the app
// can treat both flows identically.
func (h *AuthHandler) GoogleLogin(c *gin.Context) {
	if !auth.GoogleConfigured() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "error", "error": "Google sign-in is not configured on the server.",
		})
		return
	}
	var req googleLoginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	ctx := c.Request.Context()

	claims, err := auth.VerifyGoogleIDToken(ctx, req.IDToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Google sign-in failed."})
		return
	}
	if !claims.EmailVerified {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Your Google email is not verified."})
		return
	}

	uid, returning, err := h.Users.UpsertGoogleUser(ctx, claims.Sub, claims.Email, claims.Name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to sign in."})
		return
	}

	role, _ := h.Users.GetRoleID(ctx, uid)
	account, _ := h.Users.GetAccountForClient(ctx, uid)
	session, err := h.Tokens.IssueToken(ctx, uid, c.Request.UserAgent(), auth.ClientIP(c.Request.RemoteAddr))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to issue token."})
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

// adminLoginReq is the body for POST /api/auth/admin/login.
type adminLoginReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
	// Otp is the second-factor code, sent on the SECOND call once the client has
	// received "otp_required" from the first (password-only) call. Empty on the
	// first call. Only consulted when ADMIN_LOGIN_2FA is enabled.
	Otp string `json:"otp"`
}

// adminLogin2FAEnabled gates the optional OTP second factor on admin sign-in
// (§24). OFF by default so enabling it is a deliberate, reversible ops decision
// — a misconfigured OTP provider can never silently lock staff out. Accepts
// 1/true/yes/on.
func adminLogin2FAEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("ADMIN_LOGIN_2FA"))) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

// sendAdminLoginOTP issues a login OTP to phone, mirroring the permission-change
// OTP flow: demo mode returns the code inline; real mode sends via OTPIQ. Returns
// (mode, demoCode). demoCode is "" outside demo mode.
func (h *AuthHandler) sendAdminLoginOTP(ctx context.Context, phone string) (mode, demoCode string, err error) {
	if auth.DemoEnabled() {
		code := auth.DemoCode()
		if err := h.OTPs.StoreCode(ctx, phone, code, "demo"); err != nil {
			return "", "", err
		}
		return "demo", code, nil
	}
	if h.OTPIQ == nil {
		return "", "", errOTPNotConfigured
	}
	code, err := auth.GenerateCode()
	if err != nil {
		return "", "", err
	}
	if err := h.OTPs.StoreCode(ctx, phone, code, "real"); err != nil {
		return "", "", err
	}
	if _, err := h.OTPIQ.SendVerification(ctx, phone, code); err != nil {
		_ = h.OTPs.ClearRecord(ctx, phone)
		return "", "", err
	}
	return "real", "", nil
}

var errOTPNotConfigured = errors.New("OTP delivery is not configured (OTPIQ_API_KEY)")

// POST /api/auth/admin/login
//
// Phase 30 — username + password login for the admin dashboard. Unlike the
// phone login this NEVER auto-creates a user: the account must already exist,
// have a bcrypt password_hash, and be is_admin=1. All failure modes return the
// same generic message so the endpoint can't be used to enumerate usernames.
func (h *AuthHandler) AdminLogin(c *gin.Context) {
	var req adminLoginReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	username := strings.TrimSpace(req.Username)
	password := req.Password
	if username == "" || password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Username and password are required."})
		return
	}

	ctx := c.Request.Context()

	// Requirement 6c — brute-force throttle for the admin dashboard login.
	lockID := "u:" + username
	if h.LoginLocks != nil {
		if locked, retryAfter := h.LoginLocks.Status(ctx, lockID); locked {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"status": "error", "error": "Too many failed attempts. Try again later.",
				"retry_after": retryAfter,
			})
			return
		}
	}

	id, hash, isAdmin, _, err := h.Users.GetByUsername(ctx, username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Database error (lookup)."})
		return
	}
	// Generic 401 for unknown user / no password set / wrong password — never
	// reveal which one failed. Every such failure counts toward the lockout.
	if id == 0 || hash == "" || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		if h.LoginLocks != nil {
			if locked, retryAfter := h.LoginLocks.RegisterFailure(ctx, lockID); locked {
				c.JSON(http.StatusTooManyRequests, gin.H{
					"status": "error", "error": "Too many failed attempts. Try again later.",
					"retry_after": retryAfter,
				})
				return
			}
		}
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Invalid username or password."})
		return
	}
	if isAdmin != 1 {
		c.JSON(http.StatusForbidden, gin.H{"status": "error", "error": "Admin access required."})
		return
	}
	// §24 — optional OTP second factor (env-gated, OFF by default). Runs AFTER
	// the password is confirmed but BEFORE the failed-attempt counter is cleared
	// or any token is issued. Phoneless admins are intentionally allowed through
	// (a missing phone must never lock an account out of its own dashboard).
	if adminLogin2FAEnabled() {
		phone, _ := h.Users.GetPhoneByID(ctx, id)
		if phone != "" {
			if strings.TrimSpace(req.Otp) == "" {
				// First step: password was correct — send a code and ask for it.
				// We do NOT clear the lock counter or issue a token yet.
				mode, demoCode, err := h.sendAdminLoginOTP(ctx, phone)
				if err != nil {
					c.JSON(http.StatusBadGateway, gin.H{"status": "error", "error": "Could not send the verification code."})
					return
				}
				resp := gin.H{"status": "otp_required", "phone_hint": maskPhone(phone), "mode": mode}
				if mode == "demo" {
					resp["demo_code"] = demoCode
				}
				c.JSON(http.StatusOK, resp)
				return
			}
			// Second step: verify the single-use code.
			if okOtp, reason := h.OTPs.VerifyAndConsume(ctx, phone, strings.TrimSpace(req.Otp)); !okOtp {
				c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": reason})
				return
			}
		}
	}

	// Successful admin login — clear the failed-attempt counter.
	if h.LoginLocks != nil {
		h.LoginLocks.Reset(ctx, lockID)
	}

	role, _ := h.Users.GetRoleID(ctx, id)
	account, _ := h.Users.GetAccountForClient(ctx, id)
	session, err := h.Tokens.IssueToken(ctx, id, c.Request.UserAgent(), auth.ClientIP(c.Request.RemoteAddr))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to issue token."})
		return
	}

	var roleField any = nil
	if role > 0 {
		roleField = role
	}
	c.JSON(http.StatusOK, gin.H{
		"status":       "success",
		"user_id":      id,
		"has_role":     role > 0,
		"role_id":      roleField,
		"account":      account,
		"session":      session,
		"access_token": session.AccessToken,
		"token_type":   session.TokenType,
		"expires_at":   session.ExpiresAt,
		"expires_in":   session.ExpiresIn,
	})
}

// otpRequestReq is the body for POST /api/auth/otp/request.
type otpRequestReq struct {
	Phone string `json:"phone"`
	Mode  string `json:"mode"` // "real" or "demo"
}

// POST /api/auth/otp/request
// Mirrors percentage/api/auth/otp/request/index.php.
// In Phase 3a, real SMS delivery returns 502 unless an SMS provider is wired up
// (matches PHP behavior when OTPIQ key is missing). Demo mode is local-dev only.
func (h *AuthHandler) OTPRequest(c *gin.Context) {
	var req otpRequestReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body."})
		return
	}

	phone := auth.NormalizePhone(req.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "A valid mobile number is required."})
		return
	}
	mode := strings.ToLower(strings.TrimSpace(req.Mode))
	if mode != "demo" {
		mode = "real"
	}

	ctx := c.Request.Context()
	ip := auth.ClientIP(c.Request.RemoteAddr)

	rate := h.OTPs.CheckIPRate(ctx, ip)
	if !rate.Allowed {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":       "Too many verification requests from this network. Try again later.",
			"retry_after": rate.RetryAfter,
		})
		return
	}

	// Section 27 — progressive per-phone lockout. If this number is already
	// serving a lock (2h / 6h / 24h), refuse before doing anything else.
	if locked, retryAfter := h.OTPs.PhoneLockStatus(ctx, phone); locked {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":       "This number is temporarily locked after too many verification requests. Try again later.",
			"retry_after": retryAfter,
		})
		return
	}

	existing, err := h.OTPs.GetRecord(ctx, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error (otp lookup)."})
		return
	}
	if existing != nil {
		sinceSent := int(time.Since(existing.SentAt).Seconds())
		cooldown := int(auth.OTPResendCooldown.Seconds())
		if sinceSent < cooldown {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":       "Please wait before requesting another code.",
				"retry_after": cooldown - sinceSent,
			})
			return
		}
	}

	// Section 27 — count this genuine (past-cooldown) request against the
	// per-phone window; if it crosses the threshold, apply the next escalating
	// lock and refuse now.
	if locked, retryAfter := h.OTPs.RegisterPhoneRequest(ctx, phone); locked {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":       "This number is now temporarily locked after too many verification requests. Try again later.",
			"retry_after": retryAfter,
		})
		return
	}

	if mode == "demo" {
		if !auth.DemoEnabled() {
			c.JSON(http.StatusForbidden, gin.H{"error": "Demo OTP mode is disabled."})
			return
		}
		code := auth.DemoCode()
		if err := h.OTPs.StoreCode(ctx, phone, code, "demo"); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store verification code."})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"status":     "success",
			"message":    "Demo verification code is ready.",
			"mode":       "demo",
			"phone":      phone,
			"expires_in": int(auth.OTPTTL.Seconds()),
			"demo_code":  code,
		})
		return
	}

	// Phase 19 — REAL mode: send via OTPIQ. Provider = "whatsapp-sms" so
	// WhatsApp is attempted first and SMS is the fallback (product decision).
	// If OTPIQ_API_KEY isn't configured, we surface 502 the same way the
	// old PHP code did.
	if h.OTPIQ == nil {
		c.JSON(http.StatusBadGateway, gin.H{
			"error":   "Failed to send verification code.",
			"details": "OTPIQ is not configured (set OTPIQ_API_KEY).",
		})
		return
	}
	code, err := auth.GenerateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate verification code."})
		return
	}
	// Persist BEFORE sending so an OTPIQ flake doesn't accept-but-lose the
	// code; the same flow is used by every major OTP provider.
	if err := h.OTPs.StoreCode(ctx, phone, code, "real"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store verification code."})
		return
	}
	send, err := h.OTPIQ.SendVerification(ctx, phone, code)
	if err != nil {
		// Clean up the stored code so the user can request a fresh one
		// immediately without the resend-cooldown blocking them.
		_ = h.OTPs.ClearRecord(ctx, phone)

		// Map OTPIQ error sentinels to friendly user-facing messages.
		switch {
		case errors.Is(err, auth.ErrOTPIQInsufficient):
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error":   "Verification service is temporarily unavailable.",
				"details": "Account credit is low — contact support.",
			})
		case errors.Is(err, auth.ErrOTPIQBadPhone):
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Phone number is not in a supported format.",
			})
		case errors.Is(err, auth.ErrOTPIQRateLimited):
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "Too many verification requests. Try again shortly.",
			})
		default:
			c.JSON(http.StatusBadGateway, gin.H{
				"error":   "Failed to send verification code.",
				"details": err.Error(),
			})
		}
		return
	}

	// 200 — code is in the user's hands (or will be in seconds).
	// We deliberately DON'T return the code itself in real mode.
	resp := gin.H{
		"status":     "success",
		"message":    "Verification code sent.",
		"mode":       "real",
		"phone":      phone,
		"expires_in": int(auth.OTPTTL.Seconds()),
	}
	if send.SmsID != "" {
		resp["sms_id"] = send.SmsID // for admin debugging / OTPIQ tracking
	}
	c.JSON(http.StatusOK, resp)
}

// otpVerifyReq is the body for POST /api/auth/otp/verify.
type otpVerifyReq struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

// consumeOTPCode validates a submitted code against the stored OTP record for
// phone — lookup, demo-mode gate, expiry, attempt limit, hash compare — and
// clears the record on success. Shared by OTPVerify and the guest-upgrade
// phone-attach flow (Note #40 — GuestUpgradeVerify) so both apply identical
// rate/attempt/expiry rules. On success mode is the record's delivery mode
// ("demo"/"real"); on failure body is the ready-to-send JSON error payload.
func (h *AuthHandler) consumeOTPCode(ctx context.Context, phone, code string) (ok bool, mode string, status int, body gin.H) {
	rec, err := h.OTPs.GetRecord(ctx, phone)
	if err != nil {
		return false, "", http.StatusInternalServerError, gin.H{"error": "Database error (otp lookup)."}
	}
	if rec == nil {
		return false, "", http.StatusNotFound, gin.H{"error": "No verification code found for this phone number."}
	}
	if rec.Mode == "demo" && !auth.DemoEnabled() {
		_ = h.OTPs.ClearRecord(ctx, phone)
		return false, "", http.StatusForbidden, gin.H{"error": "Demo OTP mode is disabled."}
	}
	if time.Now().After(rec.ExpiresAt) {
		_ = h.OTPs.ClearRecord(ctx, phone)
		return false, "", http.StatusGone, gin.H{"error": "Verification code has expired."}
	}
	if rec.Attempts >= auth.OTPMaxAttempts {
		_ = h.OTPs.ClearRecord(ctx, phone)
		return false, "", http.StatusTooManyRequests, gin.H{"error": "Too many failed attempts. Request a new code."}
	}
	if !auth.VerifyCode(rec.CodeHash, code) {
		newCount, _ := h.OTPs.IncAttempts(ctx, phone)
		left := auth.OTPMaxAttempts - newCount
		if left < 0 {
			left = 0
		}
		return false, "", http.StatusUnauthorized, gin.H{
			"error":         "Invalid verification code.",
			"attempts_left": left,
		}
	}
	_ = h.OTPs.ClearRecord(ctx, phone)
	return true, rec.Mode, http.StatusOK, nil
}

// POST /api/auth/otp/verify
// Mirrors percentage/api/auth/otp/verify/index.php.
func (h *AuthHandler) OTPVerify(c *gin.Context) {
	var req otpVerifyReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body."})
		return
	}

	phone := auth.NormalizePhone(req.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "A valid mobile number is required."})
		return
	}
	code := strings.TrimSpace(req.Code)
	if !auth.ValidateCodeFormat(code) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Verification code must be a 6-digit number."})
		return
	}

	ctx := c.Request.Context()

	ok, mode, status, body := h.consumeOTPCode(ctx, phone, code)
	if !ok {
		c.JSON(status, body)
		return
	}

	existingID, _ := h.Users.GetIDByPhone(ctx, phone)
	returning := existingID > 0

	uid, err := h.Users.InsertWithPhone(ctx, phone)
	if err != nil || uid <= 0 {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error",
			"error":  "Unable to resolve user account.",
		})
		return
	}

	role, _ := h.Users.GetRoleID(ctx, uid)
	account, _ := h.Users.GetAccountForClient(ctx, uid)
	session, err := h.Tokens.IssueToken(ctx, uid, c.Request.UserAgent(), auth.ClientIP(c.Request.RemoteAddr))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Unable to issue token."})
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
		"message":             "Verification code is valid.",
		"mode":                mode,
		"phone":               phone,
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

// POST /api/auth/logout — revokes the bearer token used on the request.
func (h *AuthHandler) Logout(c *gin.Context) {
	header := c.GetHeader("Authorization")
	parts := strings.Fields(header)
	if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		_ = h.Tokens.RevokeToken(c.Request.Context(), parts[1])
	}
	c.JSON(http.StatusOK, gin.H{"status": "success"})
}

// guestUsernameRE — 3-32 chars, letters/digits/underscore only. Deliberately
// simple (no i18n/unicode username support) so it stays easy to type and
// unambiguous to read back during support.
var guestUsernameRE = regexp.MustCompile(`^[A-Za-z0-9_]{3,32}$`)

// guestCredentialsReq is the body for both POST /api/auth/guest/register and
// POST /api/auth/guest/login.
type guestCredentialsReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// respondWithGuestSession issues a token for uid and writes the same response
// shape the phone/Google/OTP login endpoints use, so the Flutter client can
// treat a guest session identically to any other login response.
func (h *AuthHandler) respondWithGuestSession(c *gin.Context, uid int64, returning bool) {
	ctx := c.Request.Context()
	role, _ := h.Users.GetRoleID(ctx, uid)
	account, _ := h.Users.GetAccountForClient(ctx, uid)
	session, err := h.Tokens.IssueToken(ctx, uid, c.Request.UserAgent(), auth.ClientIP(c.Request.RemoteAddr))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to issue token."})
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
		"is_guest":            true,
		"account":             account,
		"session":             session,
		"access_token":        session.AccessToken,
		"token_type":          session.TokenType,
		"expires_at":          session.ExpiresAt,
		"expires_in":          session.ExpiresIn,
	})
}

// POST /api/auth/guest/register — Note #40. Body: {username, password}.
// Creates a new lightweight browsing account: no phone, no admin review
// (registration_status starts 'approved' so the client goes straight to
// Home), server-side restricted from City Directory/messaging/purchases
// until it's upgraded (see auth.RequireNotGuest / GuestUpgradeVerify below).
func (h *AuthHandler) GuestRegister(c *gin.Context) {
	var req guestCredentialsReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	username := strings.TrimSpace(req.Username)
	if !guestUsernameRE.MatchString(username) {
		c.JSON(http.StatusBadRequest, gin.H{
			"status": "error",
			"error":  "Username must be 3-32 characters: letters, numbers, underscore only.",
		})
		return
	}
	if len(req.Password) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Password must be at least 6 characters."})
		return
	}

	ctx := c.Request.Context()

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Failed to hash password."})
		return
	}
	uid, err := h.Users.InsertGuest(ctx, username, string(hash))
	if err != nil {
		if errors.Is(err, users.ErrUsernameTaken) {
			c.JSON(http.StatusConflict, gin.H{
				"status": "error",
				"error":  "That username is taken. Please choose another.",
				"code":   "username_taken",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to create guest account."})
		return
	}
	h.notifyStaffInBackground(notify.NewGuestAccountAdminMsg(username, uid))
	h.respondWithGuestSession(c, uid, false)
}

// POST /api/auth/guest/login — Note #40. Body: {username, password}. Only
// succeeds against a row with is_guest=true, so a full account's credentials
// can never authenticate through this endpoint (see users.GetByUsername).
// Every failure mode returns the same generic message so the endpoint can't
// be used to enumerate usernames — same convention as AdminLogin above.
func (h *AuthHandler) GuestLogin(c *gin.Context) {
	var req guestCredentialsReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	username := strings.TrimSpace(req.Username)
	password := req.Password
	if username == "" || password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Username and password are required."})
		return
	}

	ctx := c.Request.Context()

	lockID := "g:" + username
	if h.LoginLocks != nil {
		if locked, retryAfter := h.LoginLocks.Status(ctx, lockID); locked {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"status": "error", "error": "Too many failed attempts. Try again later.",
				"retry_after": retryAfter,
			})
			return
		}
	}

	id, hash, _, isGuest, err := h.Users.GetByUsername(ctx, username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Database error (lookup)."})
		return
	}
	if id == 0 || !isGuest || hash == "" || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		if h.LoginLocks != nil {
			if locked, retryAfter := h.LoginLocks.RegisterFailure(ctx, lockID); locked {
				c.JSON(http.StatusTooManyRequests, gin.H{
					"status": "error", "error": "Too many failed attempts. Try again later.",
					"retry_after": retryAfter,
				})
				return
			}
		}
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Invalid username or password."})
		return
	}
	if h.LoginLocks != nil {
		h.LoginLocks.Reset(ctx, lockID)
	}
	h.respondWithGuestSession(c, id, true)
}

// guestUpgradeVerifyReq is the body for POST /api/auth/guest/upgrade/verify.
type guestUpgradeVerifyReq struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

// POST /api/auth/guest/upgrade/verify — Note #40, "Account Upgrade and
// Conversion". Authed + auth.RequireGuest() only. The phone's OTP is sent via
// the EXISTING public POST /api/auth/otp/request (no change needed there —
// sending a code to a phone number needs no special guest handling); this
// endpoint only consumes that code and, on success, attaches the phone to the
// CURRENT guest's row (instead of OTPVerify's find-or-create-by-phone, which
// would create a second, disconnected account). is_guest flips to false and
// registration_status resets to 'incomplete', so the client's very next step
// is the exact same "complete your registration" form any new phone signup
// goes through — full_name/DOB/address/role via the existing
// POST /api/registration/submit.
func (h *AuthHandler) GuestUpgradeVerify(c *gin.Context) {
	tokenUser, ok := auth.UserFromGin(c)
	if !ok || tokenUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Unauthorized."})
		return
	}

	var req guestUpgradeVerifyReq
	if !bindFlexibleJSON(c, &req) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Invalid request body."})
		return
	}
	phone := auth.NormalizePhone(req.Phone)
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "A valid mobile number is required."})
		return
	}
	code := strings.TrimSpace(req.Code)
	if !auth.ValidateCodeFormat(code) {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "Verification code must be a 6-digit number."})
		return
	}

	ctx := c.Request.Context()

	ok2, _, status, body := h.consumeOTPCode(ctx, phone, code)
	if !ok2 {
		body["status"] = "error"
		c.JSON(status, body)
		return
	}

	if err := h.Users.UpgradeGuestPhone(ctx, tokenUser.UserID, phone); err != nil {
		switch {
		case errors.Is(err, users.ErrPhoneTaken):
			c.JSON(http.StatusConflict, gin.H{"status": "error", "error": "This phone number is already registered."})
		case errors.Is(err, users.ErrNotGuest):
			c.JSON(http.StatusForbidden, gin.H{"status": "error", "error": "This account is not a guest account."})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Unable to upgrade account."})
		}
		return
	}

	account, _ := h.Users.GetAccountForClient(ctx, tokenUser.UserID)
	c.JSON(http.StatusOK, gin.H{
		"status":              "success",
		"user_id":             tokenUser.UserID,
		"phone":               phone,
		"registration_status": "incomplete",
		"account":             account,
	})
}

// bindFlexibleJSON accepts either application/json or form-encoded bodies into v.
// Returns true on success (even for empty body — handler decides what's required).
func bindFlexibleJSON(c *gin.Context, v any) bool {
	ct := strings.ToLower(c.ContentType())
	if strings.Contains(ct, "application/json") {
		if err := c.ShouldBindJSON(v); err != nil {
			return false
		}
		return true
	}
	if err := c.ShouldBind(v); err != nil {
		return false
	}
	return true
}
