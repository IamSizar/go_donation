// admin_main_admin_guard.go — the two-channel confirmation that protects the
// main-admin account (H20).
//
// # WHAT THE CLIENT ASKED FOR
//
// "حماية حساب المدير الأساسي: كلمة سر + بروتوكول حماية إضافي؛ التغيير فقط عبر
// رمز تأكيد يُرسل عبر الهاتف والبريد الإلكتروني معاً" — a change to the main
// admin's account only via a confirmation code sent through BOTH phone and
// email.
//
// # WHAT ALREADY EXISTED, AND WHY IT WAS NOT THIS
//
// admin_user_guard.go answers authorisation: the H13 tier floor (never write to
// an account that outranks you) and the credential rule (a staff sign-in number
// is the Super-Admin's to move). Both are about the CALLER'S RANK. Neither asks
// whether the person whose account is being rewritten knows it is happening —
// and production holds three super_admin accounts that may each write to the
// others, so rank alone leaves a peer takeover wide open. This file adds the
// missing half and is layered directly after that guard, on the same call
// sites; it is not a parallel path.
//
// # THE DECISION THIS FILE IS BUILT AROUND: FAIL CLOSED
//
// SMTP_* is empty in every environment the team can reach, and so is
// OTPIQ_API_KEY. A confirmation that cannot be delivered on both channels
// therefore has to mean something, and there were only two honest options:
//
//	(1) FAIL CLOSED — refuse the change and say which channel is missing.
//	(2) Proceed on the phone alone and record a warning.
//
// This file does (1), for three reasons:
//
//   - The client's word is "معاً" — together. A confirmation that half
//     happened is not the confirmation that was asked for, and shipping it as
//     one would put a protection on the checklist that does not exist in the
//     product.
//   - Nothing is stranded by refusing. The gate covers FOUR fields on ONE tier:
//     a super_admin's phone, email, password and staff_tier. Every other
//     account on the platform, every other field on a super_admin's own row,
//     the whole permissions screen, and every containment action below stay
//     exactly as they are. A Super-Admin who meets this refusal has lost no
//     ability they need today; they have found a setting they have not made yet,
//     and the refusal names the missing environment variable.
//   - Option (2) is the failure mode the owner explicitly ruled out: a success
//     message for an email that never left.
//
// # WHAT IS DELIBERATELY *NOT* GATED, AND WHY THAT IS NOT A LOOPHOLE
//
// Suspend, ban, archive and force-logout are NOT behind this code, and must not
// be. Those are the containment actions — the ones used when a main-admin
// account is believed to be COMPROMISED. Requiring a code delivered to that
// account's own phone and email before it can be locked out would hand the
// attacker, who holds exactly those channels, a veto over their own removal.
// The gate belongs on the paths that let someone TAKE the account, not on the
// paths that take it out of service.
//
// Deletion is likewise ungated: it is already Super-Admin-only, already
// PIN-gated, already reversible through the Trash, and destroying an account
// grants the destroyer nothing — it is not a takeover.
//
// # DEMO DELIVERY IS REFUSED, ON PURPOSE
//
// The rest of this system falls back to demo OTP when OTPIQ is unset, and demo
// mode returns the code to the CALLER in the response body. That is a fallback
// this gate cannot accept: handing the confirmation code to the very person
// making the change turns the whole protection into a formality that still
// renders a padlock. Both channels here must be real, or the change is refused.
package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// The four changes that can hand someone the main-admin account. Kept as
// constants because the value is written into admin_change_confirmations and a
// challenge raised for one kind must never be spendable on another.
const (
	changeKindPhone     = "phone"
	changeKindEmail     = "email"
	changeKindPassword  = "password"
	changeKindStaffTier = "staff_tier"
)

// statusConfirmationRequired is 428 Precondition Required (RFC 6585).
//
// Chosen over the 403 the sibling guard uses because the two answers mean
// opposite things and the dashboard must not blur them: 403 is "you may not do
// this, ever, as you"; 428 is "do the missing step and come back". It also
// cannot be mistaken for success by any client that only checks 2xx, which a
// 200-with-a-status-field (the shape the admin LOGIN 2FA step uses) can be.
const statusConfirmationRequired = 428

// MainAdminConfirm issues and verifies the two-channel confirmation.
//
// Both senders may be nil — that is the ordinary state of this system — and a
// nil sender is what makes the gate refuse rather than degrade. Construct with
// NewMainAdminConfirm and wire it in main.go next to the other optional
// collaborators.
type MainAdminConfirm struct {
	Pool  *pgxpool.Pool
	OTPIQ *auth.OTPIQClient // nil when OTPIQ_API_KEY is unset
	Mail  *auth.Mailer      // nil when SMTP_* is unset
}

func NewMainAdminConfirm(pool *pgxpool.Pool, otpiq *auth.OTPIQClient, mailer *auth.Mailer) *MainAdminConfirm {
	return &MainAdminConfirm{Pool: pool, OTPIQ: otpiq, Mail: mailer}
}

// mainAdminContact is the target account's two delivery channels.
type mainAdminContact struct {
	tier  string
	phone string
	email string
}

// loadMainAdminContact reads the target's tier and both channels in one query.
// Returns pgx.ErrNoRows for a missing user so the caller can let the handler
// answer its own 404.
//
// A package-level function taking an explicit pool, not a method, because it is
// called before the guard is known to exist — see mainAdminChange.Pool.
func loadMainAdminContact(ctx context.Context, pool *pgxpool.Pool, userID int64) (mainAdminContact, error) {
	var tier, phone, email *string
	err := pool.QueryRow(ctx,
		`SELECT staff_tier, phone, email FROM users WHERE id = $1`, userID,
	).Scan(&tier, &phone, &email)
	if err != nil {
		return mainAdminContact{}, err
	}
	out := mainAdminContact{}
	if tier != nil {
		out.tier = *tier
	}
	if phone != nil {
		out.phone = strings.TrimSpace(*phone)
	}
	if email != nil {
		out.email = strings.TrimSpace(*email)
	}
	return out, nil
}

// mainAdminChange describes one attempted write, and carries the CALLING
// handler's own pool.
//
// Pool is on the request rather than read off the guard for one reason, and it
// is a security reason: the question "is this target the protected account?"
// has to be answerable even when the guard itself was never wired. Asking it
// with the guard's pool would mean a nil guard could not tell a super_admin
// from a beneficiary, and the only safe answer would be to refuse EVERY user
// write — turning a missing line in main.go into an outage of the whole
// المستخدمون screen instead of a refusal on four fields.
type mainAdminChange struct {
	Pool   *pgxpool.Pool // the caller's pool; always present
	Target int64
	Kind   string // one of the changeKind* constants
	Code   string // the confirmation code, empty on the first attempt
}

// required is the whole gate, and returns true when the caller must be
// STOPPED — the response has already been written, exactly like guardUserWrite,
// so a handler reads as:
//
//	if guardUserWrite(c, pool, id, changingPhone) { return }
//	if h.MainAdmin.required(c, mainAdminChange{h.Pool, id, changeKindPhone, req.ConfirmationCode}) { return }
//
// It is a no-op (returns false) for every target that is not a super_admin, so
// the ordinary users screen is untouched.
//
// A nil receiver — the guard was never wired — refuses, but ONLY once the
// target has been identified as the protected account. That is the same
// failure-safe direction the H10 contact masking chose (a handler nobody wired
// masks rather than leaks), narrowed to the rows it is about.
func (g *MainAdminConfirm) required(c *gin.Context, ch mainAdminChange) bool {
	ctx := c.Request.Context()

	target, err := loadMainAdminContact(ctx, ch.Pool, ch.Target)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return false // no such user — the handler answers its own 404.
	case err != nil:
		log.Printf("[security] H20: could not load target %d for confirmation: %v", ch.Target, err)
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not verify this account. Please try again.", ch.Target)
		return true
	}
	// Only the main admin is protected by this gate.
	if permissions.TierFrom(target.tier) != permissions.TierSuperAdmin {
		return false
	}

	if g == nil || g.Pool == nil {
		log.Printf("[security] H20: refused %s change to main admin %d — the confirmation guard is not wired",
			ch.Kind, ch.Target)
		denyUserWrite(c, http.StatusServiceUnavailable, "main_admin_confirmation_unavailable",
			"Main-admin confirmation is not available on this server.", ch.Target)
		return true
	}

	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		denyUserWrite(c, http.StatusUnauthorized, "auth_required", "Not authenticated.", ch.Target)
		return true
	}

	if strings.TrimSpace(ch.Code) == "" {
		return g.issueChallenge(c, actor.UserID, ch.Target, ch.Kind, target)
	}
	return g.verifyChallenge(c, actor.UserID, ch.Target, ch.Kind, strings.TrimSpace(ch.Code))
}

// ─── Issuing ────────────────────────────────────────────────────────────

// issueChallenge sends one code to both channels and stores its hash, or
// refuses with the precise reason it could not. Always returns true: even the
// success path stops the request, because the change itself only happens on the
// SECOND call, the one carrying the code.
//
// Order matters and is deliberate. Every precondition is checked BEFORE
// anything is sent, and the email goes FIRST: if the email cannot leave, no SMS
// is sent either. Sending half a two-channel confirmation would spend the
// owner's SMS credit, put a live code in a stranger's hand, and teach the
// target to expect codes that mean nothing.
func (g *MainAdminConfirm) issueChallenge(
	c *gin.Context, actorID, targetID int64, kind string, target mainAdminContact,
) bool {
	ctx := c.Request.Context()

	// ── Preconditions: both channels must exist and both must be real ──
	if target.email == "" {
		denyUserWrite(c, http.StatusPreconditionFailed, "main_admin_email_missing",
			"This account has no email address on file, so the two-channel confirmation cannot be sent.", targetID)
		return true
	}
	if target.phone == "" {
		denyUserWrite(c, http.StatusPreconditionFailed, "main_admin_phone_missing",
			"This account has no phone number on file, so the two-channel confirmation cannot be sent.", targetID)
		return true
	}
	if !g.Mail.Configured() {
		// The single most likely refusal in production today, and the one the
		// owner needs named precisely: nothing is broken, an environment
		// variable is unset.
		log.Printf("[security] H20: refused %s change to main admin %d — no email channel (SMTP_HOST unset)",
			kind, targetID)
		denyUserWrite(c, http.StatusServiceUnavailable, "main_admin_email_unavailable",
			"Email delivery is not configured on the server (SMTP_HOST), so the confirmation cannot be sent to both channels.", targetID)
		return true
	}
	if g.OTPIQ == nil {
		// Demo OTP delivery is NOT accepted here — see the file header.
		log.Printf("[security] H20: refused %s change to main admin %d — no real SMS channel (OTPIQ_API_KEY unset)",
			kind, targetID)
		denyUserWrite(c, http.StatusServiceUnavailable, "main_admin_sms_unavailable",
			"SMS delivery is not configured on the server (OTPIQ_API_KEY), so the confirmation cannot be sent to both channels.", targetID)
		return true
	}

	code, err := auth.GenerateCode()
	if err != nil {
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not generate a confirmation code.", targetID)
		return true
	}

	// ── Email first. A failure here stops everything. ──
	if err := g.Mail.Send(ctx, target.email,
		"رمز تأكيد تغيير حساب المدير الأساسي",
		mainAdminEmailBody(code, kind)); err != nil {
		// The recipient is masked and the code never appears — this line is
		// safe to keep in a shared log.
		log.Printf("[security] H20: email send failed for main admin %d (%s): %v",
			targetID, auth.MaskEmail(target.email), err)
		denyUserWrite(c, http.StatusBadGateway, "main_admin_email_send_failed",
			"The confirmation email could not be sent, so the change was not applied.", targetID)
		return true
	}

	// ── Then the phone. ──
	if _, err := g.OTPIQ.SendVerification(ctx, target.phone, code); err != nil {
		log.Printf("[security] H20: SMS send failed for main admin %d (%s): %v",
			targetID, maskPhone(target.phone), err)
		denyUserWrite(c, http.StatusBadGateway, "main_admin_sms_send_failed",
			"The confirmation SMS could not be sent, so the change was not applied.", targetID)
		return true
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not store the confirmation code.", targetID)
		return true
	}
	now := time.Now().UTC()
	// Any older live challenge for the same (target, kind, actor) is voided, so
	// asking again always replaces rather than accumulates — otherwise a stale
	// code from an abandoned attempt would stay spendable for its full TTL.
	if _, err := g.Pool.Exec(ctx,
		`UPDATE admin_change_confirmations SET consumed_at = $1
		  WHERE target_user_id = $2 AND change_kind = $3 AND actor_user_id = $4
		    AND consumed_at IS NULL`,
		now, targetID, kind, actorID); err != nil {
		log.Printf("[security] H20: could not void previous challenges for %d/%s: %v", targetID, kind, err)
	}
	if _, err := g.Pool.Exec(ctx,
		`INSERT INTO admin_change_confirmations
		   (target_user_id, actor_user_id, change_kind, code_hash,
		    phone_sent_at, email_sent_at, created_at, expires_at)
		 VALUES ($1, $2, $3, $4, $5, $5, $5, $6)`,
		targetID, actorID, kind, string(hash), now, now.Add(auth.OTPTTL)); err != nil {
		log.Printf("[security] H20: could not store confirmation for %d/%s: %v", targetID, kind, err)
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not store the confirmation code.", targetID)
		return true
	}

	log.Printf("[security] H20: confirmation issued for main admin %d (%s) by actor %d — phone=%s email=%s",
		targetID, kind, actorID, maskPhone(target.phone), auth.MaskEmail(target.email))
	c.JSON(statusConfirmationRequired, gin.H{
		"success":     false,
		"code":        "main_admin_confirmation_required",
		"error":       "A confirmation code has been sent to this account's phone and email. Re-send the change with the code to apply it.",
		"change_kind": kind,
		"phone_hint":  maskPhone(target.phone),
		"email_hint":  auth.MaskEmail(target.email),
		"expires_in":  int(auth.OTPTTL.Seconds()),
	})
	return true
}

// mainAdminEmailBody is the message the account owner receives. It names the
// kind of change so a code arriving out of the blue is actionable ("nobody
// should be moving my tier") rather than merely alarming.
func mainAdminEmailBody(code, kind string) string {
	return "رمز تأكيد تغيير على حساب المدير الأساسي.\n\n" +
		"نوع التغيير: " + mainAdminKindArabic(kind) + "\n" +
		"رمز التأكيد: " + code + "\n\n" +
		"صلاحية الرمز خمس دقائق. إذا لم تطلب هذا التغيير فتجاهل هذه الرسالة وغيّر كلمة المرور فوراً."
}

// mainAdminKindArabic renders a change kind in the operator's language. The
// email is the one surface in this feature that no dashboard translation layer
// touches, so the Arabic lives here.
func mainAdminKindArabic(kind string) string {
	switch kind {
	case changeKindPhone:
		return "تغيير رقم الهاتف"
	case changeKindEmail:
		return "تغيير البريد الإلكتروني"
	case changeKindPassword:
		return "تغيير كلمة المرور"
	case changeKindStaffTier:
		return "تغيير مستوى الصلاحية"
	default:
		return kind
	}
}

// ─── Verifying ──────────────────────────────────────────────────────────

// verifyChallenge consumes the code supplied with the second request. Returns
// true (stop) on any failure, false (proceed) only when a live challenge for
// exactly this target, kind and actor matched.
func (g *MainAdminConfirm) verifyChallenge(
	c *gin.Context, actorID, targetID int64, kind, code string,
) bool {
	ctx := c.Request.Context()
	if !auth.ValidateCodeFormat(code) {
		denyUserWrite(c, http.StatusUnauthorized, "main_admin_confirmation_invalid",
			"The confirmation code must be a 6-digit number.", targetID)
		return true
	}

	var id int64
	var hash string
	var attempts int
	var expiresAt time.Time
	err := g.Pool.QueryRow(ctx,
		`SELECT id, code_hash, attempts, expires_at
		   FROM admin_change_confirmations
		  WHERE target_user_id = $1 AND change_kind = $2 AND actor_user_id = $3
		    AND consumed_at IS NULL
		  ORDER BY id DESC LIMIT 1`,
		targetID, kind, actorID,
	).Scan(&id, &hash, &attempts, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		denyUserWrite(c, http.StatusUnauthorized, "main_admin_confirmation_missing",
			"No confirmation is pending for this change — start it again to receive a new code.", targetID)
		return true
	}
	if err != nil {
		log.Printf("[security] H20: confirmation lookup failed for %d/%s: %v", targetID, kind, err)
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not verify the confirmation code.", targetID)
		return true
	}
	if time.Now().UTC().After(expiresAt) {
		g.voidChallenge(ctx, id)
		denyUserWrite(c, http.StatusUnauthorized, "main_admin_confirmation_expired",
			"The confirmation code has expired — start the change again to receive a new one.", targetID)
		return true
	}
	// Same guess budget as every other code in this system (auth.OTPMaxAttempts),
	// after which the challenge is dead and a fresh one — meaning two fresh
	// out-of-band messages to the account owner — is required.
	if attempts >= auth.OTPMaxAttempts {
		g.voidChallenge(ctx, id)
		denyUserWrite(c, http.StatusUnauthorized, "main_admin_confirmation_attempts",
			"Too many incorrect codes — start the change again to receive a new one.", targetID)
		return true
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(code)) != nil {
		if _, err := g.Pool.Exec(ctx,
			`UPDATE admin_change_confirmations SET attempts = attempts + 1 WHERE id = $1`, id); err != nil {
			log.Printf("[security] H20: could not record failed attempt on confirmation %d: %v", id, err)
		}
		log.Printf("[security] H20: wrong confirmation code for main admin %d (%s) by actor %d",
			targetID, kind, actorID)
		denyUserWrite(c, http.StatusUnauthorized, "main_admin_confirmation_invalid",
			"Incorrect confirmation code.", targetID)
		return true
	}

	// Single use: spent before the change is applied, so a retry of the same
	// request cannot replay the same code against a second change.
	if _, err := g.Pool.Exec(ctx,
		`UPDATE admin_change_confirmations SET consumed_at = $1 WHERE id = $2`,
		time.Now().UTC(), id); err != nil {
		log.Printf("[security] H20: could not consume confirmation %d: %v", id, err)
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not complete the confirmation.", targetID)
		return true
	}
	log.Printf("[security] H20: confirmation accepted for main admin %d (%s) by actor %d",
		targetID, kind, actorID)
	return false
}

// voidChallenge marks a challenge unusable without deleting it — the row stays
// as evidence that a confirmation was raised and how it ended.
func (g *MainAdminConfirm) voidChallenge(ctx context.Context, id int64) {
	if _, err := g.Pool.Exec(ctx,
		`UPDATE admin_change_confirmations SET consumed_at = $1 WHERE id = $2`,
		time.Now().UTC(), id); err != nil {
		log.Printf("[security] H20: could not void confirmation %d: %v", id, err)
	}
}
