// auth_staff_otp.go — who may spend a DEMO OTP, and when demo exists at all.
//
// # WHY THIS FILE EXISTS
//
// The product decision is that phone + OTP is the ONLY way to sign in to the
// app: a user types a number, receives a code, and is in. Until OTPIQ_API_KEY
// is configured there is no SMS/WhatsApp gateway, so the interim is "demo"
// delivery — a fixed code from OTP_DEMO_CODE which /auth/otp/request returns in
// its own response body, because that echo is the only way the app learns it
// (the login screen shows no code; see the report in CLIENT_NOTES_CHECKLIST A16).
//
// That makes demo delivery a doorbell, not a lock. Whoever knows a phone number
// can sign in as its owner. The owner has accepted this for app users during
// the interim. Two things follow, and they are what this file implements:
//
//  1. Demo delivery must not outlive its excuse. It is available only while
//     there is no real gateway to use, so the day OTPIQ_API_KEY is set the whole
//     platform moves to real codes — including the already-shipped app, which
//     hard-codes `mode: "demo"` in its request and cannot be changed without a
//     store release. See demoDeliveryActive.
//
//  2. A doorbell must not be fitted to the dashboard. Staff accounts reach
//     /api/admin/* with the same token the app is issued (A15), so a demo code
//     that opens a super_admin is a full platform takeover for the price of a
//     phone number. Staff keep an OTP-shaped door, but the code that opens it is
//     one the server never prints: OTP_STAFF_DEMO_CODE, set by the owner and
//     shared with staff out of band. See staffDemoCodeFor / staffDemoVerifyRefused.
//
// Every refusal here carries a stable `code` for the clients to translate, is
// logged with the user id, tier and IP, and fails CLOSED — a lookup error is
// never read as "not staff".
package handlers

import (
	"crypto/subtle"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// demoDeliveryActive reports whether OTP codes should be served in demo mode.
//
// Demo is a FALLBACK, never a preference: it applies only while OTP_DEMO_ENABLED
// is on AND no OTPIQ client is configured. Deciding it server-side is what makes
// the switch to real OTP a pure environment change — the deployed app always
// asks for `mode: "demo"` (it was defaulted that way because real delivery 502s
// with no key), so leaving the choice to the caller would mean every user kept
// receiving demo codes long after OTPIQ_API_KEY was set.
func demoDeliveryActive(otpiq *auth.OTPIQClient) bool {
	return otpiq == nil && auth.DemoEnabled()
}

// staffPhoneCheck resolves whether phone belongs to a dashboard-capable account.
// Writes the 500 itself and reports refused=true when the lookup fails, because
// "we could not tell" must never be read as "not staff".
func (h *AuthHandler) staffPhoneCheck(c *gin.Context, phone, stage string) (uid int64, tier string, isStaff, refused bool) {
	ip := auth.ClientIP(c.Request.RemoteAddr)
	uid, tier, err := h.Users.StaffTierByPhone(c.Request.Context(), phone)
	if err != nil {
		log.Printf("[authn] %s: staff lookup failed for phone_hint=%s ip=%s: %v",
			stage, maskPhone(phone), ip, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"status": "error", "error": "Could not verify this number.", "code": "server_error",
		})
		return 0, "", false, true
	}
	if uid == 0 || !permissions.CanAccessDashboard(permissions.TierFrom(tier)) {
		return uid, tier, false, false
	}
	return uid, tier, true, false
}

// staffDemoCodeFor picks the demo code to store for phone and says whether the
// response may echo it back.
//
//	ordinary account → the public OTP_DEMO_CODE, echoed (this is the app's only
//	                   source for it, so suppressing the echo would end sign-in
//	                   for every user on the platform)
//	staff account    → OTP_STAFF_DEMO_CODE, never echoed
//	staff, none set  → refused 403 staff_otp_unavailable, nothing stored
//
// Returns refused=true once it has written the response; the caller only has to
// return.
func (h *AuthHandler) staffDemoCodeFor(c *gin.Context, phone, stage string) (code string, echo, refused bool) {
	uid, tier, isStaff, refused := h.staffPhoneCheck(c, phone, stage)
	if refused {
		return "", false, true
	}
	if !isStaff {
		return auth.DemoCode(), true, false
	}

	staffCode := auth.StaffDemoCode()
	if staffCode == "" {
		// Fail closed. This is the state production is in right now, and it is
		// why staff ids 1 and 34 cannot sign in: they hold no password and no
		// real OTP gateway exists. One environment variable reopens the door
		// without a deploy — see the A16 notes in CLIENT_NOTES_CHECKLIST.md.
		log.Printf("[authn] %s refused: staff account needs OTP_STAFF_DEMO_CODE user_id=%d staff_tier=%q ip=%s",
			stage, uid, tier, auth.ClientIP(c.Request.RemoteAddr))
		c.JSON(http.StatusForbidden, gin.H{
			"status": "error",
			"error":  "Staff sign-in is not available yet. Ask the administrator for your code.",
			"code":   "staff_otp_unavailable",
		})
		return "", false, true
	}

	log.Printf("[authn] %s: staff demo code issued (not echoed) user_id=%d staff_tier=%q ip=%s",
		stage, uid, tier, auth.ClientIP(c.Request.RemoteAddr))
	return staffCode, false, false
}

// staffDemoVerifyRefused is the verify-side half of the same rule: a DEMO-mode
// record standing against a staff phone may only be spent by the staff code.
//
// The stored record is a bcrypt hash, so it cannot say which code created it.
// Comparing the SUBMITTED code against OTP_STAFF_DEMO_CODE settles it without
// needing to know: a record written with the public demo code — by the version
// of this handler that shipped before the rule, or by the dashboard's own demo
// paths — can never be spent, because the only code that gets past this gate is
// one that would not match its hash anyway.
//
// A wrong code here answers EXACTLY as consumeOTPCode answers any wrong code,
// down to the attempt counter, so the response tells an outsider nothing about
// whether the number belongs to staff. Returns true once it has written the
// refusal.
func (h *AuthHandler) staffDemoVerifyRefused(c *gin.Context, phone, submitted string, rec *auth.OTPRecord) bool {
	const stage = "otp verify"
	uid, tier, isStaff, refused := h.staffPhoneCheck(c, phone, stage)
	if refused {
		return true
	}
	if !isStaff {
		return false
	}

	ctx := c.Request.Context()
	ip := auth.ClientIP(c.Request.RemoteAddr)

	staffCode := auth.StaffDemoCode()
	if staffCode == "" {
		log.Printf("[authn] %s refused: staff account needs OTP_STAFF_DEMO_CODE user_id=%d staff_tier=%q ip=%s",
			stage, uid, tier, ip)
		c.JSON(http.StatusForbidden, gin.H{
			"status": "error",
			"error":  "Staff sign-in is not available yet. Ask the administrator for your code.",
			"code":   "staff_otp_unavailable",
		})
		return true
	}

	if subtle.ConstantTimeCompare([]byte(submitted), []byte(staffCode)) == 1 {
		return false // consumeOTPCode does the real work from here.
	}

	// Wrong code. Spend an attempt so guessing stays bounded (five per code,
	// and the per-phone lock in otp_lock.go caps how fast fresh codes arrive),
	// then mirror consumeOTPCode's refusal exactly.
	if rec != nil && rec.Attempts >= auth.OTPMaxAttempts {
		_ = h.OTPs.ClearRecord(ctx, phone)
		log.Printf("[authn] %s refused: staff code attempts exhausted user_id=%d staff_tier=%q ip=%s",
			stage, uid, tier, ip)
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error": "Too many failed attempts. Request a new code.",
			"code":  "otp_attempts_exhausted",
		})
		return true
	}
	newCount, _ := h.OTPs.IncAttempts(ctx, phone)
	left := auth.OTPMaxAttempts - newCount
	if left < 0 {
		left = 0
	}
	log.Printf("[authn] %s refused: wrong staff code user_id=%d staff_tier=%q attempts_left=%d ip=%s",
		stage, uid, tier, left, ip)
	c.JSON(http.StatusUnauthorized, gin.H{
		"error":         "Invalid verification code.",
		"attempts_left": left,
		"code":          "invalid_otp",
	})
	return true
}
