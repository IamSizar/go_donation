package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// DashboardKPIsHandler powers GET /api/admin/dashboard_kpis used by the
// dashboard's trend cards and donations chart.
type DashboardKPIsHandler struct {
	Pool *pgxpool.Pool
}

func NewDashboardKPIsHandler(pool *pgxpool.Pool) *DashboardKPIsHandler {
	return &DashboardKPIsHandler{Pool: pool}
}

type trend struct {
	ThisMonth int     `json:"this_month"`
	LastMonth int     `json:"last_month"`
	PctChange float64 `json:"pct_change"`
}

type moneyTrend struct {
	ThisMonth string  `json:"this_month"`
	LastMonth string  `json:"last_month"`
	PctChange float64 `json:"pct_change"`
}

type seriesPoint struct {
	Date            string `json:"date"`
	CompletedAmount string `json:"completed_amount"`
	PendingAmount   string `json:"pending_amount"`
	Count           int    `json:"count"`
}

type dashboardKPIs struct {
	Signups         trend         `json:"signups"`
	DonationsCount  trend         `json:"donations_count"`
	DonationsAmount moneyTrend    `json:"donations_amount"`
	ActiveCampaigns int           `json:"active_campaigns"`
	OpenMissions    int           `json:"open_missions"`
	OpenTickets     int           `json:"open_tickets"`
	Donations30d    []seriesPoint `json:"donations_30d"`
}

func pct(thisM, lastM float64) float64 {
	if lastM == 0 {
		if thisM == 0 {
			return 0
		}
		return 100
	}
	return ((thisM - lastM) / lastM) * 100
}

// GET /api/admin/dashboard_kpis
func (h *DashboardKPIsHandler) Get(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}

	ctx := c.Request.Context()
	now := time.Now().UTC()
	thisMonthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	lastMonthStart := thisMonthStart.AddDate(0, -1, 0)
	last30Start := now.AddDate(0, 0, -29).Truncate(24 * time.Hour)

	res := dashboardKPIs{Donations30d: []seriesPoint{}}

	// Signups (users.created_at)
	if err := h.Pool.QueryRow(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN created_at >= $1 THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN created_at >= $2 AND created_at < $1 THEN 1 ELSE 0 END), 0)
		FROM users`,
		thisMonthStart, lastMonthStart,
	).Scan(&res.Signups.ThisMonth, &res.Signups.LastMonth); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error (signups)."})
		return
	}
	res.Signups.PctChange = pct(float64(res.Signups.ThisMonth), float64(res.Signups.LastMonth))

	// Donations rollups: count (any status) + completed amount (status=1)
	var thisAmt, lastAmt float64
	if err := h.Pool.QueryRow(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN transaction_date >= $1 THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN transaction_date >= $2 AND transaction_date < $1 THEN 1 ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN transaction_date >= $1 AND payment_status = 1
		                    THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::float8,
		  COALESCE(SUM(CASE WHEN transaction_date >= $2 AND transaction_date < $1 AND payment_status = 1
		                    THEN NULLIF(amount,'')::numeric ELSE 0 END), 0)::float8
		FROM donations`,
		thisMonthStart, lastMonthStart,
	).Scan(&res.DonationsCount.ThisMonth, &res.DonationsCount.LastMonth, &thisAmt, &lastAmt); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error (donations)."})
		return
	}
	res.DonationsCount.PctChange = pct(float64(res.DonationsCount.ThisMonth), float64(res.DonationsCount.LastMonth))
	res.DonationsAmount.ThisMonth = ftoa(thisAmt)
	res.DonationsAmount.LastMonth = ftoa(lastAmt)
	res.DonationsAmount.PctChange = pct(thisAmt, lastAmt)

	// Live counts
	_ = h.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM beneficiary_project_requests WHERE status = 'approved'`,
	).Scan(&res.ActiveCampaigns)
	_ = h.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM volunteer_missions WHERE status = 'open'`,
	).Scan(&res.OpenMissions)
	_ = h.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM support_tickets WHERE status IN ('open','in_progress')`,
	).Scan(&res.OpenTickets)

	// Last-30-days donations time series — daily buckets, zero-filled.
	rows, err := h.Pool.Query(ctx, `
		SELECT to_char(d::date, 'YYYY-MM-DD'),
		       COALESCE(SUM(CASE WHEN payment_status = 1
		                         THEN NULLIF(don.amount,'')::numeric ELSE 0 END), 0)::text,
		       COALESCE(SUM(CASE WHEN payment_status = 2
		                         THEN NULLIF(don.amount,'')::numeric ELSE 0 END), 0)::text,
		       COUNT(don.id)
		  FROM generate_series($1::date, $2::date, '1 day'::interval) d
		  LEFT JOIN donations don ON don.transaction_date::date = d::date
		 GROUP BY d
		 ORDER BY d ASC`,
		last30Start, now,
	)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p seriesPoint
			if err := rows.Scan(&p.Date, &p.CompletedAmount, &p.PendingAmount, &p.Count); err == nil {
				res.Donations30d = append(res.Donations30d, p)
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"kpis":    res,
	})
}

func ftoa(f float64) string {
	return strconv.FormatFloat(f, 'f', 2, 64)
}
