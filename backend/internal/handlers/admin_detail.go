package handlers

import (
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// contactKeyRe matches column names that hold sensitive contact info, so the
// detail view can redact them for staff without the sensitive_data permission.
var contactKeyRe = regexp.MustCompile(`(?i)(phone|mobile|email|whatsapp|contact_number|tel)`)

// maskContact redacts a value, keeping only the last 2 chars for a hint.
func maskContact(v any) any {
	s, ok := v.(string)
	if !ok || s == "" {
		return v
	}
	if len(s) <= 2 {
		return "••"
	}
	return "••••" + s[len(s)-2:]
}

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
// the SELECTed column names. We use `SELECT *` so the SPA gets every column
// without us having to mirror schema changes here.
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
	"partners":                      "partners",
	"media":                         "media_posts",
	"community":                     "city_directory_entries",
	"marriage":                      "marriage_profiles",
	"products":                      "marketplace_products",
	"orders":                        "marketplace_orders",
	"beneficiary_cases":             "beneficiary_cases",
	"beneficiary_project_requests":  "beneficiary_project_requests",
	"sponsorships":                  "sponsorships",
	"in_kind_donations":             "in_kind_donations",
	"support_tickets":               "support_tickets",
	"donations":                     "donations",
	"volunteer_applications":        "volunteer_applications",
	"volunteer_missions":            "volunteer_missions",
	"campaigns":                     "campaigns",
	"users":                         "users",
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

	// pgx returns each row as a map of column-name → driver-typed value when
	// we use CollectOneRow with RowToMap. This sidesteps the need to write
	// per-table struct scans.
	rows, err := h.Pool.Query(c.Request.Context(),
		"SELECT * FROM "+table+" WHERE id = $1",
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

	// For a user, merge in the registration profile (name, DOB, address, gender,
	// city, occupation + role-specific fields) so the admin detail view shows
	// what the person actually submitted at sign-up — not just the account row.
	if table == "users" {
		if prows, perr := h.Pool.Query(c.Request.Context(),
			`SELECT full_name, date_of_birth, address, gender, city, occupation,
			        family_size, housing_status, monthly_income,
			        skills, availability, experience, profile_picture
			   FROM user_profiles WHERE user_id = $1`, id); perr == nil {
			prof, e := pgx.CollectOneRow(prows, pgx.RowToMap)
			prows.Close()
			if e == nil {
				for k, v := range prof {
					if _, exists := row[k]; !exists {
						row[k] = v
					}
				}
			}
		}
	}

	// §24 — redact sensitive contact fields (phone/email/…) unless this staff
	// member's tier is granted the `sensitive_data` view permission. Enforced
	// server-side so the raw value never leaves the backend for the ungranted.
	if h.Perms != nil {
		if actor, ok := auth.UserFromGin(c); ok && actor != nil {
			tier := permissions.TierFrom(actor.StaffTier)
			canSee, _ := h.Perms.Allowed(c.Request.Context(), tier, "sensitive_data", "view")
			if !canSee {
				for k, v := range row {
					if contactKeyRe.MatchString(strings.ToLower(k)) {
						row[k] = maskContact(v)
					}
				}
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "resource": slug, "item": row})
}
