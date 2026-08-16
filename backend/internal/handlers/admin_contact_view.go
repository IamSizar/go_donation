// admin_contact_view.go — who may see a raw phone number or email (H10).
//
// # WHY THIS FILE EXISTS
//
// The `sensitive_data` permission has existed since §24 and was consulted in
// exactly ONE place in the whole backend (admin_detail.go) while roughly twenty
// admin endpoints returned a phone or an email. The reason was structural, not
// an oversight: the question needs a *permissions.Store, and only two handler
// structs in the package carried one, so no other handler could ask.
//
// This file is that question, asked the same way everywhere.
//
// # WHY PER-ENDPOINT AND NOT ONE MIDDLEWARE OVER THE ADMIN GROUP
//
// A response middleware masking every contact-shaped key under /api/admin would
// be shorter, and it would mask the ORGANISATION'S OWN numbers along with the
// personal ones: the partner directory's office lines, the City Guide's public
// place numbers, the support WhatsApp handoff number, a donation code's
// notify_phone. Those are published contact details — the City Guide's whole
// purpose is to hand them out — so the middleware would need an exclusion list,
// and an exclusion list is exactly the thing that rots: the next endpoint
// nobody adds to it either leaks or breaks, silently, and which of the two it
// does depends on which side of the list it landed on.
//
// Per-endpoint is more edits. Each one is three lines at the point where the
// response is built, next to the field it redacts, and each one is testable on
// its own. That is the trade this codebase takes.
//
// # WHAT COUNTS AS PERSONAL
//
// Masked: a number or address that identifies or reaches a PERSON — an app
// user, an applicant, a donor, a beneficiary, a staff member.
//
// Not masked: the organisation's own published contact details. See the H10
// note in CLIENT_NOTES_CHECKLIST.md for the endpoint-by-endpoint classification.
package handlers

import (
	"log"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// canViewContact reports whether the caller behind this request may receive raw
// contact data. Call it once per request and reuse the answer — it costs a
// database round-trip, and asking per row would turn a 200-row page into 200
// permission lookups.
//
// Resolution honours Note 31's per-employee override before the tier's own
// setting, matching GET /api/admin/permissions/me — the endpoint the dashboard
// itself asks. If the two disagreed, a Super-Admin who revoked the permission
// for ONE employee would see the dashboard hide the column while the server
// kept sending the real number in the JSON behind it, which is precisely the
// leak H10 is about.
//
// FAILURE IS CLOSED, three ways: no permission store wired, no identifiable
// caller, or a failed lookup all answer "no". A masked dashboard is a cosmetic
// problem; the other direction is the leak.
func canViewContact(c *gin.Context, perms *permissions.Store) bool {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		return false
	}
	allowed, err := sensitive.CanViewForUser(c.Request.Context(), perms,
		actor.UserID, permissions.TierFrom(actor.StaffTier))
	if err != nil {
		log.Printf("[h10] sensitive_data lookup failed on %s %s — user_id=%d tier=%q: %v (masking)",
			c.Request.Method, c.Request.URL.Path, actor.UserID, actor.StaffTier, err)
		return false
	}
	return allowed
}

// staffMustNotSeeContact is canViewContact for the two endpoints that answer
// BOTH the mobile app and the dashboard from one route (GET /api/sponsorships
// today). It returns true only for a STAFF caller who lacks the permission.
//
// A plain app user is left entirely alone here, deliberately. What one user may
// see of another is already decided, by that person's own Privacy Settings
// through internal/privacy — a different mechanism with a different owner (the
// data subject, not a Super-Admin), and one whose own doc comment says staff
// dashboards are not its business. Answering this question twice, in two
// packages, with two different sources of truth, is how the two end up
// disagreeing.
func staffMustNotSeeContact(c *gin.Context, perms *permissions.Store) bool {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		return false
	}
	if !permissions.CanAccessDashboard(permissions.TierFrom(actor.StaffTier)) {
		return false
	}
	return !canViewContact(c, perms)
}

// ─── Whose contact details are these? ───────────────────────────────────

// contactColumnRe matches a column name that holds contact information. Used
// only where the response is a generic row map (the detail view, the trash
// payload) and the columns are therefore not known at compile time; every
// typed endpoint names its fields explicitly instead, which is safer.
var contactColumnRe = regexp.MustCompile(`(?i)(phone|mobile|email|whatsapp|contact_number|tel)`)

// personalContactTables says, per table, whether its contact columns belong to
// a PERSON. This is the H10 classification in one place, so the generic
// endpoints (detail, trash) cannot drift from the typed ones.
//
// The distinction is not "is it a phone number" but "whose is it":
//
//   - A beneficiary's number, a donor's number, an applicant's number and a
//     staff member's number identify and reach a person who did not choose to
//     publish them. Those are masked.
//
//   - `partners.contact_phone` and `city_directory_entries.phone` are the
//     office lines of organisations the charity lists ON PURPOSE so people can
//     call them. The City Guide's entire function is handing those out — it
//     serves them to the PUBLIC, unauthenticated, at GET /api/partners. Masking
//     them for staff would hide from an employee what any visitor can read,
//     which is not privacy, only a broken screen.
//
// A table that is not listed is treated as personal. That is the safe
// direction: a new table leaks nothing until someone deliberately declares its
// contact columns public.
var personalContactTables = map[string]bool{
	// Personal — the people the charity serves and works with.
	"users":                        true,
	"user_profiles":                true,
	"beneficiary_cases":            true,
	"beneficiary_project_requests": true,
	"volunteer_applications":       true,
	"marriage_profiles":            true,
	"sponsorships":                 true,
	"donations":                    true,
	"in_kind_donations":            true,
	"support_tickets":              true,
	"campaigns":                    true,
	"marketplace_orders":           true,

	// The organisation's own published contact details. Not personal data.
	"partners":               false,
	"city_directory_entries": false,
	"payment_methods":        false,
	"donation_section_codes": false,
	"app_settings":           false,
	"app_content":            false,
}

// tableHoldsPersonalContact reports whether a table's contact columns belong to
// a person. Unknown tables answer true — see personalContactTables.
func tableHoldsPersonalContact(table string) bool {
	public, listed := personalContactTables[table]
	if !listed {
		return true
	}
	return public
}

// maskContactColumns redacts every contact-shaped key of a generic row map in
// place, for tables whose contact columns are personal. Used by the detail view
// and the trash preview, both of which serve whole rows they do not have a
// struct for.
func maskContactColumns(table string, row map[string]any) {
	if !tableHoldsPersonalContact(table) {
		return
	}
	for k, v := range row {
		if contactColumnRe.MatchString(strings.ToLower(k)) {
			row[k] = sensitive.MaskAny(v)
		}
	}
}
