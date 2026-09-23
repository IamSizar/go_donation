// Package marketplacesections backs the admin-curated store "sections" —
// named shelves with a cover image that any number of existing marketplace
// products can be added to (e.g. "Clothing"). Mirrors the
// marketplacecategories CMS pattern, but the product relationship is
// many-to-many rather than a single tag on the product row — see migration
// 133.
package marketplacesections

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Section is one store shelf with its 4-language names and cover image.
type Section struct {
	ID             int64      `json:"id"`
	Slug           string     `json:"slug"`
	NameEN         string     `json:"name_en"`
	NameAR         string     `json:"name_ar"`
	NameCKB        string     `json:"name_ckb"`
	NameKMR        string     `json:"name_kmr"`
	CoverImagePath string     `json:"cover_image_path"`
	DisplayOrder   int        `json:"display_order"`
	Active         bool       `json:"active"`
	StartsAt       *time.Time `json:"starts_at"`
	EndsAt         *time.Time `json:"ends_at"`
	// ProductCount — how many products are currently in the section. Only
	// populated by List; zero on Add/Update since neither changes membership.
	ProductCount int `json:"product_count"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// List returns sections in admin-defined display order, with each one's
// current product count (approved products only — matching what the public
// catalogue itself shows). When publicOnly, only active rows within their
// visibility window AND holding at least one such product are returned — an
// empty or not-yet-live shelf has nothing for a shopper to tap into.
func (s *Store) List(ctx context.Context, publicOnly bool) ([]Section, error) {
	where := ""
	having := ""
	if publicOnly {
		where = ` WHERE sec.active = 1
		            AND (sec.starts_at IS NULL OR sec.starts_at <= NOW())
		            AND (sec.ends_at IS NULL OR sec.ends_at >= NOW())`
		having = " HAVING COUNT(p.id) > 0"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT sec.id, sec.slug, sec.name_en, sec.name_ar, sec.name_ckb, sec.name_kmr,
		        sec.cover_image_path, sec.display_order, (sec.active = 1), sec.starts_at, sec.ends_at,
		        COUNT(p.id)::int
		   FROM marketplace_sections sec
		   LEFT JOIN marketplace_products p
		     ON p.section_id = sec.id AND p.status = 'approved'`+where+`
		  GROUP BY sec.id`+having+`
		  ORDER BY sec.display_order, sec.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Section{}
	for rows.Next() {
		var sec Section
		if err := rows.Scan(&sec.ID, &sec.Slug, &sec.NameEN, &sec.NameAR, &sec.NameCKB, &sec.NameKMR,
			&sec.CoverImagePath, &sec.DisplayOrder, &sec.Active, &sec.StartsAt, &sec.EndsAt,
			&sec.ProductCount); err != nil {
			return nil, err
		}
		out = append(out, sec)
	}
	return out, rows.Err()
}

// Add inserts a new section, deriving the slug from the English name (or an
// explicit slug). New sections are active with no products yet.
func (s *Store) Add(ctx context.Context, sec Section, actorID *int64) (*Section, error) {
	sec.NameEN = strings.TrimSpace(sec.NameEN)
	if sec.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	key := slugify(sec.Slug)
	if key == "" {
		key = slugify(sec.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a section key")
	}
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO marketplace_sections
		   (slug, name_en, name_ar, name_ckb, name_kmr, cover_image_path, active, starts_at, ends_at, created_by)
		 VALUES ($1, $2, $3, $4, $5, $6, 1, $7, $8, $9)
		 RETURNING id, display_order, (active = 1)`,
		key, sec.NameEN, strings.TrimSpace(sec.NameAR),
		strings.TrimSpace(sec.NameCKB), strings.TrimSpace(sec.NameKMR),
		strings.TrimSpace(sec.CoverImagePath), sec.StartsAt, sec.EndsAt, actorID,
	).Scan(&sec.ID, &sec.DisplayOrder, &sec.Active)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a section with that name already exists")
		}
		return nil, err
	}
	sec.Slug = key
	return &sec, nil
}

// Update edits a section's names, cover image, visibility window and active
// flag. The slug is immutable.
func (s *Store) Update(ctx context.Context, id int64, sec Section) (*Section, error) {
	sec.NameEN = strings.TrimSpace(sec.NameEN)
	if sec.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if sec.Active {
		activeInt = 1
	}
	var out Section
	err := s.Pool.QueryRow(ctx,
		`UPDATE marketplace_sections
		    SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5,
		        cover_image_path = $6, active = $7, starts_at = $8, ends_at = $9,
		        updated_at = NOW()
		  WHERE id = $1
		  RETURNING id, slug, name_en, name_ar, name_ckb, name_kmr,
		            cover_image_path, display_order, (active = 1), starts_at, ends_at`,
		id, sec.NameEN, strings.TrimSpace(sec.NameAR),
		strings.TrimSpace(sec.NameCKB), strings.TrimSpace(sec.NameKMR),
		strings.TrimSpace(sec.CoverImagePath), activeInt, sec.StartsAt, sec.EndsAt,
	).Scan(&out.ID, &out.Slug, &out.NameEN, &out.NameAR, &out.NameCKB, &out.NameKMR,
		&out.CoverImagePath, &out.DisplayOrder, &out.Active, &out.StartsAt, &out.EndsAt)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("section not found")
		}
		return nil, err
	}
	return &out, nil
}

// Reorder rewrites display_order to match the given id sequence.
func (s *Store) Reorder(ctx context.Context, orderedIDs []int64) error {
	if len(orderedIDs) == 0 {
		return nil
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, id := range orderedIDs {
		if _, err := tx.Exec(ctx,
			`UPDATE marketplace_sections SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a section. marketplace_section_products rows cascade with
// it; the products themselves are untouched.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM marketplace_sections WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("section not found")
	}
	return nil
}

