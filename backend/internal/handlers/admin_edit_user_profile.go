// admin_edit_user_profile.go — the second half of "show me everything the user
// entered": once the detail page shows all 104 profile columns, the Edit modal
// has to be able to CORRECT them, or staff can read a wrong national ID and do
// nothing about it.
//
// WHY IT IS NOT ANOTHER 90 STRUCT FIELDS
// PATCH /api/admin/users/:id binds a typed `userEditReq` naming one Go field per
// column. That shape is right for the fourteen columns with real per-field rules
// (the sign-in phone, the email address, the nullable int) and wrong for the
// ninety that are plain nullable text: ninety more pointer fields, ninety more
// lines in the "did anything change" expression, and one typo away from writing
// the wrong column.
//
// So those ninety go through ONE allow-listed map instead. The security
// properties are the same ones admin_detail.go relies on:
//
//   - The column name never comes from the request. A key in the body is looked
//     up in userProfileWritableColumns; a key that is not there is IGNORED, not
//     interpolated. That is what makes it safe to build the SET clause.
//   - Values are always bound as $n parameters. No string-built SQL.
//   - The list is an ALLOW-list. A column added by a future migration is not
//     writable until somebody adds it here on purpose.
package handlers

import (
	"encoding/json"
	"sort"
	"strconv"
	"strings"
)

// userProfileWritableColumns — the plain-text `user_profiles` columns the admin
// Edit modal may write, beyond the typed fields on userEditReq.
//
// DELIBERATELY NOT WRITABLE, though they ARE shown on the detail page:
//
//   - grantor_code / recipient_code / volunteer_code — assign-once identity
//     codes minted by the server (internal/users/registration.go guards each
//     with `AND <col> = ''`). Staff search on them; rewriting one silently
//     breaks that search and orphans anything printed with the old code.
//   - display_name_mode — a CHECK-constrained enum ('real'|'alias') owned by
//     the user's own Privacy Settings screen. A free-text box here would
//     produce a 500 on a typo, and changing how somebody's name is displayed
//     to other users is their decision, not a data-entry correction.
//   - field_privacy — not exposed at all. See admin_detail_user_profile.go.
//   - gps_lat / gps_lng — doubles, not text. Shown read-only; a coordinate is
//     captured by the phone's GPS, and hand-typing one into a text box is a
//     worse answer than leaving it as the device recorded it.
//
// The columns handled by userEditReq's typed fields (full_name, gender,
// address, profile_picture, date_of_birth, city, occupation, family_size,
// housing_status, monthly_income, skills, availability, experience) are absent
// here on purpose — two writers for one column is how they drift.
var userProfileWritableColumns = map[string]bool{
	// Identity
	"name_first": true, "name_father": true, "name_grandfather": true,
	"name_family": true, "title_surname": true, "alias_name": true,
	"national_id": true, "nationality": true, "tribe_clan": true,
	"marital_status": true, "residency_status": true, "languages": true,

	// Contact
	"phone1": true, "phone2": true, "emergency_phone": true,
	"social_facebook": true, "social_instagram": true, "social_telegram": true,
	"social_other": true,

	// Location
	"governorate": true, "district": true, "housing_side": true,
	"neighborhood": true, "nearest_landmark": true,

	// Housing
	"housing_type": true, "rental_amount": true, "housing_area": true,
	"floors_count": true, "rooms_count": true, "families_count": true,
	"available_furniture": true, "owns_car": true,

	// Work & income
	"is_employed": true, "workplace": true, "previous_occupation": true,
	"job_description": true, "working_hours": true, "wage_amount": true,
	"registered_social_welfare": true, "registered_unemployed": true,
	"household_employees_count": true, "working_members_count": true,

	// Education
	"education_level": true, "other_certificate": true,
	"certificates_count": true,

	// Household composition
	"men_count": true, "women_count": true, "male_children_count": true,
	"female_children_count": true, "age_0_5_count": true,
	"age_5_10_count": true, "age_10_15_count": true, "age_15_25_count": true,
	"age_25_40_count": true, "age_40_plus_count": true, "students_count": true,
	"orphans_count": true, "widows_count": true, "divorced_count": true,
	"household_disabled_count": true,

	// Health
	"height": true, "weight": true, "smoking_status": true,
	"eyesight_condition": true, "has_disability": true, "disability_type": true,
	"chronic_illnesses": true, "medical_conditions_count": true,
	"medical_conditions_desc": true,

	// Needs & consent
	"needs_description": true, "consent_show_real_name": true,
	"consent_share_info": true,

	// Photos & documents — the upload path the admin/upload endpoint returns.
	"id_photo_path": true, "golden_square_photo_path": true,
	"residence_card_photo_path": true, "passport_photo_path": true,
	"graduation_cert_photo_path": true, "cv_photo_path": true,
	"ration_card_photo_path": true, "property_proof_photo_path": true,
	"medical_report_photo_path": true, "house_facade_photo_path": true,
	"house_inside_photo_path": true, "house_outside_photo_path": true,
}

// userProfileExtras is one request's worth of allow-listed profile edits:
// column name → the trimmed string to store. Sorted iteration order is not
// free with a map, so the SET clause is built from a sorted key slice — a
// deterministic statement is easier to read in a slow-query log.
type userProfileExtras map[string]string

// parseUserProfileExtras pulls the allow-listed profile columns out of a raw
// PATCH body.
//
// Unknown keys are dropped in silence ON PURPOSE: the modal posts one flat
// object holding both the typed fields and these, so "phone" and "password"
// arrive here too and are simply not ours. A non-string value is also dropped
// rather than coerced — every column in the list is TEXT, and a caller sending
// a number for one is making a mistake this endpoint should not paper over.
func parseUserProfileExtras(body []byte) userProfileExtras {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil
	}
	out := userProfileExtras{}
	for key, val := range raw {
		if !userProfileWritableColumns[key] {
			continue
		}
		var s string
		if err := json.Unmarshal(val, &s); err != nil {
			continue
		}
		out[key] = strings.TrimSpace(s)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// appendSets adds this request's extras to a setBuilder, matching the
// convention of the typed fields beside it: an empty string CLEARS the column.
//
// Clearing writes '' rather than NULL because these columns were added
// `NOT NULL DEFAULT ''` (migrations 072/073/074 onward) — NULL would violate
// the constraint. The distinction the detail page draws between "blank" and
// "not collected" is drawn from the ROLE, not from null-vs-empty, so nothing
// downstream depends on which of the two is stored.
func (e userProfileExtras) appendSets(b *setBuilder) {
	cols := make([]string, 0, len(e))
	for col := range e {
		cols = append(cols, col)
	}
	sort.Strings(cols)
	for _, col := range cols {
		b.args = append(b.args, e[col])
		// col is a key of userProfileWritableColumns — a compile-time literal,
		// never request text. The value is bound, never interpolated.
		b.sets = append(b.sets, `"`+col+`" = $`+strconv.Itoa(len(b.args)))
	}
}

// insertColumns renders the extras as parallel column-name and value slices, so
// the "no profile row yet" branch can seed them in its INSERT.
func (e userProfileExtras) insertColumns() (cols []string, vals []any) {
	names := make([]string, 0, len(e))
	for col := range e {
		names = append(names, col)
	}
	sort.Strings(names)
	for _, col := range names {
		cols = append(cols, `"`+col+`"`)
		vals = append(vals, e[col])
	}
	return cols, vals
}
