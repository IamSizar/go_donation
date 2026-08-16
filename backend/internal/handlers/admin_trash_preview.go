// admin_trash_preview.go — what a deleted record may show on its way out (B7).
//
// # WHY THIS FILE EXISTS
//
// B7 took `users.password_hash` off GET /api/admin/detail by inverting the
// mechanism: each resource declares the columns it may emit, so a credential is
// invisible unless somebody deliberately listed it (admin_detail.go).
//
// The Trash walked around that fix. A deleted row is archived as
// `to_jsonb(row.*)` — the WHOLE row, every column — and GET /api/admin/trash
// handed that snapshot back as `items[].payload`. For `source_table = 'users'`
// the snapshot carries the exact two columns admin_detail.go withholds by name:
// `password_hash` (the bcrypt credential) and `google_sub` (the identifier the
// Google sign-in path matches on). The route is gated on perm("trash","view"),
// and `view` is allowed by default for every staff tier down to `employee`
// (permissions.defaultAllowed), so the hash B7 refused to print on the عرض page
// arrived one click away on المهملات — to people the matrix never granted
// `sensitive_data` either.
//
// # WHY THE SNAPSHOT IS NOT FIXED AT THE WRITE END
//
// Because the snapshot is not a log entry, it is the record. استعادة rebuilds
// the row out of it (`jsonb_populate_record`, see AdminTrashHandler.Restore), so
// stripping `password_hash` when the row is DELETED would restore accounts whose
// password is silently blank — nobody could sign in, nothing would say why, and
// it would happen to every account ever restored. Same shape as the write-guard
// H10 needed for phone numbers: a value that is hidden must never be a value
// that gets stored.
//
// So the stored payload stays complete and byte-identical, and the withholding
// happens on DISPLAY — here.
//
// # WHY AN ALLOW-LIST AND NOT A LIST OF SECRETS
//
// A deny-list has to be told about each new secret or the secret ships by
// default. That is not a hypothetical: the redaction this replaces knew only
// about phone/email-shaped column NAMES, so a credential column was outside its
// scope by construction — which is precisely how B7 happened the first time.
// Inverted, the next migration that adds a token, a hash or a recovery answer is
// invisible here until someone lists it deliberately.
//
// # WHAT THE PREVIEW IS FOR, WHICH IS WHY THE LISTS ARE SHORT
//
// The Trash page uses `payload` for exactly one thing: naming the record, so an
// operator about to press استعادة or حذف نهائي can tell which one they have
// (`previewOf` in admin-web/src/pages/TrashPage.tsx). The row's id, who deleted
// it and when are separate top-level fields of the entry, not part of the
// snapshot. So each table lists its LABEL — the name/title it is known by, in
// every language it is authored in — plus, for a row with no name of its own,
// the one code or field an operator can recognise it by. Amounts, addresses,
// national ids, review notes and foreign keys are not part of identifying a
// record and are no longer sent.
package handlers

import (
	"encoding/json"
	"log"
)

// catalogueLabelColumns is the shape every admin catalogue table shares: a slug
// plus its name in the four authored languages (migrations 060-103). Named once
// so the eleven lists below cannot drift from each other.
var catalogueLabelColumns = []string{"slug", "name_en", "name_ar", "name_ckb", "name_kmr"}

// trashPreviewColumns is the allow-list: per source table, exactly the columns
// GET /api/admin/trash may put in a preview. Every table that trashRow can be
// called with needs an entry — TestEveryTrashedTableDeclaresItsPreviewColumns
// keeps that true — and a table without one previews as `{}` rather than as a
// whole row.
//
// Adding a column to a table does NOT add it here. That is the point: the
// omission is the safe direction.
var trashPreviewColumns = map[string][]string{
	// users — 3 of 20 columns. WITHHELD, deliberately: `password_hash` and
	// `google_sub`, the two credentials admin_detail.go also refuses; and the
	// account's whole administrative state (role_id, staff_tier, is_admin,
	// account_status, wallet_balance_iqd, the registration audit trail), none of
	// which helps anyone decide whether to restore the account.
	//
	// The three that stay are the ones the preview reads to say WHOSE account
	// this was. `phone` and `email` are contact columns, so they are masked on
	// top of this for a caller without `sensitive_data` (H10) — the allow-list
	// decides which columns exist in the preview, the mask decides whether their
	// values are readable, and both have to pass.
	"users": {"username", "phone", "email"},

	// ─── Records with a name or a title of their own ─────────────────────
	"partners":               {"name", "name_ar", "name_sorani", "name_badini"},
	"city_directory_entries": {"name", "name_ar", "name_sorani", "name_badini"},
	"marketplace_products":   {"name", "name_ar", "name_sorani", "name_badini"},
	"media_posts":            {"title", "title_ar", "title_sorani", "title_badini"},
	"campaigns":              {"title", "title_ar", "title_sorani", "title_badini"},
	"volunteer_missions":     {"title", "title_ar", "title_sorani", "title_badini"},
	"beneficiary_project_requests": {
		"project_title", "project_title_ar", "project_title_sorani", "project_title_badini",
	},
	// beneficiary_cases — the public title is the case's own name; `full_name` is
	// what the Trash page shows today and what staff recognise a case by. The
	// rest of the row (national_id, phone, address, income, health and education
	// status, review notes) is a vulnerable person's file and has no business in
	// a delete preview.
	"beneficiary_cases": {
		"case_code", "full_name",
		"public_title", "public_title_ar", "public_title_sorani", "public_title_badini",
	},
	"tasks": {"title"},

	// ─── Records identified by a code, not a name ────────────────────────
	// marriage_profiles is the extreme case: 79 columns of one person's private
	// file — national id, income, health, assets, family. `profile_code` is the
	// handle staff and the owner both use for it.
	//
	// `email` is here for one reason: it is the label the Trash page draws for
	// these rows TODAY (previewOf reads `email`; this table has no name or title
	// column for it to prefer). Dropping it would blank the row, and this change
	// is about removing credentials, not about quietly relabelling a screen. It
	// stays masked for a caller without `sensitive_data`, exactly as now.
	"marriage_profiles":  {"profile_code", "email"},
	"marketplace_orders": {"transaction_code"},
	"donations":          {"reference_number"},

	// ─── Records identified by their own free text ───────────────────────
	// The text is the record here: a comment IS its body, a ticket is its
	// subject, a signup carries only the volunteer's note.
	"support_tickets":           {"subject"},
	"post_comments":             {"body"},
	"volunteer_mission_signups": {"notes"},
	"in_kind_donations":         {"item_name", "notes"},
	"sponsorships":              {"sponsorship_type", "notes"},
	"volunteer_applications":    {"full_name"},

	// ─── Catalogue rows (H15 / M7) ───────────────────────────────────────
	// Authored in four languages, so all four names stay: the Trash reads the
	// operator's own language first and falls back through Arabic to English.
	"project_categories":             catalogueLabelColumns,
	"sponsorship_types":              catalogueLabelColumns,
	"inkind_categories":              catalogueLabelColumns,
	"city_sectors":                   catalogueLabelColumns,
	"city_categories":                catalogueLabelColumns,
	"media_categories":               catalogueLabelColumns,
	"case_categories":                catalogueLabelColumns,
	"marketplace_categories":         catalogueLabelColumns,
	"donation_types":                 catalogueLabelColumns,
	"marriage_subscription_packages": catalogueLabelColumns,
	// payment_methods shares the catalogue shape; its `account_number` and
	// `account_name` are not on the list, so the organisation's bank details no
	// longer ride along in a delete preview.
	"payment_methods": catalogueLabelColumns,
	// custom_professions labels its rows `label_*` rather than `name_*`.
	"custom_professions": {"skill_key", "label_en", "label_ar", "label_ckb", "label_kmr"},
}

// trashPreviewPayload rewrites one stored snapshot into the preview the Trash
// page may show: the allow-listed columns of that table, and nothing else.
//
// The payload is `to_jsonb(row.*)` — a whole deleted row, whose columns differ
// per source table and are not known at compile time — which is why this works
// on a decoded map rather than on a struct the way the typed lists do.
//
// It rewrites only the RESPONSE. The row in `trash_items` is never touched, so
// استعادة still rebuilds the account from a complete snapshot (Restore re-reads
// `payload` straight from the database).
//
// Every failure withholds. An unknown table, an undecodable snapshot or a
// re-encoding error all return an empty object rather than the original bytes:
// handing back a raw row because the filter failed would turn any parse bug into
// the leak this function exists to prevent. The preview loses a label; the
// record itself is untouched and still restorable.
func trashPreviewPayload(table string, payload []byte) []byte {
	allowed, listed := trashPreviewColumns[table]
	if !listed || len(allowed) == 0 {
		log.Printf("[b7] trash: %s declares no preview columns — withholding its snapshot", table)
		return []byte(`{}`)
	}

	var row map[string]any
	if err := json.Unmarshal(payload, &row); err != nil {
		log.Printf("[b7] trash: snapshot for %s could not be decoded, withholding it: %v", table, err)
		return []byte(`{}`)
	}

	preview := make(map[string]any, len(allowed))
	for _, column := range allowed {
		if value, present := row[column]; present {
			preview[column] = value
		}
	}

	out, err := json.Marshal(preview)
	if err != nil {
		log.Printf("[b7] trash: preview for %s could not be encoded, withholding it: %v", table, err)
		return []byte(`{}`)
	}
	return out
}
