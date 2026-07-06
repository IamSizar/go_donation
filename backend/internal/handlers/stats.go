package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// StatsHandler serves the public, aggregate "impact" numbers shown on the app
// home (the auto-rotating stats slider). No auth — these are org-wide totals
// with no personal data, safe to render before/without login.
type StatsHandler struct {
	Pool *pgxpool.Pool
}

func NewStatsHandler(pool *pgxpool.Pool) *StatsHandler {
	return &StatsHandler{Pool: pool}
}

// ImpactStats handles GET /api/stats/impact.
//
// Returns five headline numbers:
//   - grantors        active users with role_id = 1 (givers)
//   - eligibles       active users with role_id = 2 (aid recipients)
//   - volunteers      active users with role_id = 3
//   - completed_works completed volunteer missions + approved beneficiary
//     projects (the two things the app treats as "delivered" work)
//   - total_given     sum of successful donation amounts (payment_status = 1)
//
// `donations.amount` is stored as TEXT, so it's cast via NULLIF(amount,'')::numeric
// and returned as a string to avoid float rounding on large IQD totals.
// Everything is COALESCE'd so an empty database returns zeros, never null.
func (h *StatsHandler) ImpactStats(c *gin.Context) {
	const q = `
		SELECT
		  (SELECT COUNT(*) FROM users WHERE role_id = 1 AND active = 1)::bigint,
		  (SELECT COUNT(*) FROM users WHERE role_id = 2 AND active = 1)::bigint,
		  (SELECT COUNT(*) FROM users WHERE role_id = 3 AND active = 1)::bigint,
		  (
		    (SELECT COUNT(*) FROM volunteer_missions WHERE status = 'completed')
		    + (SELECT COUNT(*) FROM beneficiary_project_requests WHERE status = 'approved')
		  )::bigint,
		  (
		    SELECT COALESCE(SUM(NULLIF(amount, '')::numeric), 0)
		    FROM donations
		    WHERE payment_status = 1
		  )::text
	`

	var grantors, eligibles, volunteers, completedWorks int64
	var totalGiven string
	if err := h.Pool.QueryRow(c.Request.Context(), q).
		Scan(&grantors, &eligibles, &volunteers, &completedWorks, &totalGiven); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"stats": gin.H{
			"grantors":        grantors,
			"eligibles":       eligibles,
			"volunteers":      volunteers,
			"completed_works": completedWorks,
			"total_given":     totalGiven,
		},
	})
}
