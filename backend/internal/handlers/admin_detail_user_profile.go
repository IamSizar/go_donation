// admin_detail_user_profile.go — everything the `users` detail payload adds on
// top of the account row: the registration profile the person actually filled
// in, the privacy choices they made about it, and the documents they uploaded.
//
// WHY THIS FILE EXISTS
// `user_profiles` has 107 columns. The detail endpoint's allow-list named 13 of
// them, so the عرض page showed a wall of "—" for data the person HAD entered —
// it was simply never SELECTed. The owner read those dashes as "the app is not
// saving anything". They are broken out here rather than inlined into
// admin_detail.go's map so the reasoning for each omission has room to be
// written down, and so the frontend's grouping has one server-side list to
// match against.
//
// THE ALLOW-LIST IS STILL AN ALLOW-LIST. Widening it does not change its
// direction: a column that nobody names below is invisible, and a future
// migration that adds a token, a hash or a recovery answer to `user_profiles`
// stays invisible without anyone remembering this file. Do NOT replace this
// with `SELECT *` or with "every column except a denylist".
package handlers

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// userProfileDetailColumns — the user-entered columns of `user_profiles` that
// the admin detail view may return, in the order the registration forms ask
// for them.
//
// DELIBERATELY OMITTED, and why:
//
//   - id           — user_profiles' own primary key. An internal row number
//     with no meaning to staff, and it would collide with the
//     account's `id` in the merged row map.
//   - user_id      — already present on the merged row as `id`. Printing the
//     same number twice under two labels is noise.
//   - field_privacy— NOT a profile field. It is the settings blob behind the
//     app's Privacy Settings screen: a TEXT[] of the field keys
//     this person asked other USERS not to see (migration 040,
//     catalogue in 083). Rendering it as a row would show staff a
//     list of machine keys, and would invite editing a privacy
//     control from a data-entry screen. It is read below and
//     re-emitted as `_privacy_hidden`, a meta key the UI uses to
//     BADGE the affected fields — see loadUserPrivacyHidden.
//
// Nothing on this table is a credential: `password_hash` and `google_sub` live
// on `users` and remain withheld there (see detailColumns).
var userProfileDetailColumns = []string{
	// ─── Identity ───────────────────────────────────────────────────────
	"full_name", "name_first", "name_father", "name_grandfather", "name_family",
	"title_surname", "display_name_mode", "alias_name", "national_id",
	"date_of_birth", "gender", "nationality", "tribe_clan", "marital_status",
	"residency_status", "languages",
	// Identity codes the backend assigns once per role (GR-/ER-/VL-). Staff
	// search on these, so they belong on the record they identify.
	"grantor_code", "recipient_code", "volunteer_code",

	// ─── Contact ────────────────────────────────────────────────────────
	// phone1/phone2/emergency_phone/email are matched by contactColumnRe and
	// are therefore masked for a caller without `sensitive_data`, exactly like
	// `users.phone` already was.
	"phone1", "phone2", "emergency_phone", "email",
	"social_facebook", "social_instagram", "social_telegram", "social_other",
	"gps_lat", "gps_lng",

	// ─── Location ───────────────────────────────────────────────────────
	"governorate", "district", "city", "housing_side", "neighborhood",
	"address", "nearest_landmark",

	// ─── Housing ────────────────────────────────────────────────────────
	"housing_type", "housing_status", "rental_amount", "housing_area",
	"floors_count", "rooms_count", "families_count", "available_furniture",
	"owns_car",

	// ─── Work & income ──────────────────────────────────────────────────
	"is_employed", "workplace", "occupation", "previous_occupation",
	"job_description", "working_hours", "wage_amount", "monthly_income",
	"registered_social_welfare", "registered_unemployed",
	"household_employees_count", "working_members_count",

	// ─── Education ──────────────────────────────────────────────────────
	"education_level", "other_certificate", "certificates_count",

	// ─── Household composition ──────────────────────────────────────────
	"family_size", "men_count", "women_count", "male_children_count",
	"female_children_count", "age_0_5_count", "age_5_10_count",
	"age_10_15_count", "age_15_25_count", "age_25_40_count",
	"age_40_plus_count", "students_count", "orphans_count", "widows_count",
	"divorced_count", "household_disabled_count",

	// ─── Health ─────────────────────────────────────────────────────────
	"height", "weight", "smoking_status", "eyesight_condition",
	"has_disability", "disability_type", "chronic_illnesses",
	"medical_conditions_count", "medical_conditions_desc",

	// ─── Volunteering ───────────────────────────────────────────────────
	"skills", "availability", "experience",

	// ─── Needs & consent ────────────────────────────────────────────────
	"needs_description", "consent_show_real_name", "consent_share_info",

	// ─── Photos & documents (stored as upload paths) ────────────────────
	"profile_picture", "id_photo_path", "golden_square_photo_path",
	"residence_card_photo_path", "passport_photo_path",
	"graduation_cert_photo_path", "cv_photo_path", "ration_card_photo_path",
	"property_proof_photo_path", "medical_report_photo_path",
	"house_facade_photo_path", "house_inside_photo_path",
	"house_outside_photo_path",
}

// userDetailMetaPrivacy is the row key carrying the person's saved
// "hide this from other users" list. Prefixed with an underscore because no
// database column starts with one, so the SPA can tell the meta keys apart
// from the fields it must render as rows.
const userDetailMetaPrivacy = "_privacy_hidden"

// userDetailMetaDocuments is the row key carrying the uploaded documents.
const userDetailMetaDocuments = "_documents"

// loadUserProfile returns the allow-listed profile columns for one user, or nil
// when the account has no `user_profiles` row at all (a guest, or an account
// created before the profile was filled in). A missing row is NOT an error: the
// detail page must still render the account.
func loadUserProfile(ctx context.Context, pool *pgxpool.Pool, userID int64) (map[string]any, error) {
	rows, err := pool.Query(ctx,
		"SELECT "+selectList(userProfileDetailColumns)+" FROM user_profiles WHERE user_id = $1",
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	prof, err := pgx.CollectOneRow(rows, pgx.RowToMap)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return prof, nil
}

// loadUserPrivacyHidden returns the field keys this person switched OFF in the
// app's Privacy Settings screen.
//
// WHAT THIS IS AND IS NOT. The app's promise (`privacy_desc`: "Choose which
// profile details other people can see") is about other USERS; staff access is
// governed by a separate, already-implemented mechanism — the `sensitive_data`
// permission — and internal/privacy states in so many words that admin queries
// must not use the user-facing masking. So this does not hide anything from
// staff. It exists so the dashboard can SAY that a value was marked private,
// instead of showing it as though the person had chosen to share it. Nothing
// here writes to field_privacy, and nothing here changes what privacy means.
func loadUserPrivacyHidden(ctx context.Context, pool *pgxpool.Pool, userID int64) []string {
	var hidden []string
	err := pool.QueryRow(ctx,
		`SELECT COALESCE(field_privacy, '{}') FROM user_profiles WHERE user_id = $1`,
		userID).Scan(&hidden)
	if err != nil {
		// A user with no profile row is the common case, not a fault; anything
		// else is logged but must not break the page.
		if err != pgx.ErrNoRows {
			log.Printf("[detail] user %d: reading field_privacy: %v", userID, err)
		}
		return []string{}
	}
	if hidden == nil {
		return []string{}
	}
	return hidden
}

// userDocument is one row of `beneficiary_case_documents` as the detail page
// needs it: enough to render a link or a thumbnail, and nothing else.
type userDocument struct {
	ID            int64  `json:"id"`
	CaseID        int64  `json:"case_id"`
	CaseCode      string `json:"case_code"`
	DocumentType  string `json:"document_type"`
	FilePath      string `json:"file_path"`
	PublicAllowed bool   `json:"public_allowed"`
	CreatedAt     string `json:"created_at"`
}

// loadUserDocuments returns every document uploaded against any beneficiary
// case belonging to this user, newest first.
//
// Joined through `beneficiary_cases` because the documents table keys on
// case_id, not user_id — a user with no case simply has no documents, which is
// an empty list rather than an error.
func loadUserDocuments(ctx context.Context, pool *pgxpool.Pool, userID int64) []userDocument {
	rows, err := pool.Query(ctx, `
		SELECT d.id, d.case_id, COALESCE(c.case_code, ''), d.document_type,
		       d.file_path, d.public_allowed,
		       to_char(d.created_at, 'YYYY-MM-DD"T"HH24:MI:SS')
		  FROM beneficiary_case_documents d
		  JOIN beneficiary_cases c ON c.id = d.case_id
		 WHERE c.user_id = $1
		 ORDER BY d.created_at DESC, d.id DESC`, userID)
	if err != nil {
		log.Printf("[detail] user %d: reading uploaded documents: %v", userID, err)
		return []userDocument{}
	}
	defer rows.Close()
	out := []userDocument{}
	for rows.Next() {
		var d userDocument
		var publicAllowed int16
		if err := rows.Scan(&d.ID, &d.CaseID, &d.CaseCode, &d.DocumentType,
			&d.FilePath, &publicAllowed, &d.CreatedAt); err != nil {
			log.Printf("[detail] user %d: scanning document row: %v", userID, err)
			return out
		}
		d.PublicAllowed = publicAllowed != 0
		out = append(out, d)
	}
	if err := rows.Err(); err != nil {
		log.Printf("[detail] user %d: iterating documents: %v", userID, err)
	}
	return out
}

// mergeUserProfile attaches the profile, the privacy flags and the documents to
// an already-loaded `users` row. Account columns always win a name collision —
// `email` exists on both tables and the account's is the one sign-in uses.
func mergeUserProfile(ctx context.Context, pool *pgxpool.Pool, userID int64, row map[string]any) {
	prof, err := loadUserProfile(ctx, pool, userID)
	if err != nil {
		// Never swallow: the page still renders the account row, and the
		// operator is not shown a half-truth silently.
		log.Printf("[detail] user %d: reading profile: %v", userID, err)
	}
	for k, v := range prof {
		if _, exists := row[k]; !exists {
			row[k] = v
		}
	}
	row[userDetailMetaPrivacy] = loadUserPrivacyHidden(ctx, pool, userID)
	row[userDetailMetaDocuments] = loadUserDocuments(ctx, pool, userID)
}
