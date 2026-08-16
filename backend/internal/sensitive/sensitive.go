// Package sensitive holds the ONE definition of what a redacted contact value
// looks like, plus the two questions the rest of the backend asks about it:
// "may this caller see raw contact data?" and "is this value a redaction?".
//
// # WHY THIS PACKAGE EXISTS (H10)
//
// The client asked that only authorised staff see phone numbers and email
// addresses. The `sensitive_data` permission for that has existed since §24 and
// was consulted in exactly ONE place in the whole backend
// (handlers/admin_detail.go) while roughly twenty admin endpoints returned a
// phone or an email. The reason was structural rather than an oversight: the
// mask, the permission lookup and the "is this a mask?" test all lived as
// unexported helpers inside one handler file, so no other handler could reuse
// them even if someone had wanted to.
//
// # WHY IT IS NOT internal/privacy
//
// `internal/privacy` enforces the choices a USER made about their own profile,
// for other USERS. Its own doc comment draws the line explicitly: staff
// dashboards are governed by a different mechanism. This is that mechanism.
//
// # THE MARK, AND WHY IT IS LOAD-BEARING
//
// A masked value is written with U+2022 BULLET (•). That character cannot occur
// in a phone number, an email address or a WhatsApp number, which is what makes
// IsMasked a reliable test at a WRITE boundary — see
// handlers/admin_contact_write_guard.go. The dashboard prefills its edit forms
// from the list row it just rendered, so without that test the first masked
// list response would have started writing "••••61" into `users.phone`, the
// column sign-in looks accounts up by.
//
// The mark is deliberately NOT a blanket rule over whole request bodies: prose
// fields legitimately contain bullets (a bulleted case note, a partner's
// service list). Only contact-shaped fields are tested.
package sensitive

import (
	"context"
	"strings"

	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// Module is the permissions slug that governs raw contact data. It is a real
// row in permissions.Modules and defaults to admins only (see
// permissions.moduleDefaultAllowed) — the opposite of the usual "view is
// allowed by default" rule.
const Module = "sensitive_data"

// mark is the character every redaction is built from. Exported through
// IsMasked rather than directly, so call sites test the QUESTION instead of
// re-deriving the answer.
const mark = '•' // •

// keptRunes is how much of the original survives a mask: enough for a staff
// member to confirm "yes, that is the number the caller just read out to me"
// without the value itself being usable to contact or impersonate anyone.
const keptRunes = 2

// Mask replaces a contact value with its redacted form, keeping the last two
// characters as a hint ("9647500000903" → "••••03").
//
// Empty input stays empty: a blank column is not a secret, and masking it would
// invent a value the record does not hold — the operator would read "••" and go
// looking for a number nobody ever gave.
//
// Values of two characters or fewer collapse to "••" with no hint, because a
// hint the same length as the value is not a hint.
//
// Runes, not bytes: slicing a UTF-8 string by byte offset can cut a character
// in half and produce invalid JSON output. Contact data is overwhelmingly ASCII
// today, so this costs nothing and removes a class of bug from the future.
func Mask(v string) string {
	if v == "" {
		return ""
	}
	r := []rune(v)
	if len(r) <= keptRunes {
		return strings.Repeat(string(mark), keptRunes)
	}
	return strings.Repeat(string(mark), 4) + string(r[len(r)-keptRunes:])
}

// MaskPtr is Mask for a nullable column. A nil pointer stays nil — SQL NULL is
// "no value recorded", which is not a secret and must not become one.
func MaskPtr(v *string) *string {
	if v == nil {
		return nil
	}
	masked := Mask(*v)
	return &masked
}

// MaskAny masks a value that arrived as `any` (a pgx row map, a JSON payload).
// Non-string values pass through untouched: a phone stored as a number, or a
// nil, is not something Mask can meaningfully redact and silently stringifying
// it would corrupt the response shape.
func MaskAny(v any) any {
	s, ok := v.(string)
	if !ok {
		return v
	}
	return Mask(s)
}

// IsMasked reports whether a value carries the redaction mark — i.e. whether it
// came back out of a screen that was never shown the real thing.
//
// This is the write-boundary test. It answers on the VALUE, never on the
// caller's rank: a bullet string posted by a Super-Admin (who sees raw data) is
// a bug in the client, not an intention, and storing it would break the record
// just as thoroughly.
func IsMasked(v string) bool {
	return strings.ContainsRune(v, mark)
}

// CanViewForUser reports whether one named staff member may see raw contact
// data.
//
// Resolution is Note 31's: the person's OWN override first, then their tier's
// override, then the module default (admins only). It is deliberately the
// per-user form rather than the tier-only one, because that is what
// GET /api/admin/permissions/me answers and therefore what the dashboard
// believes about itself. If the two disagreed, a Super-Admin revoking the
// permission for a single employee would see the column disappear from the
// screen while the server kept sending the real number in the JSON behind it.
//
// FAILURE IS CLOSED. A nil store — a handler that was never wired — answers
// "no" rather than "yes", so a new endpoint that forgets this question masks
// instead of leaking. A failed lookup returns the error alongside false so the
// caller can log it and still fail safe.
func CanViewForUser(ctx context.Context, store *permissions.Store, userID int64, tier permissions.Tier) (bool, error) {
	if store == nil {
		return false, nil
	}
	allowed, err := store.AllowedForUser(ctx, userID, tier, Module, permissions.ActionView)
	if err != nil {
		return false, err
	}
	return allowed, nil
}
