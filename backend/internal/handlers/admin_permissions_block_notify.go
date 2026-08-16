// admin_permissions_block_notify.go — getting the unlock code to the person who
// was just frozen out of إدارة الصلاحيات (H14).
//
// # WHY THIS IS A SEPARATE FILE FROM THE BLOCK ITSELF
//
// admin_permissions_block.go decides WHETHER to freeze; this file decides
// whether anything can be delivered and says so truthfully. They were one file
// in the first draft and it was already past the size where the two questions
// blur together — and blurring them is how "we tried to send" quietly becomes
// "we sent". Same split, and the same reason, as admin_status.go /
// admin_status_notify.go.
//
// # THE ONE RULE
//
//	NOTHING IN THIS FILE REPORTS A MESSAGE THAT DID NOT LEAVE THE PROCESS.
//
// sendUnlockCode returns an EMPTY channel when nothing was delivered, and the
// caller writes NULL into permission_section_blocks.unlock_channel — which is
// why that column is nullable. The refusal the operator then meets tells them to
// wait, not to check a phone that was never texted.
//
// # WHY BOTH CHANNELS, WHEN THE CLIENT SAID SMS
//
// The client's sentence names SMS ("رسالة تأكيد SMS"), and SMS is tried first
// for exactly that reason. But H20 landed a working SMTP sender and main.go
// already hands it to this handler — the second factor on this same screen uses
// it. A block that ignored a configured mail relay and downgraded itself to a
// short cooldown would be throwing away a real channel to honour the letter of a
// sentence at the expense of its point.
package handlers

import (
	"context"
	"log"
	"strings"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// The values written to permission_section_blocks.unlock_channel. Constants
// rather than literals because the dashboard branches on the matching response
// code and the two must not drift apart.
const (
	permBlockChannelSMS   = "sms"
	permBlockChannelEmail = "email"
	// permBlockChannelNone is the empty string on purpose: it is what gets
	// turned into a SQL NULL, and giving it a spelling ("none") would put a
	// value in a column whose whole meaning is the absence of one.
	permBlockChannelNone = ""
)

// unlockDelivery is what sendUnlockCode managed to do.
//
// Code is non-empty only when Channel is too. A caller that reads one without
// checking the other cannot go wrong, because they are set and cleared together
// and never independently.
type unlockDelivery struct {
	Code    string // the plaintext code, for hashing only — never logged, never returned
	Channel string // permBlockChannel* above
	Hint    string // masked destination, safe for a log line
}

// Delivered reports whether a code actually left the server.
func (d unlockDelivery) Delivered() bool { return d.Channel != permBlockChannelNone }

// sendUnlockCode mints one unlock code and delivers it on the first channel
// that is real, preferring SMS.
//
// Returns a zero unlockDelivery when nothing could be sent — which is the
// ordinary case on every environment the team can reach today, not an error
// case. It is therefore not reported as an error: the caller has a different and
// entirely valid plan for that outcome (a short self-clearing cooldown), and
// making it handle an error here would invite it to abandon the block instead,
// which is the one thing that must not happen.
//
// Failures of a channel that IS configured are logged with the destination
// masked, and fall through to the next channel. The code itself is never logged.
func (h *AdminPermissionsHandler) sendUnlockCode(
	ctx context.Context, actorID int64, phone string,
) unlockDelivery {
	code, err := auth.GenerateCode()
	if err != nil {
		log.Printf("[security] H14: could not generate an unlock code for actor %d: %v", actorID, err)
		return unlockDelivery{}
	}

	// ── SMS first: it is the channel the client asked for by name. ──
	phone = strings.TrimSpace(phone)
	if h.OTPIQ != nil && phone != "" {
		if _, err := h.OTPIQ.SendVerification(ctx, phone, code); err != nil {
			log.Printf("[security] H14: unlock SMS to %s FAILED for actor %d: %v",
				maskPhone(phone), actorID, err)
		} else {
			return unlockDelivery{Code: code, Channel: permBlockChannelSMS, Hint: maskPhone(phone)}
		}
	}

	// ── Then email, when the account has an address and SMTP is configured. ──
	email := h.actorEmail(ctx, actorID)
	if h.Mail.Configured() && email != "" {
		if err := h.Mail.Send(ctx, email,
			"رمز رفع الحظر المؤقت عن إدارة الصلاحيات", permissionUnlockEmailBody(code)); err != nil {
			log.Printf("[security] H14: unlock email to %s FAILED for actor %d: %v",
				auth.MaskEmail(email), actorID, err)
		} else {
			return unlockDelivery{Code: code, Channel: permBlockChannelEmail, Hint: auth.MaskEmail(email)}
		}
	}

	// Nothing left the server. Said plainly, because the freeze that follows is
	// deliberately shortened on the strength of this line being true.
	log.Printf("[security] H14: no unlock code could be delivered for actor %d "+
		"(OTPIQ configured=%t, SMTP configured=%t, phone set=%t, email set=%t) — "+
		"the freeze will lapse on its own instead",
		actorID, h.OTPIQ != nil, h.Mail.Configured(), phone != "", email != "")
	return unlockDelivery{}
}

// permissionUnlockEmailBody is the message the frozen-out Super-Admin receives.
//
// Arabic, for the same reason as every other message this backend composes: the
// recipient is the administrator of this one organisation, the dashboard's
// locale is not known at send time, and there is no per-account language
// preference on the users row to consult. See TRANSLATION_REQUEST.md.
//
// It names what happened as well as the code. An unexplained six-digit number
// arriving after an unexplained sign-out is indistinguishable from a phishing
// attempt, and an administrator who has just been logged out is exactly the
// person who should be suspicious.
func permissionUnlockEmailBody(code string) string {
	return "تم تجميد قسم إدارة الصلاحيات مؤقتاً بعد سلسلة تعديلات سريعة على الصلاحيات، " +
		"وأُنهيت جلساتك المفتوحة تلقائياً.\n\n" +
		"رمز رفع الحظر: " + code + "\n\n" +
		"سجّل الدخول من جديد وأدخل هذا الرمز في صفحة إدارة الصلاحيات لرفع التجميد. " +
		"إذا لم تكن أنت من أجرى هذه التعديلات، غيّر كلمة المرور فوراً وراجع سجل التدقيق."
}
