// pending_counts.go — GET /api/admin/pending-counts
//
// Returns a single small JSON object the admin SPA polls every few seconds
// to render badge numbers next to each sidebar item. One round-trip per
// poll, one SQL query (with FILTER) — sub-millisecond at this scale on the
// already-indexed status columns.
//
// Phase 16 — sidebar live notifications. Pure Postgres; no Firestore.
//
// "Pending" means "needs admin action" per the table below. Verified against
// the actual seeded values on 2026-05-17:
//
//   donations                    delivery_status = 'registered'
//   sponsorships                 status          = 'pending'
//   beneficiary_cases            verification_status = 'pending'
//   beneficiary_project_requests status          = 'under_review'
//   marketplace_orders           status          IN ('pending','processing')
//   support_tickets              status          IN ('open','in_progress')
//   in_kind_donations            status          = 'scheduled'
//   volunteer_applications       status          = 'submitted'
//   marriage_profiles            status          = 'pending'
//
// The combined "beneficiary" badge sums beneficiary_cases + project_requests
// because the admin's sidebar has one entry for both.

package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PendingCountsHandler struct {
	Pool *pgxpool.Pool
}

func NewPendingCountsHandler(pool *pgxpool.Pool) *PendingCountsHandler {
	return &PendingCountsHandler{Pool: pool}
}

// PendingCounts is the JSON shape the SPA sidebar consumes. Every value is
// non-negative; missing tables would manifest as a 500 (we don't silently
// swallow errors because a wrong zero badge would be more confusing than
// a "Counts unavailable" toast).
type PendingCounts struct {
	Donations      int `json:"donations"`
	Sponsorships   int `json:"sponsorships"`
	Beneficiary    int `json:"beneficiary"`     // cases + project_requests, combined
	Marketplace    int `json:"marketplace"`
	Support        int `json:"support"`
	InKind         int `json:"in_kind"`
	Volunteers     int `json:"volunteers"`     // volunteer_applications submitted
	MissionSignups int `json:"mission_signups"` // Phase 21 — join requests awaiting admin
	Marriage       int `json:"marriage"`
	Registrations  int `json:"registrations"` // new-user signups awaiting approval
	// Total is server-derived so the client doesn't have to re-sum it for the
	// global "all pending" indicator (e.g. window title prefix).
	Total          int `json:"total"`
}

// Counts handles GET /api/admin/pending-counts.
//
// A single query with one COUNT(*) FILTER clause per table runs all eight
// counts in one round-trip. We use FROM (VALUES (1)) AS _ so the row is
// always produced even when every count is zero (otherwise GROUP BY would
// elide the row and we'd get an empty result set).
func (h *PendingCountsHandler) Counts(c *gin.Context) {
	if !requireAuth(c) {
		return
	}

	const q = `
		SELECT
		  (SELECT COUNT(*) FROM donations
		     WHERE delivery_status = 'registered')                            AS donations,
		  (SELECT COUNT(*) FROM sponsorships
		     WHERE status = 'pending')                                        AS sponsorships,
		  (SELECT COUNT(*) FROM beneficiary_cases
		     WHERE verification_status = 'pending')
		  + (SELECT COUNT(*) FROM beneficiary_project_requests
		     WHERE status = 'under_review')                                   AS beneficiary,
		  (SELECT COUNT(*) FROM marketplace_orders
		     WHERE status IN ('pending', 'processing'))                       AS marketplace,
		  (SELECT COUNT(*) FROM support_tickets
		     WHERE status IN ('open', 'in_progress'))                         AS support,
		  (SELECT COUNT(*) FROM in_kind_donations
		     WHERE status = 'scheduled')                                      AS in_kind,
		  (SELECT COUNT(*) FROM volunteer_applications
		     WHERE status = 'submitted')                                      AS volunteers,
		  -- Phase 21 — pending join requests + volunteer-claimed completions
		  -- the admin needs to confirm. Both states need admin action so
		  -- they're surfaced as a single count.
		  (SELECT COUNT(*) FROM volunteer_mission_signups
		     WHERE status IN ('pending', 'completion_requested'))             AS mission_signups,
		  (SELECT COUNT(*) FROM marriage_profiles
		     WHERE status = 'pending')                                        AS marriage,
		  (SELECT COUNT(*) FROM users
		     WHERE registration_status = 'pending')                           AS registrations
	`

	var out PendingCounts
	if err := h.Pool.QueryRow(c.Request.Context(), q).Scan(
		&out.Donations,
		&out.Sponsorships,
		&out.Beneficiary,
		&out.Marketplace,
		&out.Support,
		&out.InKind,
		&out.Volunteers,
		&out.MissionSignups,
		&out.Marriage,
		&out.Registrations,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to compute pending counts: " + err.Error(),
		})
		return
	}

	out.Total = out.Donations + out.Sponsorships + out.Beneficiary +
		out.Marketplace + out.Support + out.InKind + out.Volunteers +
		out.MissionSignups + out.Marriage + out.Registrations

	c.JSON(http.StatusOK, out)
}
