// Package campaigns serves the donor-facing /api/campaigns endpoint.
//
// Phase 15: this endpoint now reads from the real `campaigns` table —
// the same table the admin manages via /api/admin/campaigns. Previously
// it projected `beneficiary_project_requests` rows, which meant admin
// and donor saw completely different campaign lists. Donations already
// FK to `campaigns`, so this table is the natural single source of truth.
//
// The Flutter app's `FeaturedCampaignData.fromJson` uses a `pick(...)`
// helper that accepts both `title`/`project_title`, `address`/`location`,
// etc. — so the simpler schema of `campaigns` (no _sorani/_badini variants,
// no separate summary column, etc.) is fine. Missing fields are emitted as
// nil/empty and Flutter silently substitutes defaults.
package campaigns

import (
	"context"
	"errors"
	"math"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Campaign keeps the JSON shape stable for the Flutter app. Fields that the
// `campaigns` table doesn't have (categories, summary, currency, languages
// beyond AR, like/comment counts) are left as nil/zero so the JSON keys still
// exist and the client doesn't trip on missing keys.
type Campaign struct {
	ID                              int64   `json:"id"`
	UserID                          int     `json:"user_id"`
	Title                           string  `json:"title"`
	TitleAr                         *string `json:"title_ar"`
	TitleSorani                     *string `json:"title_sorani"`
	TitleBadini                     *string `json:"title_badini"`
	Category                        string  `json:"category"`
	CategoryAr                      *string `json:"category_ar"`
	CategorySorani                  *string `json:"category_sorani"`
	CategoryBadini                  *string `json:"category_badini"`
	Summary                         string  `json:"summary"`
	SummaryAr                       *string `json:"summary_ar"`
	SummarySorani                   *string `json:"summary_sorani"`
	SummaryBadini                   *string `json:"summary_badini"`
	Description                     string  `json:"description"`
	DescriptionAr                   *string `json:"description_ar"`
	DescriptionSorani               *string `json:"description_sorani"`
	DescriptionBadini               *string `json:"description_badini"`
	Address                         string  `json:"address"`
	AddressAr                       *string `json:"address_ar"`
	AddressSorani                   *string `json:"address_sorani"`
	AddressBadini                   *string `json:"address_badini"`
	BeneficiaryCommunityName        string  `json:"beneficiary_community_name"`
	BeneficiaryCommunityNameAr      *string `json:"beneficiary_community_name_ar"`
	BeneficiaryCommunityNameSorani  *string `json:"beneficiary_community_name_sorani"`
	BeneficiaryCommunityNameBadini  *string `json:"beneficiary_community_name_badini"`
	Beneficiaries                   string  `json:"beneficiaries"`
	GoalAmount                      string  `json:"goal_amount"`
	RaisedAmount                    string  `json:"raised_amount"`
	Currency                        string  `json:"currency"`
	// Status is the lifecycle string the SPA + Flutter app both reason on:
	//   "active"   — donor can see + donate
	//   "hidden"   — donor list omits the row
	//   "finished" — donor list omits the row; donations are rejected
	// `is_active` is a derived 1/0 mirror retained for any legacy reader.
	Status                          string  `json:"status"`
	IsActive                        int     `json:"is_active"`
	LikeCount                       int     `json:"like_count"`
	CommentCount                    int     `json:"comment_count"`
}

type Pagination struct {
	Page        int  `json:"page"`
	PerPage     int  `json:"per_page"`
	TotalItems  int  `json:"total_items"`
	TotalPages  int  `json:"total_pages"`
	HasMore     bool `json:"has_more"`
}

type Page struct {
	Items      []Campaign `json:"items"`
	Pagination Pagination `json:"pagination"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// listSelect projects a row from `campaigns` into the JSON shape Flutter
// expects. Lifecycle is now carried by the `status` column directly; the
// `is_active` int is derived (1 only when status='active') so any legacy
// reader still gets a sensible boolean.
const listSelect = `
	SELECT id,
	       0                              AS user_id,
	       title,
	       NULLIF(title_ar, '')           AS title_ar,
	       NULLIF(title_sorani, '')       AS title_sorani,
	       NULLIF(title_badini, '')       AS title_badini,
	       ''::text                       AS category,
	       NULL::text                     AS category_ar,
	       NULL::text                     AS category_sorani,
	       NULL::text                     AS category_badini,
	       description                    AS summary,
	       NULLIF(description_ar, '')     AS summary_ar,
	       NULLIF(description_sorani, '') AS summary_sorani,
	       NULLIF(description_badini, '') AS summary_badini,
	       description,
	       NULLIF(description_ar, '')     AS description_ar,
	       NULLIF(description_sorani, '') AS description_sorani,
	       NULLIF(description_badini, '') AS description_badini,
	       address,
	       NULL::text                     AS address_ar,
	       NULL::text                     AS address_sorani,
	       NULL::text                     AS address_badini,
	       ''::text                       AS beneficiary_community_name,
	       NULL::text                     AS beneficiary_community_name_ar,
	       NULL::text                     AS beneficiary_community_name_sorani,
	       NULL::text                     AS beneficiary_community_name_badini,
	       beneficiaries,
	       goal_amount,
	       raised_amount,
	       'IQD'::text                    AS currency,
	       status,
	       CASE WHEN status = 'active' THEN 1 ELSE 0 END AS is_active,
	       0 AS like_count,
	       0 AS comment_count
	  FROM campaigns
`

func scanRow(row pgx.Row, c *Campaign) error {
	return row.Scan(
		&c.ID, &c.UserID,
		&c.Title, &c.TitleAr, &c.TitleSorani, &c.TitleBadini,
		&c.Category, &c.CategoryAr, &c.CategorySorani, &c.CategoryBadini,
		&c.Summary, &c.SummaryAr, &c.SummarySorani, &c.SummaryBadini,
		&c.Description, &c.DescriptionAr, &c.DescriptionSorani, &c.DescriptionBadini,
		&c.Address, &c.AddressAr, &c.AddressSorani, &c.AddressBadini,
		&c.BeneficiaryCommunityName, &c.BeneficiaryCommunityNameAr,
		&c.BeneficiaryCommunityNameSorani, &c.BeneficiaryCommunityNameBadini,
		&c.Beneficiaries,
		&c.GoalAmount, &c.RaisedAmount, &c.Currency, &c.Status, &c.IsActive,
		&c.LikeCount, &c.CommentCount,
	)
}

// List returns a paginated page of campaigns visible to donors.
//
// Filtering rules:
//   • status == "" or "approved" or "active" → donor default (only status='active').
//   • status == "hidden"                      → only hidden rows.
//   • status == "finished"                    → only finished rows.
//   • status == "all"                         → every row (admin diagnostic).
//   • any other value                         → donor default.
func (s *Store) List(ctx context.Context, page, perPage int, status string) (*Page, error) {
	page = normalizePage(page)
	perPage = normalizePerPage(perPage, 12, 100)

	var where string
	var args []any
	switch status {
	case "all":
		where = ""
	case "hidden":
		where = " WHERE status = $1"
		args = []any{"hidden"}
	case "finished":
		where = " WHERE status = $1"
		args = []any{"finished"}
	default: // "", "approved", "active", or unknown → donor-visible only
		where = " WHERE status = $1"
		args = []any{"active"}
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM campaigns"+where, args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	offset := (page - 1) * perPage
	args = append(args, perPage, offset)
	limitArg := "$" + strconv.Itoa(len(args)-1)
	offsetArg := "$" + strconv.Itoa(len(args))
	rows, err := s.Pool.Query(ctx,
		listSelect+where+` ORDER BY id DESC LIMIT `+limitArg+` OFFSET `+offsetArg,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]Campaign, 0, perPage)
	for rows.Next() {
		var c Campaign
		if err := scanRow(rows, &c); err != nil {
			return nil, err
		}
		items = append(items, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := int(math.Ceil(float64(total) / float64(perPage)))
	if totalPages < 1 {
		totalPages = 1
	}
	return &Page{
		Items: items,
		Pagination: Pagination{
			Page:       page,
			PerPage:    perPage,
			TotalItems: total,
			TotalPages: totalPages,
			HasMore:    page < totalPages,
		},
	}, nil
}

// GetByID returns one campaign by id (any visibility). Used by the donations
// handler to validate that `campaigns_id` references a real row before insert.
func (s *Store) GetByID(ctx context.Context, id int64) (*Campaign, error) {
	if id <= 0 {
		return nil, nil
	}
	var c Campaign
	err := scanRow(
		s.Pool.QueryRow(ctx, listSelect+` WHERE id = $1`, id),
		&c,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

// normalizePage mirrors normalizePage() in PHP.
func normalizePage(p int) int {
	if p < 1 {
		return 1
	}
	return p
}

// normalizePerPage mirrors normalizePerPage() in PHP.
func normalizePerPage(p, defaultPP, max int) int {
	if p <= 0 {
		return defaultPP
	}
	if p > max {
		return max
	}
	return p
}
