// admin_contact_write_guard.go — a redacted value is never stored (H10).
//
// # WHY THIS FILE EXISTS, AND WHY IT LANDED BEFORE THE REDACTION IT PROTECTS
//
// H10 asks that phone numbers and email addresses stop reaching staff who were
// not granted `sensitive_data`. Doing only that — masking the value in the list
// response — is a DATA-DESTROYING change on this codebase, because the
// dashboard prefills its edit form from the list row it just rendered:
//
//	admin-web/src/pages/UsersPage.tsx  flattenForEdit()  → phone: u.phone
//	backend/.../admin_edit.go          User()            → UPDATE users SET phone = $1
//
// A supervisor who opens تعديل on a masked row and presses حفظ would therefore
// store "••••03" as that account's phone. `users.phone` is the sign-in identity
// — auth resolves accounts by the normalised value — so the account could never
// sign in again, and nothing on screen would say what had happened. The same
// shape exists on beneficiary cases, project requests and volunteer
// applications, whose edit forms are prefilled the same way.
//
// # THE RULE, AND WHY IT IS ABOUT THE VALUE RATHER THAN THE CALLER
//
//	A VALUE CARRYING THE REDACTION MARK IS NEVER PERSISTED, BY ANYONE.
//
// Not "staff without sensitive_data may not write phones" — that would remove
// an everyday task (correcting a beneficiary's mistyped number) that H13
// deliberately left available to every rank holding تعديل, and it would still
// miss the case where a client bug replays a mask from a privileged session. It
// is the VALUE that is unstorable: U+2022 BULLET cannot occur in a real phone
// number, email address or WhatsApp number, so the test has no false positives
// on contact fields and needs no knowledge of who is asking.
//
// # WHY IT IS PER-FIELD AND NOT A BODY-WIDE SWEEP
//
// A middleware rejecting any bullet anywhere in the request body would be one
// line and would be wrong: staff write bulleted lists into prose columns —
// "• سكن غير ملائم" in a case's actual_needs, a partner's service list — and
// those are content, not redactions. Each handler names the contact fields it
// accepts. That is a few more lines per endpoint, and every one of them is
// readable at the call site.
//
// # WHERE IT IS APPLIED
//
// Every write whose matching READ is redacted (see the H10 inventory): the
// users PATCH and create, beneficiary cases, beneficiary project requests, and
// volunteer applications. The organisation's OWN contact details — a partner's
// office line, a City Guide place's public number, the support WhatsApp number,
// a donation code's notify_phone — are never masked on the way out, so a mask
// cannot arrive on the way in and no guard is needed there.
//
// Pinned by admin_contact_write_guard_test.go, which fails loudly (and names
// the destroyed sign-in number) if any of these endpoints stops calling it.
package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// contactWrite names one inbound contact field and the value this request
// carried for it.
//
// A nil Value means the request did not mention the field at all. That is not a
// write, so it cannot be a mask — the PATCH handlers use nil-pointer fields
// exactly this way to distinguish "leave unchanged" from "set to empty".
type contactWrite struct {
	Field string
	Value *string
}

// rejectMaskedContactWrite refuses the request when any named field carries a
// redacted value, and reports whether the caller must be STOPPED — the refusal
// has already been written, so the handler returns immediately. Same convention
// as guardUserWrite in admin_user_guard.go.
//
// Call it AFTER binding the body and BEFORE any write, so a refusal can never
// leave a half-applied edit. On the multi-column PATCH handlers that matters:
// those build one UPDATE from every field the request sent, and a mask must not
// take the legitimate fields down with it silently or land them without it.
//
// The reply carries `code` — a STABLE machine key the SPA maps through its
// `error.*` namespace, so the operator reads the refusal in their own language.
// The English in `error` is for logs and non-SPA callers, never for the screen.
// Every refusal is logged: a silent 400 is invisible both to the employee whose
// save mysteriously failed and to whoever is probing the boundary.
func rejectMaskedContactWrite(c *gin.Context, fields ...contactWrite) bool {
	for _, f := range fields {
		if f.Value == nil || !sensitive.IsMasked(*f.Value) {
			continue
		}

		actorID := int64(0)
		actorTier := ""
		if u, ok := auth.UserFromGin(c); ok && u != nil {
			actorID, actorTier = u.UserID, u.StaffTier
		}
		// The value itself is NOT logged. It is a redaction, so it carries the
		// tail of somebody's real number — writing it to the log would put back
		// the fragment the redaction just removed.
		log.Printf("[h10] refused masked contact write on %s %s — field=%s actor_id=%d actor_tier=%q ip=%s",
			c.Request.Method, c.Request.URL.Path, f.Field, actorID, actorTier, c.ClientIP())

		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"code":    "redacted_contact_write",
			"error": "This contact value is hidden from you, so it cannot be saved. " +
				"Leave the field untouched, or ask the Primary Administrator for the " +
				"'Sensitive contact data' permission.",
			"field": f.Field,
		})
		return true
	}
	return false
}
