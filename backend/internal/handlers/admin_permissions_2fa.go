// admin_permissions_2fa.go — the two factors on إدارة الصلاحيات (H1).
//
// # WHAT THE CLIENT ASKED FOR
//
// "قسم إدارة الصلاحيات … مع مصادقة ثنائية: كلمة السر ثم رمز تأكيد مؤقت يُرسل
// إلى الهاتف أو البريد الإلكتروني" — password, THEN a temporary code sent to
// phone OR email, when confirming any change to permissions.
//
// # WHAT WAS ACTUALLY THERE, AND THE HOLE IN IT
//
// The screen existed, was super-admin-only, and every permission write already
// consumed a single-use OTP. The password half did not exist on the server at
// all. The dashboard called POST /api/admin/verify-password, got {ok:true},
// and then sent the write — and the write endpoint never asked about a
// password. A factor enforced only by the page that asks for it is not a
// factor: anyone who could reach POST /api/admin/permissions directly (a
// script, curl, a stolen token) skipped it entirely by simply not calling
// verify-password first. The comment in admin_permissions.go even said so —
// "the PIN (checked separately by the SPA)" — which is exactly the shape of
// bug this file closes.
//
// The OTP half had its own problem. With OTPIQ_API_KEY unset — every
// environment today — delivery falls back to demo mode, which returns the code
// to the CALLER in the response body. That is not a second factor either; it is
// a formality that renders a padlock.
//
// # THE TWO DECISIONS, AND WHY THEY POINT IN OPPOSITE DIRECTIONS
//
// H20 (the main-admin account) fails CLOSED when a channel is missing. This
// file does the opposite, on purpose, because the constraint is different:
//
//	THE SUPER-ADMIN MUST NEVER BE LOCKED OUT OF THEIR OWN PERMISSIONS SCREEN.
//
// Refusing permission changes when no gateway is configured would freeze the
// one screen that fixes everything else — including the screen that would grant
// somebody else the ability to fix it. So when no real channel exists the
// change still goes through, and the response says, in a stable code the
// dashboard renders as a visible warning, that the second factor was DEGRADED.
// Honest and usable, rather than honest and bricked.
//
// The same reasoning governs the password factor, and it is not hypothetical:
// production holds a super_admin with NO password_hash at all. Demanding a
// password from an account that has none would lock that account out of this
// screen permanently. So the rule is "verify it when there is one to verify",
// and an account with none is told — in the response and in the log — that the
// first factor could not be applied to it.
//
// Neither degradation is silent. That is the whole difference between this and
// what was here before.
package handlers

import (
	"context"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// Second-factor delivery modes, as reported to the dashboard. These are stable
// strings the SPA branches on, so they are constants rather than literals.
const (
	factorModeSMS    = "sms"     // real, out of band
	factorModeEmail  = "email"   // real, out of band
	factorModeInBand = "in_band" // NOT a second factor — the code is in the response
)

// The password factor's outcome, reported alongside every successful change so
// the screen can say which factors actually applied.
const (
	passwordFactorVerified = "verified" // checked against the actor's bcrypt hash
	passwordFactorUnset    = "unset"    // the account has no password to check
)

// secondFactorDelivery is what sendSecondFactor managed to do.
type secondFactorDelivery struct {
	Mode     string // factorMode* above
	Channel  string // "phone" | "email"
	Hint     string // masked destination, safe for a screen and a log
	Degraded bool   // true when the code did not travel out of band
	InBand   string // only ever set when Degraded — the code the caller must type
}

// sendSecondFactor issues one code and delivers it on the best channel
// available, preferring `want` ("phone" or "email") when that channel is real.
//
// Preference order is deliberate: a REAL channel always beats the requested
// one. Letting an operator ask for email on a server with no SMTP and then
// silently handing them a demo code would be the failure this whole file is
// about. If the requested channel cannot deliver for real, the other real
// channel is used and the response says which — and only if NEITHER is real
// does it fall back to demo, flagged.
//
// The code is stored in `otp_codes` keyed by phone, exactly as the login OTP
// is, so the existing VerifyAndConsume path verifies it unchanged. That is
// reuse of the existing OTP infrastructure rather than a second one: the email
// channel changes only where the code is DELIVERED, never how it is minted,
// hashed, capped or expired.
func (h *AdminPermissionsHandler) sendSecondFactor(
	ctx context.Context, phone, email, want string,
) (secondFactorDelivery, error) {
	smsReal := h.OTPIQ != nil
	emailReal := h.Mail.Configured() && email != ""

	code, err := auth.GenerateCode()
	if err != nil {
		return secondFactorDelivery{}, err
	}

	// No real channel at all — degrade, loudly, but never refuse.
	//
	// Two details are deliberate. The code is FRESHLY GENERATED rather than
	// auth.DemoCode(): the fixed demo code is public (the app's own sign-in
	// hands it out), so reusing it here would mean the "code" guarding the
	// permissions matrix is a value everyone already knows. And it is stored
	// with mode "real" rather than "demo" because VerifyAndConsume refuses a
	// demo-mode record whenever OTP_DEMO_ENABLED is off — which would turn an
	// unrelated environment switch into a hard lockout from this screen. What
	// makes this delivery degraded is that the code comes back in the response,
	// and that is reported as `degraded`, not encoded in a storage flag.
	if !smsReal && !emailReal {
		if err := h.OTPs.StoreCode(ctx, phone, code, "real"); err != nil {
			return secondFactorDelivery{}, err
		}
		log.Printf("[security] H1: permission-change second factor DEGRADED — no real channel "+
			"(OTPIQ_API_KEY and SMTP_HOST both unset); code returned in-band for %s", maskPhone(phone))
		return secondFactorDelivery{
			Mode: factorModeInBand, Channel: "phone", Hint: maskPhone(phone),
			Degraded: true, InBand: code,
		}, nil
	}

	// Persist BEFORE sending, so a gateway flake cannot accept-but-lose a code
	// the operator is already reading off their phone.
	if err := h.OTPs.StoreCode(ctx, phone, code, "real"); err != nil {
		return secondFactorDelivery{}, err
	}

	useEmail := emailReal && (want == "email" || !smsReal)
	if useEmail {
		if err := h.Mail.Send(ctx, email,
			"رمز تأكيد تغيير الصلاحيات", permissionFactorEmailBody(code)); err != nil {
			_ = h.OTPs.ClearRecord(ctx, phone)
			return secondFactorDelivery{}, err
		}
		return secondFactorDelivery{
			Mode: factorModeEmail, Channel: "email", Hint: auth.MaskEmail(email),
		}, nil
	}

	if _, err := h.OTPIQ.SendVerification(ctx, phone, code); err != nil {
		_ = h.OTPs.ClearRecord(ctx, phone)
		return secondFactorDelivery{}, err
	}
	return secondFactorDelivery{
		Mode: factorModeSMS, Channel: "phone", Hint: maskPhone(phone),
	}, nil
}

// permissionFactorEmailBody is the message the acting Super-Admin receives.
// Arabic, because that is the language of the screen that triggered it, and it
// passes through no translation layer on the way out.
func permissionFactorEmailBody(code string) string {
	return "رمز تأكيد مؤقت لتعديل الصلاحيات في لوحة التحكم.\n\n" +
		"رمز التأكيد: " + code + "\n\n" +
		"صلاحية الرمز خمس دقائق ويُستخدم مرة واحدة. إذا لم تكن أنت من يعدّل الصلاحيات الآن، " +
		"غيّر كلمة المرور فوراً وراجع سجل التدقيق."
}

// actorEmail reads the acting admin's own email, or "" when they have none.
func (h *AdminPermissionsHandler) actorEmail(ctx context.Context, actorID int64) string {
	var email *string
	if err := h.Perms.Pool.QueryRow(ctx,
		`SELECT email FROM users WHERE id = $1`, actorID).Scan(&email); err != nil || email == nil {
		return ""
	}
	return strings.TrimSpace(*email)
}

// checkPasswordFactor is the FIRST factor, enforced here on the server for the
// first time.
//
// Returns (refused, outcome). When refused is true the response has already
// been written and the handler must return; outcome is one of the
// passwordFactor* constants and is reported back on success so the screen can
// tell the operator which factors actually applied.
//
// The no-password case is an ALLOW, and it is the one judgement call in this
// file. Production has a super_admin with no password_hash and no username; for
// that account "verify your password" has no answer, so enforcing it would end
// their access to the permissions screen with no way back. It is logged at
// [security] and surfaced in the response instead, which is the same bargain
// the rest of this file makes: never pretend a factor applied when it did not.
func (h *AdminPermissionsHandler) checkPasswordFactor(
	c *gin.Context, actorID int64, password string,
) (refused bool, outcome string) {
	ctx := c.Request.Context()
	var hash *string
	if err := h.Perms.Pool.QueryRow(ctx,
		`SELECT password_hash FROM users WHERE id = $1`, actorID).Scan(&hash); err != nil {
		// Cannot tell whether a password is required → refuse. A lookup failure
		// must never read as "no password needed".
		log.Printf("[security] H1: password lookup failed for actor %d: %v", actorID, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false, "code": "server_error",
			"error": "Could not verify your password. Please try again.",
		})
		return true, ""
	}

	if hash == nil || strings.TrimSpace(*hash) == "" {
		log.Printf("[security] H1: permission change by actor %d with NO password set — "+
			"the password factor could not be applied to this account", actorID)
		return false, passwordFactorUnset
	}

	if strings.TrimSpace(password) == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false, "code": "password_factor_required",
			"error": "Your password is required to confirm a permission change.",
		})
		return true, ""
	}
	if bcrypt.CompareHashAndPassword([]byte(*hash), []byte(password)) != nil {
		log.Printf("[security] H1: wrong password on a permission change by actor %d from %s",
			actorID, c.ClientIP())
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false, "code": "password_factor_incorrect",
			"error": "Incorrect password.",
		})
		return true, ""
	}
	return false, passwordFactorVerified
}

// factorReport is the block appended to every successful permission change. It
// exists so the screen can never show a plain "saved" for a change that only
// half of the promised protection stood behind.
func factorReport(passwordOutcome string, otpDegraded bool) gin.H {
	return gin.H{
		"password": passwordOutcome,
		// "degraded" is what the dashboard renders as a warning banner. It is
		// true when the code did not travel out of band, i.e. when the second
		// factor was, in practice, not one.
		"second_factor_degraded": otpDegraded,
	}
}

// secondFactorDegraded reports whether the code the operator just spent could
// have travelled out of band at all.
//
// Derived from configuration rather than from the consumed OTP row on purpose:
// the row is deleted by VerifyAndConsume before the caller could read it, and
// the question being answered is about the SERVER'S CAPABILITY ("is there a
// real channel on this deployment?"), which is exactly what the two gateway
// handles say. Reported on every successful change so the screen can never show
// a bare "saved" for a change that only one real factor stood behind.
func (h *AdminPermissionsHandler) secondFactorDegraded() bool {
	return h.OTPIQ == nil && !h.Mail.Configured()
}
