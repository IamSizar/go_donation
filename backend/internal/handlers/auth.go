package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

type AuthHandler struct {
	Tokens *auth.TokenStore
	OTPs   *auth.OTPStore
	Users  *users.Store
	// Phase 19 — OTPIQ delivery client. nil when OTPIQ_API_KEY is not set;
	// the handler then refuses real-mode OTP with a 502 (demo still works).
	OTPIQ  *auth.OTPIQClient
}

func NewAuthHandler(t *auth.TokenStore, o *auth.OTPStore, u *users.Store, otpiq *auth.OTPIQClient) *AuthHandler {
	return &AuthHandler{Tokens: t, OTPs: o, Users: u, OTPIQ: otpiq}
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
			provided := strings.TrimSpace(req.Password)
			if provided == "" {
				// Tell the client a password is required so the SPA can
				// re-prompt without having to guess.
				c.JSON(http.StatusUnauthorized, gin.H{
					"status":            "error",
					"error":             "Password required for this account.",
					"password_required": true,
				})
				return
			}
			if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(provided)); err != nil {
				c.JSON(http.StatusUnauthorized, gin.H{
					"status": "error",
					"error":  "Incorrect phone or password.",
				})
				return
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
}

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

	id, hash, isAdmin, err := h.Users.GetByUsername(ctx, username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "error", "error": "Database error (lookup)."})
		return
	}
	// Generic 401 for unknown user / no password set / wrong password — never
	// reveal which one failed.
	if id == 0 || hash == "" || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": "error", "error": "Invalid username or password."})
		return
	}
	if isAdmin != 1 {
		c.JSON(http.StatusForbidden, gin.H{"status": "error", "error": "Admin access required."})
		return
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

	rec, err := h.OTPs.GetRecord(ctx, phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error (otp lookup)."})
		return
	}
	if rec == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "No verification code found for this phone number."})
		return
	}
	if rec.Mode == "demo" && !auth.DemoEnabled() {
		_ = h.OTPs.ClearRecord(ctx, phone)
		c.JSON(http.StatusForbidden, gin.H{"error": "Demo OTP mode is disabled."})
		return
	}
	if time.Now().After(rec.ExpiresAt) {
		_ = h.OTPs.ClearRecord(ctx, phone)
		c.JSON(http.StatusGone, gin.H{"error": "Verification code has expired."})
		return
	}
	if rec.Attempts >= auth.OTPMaxAttempts {
		_ = h.OTPs.ClearRecord(ctx, phone)
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "Too many failed attempts. Request a new code."})
		return
	}
	if !auth.VerifyCode(rec.CodeHash, code) {
		newCount, _ := h.OTPs.IncAttempts(ctx, phone)
		left := auth.OTPMaxAttempts - newCount
		if left < 0 {
			left = 0
		}
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":         "Invalid verification code.",
			"attempts_left": left,
		})
		return
	}

	_ = h.OTPs.ClearRecord(ctx, phone)

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
		"mode":                rec.Mode,
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
