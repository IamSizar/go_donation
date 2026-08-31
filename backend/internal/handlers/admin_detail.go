package handlers

import (
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// AdminDetailHandler exposes Phase 16's GET /api/admin/detail/:resource/:id
// endpoint. It returns the full row from any allowlisted admin resource so
// the SPA can render a read-only detail page without needing N hand-rolled
// per-resource SELECT handlers.
//
// Security: the :resource path parameter is matched against an allowlist
// (resourceTables map). Anything not in the map returns 404 — we never
// interpolate user input into the table name.
//
// Output shape: {success, item} where item is a JSON object whose keys are
// the SELECTed column names — the ones detailColumns lists for that resource,
// and only those.
//
// B7 — this used to `SELECT *` and then redact the columns whose NAME looked
// like contact information. That handed `users.password_hash`, the bcrypt hash
// the account signs in with, to every staff member who opened a عرض page;
// production holds ten of them, two on `super_admin` rows. The redaction list
// was never the right mechanism — it has to be updated for each new secret or
// the secret ships by default, and it only ever knew about phone/email-shaped
// names, so a credential column was never in its scope.
//
// It is inverted now: each resource declares what it may emit. A column nobody
// listed is invisible, so the next migration that adds a token, a hash or a
// recovery answer is safe without anyone remembering this file. The cost is
// real and deliberate — a genuinely new business column has to be added to the
// list before it shows up on the detail page.
type AdminDetailHandler struct {
	Pool  *pgxpool.Pool
	Perms *permissions.Store // §24 — gates who sees raw phone/email.
}

func NewAdminDetailHandler(pool *pgxpool.Pool, perms *permissions.Store) *AdminDetailHandler {
	return &AdminDetailHandler{Pool: pool, Perms: perms}
}

// resourceTables maps the URL :resource slug to the underlying table name.
// Add to this map when introducing a new admin resource.
var resourceTables = map[string]string{
	"partners":                     "partners",
	"media":                        "media_posts",
	"community":                    "city_directory_entries",
	"marriage":                     "marriage_profiles",
	"products":                     "marketplace_products",
	"orders":                       "marketplace_orders",
	"beneficiary_cases":            "beneficiary_cases",
	"beneficiary_project_requests": "beneficiary_project_requests",
	"sponsorships":                 "sponsorships",
	"in_kind_donations":            "in_kind_donations",
	"support_tickets":              "support_tickets",
	"donations":                    "donations",
	"volunteer_applications":       "volunteer_applications",
	"volunteer_missions":           "volunteer_missions",
	"campaigns":                    "campaigns",
	"users":                        "users",
}

// detailColumns is the allow-list: for each resource slug, exactly the columns
// the detail view may return. Generated from the migrated schema and verified
// against production, so nothing visible today was lost — with two deliberate
// omissions, both on `users`:
//
//   - password_hash — the bcrypt credential. There is no version of "show the
//     admin this record" that includes it.
//   - google_sub    — the Google account identifier the OAuth sign-in path
//     matches on (internal/auth/google.go). Not secret in the way a hash is,
//     but it is an authentication identifier with no business meaning on a
//     detail page, so it stays behind.
//
// Adding a column to a table does NOT add it here. That is the point: the
// omission is the safe direction.
var detailColumns = map[string][]string{
	// beneficiary_cases — 32 columns
	"beneficiary_cases": {
		"id", "user_id", "case_code", "public_title", "public_title_ar", "full_name",
		"national_id", "phone", "city", "district", "address", "family_members_count",
		"income_amount", "housing_status", "work_status", "health_status", "education_status",
		"actual_needs", "priority_level", "verification_status", "public_visibility",
		"review_notes", "reviewed_by_user_id", "reviewed_at", "created_at", "updated_at",
		"public_title_sorani", "public_title_badini", "gender", "date_of_birth",
		"marital_status", "category_slug",
	},
	// beneficiary_project_requests — 63 columns
	"beneficiary_project_requests": {
		"id", "user_id", "project_title", "project_title_ar", "category", "category_ar",
		"summary", "summary_ar", "description_long", "description_long_ar", "amount_needed",
		"raised_amount", "currency", "location", "location_ar", "beneficiary_community_name",
		"beneficiary_community_name_ar", "people_affected_total", "male_count", "female_count",
		"volunteer_age_profile", "volunteer_age_profile_ar", "volunteer_skills_knowledge",
		"volunteer_skills_knowledge_ar", "people_volunteers_extra_description",
		"people_volunteers_extra_description_ar", "timeline_target", "timeline_target_ar",
		"contact_person_name", "contact_person_name_ar", "contact_phone", "contact_email",
		"other_notes", "other_notes_ar", "status", "like_count", "comment_count", "created_at",
		"updated_at", "project_title_sorani", "project_title_badini", "category_sorani",
		"category_badini", "summary_sorani", "summary_badini", "description_long_sorani",
		"description_long_badini", "location_sorani", "location_badini",
		"beneficiary_community_name_sorani", "beneficiary_community_name_badini",
		"volunteer_age_profile_sorani", "volunteer_age_profile_badini",
		"volunteer_skills_knowledge_sorani", "volunteer_skills_knowledge_badini",
		"people_volunteers_extra_description_sorani",
		"people_volunteers_extra_description_badini", "timeline_target_sorani",
		"timeline_target_badini", "contact_person_name_sorani", "contact_person_name_badini",
		"other_notes_sorani", "other_notes_badini",
	},
	// campaigns — 16 columns
	"campaigns": {
		"id", "title", "title_ar", "description", "description_ar", "address", "beneficiaries",
		"goal_amount", "raised_amount", "title_sorani", "title_badini", "description_sorani",
		"description_badini", "is_active", "status", "owner_user_id",
	},
	// city_directory_entries — 31 columns
	"community": {
		"id", "name", "name_ar", "category", "city", "address", "phone", "email", "website",
		"description", "description_ar", "latitude", "longitude", "status", "created_at",
		"updated_at", "name_sorani", "name_badini", "description_sorani", "description_badini",
		"sectors", "opening_hours", "opening_hours_ar", "opening_hours_sorani",
		"opening_hours_badini", "gallery", "submitted_by", "approx_location", "sector_type",
		"social_links", "hours",
	},
	// donations — 16 columns
	"donations": {
		"id", "reference_number", "user_id", "campaign_id", "donation_kind", "is_recurring",
		"recurring_interval", "message", "amount", "payment_status", "delivery_status",
		"payment_method", "impact_note", "transaction_date", "donation_type", "project_slug",
	},
	// in_kind_donations — 11 columns
	"in_kind_donations": {
		"id", "donor_user_id", "category", "item_name", "quantity", "condition_note",
		"pickup_address", "status", "notes", "created_at", "updated_at",
	},
	// marketplace_orders — 11 columns
	"orders": {
		"id", "product_id", "buyer_user_id", "quantity", "total_amount", "currency", "status",
		"buyer_note", "created_at", "updated_at", "transaction_code",
	},
	// marketplace_products — 25 columns
	"products": {
		"id", "seller_user_id", "beneficiary_case_id", "name", "name_ar", "description",
		"description_ar", "category", "price", "currency", "image_path", "stock_quantity",
		"status", "created_at", "updated_at", "name_sorani", "name_badini", "description_sorani",
		"description_badini", "category_slug", "sku", "specs", "labels", "brand",
		// Migration 117 — the product's additional photos, so the View page
		// reads the same set of columns the edit form writes.
		"gallery",
	},
	// marriage_profiles — 79 columns
	"marriage": {
		"id", "user_id", "profile_code", "gender", "age", "city", "social_summary",
		"private_notes", "visibility_level", "subscription_status", "status", "created_at",
		"updated_at", "marital_status", "religion", "employment_status", "weight_kg",
		"height_cm", "photo_url", "national_id", "name_first", "name_father", "name_grandfather",
		"name_family", "tribe_clan", "title_surname", "date_of_birth", "email", "phone1",
		"phone2", "nationality", "residency_status", "governorate", "housing_side",
		"neighborhood", "nearest_landmark", "gps_lat", "gps_lng", "years_current_residence",
		"previous_residence", "years_previous_residence", "housing_type", "rental_amount",
		"housing_area", "floors_count", "rooms_count", "families_count", "education_level",
		"other_certificate", "certificates_count", "occupation", "previous_occupation",
		"job_description", "working_hours", "monthly_income", "skin_tone",
		"family_members_count", "children_count", "smoking_status", "eyesight_condition",
		"has_disability", "disability_type", "chronic_illnesses", "ethnicity", "skills",
		"owns_car", "owns_house", "owns_shop", "owns_company", "owns_land", "other_assets",
		"partner_requirements", "golden_square_url", "graduation_cert_url", "cv_url",
		"social_facebook", "social_instagram", "social_telegram", "social_other",
	},
	// media_posts — 26 columns
	"media": {
		"id", "title", "title_ar", "body", "body_ar", "post_type", "media_url", "link_url",
		"event_date", "status", "created_by_user_id", "created_at", "updated_at", "title_sorani",
		"title_badini", "body_sorani", "body_badini", "category_slug", "location", "location_ar",
		"location_sorani", "location_badini", "gallery", "share_count", "activity_code",
		"partner_id",
	},
	// partners — 30 columns
	"partners": {
		"id", "name", "name_ar", "partner_type", "contact_phone", "website", "description",
		"description_ar", "logo_path", "status", "created_at", "updated_at", "name_sorani",
		"name_badini", "description_sorani", "description_badini", "email", "social_links",
		"location", "location_ar", "location_sorani", "location_badini", "avg_rating",
		"rating_count", "admin_rating", "admin_rating_note", "score_activities",
		"score_donations", "score_cooperation", "score_continuity",
	},
	// sponsorships — 14 columns
	"sponsorships": {
		"id", "donor_user_id", "beneficiary_case_id", "project_request_id", "sponsorship_type",
		"amount", "currency", "schedule_interval", "next_due_date", "status", "notes",
		"created_at", "updated_at", "last_reminder_due_date",
	},
	// support_tickets — 10 columns
	"support_tickets": {
		"id", "user_id", "subject", "message", "status", "created_at", "updated_at",
		"admin_reply", "replied_at", "replied_by",
	},
	// users — 18 of 20 columns; WITHHELD: password_hash, google_sub
	"users": {
		"id", "phone", "role_id", "active", "is_admin", "created_at", "registration_status",
		"registration_submitted_at", "registration_reviewed_at", "registration_reviewed_by",
		"registration_reject_reason", "username", "staff_tier", "email", "account_status",
		"notifications_enabled", "is_guest", "wallet_balance_iqd",
	},
	// volunteer_applications — 20 columns
	"volunteer_applications": {
		"id", "user_id", "full_name", "phone", "city", "skills", "skill_tags_legacy",
		"other_skill", "experience", "availability", "cv_link", "cv_file_path",
		"cv_original_name", "status", "created_at", "updated_at", "skill_tags", "skills_ar",
		"skills_sorani", "skills_badini",
	},
	// volunteer_missions — 16 columns
	"volunteer_missions": {
		"id", "title", "title_ar", "description", "description_ar", "city", "mission_date",
		"needed_volunteers", "status", "created_at", "updated_at", "title_sorani",
		"title_badini", "project_request_id", "description_sorani", "description_badini",
	},
}

// selectList renders an allow-listed column set as a quoted SELECT list. The
// names come from the map above — never from the request — but they are quoted
// anyway so a column that collides with a reserved word cannot break the query.
func selectList(cols []string) string {
	quoted := make([]string, len(cols))
	for i, c := range cols {
		quoted[i] = `"` + c + `"`
	}
	return strings.Join(quoted, ", ")
}

func (h *AdminDetailHandler) Detail(c *gin.Context) {
	slug := c.Param("resource")
	table, ok := resourceTables[slug]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Unknown resource."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}

	// B7 — no allow-list, no answer. A resource added to resourceTables without
	// declaring its columns must fail closed rather than fall back to SELECT *,
	// which is exactly the shape this endpoint is being fixed for.
	cols, ok := detailColumns[slug]
	if !ok || len(cols) == 0 {
		log.Printf("[detail] resource %q has no column allow-list — refusing to guess", slug)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false,
			"error": "This record cannot be displayed.", "code": "detail_unavailable"})
		return
	}

	// pgx returns each row as a map of column-name → driver-typed value when
	// we use CollectOneRow with RowToMap. This sidesteps the need to write
	// per-table struct scans.
	rows, err := h.Pool.Query(c.Request.Context(),
		"SELECT "+selectList(cols)+" FROM "+table+" WHERE id = $1",
		id,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}
	defer rows.Close()
	row, err := pgx.CollectOneRow(rows, pgx.RowToMap)
	if err != nil {
		if err == pgx.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return
	}

	// For a user, merge in everything the person actually submitted: the full
	// registration profile, the privacy flags they set on it, and the documents
	// they uploaded. See admin_detail_user_profile.go for the allow-list and
	// for what is deliberately left out of it.
	if table == "users" {
		mergeUserProfile(c.Request.Context(), h.Pool, id, row)
	}

	// Note #22 — a sponsorship's own row has no phone/name column; merge in the
	// donor's contact info (via users/user_profiles) so the View page can show
	// it, matching the client's ask to surface the phone only in View, not in
	// the list table.
	if table == "sponsorships" {
		if donorID, ok := row["donor_user_id"]; ok && donorID != nil {
			if prows, perr := h.Pool.Query(c.Request.Context(),
				`SELECT u.phone AS donor_phone, up.full_name AS donor_full_name
				   FROM users u
				   LEFT JOIN user_profiles up ON up.user_id = u.id
				  WHERE u.id = $1`, donorID); perr == nil {
				prof, e := pgx.CollectOneRow(prows, pgx.RowToMap)
				prows.Close()
				if e == nil {
					for k, v := range prof {
						row[k] = v
					}
				}
			}
		}
	}

	// §24 / H10 — redact contact fields unless this caller holds
	// `sensitive_data`. This was the ONE place in the backend that asked the
	// question; it now asks it the same way as the other twenty endpoints
	// (admin_contact_view.go), which changed two things here on purpose:
	//
	//   - The answer honours a per-EMPLOYEE override, not just the tier. It
	//     used to disagree with GET /api/admin/permissions/me — the endpoint
	//     the dashboard asks about itself — so revoking the permission for one
	//     named employee hid the column on screen while this route kept sending
	//     the real value underneath it.
	//
	//   - Partners and City Guide places are NO LONGER masked. Their numbers
	//     are the organisations' own published office lines, served to the
	//     PUBLIC at GET /api/partners; hiding from an employee what any visitor
	//     can read is a broken screen, not privacy. The classification lives in
	//     personalContactTables, shared with the trash preview.
	//
	// The `sponsorships` detail merges in a donor phone above under the key
	// `donor_phone`; `table` is "sponsorships", which is classified personal,
	// so that merged column is covered by the same pass.
	if !canViewContact(c, h.Perms) {
		maskContactColumns(table, row)
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "resource": slug, "item": row})
}
