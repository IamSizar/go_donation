package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// AdminExportHandler dumps every business table as a single JSON document
// for backup / migration / offline analysis.
//
// Behaviour:
//   • Streams to the response with Content-Disposition: attachment so the
//     browser opens a Save dialog with a dated filename.
//   • Tables are read in a fixed order so diffs across exports stay stable.
//   • Each row is returned as a JSON object (column name → value) via pgx's
//     RowToMap — no per-table struct definitions needed.
//   • Security: protected by RequireAdmin (wired in main.go). The OTP
//     codes table is deliberately excluded because it holds active codes
//     and exporting them would let anyone with the file replay logins.
//
// The output shape is:
//   {
//     "database": "humanitarian",
//     "exported_at": "2026-05-16T12:34:56Z",
//     "row_counts": { "users": 4, "donations": 12, ... },
//     "tables": {
//       "users":     [ {...}, {...} ],
//       "donations": [ {...}, ... ],
//       ...
//     }
//   }
type AdminExportHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminExportHandler(pool *pgxpool.Pool) *AdminExportHandler {
	return &AdminExportHandler{Pool: pool}
}

// exportOrder maps a table name to its ORDER BY clause. Almost every table
// has an `id` primary key, but the join tables (e.g. app_notification_reads)
// use composite keys — those need explicit overrides so the export query
// doesn't fail with "column id does not exist".
var exportOrder = map[string]string{
	"app_notification_reads":    "notification_id ASC, user_id ASC",
	"volunteer_mission_signups": "id ASC", // has id; keep default but be explicit
}

// exportTables is the fixed allowlist. Ordering matters only for diff
// stability — Postgres returns rows in arbitrary order so each table is
// sorted by id (or the override above) below.
//
// Excluded:
//   • otp_codes           — active login codes; security risk
//   • otp_ip_rate_limit   — transient operational counter, no business value
var exportTables = []string{
	// users + auth
	"users",
	"user_profiles",
	"user_device_tokens",
	"api_access_tokens",
	"audit_log",
	"user_profile_audit_logs",
	// notifications
	"app_notifications",
	"app_notification_devices",
	"app_notification_reads",
	// beneficiary
	"beneficiary_cases",
	"beneficiary_case_documents",
	"beneficiary_project_requests",
	"beneficiary_project_request_comments",
	"beneficiary_project_request_likes",
	// donations + campaigns
	"campaigns",
	"campaigns_category",
	"campaings_datas",
	"donations",
	"financial_expenses",
	"in_kind_donations",
	// marketplace
	"marketplace_products",
	"marketplace_orders",
	// directory + content
	"city_directory_entries",
	"media_posts",
	"partners",
	"marriage_profiles",
	// support + giving
	"sponsorships",
	"support_tickets",
	// volunteers
	"volunteer_applications",
	"volunteer_missions",
	"volunteer_mission_signups",
}

func (h *AdminExportHandler) ExportAll(c *gin.Context) {
	tables := make(map[string][]map[string]any, len(exportTables))
	counts := make(map[string]int, len(exportTables))

	for _, t := range exportTables {
		// We select * and rely on pgx's CollectRows + RowToMap so adding a
		// column to the schema doesn't require touching this handler.
		// Ordering keeps the diff between two exports meaningful — defaults
		// to `id ASC`, but tables with composite keys override above.
		orderBy := exportOrder[t]
		if orderBy == "" {
			orderBy = "id ASC"
		}
		rows, err := h.Pool.Query(c.Request.Context(),
			"SELECT * FROM "+t+" ORDER BY "+orderBy,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   "Failed reading table " + t + ": " + err.Error(),
			})
			return
		}
		items, err := pgx.CollectRows(rows, pgx.RowToMap)
		rows.Close()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   "Failed scanning table " + t + ": " + err.Error(),
			})
			return
		}
		tables[t] = items
		counts[t] = len(items)
	}

	// Server-side dated filename so a user double-clicking the link gets
	// something they can put straight into a backups folder.
	filename := "humanitarian-export-" + time.Now().UTC().Format("2006-01-02-150405") + ".json"
	c.Header("Content-Disposition", `attachment; filename="`+filename+`"`)
	// JSON encoding happens inside gin.JSON; we set the header explicitly
	// only so the download attachment kicks in.

	c.JSON(http.StatusOK, gin.H{
		"database":    "humanitarian",
		"exported_at": time.Now().UTC().Format(time.RFC3339),
		"row_counts":  counts,
		"tables":      tables,
	})
}
