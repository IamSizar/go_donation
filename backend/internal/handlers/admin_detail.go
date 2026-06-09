package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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
// the SELECTed column names. We use `SELECT *` so the SPA gets every column
// without us having to mirror schema changes here.
type AdminDetailHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminDetailHandler(pool *pgxpool.Pool) *AdminDetailHandler {
	return &AdminDetailHandler{Pool: pool}
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

	c.JSON(http.StatusOK, gin.H{"success": true, "resource": slug, "item": row})
}
