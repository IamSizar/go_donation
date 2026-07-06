// Package projectcategories backs the admin-managed project-category list (#17):
// an ordered, 4-language taxonomy the beneficiary picks from when submitting a
// project. Mirrors the custom_professions CMS pattern.
package projectcategories

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Category is one project category with its 4-language display names.
type Category struct {
	ID           int64  `json:"id"`
	Slug         string `json:"slug"`
	NameEN       string `json:"name_en"`
	NameAR       string `json:"name_ar"`
	NameCKB      string `json:"name_ckb"`
	NameKMR      string `json:"name_kmr"`
	DisplayOrder int    `json:"display_order"`
	Active       bool   `json:"active"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

// slugify turns a free-text name into a canonical slug: lowercased, non-alnum
// runs collapsed to a single underscore.
func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// List returns categories in admin-defined display order (id tiebreak). When
// activeOnly, only active rows (used by the public app dropdown).
func (s *Store) List(ctx context.Context, activeOnly bool) ([]Category, error) {
	where := ""
	if activeOnly {
		where = " WHERE active = 1"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT id, slug, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)
		   FROM project_categories`+where+`
		  ORDER BY display_order, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Category{}
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.Slug, &c.NameEN, &c.NameAR, &c.NameCKB, &c.NameKMR,
			&c.DisplayOrder, &c.Active); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// Add inserts a new category, deriving the slug from the English name (or an
// explicit slug). New categories are active. Returns the stored row.
func (s *Store) Add(ctx context.Context, c Category, actorID *int64) (*Category, error) {
	c.NameEN = strings.TrimSpace(c.NameEN)
	if c.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	key := slugify(c.Slug)
	if key == "" {
		key = slugify(c.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a category key")
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO project_categories (slug, name_en, name_ar, name_ckb, name_kmr, active, created_by)
		 VALUES ($1, $2, $3, $4, $5, 1, $6)
		 RETURNING id, display_order, (active = 1)`,
		key, c.NameEN, strings.TrimSpace(c.NameAR),
		strings.TrimSpace(c.NameCKB), strings.TrimSpace(c.NameKMR), actorID,
	).Scan(&id, &c.DisplayOrder, &c.Active)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a category with that name already exists")
		}
		return nil, err
	}
	c.ID = id
	c.Slug = key
	return &c, nil
}

// Update edits a category's names and active flag. The slug is immutable.
func (s *Store) Update(ctx context.Context, id int64, c Category) (*Category, error) {
	c.NameEN = strings.TrimSpace(c.NameEN)
	if c.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if c.Active {
		activeInt = 1
	}
	var out Category
	err := s.Pool.QueryRow(ctx,
		`UPDATE project_categories
		    SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5, active = $6
		  WHERE id = $1
		  RETURNING id, slug, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)`,
		id, c.NameEN, strings.TrimSpace(c.NameAR),
		strings.TrimSpace(c.NameCKB), strings.TrimSpace(c.NameKMR), activeInt,
	).Scan(&out.ID, &out.Slug, &out.NameEN, &out.NameAR, &out.NameCKB, &out.NameKMR,
		&out.DisplayOrder, &out.Active)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("category not found")
		}
		return nil, err
	}
	return &out, nil
}

// Reorder rewrites display_order to match the given id sequence (first id → 1,
// etc.) in a single transaction.
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
			`UPDATE project_categories SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a category. Existing projects keep their snapshotted category
// text; the category simply drops out of the dropdown.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM project_categories WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("category not found")
	}
	return nil
}
